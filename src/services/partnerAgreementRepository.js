import { supabase } from "../lib/supabase";
import {
  canonicalJson,
  sha256Utf8Hex,
  validateAcceptanceReceipt,
  validateAgreementEnvelope,
  verifyAgreementDocumentDigest,
} from "../lib/partnerAgreementVerification";

const GENERIC_AGREEMENT_ERROR = "This protected agreement is not available for this account. Ask HEHA to review access.";

function rpcObject(value) {
  if (Array.isArray(value)) return value[0] || null;
  return value && typeof value === "object" ? value : null;
}

export async function loadPartnerAgreementForAcceptance(partnerId, actorId) {
  try {
    const { data, error } = await supabase.rpc("get_partner_agreement_for_acceptance_v1", {
      p_partner_id: partnerId,
    });
    if (error) throw new Error(GENERIC_AGREEMENT_ERROR);
    const agreement = validateAgreementEnvelope(rpcObject(data), partnerId, actorId);
    return await verifyAgreementDocumentDigest(agreement);
  } catch {
    throw new Error(GENERIC_AGREEMENT_ERROR);
  }
}

export async function recordPartnerAgreementAcceptance({
  partnerId,
  actorId,
  agreement,
  requestKey,
  assertions,
}) {
  try {
    const { data, error } = await supabase.rpc("record_category_partner_agreement_acceptance_v1", {
      p_partner_id: partnerId,
      p_agreement_version_id: agreement.agreement_version_id,
      p_expected_document_sha256: agreement.document_sha256,
      p_request_key: requestKey,
      p_assertions: assertions,
    });
    if (error) throw new Error(GENERIC_AGREEMENT_ERROR);
    const expectedAssertionsSha256 = await sha256Utf8Hex(canonicalJson(assertions));
    return validateAcceptanceReceipt(rpcObject(data), {
      partnerId,
      actorId,
      agreement,
      requestKey,
      assertions,
      expectedAssertionsSha256,
    });
  } catch {
    throw new Error(GENERIC_AGREEMENT_ERROR);
  }
}
