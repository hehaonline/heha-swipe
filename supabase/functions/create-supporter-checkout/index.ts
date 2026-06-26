import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPPORTER_SOURCE = "heha_swipe_supporter";
const PRODUCT_NAME = "HEHA Swipe Monthly Supporter";
const SUCCESS_URL = "https://hehaswipe.app/support/success?session_id={CHECKOUT_SESSION_ID}";
const CANCEL_URL = "https://hehaswipe.app/support/cancel";

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authHeader = req.headers.get("Authorization") || "";

  if (!stripeSecretKey || !supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: "supporter_checkout_unavailable" }, 503);
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData?.user?.id) {
      return jsonResponse({ error: "not_authenticated" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const supportAmount = Number(body.support_amount);
    if (!Number.isInteger(supportAmount) || supportAmount < 1 || supportAmount > 100) {
      return jsonResponse({ error: "invalid_support_amount" }, 400);
    }

    const user = authData.user;
    const supportAmountCents = supportAmount * 100;
    const metadata = {
      source: SUPPORTER_SOURCE,
      user_id: user.id,
      support_amount: String(supportAmount),
      support_amount_cents: String(supportAmountCents),
    };

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [
        {
          price_data: {
            currency: "usd",
            unit_amount: supportAmountCents,
            recurring: { interval: "month" },
            product_data: { name: PRODUCT_NAME },
          },
          quantity: 1,
        },
      ],
      success_url: SUCCESS_URL,
      cancel_url: CANCEL_URL,
      client_reference_id: user.id,
      customer_email: user.email || undefined,
      metadata,
      subscription_data: { metadata },
      allow_promotion_codes: true,
    });

    if (!session.url) return jsonResponse({ error: "supporter_checkout_unavailable" }, 503);
    return jsonResponse({ url: session.url });
  } catch (error) {
    console.error("create-supporter-checkout failed", error);
    return jsonResponse({ error: "supporter_checkout_unavailable" }, 503);
  }
});
