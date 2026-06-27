import { supabase } from "./supabase";

// Single canonical entry point for HEHA Swipe supporter checkout.
// Wraps the already-deployed `create-supporter-checkout` Edge Function (PR #26)
// so onboarding and the Community Pass dashboard share ONE Stripe entry point —
// no duplicated Stripe logic, no new checkout function.
//
// The deployed checkout uses a fixed $1/month price, so the selected monthly
// dollar amount maps directly to quantity ($10/month => quantity 10).
// On success this redirects the browser to Stripe Checkout. Throws on failure
// so callers can surface a safe message.
export async function startSupporterCheckout(amount) {
  const quantity = Number(amount);
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > 100) {
    throw new Error("Supporter checkout is not available yet. Please try again later.");
  }

  // Forward the active Supabase session token so the Edge Function can verify the user.
  const { data: sessionData } = await supabase.auth.getSession();
  const accessToken = sessionData?.session?.access_token;
  if (!accessToken) {
    throw new Error("Please sign in again to start monthly support.");
  }

  const origin = window.location.origin;
  const { data, error: checkoutError } = await supabase.functions.invoke("create-supporter-checkout", {
    body: {
      quantity,
      successUrl: `${origin}/support/success`,
      cancelUrl: `${origin}/support/cancel`,
    },
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  const checkoutUrl = data?.checkoutUrl;
  if (checkoutError || !checkoutUrl) {
    console.error("Supporter checkout failed", checkoutError || data);
    throw new Error("Supporter checkout is not available yet. Please try again later.");
  }

  window.location.assign(checkoutUrl);
}
