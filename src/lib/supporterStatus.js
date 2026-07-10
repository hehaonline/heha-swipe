import { supabase } from "./supabase";

// Fetch the authenticated user's canonical live supporter entitlement, or null.
// The no-argument RPC derives the user from auth.uid(); the browser cannot ask
// for another user's subscription and receives no Stripe IDs or metadata.
export async function fetchActiveSupporterSubscription(uid) {
  if (!uid) return null;
  const { data, error } = await supabase.rpc("get_my_active_supporter_entitlement");
  if (error || !Array.isArray(data) || !data.length) return null;
  return data[0];
}
