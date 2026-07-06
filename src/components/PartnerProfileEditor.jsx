import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const DIRECT_EDIT_STATUSES = ["draft", "submitted", "pending", "missing_info"];
const CATEGORIES = [
  "Restaurant",
  "Vendor",
  "Catering",
  "PrivateChef",
  "Wellness",
  "Coach",
  "Service",
  "Events",
];

const ARRAY_FIELDS = new Set(["tags", "offerings", "delivery_days"]);
const EDITABLE_FIELDS = [
  "name",
  "category",
  "location",
  "contact",
  "instagram",
  "website",
  "bio",
  "tags",
  "hours",
  "business_type",
  "offerings",
  "neighborhood",
  "tagline",
  "phone",
  "price_range",
  "delivery_days",
  "pricing_notes",
];

function toCommaList(value) {
  return Array.isArray(value) ? value.join(", ") : "";
}

function parseCommaList(value) {
  return [...new Set(
    String(value || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean)
  )];
}

function initialForm(listing) {
  return {
    name: listing?.name || "",
    category: listing?.category || "",
    location: listing?.location || "",
    contact: listing?.contact || "",
    instagram: listing?.instagram || "",
    website: listing?.website || "",
    bio: listing?.bio || "",
    tags: toCommaList(listing?.tags),
    hours: listing?.hours || "",
    business_type: listing?.business_type || "",
    offerings: toCommaList(listing?.offerings),
    neighborhood: listing?.neighborhood || "",
    tagline: listing?.tagline || "",
    phone: listing?.phone || "",
    price_range: listing?.price_range || "",
    delivery_days: toCommaList(listing?.delivery_days),
    pricing_notes: listing?.pricing_notes || "",
  };
}

function normalizedValue(field, value) {
  if (ARRAY_FIELDS.has(field)) return parseCommaList(value);
  if (field === "instagram") return String(value || "").trim().replace(/^@/, "") || null;
  return String(value || "").trim() || null;
}

function currentValue(field, listing) {
  if (ARRAY_FIELDS.has(field)) return Array.isArray(listing?.[field]) ? listing[field] : [];
  if (field === "instagram") return String(listing?.instagram || "").trim().replace(/^@/, "") || null;
  return String(listing?.[field] || "").trim() || null;
}

function buildChanges(form, listing) {
  return EDITABLE_FIELDS.reduce((changes, field) => {
    const nextValue = normalizedValue(field, form[field]);
    const existingValue = currentValue(field, listing);
    if (JSON.stringify(nextValue) !== JSON.stringify(existingValue)) {
      changes[field] = nextValue;
    }
    return changes;
  }, {});
}

function formatStatus(value) {
  return String(value || "submitted")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

export default function PartnerProfileEditor({ user, listing, onClose, onSaved }) {
  const [form, setForm] = useState(() => initialForm(listing));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);
  const [latestRequest, setLatestRequest] = useState(null);
  const [requestLoading, setRequestLoading] = useState(false);

  const listingStatus = String(listing?.status || "pending").toLowerCase();
  const directEdit = DIRECT_EDIT_STATUSES.includes(listingStatus);
  const changes = useMemo(() => buildChanges(form, listing), [form, listing]);
  const changeCount = Object.keys(changes).length;
  const alreadyAwaitingReview = !directEdit && latestRequest?.status === "submitted";

  useEffect(() => {
    if (directEdit || !user?.id || !listing?.id) return;
    let cancelled = false;
    setRequestLoading(true);
    supabase
      .from("partner_profile_change_requests")
      .select("id, status, submitted_at, review_note")
      .eq("partner_id", listing.id)
      .eq("owner_id", user.id)
      .order("submitted_at", { ascending: false })
      .limit(1)
      .maybeSingle()
      .then(({ data, error: requestError }) => {
        if (cancelled) return;
        if (requestError) setError(requestError.message || "Could not load your latest change request.");
        else setLatestRequest(data || null);
      })
      .finally(() => {
        if (!cancelled) setRequestLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [directEdit, listing?.id, user?.id]);

  const set = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
    setError(null);
    setMessage(null);
  };

  const save = async () => {
    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      if (!changeCount) {
        setMessage("No profile changes to save yet.");
        return;
      }

      if (directEdit) {
        const { data, error: updateError } = await supabase
          .from("partners")
          .update(changes)
          .eq("id", listing.id)
          .eq("owner_id", user.id)
          .select("id, name, category, status, created_at, updated_at, complete_pct, heha_partner, image_url, gallery_urls, neighborhood, tagline, bio, tags, offerings, items, website, instagram, price_range, photo_emoji, color, location, hours, contact, business_type, phone, delivery_days, pricing_notes")
          .single();

        if (updateError) throw updateError;
        await onSaved?.(data, "Business profile updated. Your listing remains in HEHA review.");
        return;
      }

      if (alreadyAwaitingReview) {
        setMessage("You already have profile changes waiting for HEHA review.");
        return;
      }

      const { data, error: requestError } = await supabase
        .from("partner_profile_change_requests")
        .insert({
          partner_id: listing.id,
          owner_id: user.id,
          proposed_changes: changes,
        })
        .select("id, status, submitted_at, review_note")
        .single();

      if (requestError) throw requestError;
      setLatestRequest(data);
      await onSaved?.(listing, "Profile changes submitted for HEHA review. Your current public listing stays unchanged until approved.");
    } catch (saveError) {
      setError(saveError.message || "Could not save these business profile changes yet.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="preview-backdrop"
      role="dialog"
      aria-modal="true"
      aria-label="Edit business profile"
      onClick={onClose}
    >
      <section className="partner-preview-sheet partner-editor-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close editor">×</button>

        <div className="preview-body partner-editor-body">
          <p className="eyebrow">Business profile</p>
          <h2>Edit {listing?.name || "your business"}</h2>
          <p className="preview-tagline">
            {directEdit
              ? "Your listing is still in pre-approval review, so safe profile fields can be updated directly."
              : "Your current listing stays unchanged while HEHA reviews submitted profile edits."}
          </p>

          {!directEdit && latestRequest && (
            <div className="partner-cert-note">
              Latest change request: <strong>{formatStatus(latestRequest.status)}</strong>
              {latestRequest.review_note ? ` — ${latestRequest.review_note}` : ""}
            </div>
          )}

          <div className="profile-form partner-editor-form">
            <Field label="Business name">
              <input value={form.name} onChange={(event) => set("name", event.target.value)} />
            </Field>

            <Field label="Category">
              <select value={form.category} onChange={(event) => set("category", event.target.value)}>
                <option value="">Choose a category</option>
                {CATEGORIES.map((category) => <option key={category} value={category}>{category}</option>)}
              </select>
            </Field>

            <Field label="Neighborhood">
              <input value={form.neighborhood} onChange={(event) => set("neighborhood", event.target.value)} placeholder="South Tampa, Hyde Park…" />
            </Field>

            <Field label="Card headline">
              <input value={form.tagline} onChange={(event) => set("tagline", event.target.value)} maxLength={80} />
            </Field>

            <Field label="About your business">
              <textarea value={form.bio} onChange={(event) => set("bio", event.target.value)} />
            </Field>

            <Field label="Business type">
              <input value={form.business_type} onChange={(event) => set("business_type", event.target.value)} placeholder="Studio, mobile, online, brick & mortar…" />
            </Field>

            <Field label="Hours">
              <input value={form.hours} onChange={(event) => set("hours", event.target.value)} placeholder="Mon–Fri 8am–6pm" />
            </Field>

            <Field label="Business phone">
              <input value={form.phone} onChange={(event) => set("phone", event.target.value)} type="tel" />
            </Field>

            <Field label="Business email">
              <input value={form.contact} onChange={(event) => set("contact", event.target.value)} type="email" />
            </Field>

            <Field label="Website">
              <input value={form.website} onChange={(event) => set("website", event.target.value)} placeholder="https://…" />
            </Field>

            <Field label="Instagram">
              <input value={form.instagram} onChange={(event) => set("instagram", event.target.value)} placeholder="@yourbusiness" />
            </Field>

            <Field label="Business address / service area">
              <textarea value={form.location} onChange={(event) => set("location", event.target.value)} />
            </Field>

            <Field label="Offerings" hint="comma-separated">
              <textarea value={form.offerings} onChange={(event) => set("offerings", event.target.value)} placeholder="Coaching, breathwork, workshops" />
            </Field>

            <Field label="Health / discovery tags" hint="comma-separated">
              <textarea value={form.tags} onChange={(event) => set("tags", event.target.value)} placeholder="movement, wellness, local" />
            </Field>

            <Field label="Price range">
              <input value={form.price_range} onChange={(event) => set("price_range", event.target.value)} placeholder="$, $$, or a short range" />
            </Field>

            <Field label="Delivery / availability days" hint="comma-separated, if applicable">
              <input value={form.delivery_days} onChange={(event) => set("delivery_days", event.target.value)} placeholder="Monday, Wednesday, Friday" />
            </Field>

            <Field label="Pricing notes">
              <textarea value={form.pricing_notes} onChange={(event) => set("pricing_notes", event.target.value)} placeholder="Optional pricing context" />
            </Field>
          </div>

          <div className="partner-cert-note">
            {directEdit
              ? `${changeCount} profile field${changeCount === 1 ? "" : "s"} changed. HEHA-controlled status and certification cannot be edited here.`
              : `${changeCount} profile field${changeCount === 1 ? "" : "s"} changed. Saving submits the edits for HEHA review; it does not change the live listing immediately.`}
          </div>

          {requestLoading && <div className="cp-billing-note">Checking your latest change request…</div>}
          {message && <div className="success-banner">{message}</div>}
          {error && <div className="error-banner">{error}</div>}

          <div className="preview-actions">
            <button
              className="primary-button"
              type="button"
              onClick={save}
              disabled={busy || requestLoading || alreadyAwaitingReview}
            >
              {busy
                ? "Saving…"
                : directEdit
                ? "Save business profile"
                : alreadyAwaitingReview
                ? "Changes already under review"
                : "Submit changes for HEHA review"}
            </button>
            <button className="secondary-button" type="button" onClick={onClose} disabled={busy}>Cancel</button>
          </div>
        </div>
      </section>
    </div>
  );
}

function Field({ label, hint, children }) {
  return (
    <label className="field-block">
      <span>{label}{hint ? ` · ${hint}` : ""}</span>
      {children}
    </label>
  );
}
