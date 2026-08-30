import { supabase } from "../lib/supabase";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PRIVATE_STATUSES = new Set(["draft", "submitted", "pending", "missing_info"]);
const GENERIC_APPLICATION_ERROR = "This private partner application could not be saved. Ask HEHA for a protected link or support.";

function rpcObject(value) {
  if (Array.isArray(value)) return value[0] || null;
  return value && typeof value === "object" ? value : null;
}

export async function createOrResumePartnerApplication({ actorId, requestKey, application }) {
  try {
    const { data, error } = await supabase.rpc("create_or_resume_partner_application_v1", {
      p_request_key: requestKey,
      p_application: application,
    });
    if (error) throw new Error(GENERIC_APPLICATION_ERROR);

    const result = rpcObject(data);
    if (!result
        || !UUID_PATTERN.test(String(result.id || ""))
        || !UUID_PATTERN.test(String(result.owner_id || ""))
        || !UUID_PATTERN.test(String(result.request_key || ""))
        || result.owner_id !== actorId
        || result.request_key !== requestKey
        || !PRIVATE_STATUSES.has(String(result.status || "").toLowerCase())) {
      throw new Error(GENERIC_APPLICATION_ERROR);
    }
    return result;
  } catch {
    throw new Error(GENERIC_APPLICATION_ERROR);
  }
}
