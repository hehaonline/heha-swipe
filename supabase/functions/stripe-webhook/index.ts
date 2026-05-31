import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY"), {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get("SUPABASE_URL"),
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, stripe-signature",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body, signature, Deno.env.get("STRIPE_WEBHOOK_SECRET")
    );
  } catch (err) {
    return new Response(`Webhook Error: ${err.message}`, { status: 400 });
  }

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object;
      const userId = session.metadata?.user_id;
      const amountCents = Number(session.metadata?.amount_cents || 0);
      const role = session.metadata?.role || "customer";
      if (userId) {
        await supabase.from("profiles").update({
          subscription_type: role === "partner" ? "partner_monthly" : "monthly",
          subscription_amount: amountCents / 100,
          subscription_active: true,
          subscription_status: "active",
          stripe_subscription_id: session.subscription,
        }).eq("id", userId);
      }
      break;
    }
    case "invoice.payment_succeeded": {
      const invoice = event.data.object;
      const sub = await stripe.subscriptions.retrieve(invoice.subscription);
      const userId = sub.metadata?.user_id;
      if (userId) await supabase.from("profiles").update({ subscription_active: true, subscription_status: "active" }).eq("id", userId);
      break;
    }
    case "customer.subscription.deleted":
    case "invoice.payment_failed": {
      const obj = event.data.object;
      const subId = obj.subscription || obj.id;
      if (subId) await supabase.from("profiles").update({ subscription_active: false, subscription_status: "cancelled" }).eq("stripe_subscription_id", subId);
      break;
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200,
  });
});
