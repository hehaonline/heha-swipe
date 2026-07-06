import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";

const BUCKET = "partner-media-pending";
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_FILE_SIZE = 8 * 1024 * 1024;

function formatStatus(value) {
  return String(value || "submitted")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function safeFilename(name) {
  const clean = String(name || "photo")
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return clean || "photo";
}

function requestLabel(request) {
  const action = formatStatus(request.change_type);
  const media = formatStatus(request.media_type);
  return `${action} ${media}`;
}

export default function PartnerMediaManager({ user, listing, onClose, onChanged }) {
  const fileInputRef = useRef(null);
  const uploadTargetRef = useRef(null);
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);

  const currentGallery = useMemo(
    () => (Array.isArray(listing?.gallery_urls) ? listing.gallery_urls.filter(Boolean).slice(0, 6) : []),
    [listing?.gallery_urls]
  );

  const loadRequests = useCallback(async () => {
    if (!user?.id || !listing?.id) return;
    setLoading(true);
    setError(null);

    try {
      const { data, error: requestError } = await supabase
        .from("partner_media_requests")
        .select("id, media_type, change_type, storage_path, replaces_url, original_filename, position, status, submitted_at, review_note")
        .eq("partner_id", listing.id)
        .eq("owner_id", user.id)
        .order("submitted_at", { ascending: false });

      if (requestError) throw requestError;

      const hydrated = await Promise.all(
        (data || []).map(async (request) => {
          if (!request.storage_path) return { ...request, preview_url: null };
          const { data: signed, error: signedError } = await supabase.storage
            .from(BUCKET)
            .createSignedUrl(request.storage_path, 60 * 30);
          return {
            ...request,
            preview_url: signedError ? null : signed?.signedUrl || null,
          };
        })
      );

      setRequests(hydrated);
    } catch (loadError) {
      setError(loadError.message || "Could not load your media requests.");
    } finally {
      setLoading(false);
    }
  }, [listing?.id, user?.id]);

  useEffect(() => {
    loadRequests();
  }, [loadRequests]);

  const beginUpload = (mediaType, changeType, replacesUrl = null, position = 0) => {
    uploadTargetRef.current = { mediaType, changeType, replacesUrl, position };
    setError(null);
    setMessage(null);
    fileInputRef.current?.click();
  };

  const uploadSelectedFile = async (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    const target = uploadTargetRef.current;
    if (!file || !target || !user?.id || !listing?.id) return;

    if (!ALLOWED_TYPES.includes(file.type)) {
      setError("Please upload a JPG, PNG, or WEBP image.");
      return;
    }

    if (file.size > MAX_FILE_SIZE) {
      setError("Please keep each image at 8 MB or less.");
      return;
    }

    setBusy(true);
    setError(null);
    setMessage(null);

    const unique = typeof crypto?.randomUUID === "function" ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const path = `${user.id}/${listing.id}/${unique}-${safeFilename(file.name)}`;

    try {
      const { error: uploadError } = await supabase.storage
        .from(BUCKET)
        .upload(path, file, { cacheControl: "3600", upsert: false, contentType: file.type });
      if (uploadError) throw uploadError;

      const { error: insertError } = await supabase
        .from("partner_media_requests")
        .insert({
          partner_id: listing.id,
          owner_id: user.id,
          media_type: target.mediaType,
          change_type: target.changeType,
          storage_path: path,
          replaces_url: target.replacesUrl,
          original_filename: file.name,
          mime_type: file.type,
          file_size_bytes: file.size,
          position: target.position,
        });

      if (insertError) {
        await supabase.storage.from(BUCKET).remove([path]);
        throw insertError;
      }

      setMessage("Media submitted for HEHA review. Your current public images stay unchanged until approved.");
      await loadRequests();
      await onChanged?.();
    } catch (uploadError) {
      setError(uploadError.message || "Could not upload this image yet.");
    } finally {
      setBusy(false);
      uploadTargetRef.current = null;
    }
  };

  const requestRemoval = async (mediaType, currentUrl, position = 0) => {
    if (!currentUrl || !user?.id || !listing?.id) return;
    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      const { error: insertError } = await supabase
        .from("partner_media_requests")
        .insert({
          partner_id: listing.id,
          owner_id: user.id,
          media_type: mediaType,
          change_type: "remove",
          replaces_url: currentUrl,
          position,
        });
      if (insertError) throw insertError;

      setMessage("Removal submitted for HEHA review. The current public image stays visible until approved.");
      await loadRequests();
      await onChanged?.();
    } catch (removeError) {
      setError(removeError.message || "Could not request this image removal yet.");
    } finally {
      setBusy(false);
    }
  };

  const pendingRequests = requests.filter((request) => ["submitted", "needs_info"].includes(request.status));

  return (
    <div
      className="preview-backdrop"
      role="dialog"
      aria-modal="true"
      aria-label="Manage business logo and photos"
      onClick={onClose}
    >
      <section className="partner-preview-sheet partner-media-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close media manager">×</button>

        <div className="preview-body partner-media-body">
          <p className="eyebrow">Photos &amp; Logo</p>
          <h2>Manage business media</h2>
          <p className="preview-tagline">
            View your current business images and submit additions, replacements, or removals. HEHA reviews media before public images change.
          </p>

          <input
            ref={fileInputRef}
            className="partner-media-file-input"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={uploadSelectedFile}
          />

          <section className="partner-media-section">
            <div className="partner-media-heading">
              <div>
                <span className="cp-status-label">Business logo</span>
                <h3>Logo</h3>
              </div>
              <button
                className="secondary-button compact"
                type="button"
                disabled={busy}
                onClick={() => beginUpload("logo", listing?.logo_url ? "replace" : "add", listing?.logo_url || null)}
              >
                {listing?.logo_url ? "Replace logo" : "Upload logo"}
              </button>
            </div>

            {listing?.logo_url ? (
              <div className="partner-media-current-card logo">
                <img src={listing.logo_url} alt={`${listing.name || "Business"} logo`} />
                <button className="text-button" type="button" disabled={busy} onClick={() => requestRemoval("logo", listing.logo_url)}>Request removal</button>
              </div>
            ) : (
              <div className="partner-media-empty">No approved logo is connected yet.</div>
            )}
          </section>

          <section className="partner-media-section">
            <div className="partner-media-heading">
              <div>
                <span className="cp-status-label">Main discovery image</span>
                <h3>Cover photo</h3>
              </div>
              <button
                className="secondary-button compact"
                type="button"
                disabled={busy}
                onClick={() => beginUpload("cover", listing?.image_url ? "replace" : "add", listing?.image_url || null)}
              >
                {listing?.image_url ? "Replace cover" : "Upload cover"}
              </button>
            </div>

            {listing?.image_url ? (
              <div className="partner-media-current-card cover">
                <img src={listing.image_url} alt={`${listing.name || "Business"} cover`} />
                <button className="text-button" type="button" disabled={busy} onClick={() => requestRemoval("cover", listing.image_url)}>Request removal</button>
              </div>
            ) : (
              <div className="partner-media-empty">No approved cover photo yet. HEHA Swipe currently uses a category placeholder.</div>
            )}
          </section>

          <section className="partner-media-section">
            <div className="partner-media-heading">
              <div>
                <span className="cp-status-label">Up to 6 photos</span>
                <h3>Business gallery</h3>
              </div>
              <button
                className="secondary-button compact"
                type="button"
                disabled={busy || currentGallery.length >= 6}
                onClick={() => beginUpload("gallery", "add", null, Math.min(currentGallery.length, 5))}
              >
                Add photo
              </button>
            </div>

            {currentGallery.length ? (
              <div className="partner-media-gallery">
                {currentGallery.map((url, index) => (
                  <article className="partner-media-gallery-card" key={`${url}-${index}`}>
                    <img src={url} alt={`${listing.name || "Business"} gallery ${index + 1}`} />
                    <div>
                      <button className="text-button" type="button" disabled={busy} onClick={() => beginUpload("gallery", "replace", url, index)}>Replace</button>
                      <button className="text-button danger" type="button" disabled={busy} onClick={() => requestRemoval("gallery", url, index)}>Remove</button>
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="partner-media-empty">No approved gallery photos yet.</div>
            )}
          </section>

          <section className="partner-media-section">
            <div className="partner-media-heading">
              <div>
                <span className="cp-status-label">HEHA review queue</span>
                <h3>Submitted media</h3>
              </div>
              <button className="secondary-button compact" type="button" onClick={loadRequests} disabled={busy || loading}>Refresh</button>
            </div>

            {loading ? (
              <div className="partner-media-empty">Loading submitted media…</div>
            ) : pendingRequests.length ? (
              <div className="partner-media-request-list">
                {pendingRequests.map((request) => (
                  <article className="partner-media-request-card" key={request.id}>
                    {request.preview_url ? (
                      <img src={request.preview_url} alt={requestLabel(request)} />
                    ) : (
                      <div className="partner-media-request-placeholder">{request.change_type === "remove" ? "Remove" : "Image"}</div>
                    )}
                    <div>
                      <strong>{requestLabel(request)}</strong>
                      <span>{formatStatus(request.status)} · {formatDate(request.submitted_at)}</span>
                      {request.review_note && <small>{request.review_note}</small>}
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="partner-media-empty">No media is waiting for HEHA review.</div>
            )}
          </section>

          <div className="partner-cert-note">
            JPG, PNG, or WEBP · maximum 8 MB each. Uploading a photo never publishes or certifies a business automatically.
          </div>

          {message && <div className="success-banner">{message}</div>}
          {error && <div className="error-banner">{error}</div>}

          <div className="preview-actions">
            <button className="primary-button" type="button" onClick={onClose} disabled={busy}>Back to Partner Hub</button>
          </div>
        </div>
      </section>
    </div>
  );
}
