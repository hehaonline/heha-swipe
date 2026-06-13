const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function getRequiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required env variable: ${name}`);
  return value;
}

function normalizeAmount(value: unknown) {
  const amount = Number(value);
  if (!Number.isInteger(amount) || amount < 1 || amount > 100) {
    throw new Error("Support amount must be a whole dollar amount between $1 and $100.");
  }
  return amount;
}

function normalizeRole(value: unknown) {
  return value === "partner" ? "partner" : "customer";
}

async function getAuthenticatedUser(authorizationHeader: string) {
  const supabaseUrl = getRequiredEnv("SUPABASE_URL");
  const supabaseAnonKey = getRequiredEnv("SUPABASE_ANON_KEY");

  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      Authorization: authorizationHeader,
      apikey: supabaseAnonKey,
    },
  });

  if (!response.ok) {
    throw new Error("You must be signed in to start supporter checkout.");
  }

  return response.json();
}

async function createStripeCheckoutSession({
  amount,
  role,
  userId,
  email,
}: {
  amount: number;
  role: "customer" | "partner";
  userId: string;
  email?: string | null;
}) {
  const stripeSecretKey = getRequiredEnv("STRIPE_SECRET_KEY");
  const appUrl = Deno.env.get("HEHA_SWIPE_URL") || "https://hehaswipe.app";
  const unitAmount = amount * 100;

  const params = new URLSearchParams();
  params.set("mode", "subscription");
  params.set("success_url", `${appUrl}/?checkout=success&type=supporter&role=${role}`);
  params.set("cancel_url", `${appUrl}/?checkout=cancel&type=supporter&role=${role}`);
  params.set("client_reference_id", userId);
  if (email) params.set("customer_email", email);

  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set("line_items[0][price_data][unit_amount]", String(unitAmount));
  params.set("line_items[0][price_data][recurring][interval]", "month");
  params.set("line_items[0][price_data][product_data][name]", "HEHA Swipe Supporter Membership");
  params.set(
    "line_items[0][price_data][product_data][description]",
    "Choose-your-own monthly supporter contribution for HEHA Swipe and the local healthy business network."
  );

  params.set("metadata[payment_type]", "supporter_subscription");
  params.set("metadata[user_id]", userId);
  params.set("metadata[role]", role);
  params.set("metadata[support_amount]", String(amount));
  params.set("subscription_data[metadata][payment_type]", "supporter_subscription");
  params.set("subscription_data[metadata][user_id]", userId);
  params.set("subscription_data[metadata][role]", role);
  params.set("subscription_data[metadata][support_amount]", String(amount));

  const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeSecretKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params,
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data?.error?.message || "Stripe checkout session could not be created.");
  }

  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const authorizationHeader = req.headers.get("Authorization");
    if (!authorizationHeader) {
      return jsonResponse({ error: "Missing Authorization header." }, 401);
    }

    const body = await req.json();
    const amount = normalizeAmount(body?.amount);
    const role = normalizeRole(body?.role);
    const user = await getAuthenticatedUser(authorizationHeader);

    const session = await createStripeCheckoutSession({
      amount,
      role,
      userId: user.id,
      email: user.email,
    });

    return jsonResponse({ url: session.url, id: session.id });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Could not start supporter checkout." },
      400
    );
  }
});
