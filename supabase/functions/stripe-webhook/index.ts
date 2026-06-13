import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
const stripeWebhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!stripeSecretKey) throw new Error("Missing STRIPE_SECRET_KEY");
if (!stripeWebhookSecret) throw new Error("Missing STRIPE_WEBHOOK_SECRET");
if (!supabaseUrl) throw new Error("Missing SUPABASE_URL");
if (!supabaseServiceRoleKey) throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY");

const stripe = new Stripe(stripeSecretKey, {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, stripe-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function roleSubscriptionType(role?: string) {
  return role === "partner" ? "partner_supporter" : "customer_supporter";
}

function isActiveSubscriptionStatus(status?: string | null) {
  return status === "active" || status === "trialing";
}

function getSubscriptionAmount(subscription: Stripe.Subscription) {
  const amountCents = subscription.items?.data?.[0]?.price?.unit_amount;
  return typeof amountCents === "number" ? amountCents / 100 : null;
}

function getCurrentPeriodEnd(subscription: Stripe.Subscription) {
  return subscription.current_period_end
    ? new Date(subscription.current_period_end * 1000).toISOString()
    : null;
}

async function updateProfileByUserId(userId: string, fields: Record<string, unknown>) {
  const { error } = await supabase.from("profiles").update(fields).eq("id", userId);
  if (error) throw error;
}

async function updateProfileBySubscriptionId(subscriptionId: string, fields: Record<string, unknown>) {
  const { error } = await supabase
    .from("profiles")
    .update(fields)
    .eq("stripe_subscription_id", subscriptionId);
  if (error) throw error;
}

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  if (session.metadata?.payment_type !== "supporter_subscription") return;

  const userId = session.metadata?.user_id || session.client_reference_id;
  if (!userId) throw new Error("Supporter checkout session is missing user_id metadata.");

  const role = session.metadata?.role || "customer";
  const amount = Number(session.metadata?.support_amount || 0) || null;

  await updateProfileByUserId(userId, {
    stripe_customer_id: typeof session.customer === "string" ? session.customer : null,
    stripe_subscription_id: typeof session.subscription === "string" ? session.subscription : null,
    subscription_type: roleSubscriptionType(role),
    subscription_active: true,
    subscription_status: "active",
    subscription_amount: amount,
    updated_at: new Date().toISOString(),
  });
}

async function handleSubscriptionLifecycle(subscription: Stripe.Subscription) {
  if (subscription.metadata?.payment_type !== "supporter_subscription") return;

  const amount = getSubscriptionAmount(subscription);
  const role = subscription.metadata?.role || "customer";
  const updateFields: Record<string, unknown> = {
    stripe_customer_id: typeof subscription.customer === "string" ? subscription.customer : null,
    stripe_subscription_id: subscription.id,
    subscription_type: roleSubscriptionType(role),
    subscription_active: isActiveSubscriptionStatus(subscription.status),
    subscription_status: subscription.status,
    subscription_current_period_end: getCurrentPeriodEnd(subscription),
    updated_at: new Date().toISOString(),
  };

  if (amount !== null) updateFields.subscription_amount = amount;

  const userId = subscription.metadata?.user_id;
  if (userId) {
    await updateProfileByUserId(userId, updateFields);
  } else {
    await updateProfileBySubscriptionId(subscription.id, updateFields);
  }
}

async function handleInvoiceEvent(invoice: Stripe.Invoice, status: "active" | "past_due") {
  const subscriptionId = typeof invoice.subscription === "string" ? invoice.subscription : null;
  if (!subscriptionId) return;

  await updateProfileBySubscriptionId(subscriptionId, {
    subscription_active: status === "active",
    subscription_status: status,
    updated_at: new Date().toISOString(),
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const signature = req.headers.get("stripe-signature");
  if (!signature) return jsonResponse({ error: "Missing Stripe signature." }, 400);

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, stripeWebhookSecret);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown webhook signature error";
    return jsonResponse({ error: `Webhook Error: ${message}` }, 400);
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session);
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
        await handleSubscriptionLifecycle(event.data.object as Stripe.Subscription);
        break;
      case "invoice.payment_succeeded":
        await handleInvoiceEvent(event.data.object as Stripe.Invoice, "active");
        break;
      case "invoice.payment_failed":
        await handleInvoiceEvent(event.data.object as Stripe.Invoice, "past_due");
        break;
      default:
        break;
    }

    return jsonResponse({ received: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Webhook processing failed.";
    return jsonResponse({ error: message }, 400);
  }
});
