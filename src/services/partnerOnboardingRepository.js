import { supabase } from "../lib/supabase";

const SUBMISSION_STATUS_FIELDS =
  "id, name, category, status, created_at, updated_at, complete_pct, heha_partner";

export function normalizeInstagram(value) {
  return String(value || "").trim().replace(/^@/, "");
}

export function calculatePartnerCompletion(form) {
  return [
    form?.name,
    form?.category,
    form?.neighborhood,
    form?.tagline,
    form?.bio,
    form?.phone || form?.contact,
    form?.website,
    form?.instagram,
    Array.isArray(form?.offerings) && form.offerings.length > 0,
    Array.isArray(form?.items) && form.items.length > 0,
  ].filter(Boolean).length * 10;
}

export function buildPartnerListingPayload({ ownerId, form }) {
  if (!ownerId) throw new Error("A signed-in owner is required to register a business.");

  return {
    owner_id: ownerId,
    name: String(form?.name || "").trim(),
    category: form?.category || null,
    neighborhood: String(form?.neighborhood || "").trim(),
    tagline: String(form?.tagline || "").trim(),
    bio: String(form?.bio || "").trim(),
    hours: String(form?.hours || "").trim() || null,
    business_type: String(form?.business_type || "").trim() || null,
    phone: String(form?.phone || "").trim() || null,
    contact: String(form?.contact || "").trim() || null,
    website: String(form?.website || "").trim() || null,
    instagram: normalizeInstagram(form?.instagram) || null,
    location: String(form?.location || "").trim() || null,
    offerings: Array.isArray(form?.offerings) ? form.offerings : [],
    items: Array.isArray(form?.items) ? form.items : [],
    photo_emoji: form?.photo_emoji || "🏪",
    color: form?.color || "#ff8a24",
    status: "pending",
    complete_pct: calculatePartnerCompletion(form),
    heha_partner: false,
  };
}

export async function createPartnerListing({ ownerId, form }) {
  const payload = buildPartnerListingPayload({ ownerId, form });
  const { data, error } = await supabase.from("partners").insert(payload).select().single();
  if (error) throw error;
  return data;
}

export async function getPartnerSubmissionStatus({ partnerId, ownerId }) {
  if (!partnerId || !ownerId) return null;

  const { data, error } = await supabase
    .from("partners")
    .select(SUBMISSION_STATUS_FIELDS)
    .eq("id", partnerId)
    .eq("owner_id", ownerId)
    .maybeSingle();

  if (error) throw error;
  return data || null;
}

export async function notifyPartnerApprovalRequested({ listing, ownerContact }) {
  const webhookUrl = import.meta.env.VITE_MAKE_PARTNER_APPROVAL_WEBHOOK;
  if (!webhookUrl || !listing?.id) return { status: "skipped" };

  try {
    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        partner_id: listing.id,
        partner_name: listing.name,
        category: listing.category,
        neighborhood: listing.neighborhood,
        owner_email: ownerContact || null,
        status: "pending_review",
      }),
    });

    return response.ok
      ? { status: "sent" }
      : { status: "failed", httpStatus: response.status };
  } catch (error) {
    // Registration must remain successful when an external notification fails.
    return { status: "failed", error };
  }
}
