import { supabase } from "./supabase";

// Fetch the authenticated user's canonical live supporter entitlement, or null.
// The sanitized Supabase view exposes no Stripe IDs or metadata and only returns
// active/trialing LIVE supporter rows through the base table's RLS contract.
export async function fetchActiveSupporterSubscription(uid) {
  if (!uid) return null;
  const { data, error } = await supabase
    .from("my_active_supporter_entitlements")
    .select("status, quantity, amount_cents")
    .eq("user_id", uid)
    .limit(1);
  if (error || !Array.isArray(data) || !data.length) return null;
  return data[0];
}
