import { supabase } from "../lib/supabase";
import { normalizePartnerOnboardingAssignments } from "../lib/partnerOnboardingAssignments";
import { normalizePartnerOnboardingCapabilities } from "../lib/partnerOnboardingCapabilities";

const GENERIC_CAPABILITY_ERROR = "Partner release receipts are not available for this account.";
const GENERIC_ASSIGNMENT_ERROR = "Partner setup assignments are not available for this account.";

function rpcObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}

export async function loadPartnerOnboardingCapabilities(partnerId, actorId) {
  try {
    const { data, error } = await supabase.rpc("get_partner_onboarding_capabilities_v1", {
      p_partner_id: partnerId,
    });
    if (error) throw new Error(GENERIC_CAPABILITY_ERROR);

    return normalizePartnerOnboardingCapabilities(rpcObject(data), { partnerId, actorId });
  } catch {
    throw new Error(GENERIC_CAPABILITY_ERROR);
  }
}

export async function loadMyPartnerOnboardingAssignments(actorId) {
  try {
    const { data, error } = await supabase.rpc("list_my_partner_onboarding_assignments_v1");
    if (error) throw new Error(GENERIC_ASSIGNMENT_ERROR);
    return normalizePartnerOnboardingAssignments(rpcObject(data), actorId).assignments;
  } catch {
    throw new Error(GENERIC_ASSIGNMENT_ERROR);
  }
}
