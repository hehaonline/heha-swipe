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

const SUPPORTER_SOURCE = "heha_swipe_supporter";

function toTimestamp(value) {
  return value ? new Date(value * 1000).toISOString() : null;
}

function getSupporterAmountCents(metadata = {}) {
  return Number(metadata.support_amount_cents || metadata.amount_cents || 0);
}

function isSupporterMetadata(metadata = {}) {
  return metadata.source === SUPPORTER_SOURCE;
}

async function upsertSupporterSubscription(fields) {
  if (!fields?.user_id || !fields?.support_amount_cents) return;

  const nextRow = {
    ...fields,
    updated_at: new Date().toISOString(),
  };

  let existing = null;
  if (fields.stripe_subscription_id) {
    const { data } = await supabase
      .from("supporter_subscriptions")
      .select("id")
      .eq("stripe_subscription_id", fields.stripe_subscription_id)
      .maybeSingle();
    existing = data;
  }

  if (!existing && fields.stripe_checkout_session_id) {
    const { data } = await supabase
      .from("supporter_subscriptions")
      .select("id")
      .eq("stripe_checkout_session_id", fields.stripe_checkout_session_id)
      .maybeSingle();
    existing = data;
  }

  const result = existing?.id
    ? await supabase.from("supporter_subscriptions").update(nextRow).eq("id", existing.id)
    : await supabase.from("supporter_subscriptions").insert(nextRow);

  if (result.error) console.error("supporter_subscriptions write failed", result.error);
}

async function markSupporterPaymentFailed(subscriptionId) {
  if (!subscriptionId) return;

  const { data: existing } = await supabase
    .from("supporter_subscriptions")
    .select("user_id")
    .eq("stripe_subscription_id", subscriptionId)
    .maybeSingle();

  await supabase
    .from("supporter_subscriptions")
    .update({ status: "payment_failed", updated_at: new Date().toISOString() })
    .eq("stripe_subscription_id", subscriptionId);

  if (existing?.user_id) {
    await supabase.from("profiles").update({
      subscription_active: false,
      subscription_status: "payment_failed",
    }).eq("id", existing.user_id);
  }
}

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
      const metadata = session.metadata || {};
      const userId = metadata.user_id;
      const amountCents = getSupporterAmountCents(metadata);
      const role = session.metadata?.role || "customer";
      const subscriptionId = typeof session.subscription === "string" ? session.subscription : session.subscription?.id;
      const customerId = typeof session.customer === "string" ? session.customer : session.customer?.id;

      if (userId && isSupporterMetadata(metadata)) {
        await upsertSupporterSubscription({
          user_id: userId,
          stripe_customer_id: customerId || null,
          stripe_subscription_id: subscriptionId || null,
          stripe_checkout_session_id: session.id,
          support_amount_cents: amountCents,
          status: "active",
        });

        await supabase.from("profiles").update({
          subscription_type: "customer_supporter",
          subscription_amount: amountCents / 100,
          subscription_active: true,
          subscription_status: "active",
          stripe_customer_id: customerId || null,
          stripe_subscription_id: subscriptionId || null,
        }).eq("id", userId);
      } else if (userId) {
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
    case "customer.subscription.updated": {
      const subscription = event.data.object;
      const metadata = subscription.metadata || {};
      const userId = metadata.user_id;
      if (userId && isSupporterMetadata(metadata)) {
        const amountCents = getSupporterAmountCents(metadata);
        await upsertSupporterSubscription({
          user_id: userId,
          stripe_customer_id: typeof subscription.customer === "string" ? subscription.customer : subscription.customer?.id || null,
          stripe_subscription_id: subscription.id,
          support_amount_cents: amountCents,
          status: subscription.status || "updated",
          current_period_start: toTimestamp(subscription.current_period_start),
          current_period_end: toTimestamp(subscription.current_period_end),
        });

        await supabase.from("profiles").update({
          subscription_type: "customer_supporter",
          subscription_amount: amountCents / 100,
          subscription_active: subscription.status === "active" || subscription.status === "trialing",
          subscription_status: subscription.status || "updated",
          stripe_subscription_id: subscription.id,
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
    case "customer.subscription.deleted": {
      const subscription = event.data.object;
      const metadata = subscription.metadata || {};
      const subId = subscription.id;
      if (isSupporterMetadata(metadata)) {
        await supabase
          .from("supporter_subscriptions")
          .update({
            status: subscription.status || "cancelled",
            current_period_start: toTimestamp(subscription.current_period_start),
            current_period_end: toTimestamp(subscription.current_period_end),
            updated_at: new Date().toISOString(),
          })
          .eq("stripe_subscription_id", subId);
      }
      if (subId) await supabase.from("profiles").update({ subscription_active: false, subscription_status: "cancelled" }).eq("stripe_subscription_id", subId);
      break;
    }
    case "invoice.payment_failed": {
      const invoice = event.data.object;
      const subId = typeof invoice.subscription === "string" ? invoice.subscription : invoice.subscription?.id;
      await markSupporterPaymentFailed(subId);
      if (subId) await supabase.from("profiles").update({ subscription_active: false, subscription_status: "cancelled" }).eq("stripe_subscription_id", subId);
      break;
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200,
  });
});
