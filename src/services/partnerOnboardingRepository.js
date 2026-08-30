import { supabase } from "../lib/supabase";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function rpcObject(value) {
  if (Array.isArray(value)) return value[0] || null;
  return value && typeof value === "object" ? value : null;
}

export async function loadPartnerOnboardingCapabilities(partnerId, actorId) {
  const { data, error } = await supabase.rpc("get_partner_onboarding_capabilities_v1", {
    p_partner_id: partnerId,
  });
  if (error) throw error;

  const capabilities = rpcObject(data);
  if (!capabilities) throw new Error("Partner release receipts are not connected.");
  if (capabilities.projection_version !== "heha-partner-onboarding-v1") {
    throw new Error("Partner release receipts use an unsupported projection version.");
  }
  if (!UUID_PATTERN.test(String(capabilities.partner_id || ""))
      || !UUID_PATTERN.test(String(capabilities.authorized_actor_id || ""))
      || capabilities.partner_id !== partnerId
      || capabilities.authorized_actor_id !== actorId) {
    throw new Error("Partner release receipts do not match this partner account.");
  }
  return capabilities;
}
