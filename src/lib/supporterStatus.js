import { supabase } from "./supabase";

// Fetch the authenticated user's active/trialing supporter subscription row, or
// null. RLS allows a user to read only their own supporter_subscriptions rows.
// Selects no Stripe IDs — only the fields the UI needs (status/quantity/amount).
// Used as a safe fallback when the profile row hasn't been flipped by the
// Stripe webhook yet (both for app entry and the dashboard display).
export async function fetchActiveSupporterSubscription(uid) {
  if (!uid) return null;
  const { data, error } = await supabase
    .from("supporter_subscriptions")
    .select("status, quantity, amount_cents")
    .eq("user_id", uid)
    .in("status", ["active", "trialing"])
    .order("created_at", { ascending: false })
    .limit(1);
  if (error || !Array.isArray(data) || !data.length) return null;
  return data[0];
}
