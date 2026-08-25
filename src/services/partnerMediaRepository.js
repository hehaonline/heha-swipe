import { supabase } from "../lib/supabase";

export const PARTNER_MEDIA_BUCKET = "partner-media-pending";
export const PARTNER_MEDIA_ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];
export const PARTNER_MEDIA_MAX_FILE_SIZE = 8 * 1024 * 1024;

const MEDIA_REQUEST_SELECT =
  "id, media_type, change_type, storage_path, replaces_url, original_filename, position, status, submitted_at, review_note";

export function safePartnerMediaFilename(name) {
  const clean = String(name || "photo")
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return clean || "photo";
}

export function validatePartnerMediaFile(file) {
  if (!file) return "Choose an image to upload.";
  if (!PARTNER_MEDIA_ALLOWED_TYPES.includes(file.type)) {
    return "Please upload a JPG, PNG, or WEBP image.";
  }
  if (file.size > PARTNER_MEDIA_MAX_FILE_SIZE) {
    return "Please keep each image at 8 MB or less.";
  }
  return null;
}

export function buildPartnerMediaStoragePath({ ownerId, partnerId, filename }) {
  if (!ownerId || !partnerId) throw new Error("A valid owner and business are required.");
  const unique =
    typeof crypto?.randomUUID === "function"
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return `${ownerId}/${partnerId}/${unique}-${safePartnerMediaFilename(filename)}`;
}

async function createSignedPreview(storagePath) {
  if (!storagePath) return null;
  const { data, error } = await supabase.storage
    .from(PARTNER_MEDIA_BUCKET)
    .createSignedUrl(storagePath, 60 * 30);
  return error ? null : data?.signedUrl || null;
}

export async function listPartnerMediaRequests({ partnerId, ownerId }) {
  if (!partnerId || !ownerId) return [];

  const { data, error } = await supabase
    .from("partner_media_requests")
    .select(MEDIA_REQUEST_SELECT)
    .eq("partner_id", partnerId)
    .eq("owner_id", ownerId)
    .order("submitted_at", { ascending: false });

  if (error) throw error;

  return Promise.all(
    (data || []).map(async (request) => ({
      ...request,
      preview_url: await createSignedPreview(request.storage_path),
    }))
  );
}

export async function submitPartnerMediaUpload({ partnerId, ownerId, file, target }) {
  const validationError = validatePartnerMediaFile(file);
  if (validationError) throw new Error(validationError);
  if (!target?.mediaType || !target?.changeType) throw new Error("Choose where this image belongs.");

  const storagePath = buildPartnerMediaStoragePath({
    ownerId,
    partnerId,
    filename: file.name,
  });

  const { error: uploadError } = await supabase.storage
    .from(PARTNER_MEDIA_BUCKET)
    .upload(storagePath, file, {
      cacheControl: "3600",
      upsert: false,
      contentType: file.type,
    });
  if (uploadError) throw uploadError;

  const { error: requestError } = await supabase.from("partner_media_requests").insert({
    partner_id: partnerId,
    owner_id: ownerId,
    media_type: target.mediaType,
    change_type: target.changeType,
    storage_path: storagePath,
    replaces_url: target.replacesUrl || null,
    original_filename: file.name,
    mime_type: file.type,
    file_size_bytes: file.size,
    position: target.position || 0,
  });

  if (requestError) {
    await supabase.storage.from(PARTNER_MEDIA_BUCKET).remove([storagePath]);
    throw requestError;
  }

  return { storagePath };
}

export async function submitPartnerMediaRemoval({
  partnerId,
  ownerId,
  mediaType,
  currentUrl,
  position = 0,
}) {
  if (!partnerId || !ownerId || !mediaType || !currentUrl) {
    throw new Error("The media removal request is incomplete.");
  }

  const { error } = await supabase.from("partner_media_requests").insert({
    partner_id: partnerId,
    owner_id: ownerId,
    media_type: mediaType,
    change_type: "remove",
    replaces_url: currentUrl,
    position,
  });

  if (error) throw error;
}
