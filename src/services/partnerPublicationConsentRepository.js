import { supabase } from "../lib/supabase";
import { PARTNER_PROFILE_CONSENT_VERSION } from "../lib/partnerPublicationConsent";

function clean(value) {
  const normalized = String(value || "").trim();
  return normalized || null;
}

export async function submitPartnerRegistrationWithConsent({
  form,
  authorization,
  submissionKey,
}) {
  const { data, error } = await supabase.rpc("submit_partner_registration_with_consent", {
    p_submission_key: submissionKey,
    p_name: form.name.trim(),
    p_categories: form.categories,
    p_neighborhood: form.neighborhood.trim(),
    p_tagline: form.tagline.trim(),
    p_bio: form.bio.trim(),
    p_hours: clean(form.hours),
    p_delivery_days: form.deliveryDays,
    p_business_type: clean(form.business_type),
    p_phone: clean(form.phone),
    p_contact: clean(form.contact),
    p_website: clean(form.website),
    p_instagram: clean(form.instagram),
    p_location: clean(form.location),
    p_offerings: form.offerings,
    p_items: form.items,
    p_photo_emoji: form.photo_emoji,
    p_color: form.color,
    p_destinations: authorization.destinations,
    p_authorized_representative_name: authorization.representativeName.trim(),
    p_authorized_representative_title: authorization.representativeTitle.trim(),
    p_media_permission_confirmed: authorization.mediaPermissionConfirmed,
    p_tampa_bay_service_confirmed: authorization.tampaBayServiceConfirmed,
    p_consent_statement_version: PARTNER_PROFILE_CONSENT_VERSION,
  });

  if (error) throw error;
  return data;
}

export async function authorizeExistingPartnerProfilePreparation({
  partnerId,
  authorization,
  requestKey,
}) {
  const { data, error } = await supabase.rpc("authorize_existing_partner_profile_preparation", {
    p_partner_id: partnerId,
    p_destinations: authorization.destinations,
    p_authorized_representative_name: authorization.representativeName.trim(),
    p_authorized_representative_title: authorization.representativeTitle.trim(),
    p_media_permission_confirmed: authorization.mediaPermissionConfirmed,
    p_tampa_bay_service_confirmed: authorization.tampaBayServiceConfirmed,
    p_request_key: requestKey,
    p_consent_statement_version: PARTNER_PROFILE_CONSENT_VERSION,
  });

  if (error) throw error;
  return data;
}

export async function authorizePartnerProfilePublication({
  partnerId,
  destinations,
  representativeName,
  representativeTitle,
  requestKey,
  expectedProfileSnapshotHash,
}) {
  const { data, error } = await supabase.rpc("authorize_partner_profile_publication", {
    p_partner_id: partnerId,
    p_destinations: destinations,
    p_authorized_representative_name: representativeName.trim(),
    p_authorized_representative_title: representativeTitle.trim(),
    p_request_key: requestKey,
    p_consent_statement_version: PARTNER_PROFILE_CONSENT_VERSION,
    p_expected_profile_snapshot_hash: expectedProfileSnapshotHash,
  });

  if (error) throw error;
  return data;
}

export async function getMyPartnerPublicationStatus(partnerId) {
  const { data, error } = await supabase.rpc("get_my_partner_publication_status", {
    p_partner_id: partnerId,
  });

  if (error) throw error;
  return data;
}
