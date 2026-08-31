import { supabase } from "../lib/supabase";
import {
  preparePartnerApplication,
  validatePartnerApplicationReceipt,
  validatePartnerProfileCorrectionReceipt,
} from "../lib/partnerApplicationReceipt";

const GENERIC_APPLICATION_ERROR = "This private partner application could not be saved. Ask HEHA for a protected link or support.";

function rpcObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}

export async function revisePartnerProfile({
  actorId,
  partnerId,
  requestKey,
  profileSnapshot,
}) {
  try {
    const prepared = await preparePartnerApplication(profileSnapshot);
    const { data, error } = await supabase.rpc("revise_partner_profile_v1", {
      p_partner_id: partnerId,
      p_request_key: requestKey,
      p_profile_snapshot: prepared.application,
    });
    if (error) throw new Error(GENERIC_APPLICATION_ERROR);

    return validatePartnerProfileCorrectionReceipt(rpcObject(data), {
      actorId,
      partnerId,
      requestKey,
      expectedSubmittedSha256: prepared.applicationSha256,
    });
  } catch {
    throw new Error(GENERIC_APPLICATION_ERROR);
  }
}

export async function createOrResumePartnerApplication({ actorId, requestKey, application }) {
  try {
    const prepared = await preparePartnerApplication(application);
    const { data, error } = await supabase.rpc("create_or_resume_partner_application_v1", {
      p_request_key: requestKey,
      p_application: prepared.application,
    });
    if (error) throw new Error(GENERIC_APPLICATION_ERROR);

    return validatePartnerApplicationReceipt(rpcObject(data), {
      actorId,
      requestKey,
      expectedApplicationSha256: prepared.applicationSha256,
    });
  } catch {
    throw new Error(GENERIC_APPLICATION_ERROR);
  }
}
