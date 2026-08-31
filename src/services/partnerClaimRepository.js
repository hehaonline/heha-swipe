import { supabase } from "../lib/supabase";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PRIVATE_STATUSES = new Set(["draft", "submitted", "pending", "missing_info"]);
const GENERIC_CLAIM_ERROR = "This private invitation could not be verified. Ask HEHA for a new protected link.";

function rpcObject(value) {
  if (Array.isArray(value)) return value[0] || null;
  return value && typeof value === "object" ? value : null;
}

export async function claimPartnerInvitation({ actorId, requestKey, inviteToken }) {
  try {
    const { data, error } = await supabase.rpc("claim_partner_invitation_v1", {
      p_invite_token: inviteToken,
      p_request_key: requestKey,
    });
    if (error) throw new Error(GENERIC_CLAIM_ERROR);

    const result = rpcObject(data);
    if (!result
        || result.receipt_status !== "verified"
        || !UUID_PATTERN.test(String(result.id || ""))
        || !UUID_PATTERN.test(String(result.owner_id || ""))
        || !UUID_PATTERN.test(String(result.claim_evidence_id || ""))
        || result.owner_id !== actorId
        || result.request_key !== requestKey
        || !PRIVATE_STATUSES.has(String(result.status || "").toLowerCase())) {
      throw new Error(GENERIC_CLAIM_ERROR);
    }
    return result;
  } catch {
    throw new Error(GENERIC_CLAIM_ERROR);
  }
}
