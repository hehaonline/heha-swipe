import { supabase } from "../lib/supabase";

export const PARTNER_PROFILE_SELECT =
  "id, name, category, status, created_at, updated_at, complete_pct, heha_partner, image_url, logo_url, gallery_urls, neighborhood, tagline, bio, tags, offerings, items, website, instagram, price_range, photo_emoji, color, location, hours, contact, business_type, phone, delivery_days, pricing_notes";

const CHANGE_REQUEST_SELECT = "id, status, submitted_at, review_note";

export async function getLatestPartnerProfileChangeRequest({ partnerId, ownerId }) {
  if (!partnerId || !ownerId) return null;

  const { data, error } = await supabase
    .from("partner_profile_change_requests")
    .select(CHANGE_REQUEST_SELECT)
    .eq("partner_id", partnerId)
    .eq("owner_id", ownerId)
    .order("submitted_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return data || null;
}

export async function updatePartnerProfile({ partnerId, ownerId, changes }) {
  if (!partnerId || !ownerId) throw new Error("A valid business owner is required.");

  const { data, error } = await supabase
    .from("partners")
    .update(changes)
    .eq("id", partnerId)
    .eq("owner_id", ownerId)
    .select(PARTNER_PROFILE_SELECT)
    .single();

  if (error) throw error;
  return data;
}

export async function submitPartnerProfileChangeRequest({ partnerId, ownerId, changes }) {
  if (!partnerId || !ownerId) throw new Error("A valid business owner is required.");

  const { data, error } = await supabase
    .from("partner_profile_change_requests")
    .insert({
      partner_id: partnerId,
      owner_id: ownerId,
      proposed_changes: changes,
    })
    .select(CHANGE_REQUEST_SELECT)
    .single();

  if (error) throw error;
  return data;
}
