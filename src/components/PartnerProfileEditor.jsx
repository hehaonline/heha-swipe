import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import {
  buildProtectedPartnerProfileSnapshot,
  claimedProfileHasStructuredHours,
  hasVerifiedPartnerClaim,
} from "../lib/partnerProfileCorrection";
import { revisePartnerProfile } from "../services/partnerApplicationRepository";

const PROTECTED_APPLICATION_STATUSES = ["draft", "submitted", "pending", "missing_info"];
const PROFILE_REQUEST_LOAD_ERROR = "We could not check your latest profile request. Try again, or ask HEHA for help.";
const PROFILE_REQUEST_SAVE_ERROR = "We could not submit these profile changes. Try again, or ask HEHA for help.";
const PROTECTED_CORRECTION_SAVE_ERROR = "We could not save this protected correction. Try again, or ask HEHA to resend your private partner link.";
const CATEGORIES = [
  { value: "Restaurant", label: "Restaurants", emoji: "🥗" },
  { value: "Vendor", label: "Product vendors", emoji: "🛍️" },
  { value: "Markets", label: "Grocery & farmers markets", emoji: "🛒" },
  { value: "Catering", label: "Catering", emoji: "🍱" },
  { value: "Private Chef", label: "Private Chefs", emoji: "👨‍🍳" },
  { value: "Wellness", label: "Wellness", emoji: "🧘" },
  { value: "Coach", label: "Coaches", emoji: "🏆" },
  { value: "Service", label: "Services", emoji: "💆" },
  { value: "Events", label: "Events", emoji: "🎉" },
];
const PROTECTED_APPLICATION_CATEGORIES = CATEGORIES.slice(0, 5);
const CLAIM_LOCKED_FIELDS = new Set([
  "name",
  "location",
  "business_type",
  "neighborhood",
]);

const ARRAY_FIELDS = new Set(["categories", "tags", "offerings", "delivery_days"]);
const LEGACY_CATEGORY_ALIASES = new Map([
  ["PrivateChef", "Private Chef"],
  ["FarmersMarket", "Markets"],
  ["Market", "Markets"],
  ["Grocery", "Markets"],
]);
const EDITABLE_FIELDS = [
  "name",
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
  if (Array.isArray(value)) {
    return [...new Set(value.map((item) => String(item || "").trim()).filter(Boolean))];
  }

  return [...new Set(
    String(value || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean)
  )];
}

function rawListingCategories(listing) {
  if (Array.isArray(listing?.categories) && listing.categories.length) return listing.categories;
  return listing?.category ? [listing.category] : [];
}

function canonicalEditableCategory(value) {
  const normalized = String(value || "").trim();
  return LEGACY_CATEGORY_ALIASES.get(normalized) || normalized;
}

function listingCategories(listing) {
  return [...new Set(rawListingCategories(listing).map(canonicalEditableCategory).filter(Boolean))];
}

function initialForm(listing) {
  const hours = typeof listing?.hours === "string"
    ? listing.hours
    : listing?.hours?.summary || "";
  return {
    name: listing?.name || "",
    categories: listingCategories(listing),
    location: listing?.location || "",
    contact: listing?.contact || "",
    instagram: listing?.instagram || "",
    website: listing?.website || "",
    bio: listing?.bio || "",
    tags: toCommaList(listing?.tags),
    hours,
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
  if (field === "categories") {
    return [...new Set(parseCommaList(value).map(canonicalEditableCategory).filter(Boolean))];
  }
  if (ARRAY_FIELDS.has(field)) return parseCommaList(value);
  if (field === "instagram") return String(value || "").trim().replace(/^@/, "") || null;
  return String(value || "").trim() || null;
}

function currentValue(field, listing) {
  if (field === "categories") return rawListingCategories(listing);
  if (ARRAY_FIELDS.has(field)) return Array.isArray(listing?.[field]) ? listing[field] : [];
  if (field === "hours") {
    return typeof listing?.hours === "string"
      ? listing.hours.trim() || null
      : String(listing?.hours?.summary || "").trim() || null;
  }
  if (field === "instagram") return String(listing?.instagram || "").trim().replace(/^@/, "") || null;
  return String(listing?.[field] || "").trim() || null;
}

function buildChanges(form, listing, { claimBound, structuredHoursLocked }) {
  const changes = EDITABLE_FIELDS.reduce((nextChanges, field) => {
    if ((claimBound && CLAIM_LOCKED_FIELDS.has(field))
        || (structuredHoursLocked && field === "hours")) {
      return nextChanges;
    }
    const nextValue = normalizedValue(field, form[field]);
    const existingValue = currentValue(field, listing);
    if (JSON.stringify(nextValue) !== JSON.stringify(existingValue)) {
      nextChanges[field] = nextValue;
    }
    return nextChanges;
  }, {});

  if (!claimBound) {
    const categories = normalizedValue("categories", form.categories);
    const existingCategories = currentValue("categories", listing);
    if (JSON.stringify(categories) !== JSON.stringify(existingCategories)) {
      changes.categories = categories;
    }

    const primaryCategory = categories[0] || null;
    const existingPrimaryCategory = String(listing?.category || "").trim() || null;
    if (primaryCategory !== existingPrimaryCategory) {
      changes.category = primaryCategory;
    }
  }

  return changes;
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
  const [correctionRequestKey] = useState(() => crypto.randomUUID());

  const listingStatus = String(listing?.status || "pending").trim().toLowerCase();
  const protectedCorrection = PROTECTED_APPLICATION_STATUSES.includes(listingStatus);
  const claimBound = hasVerifiedPartnerClaim(listing?.onboarding_capabilities, {
    partnerId: listing?.id,
    actorId: user?.id,
  });
  const structuredHoursLocked = claimBound && claimedProfileHasStructuredHours(listing);
  const changes = useMemo(
    () => buildChanges(form, listing, { claimBound, structuredHoursLocked }),
    [claimBound, form, listing, structuredHoursLocked],
  );
  const changeCount = Object.keys(changes).length;
  const alreadyAwaitingReview = !protectedCorrection && latestRequest?.status === "submitted";

  useEffect(() => {
    if (protectedCorrection || !user?.id || !listing?.id) return;
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
        if (requestError) setError(PROFILE_REQUEST_LOAD_ERROR);
        else setLatestRequest(data || null);
      })
      .catch(() => {
        if (!cancelled) setError(PROFILE_REQUEST_LOAD_ERROR);
      })
      .finally(() => {
        if (!cancelled) setRequestLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [protectedCorrection, listing?.id, user?.id]);

  const set = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
    setError(null);
    setMessage(null);
  };

  const toggleCategory = (value) => {
    setForm((current) => ({
      ...current,
      categories: claimBound
        ? current.categories
        : protectedCorrection
          ? (current.categories.includes(value) ? [] : [value])
        : current.categories.includes(value)
          ? current.categories.filter((category) => category !== value)
          : [...current.categories, value],
    }));
    setError(null);
    setMessage(null);
  };

  const save = async () => {
    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      if (!form.categories.length) {
        setError("Choose at least one business category.");
        return;
      }

      if (!changeCount) {
        setMessage("No profile changes to save yet.");
        return;
      }

      if (protectedCorrection) {
        if (!user?.id || !listing?.id) {
          setError(PROTECTED_CORRECTION_SAVE_ERROR);
          return;
        }

        const profileSnapshot = buildProtectedPartnerProfileSnapshot(form, listing, { claimBound });
        if (!claimBound && profileSnapshot.categories.length !== 1) {
          setError("Choose exactly one HEHA business relationship.");
          return;
        }

        await revisePartnerProfile({
          actorId: user.id,
          partnerId: listing.id,
          requestKey: correctionRequestKey,
          profileSnapshot,
        });
        await onSaved?.(
          { ...listing, ...changes },
          "Protected profile correction recorded. Your profile remains private until HEHA review and release proof are complete."
        );
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
    } catch {
      setError(protectedCorrection ? PROTECTED_CORRECTION_SAVE_ERROR : PROFILE_REQUEST_SAVE_ERROR);
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
            {protectedCorrection
              ? claimBound
                ? "Your claimed listing is private. Business identity stays locked to the invitation; operational edits receive a protected correction receipt."
                : "Your listing is still private. Saving creates a protected correction receipt and does not publish it."
              : "Your current listing stays unchanged while HEHA reviews submitted profile edits."}
          </p>

          {!protectedCorrection && latestRequest && (
            <div className="partner-cert-note">
              Latest change request: <strong>{formatStatus(latestRequest.status)}</strong>
              {latestRequest.review_note ? ` — ${latestRequest.review_note}` : ""}
            </div>
          )}

          <div className="profile-form partner-editor-form">
            <Field label="Business name">
              <input value={form.name} onChange={(event) => set("name", event.target.value)} disabled={claimBound} />
            </Field>

            <Field
              label="Categories"
              hint={claimBound
                ? "locked to your verified invitation"
                : protectedCorrection
                ? "choose exactly one legal relationship"
                : "choose one or more; first selected is primary"}
            >
              <div className="wizard-chip-grid">
                {(protectedCorrection ? PROTECTED_APPLICATION_CATEGORIES : CATEGORIES).map((category) => (
                  <button
                    type="button"
                    key={category.value}
                    className={form.categories.includes(category.value) ? "selected" : ""}
                    onClick={() => toggleCategory(category.value)}
                    aria-pressed={form.categories.includes(category.value)}
                    disabled={claimBound}
                  >
                    <span>{category.emoji}</span>
                    {category.label}
                  </button>
                ))}
              </div>
            </Field>

            <Field label="Neighborhood">
              <input value={form.neighborhood} onChange={(event) => set("neighborhood", event.target.value)} placeholder="South Tampa, Hyde Park…" disabled={claimBound} />
            </Field>

            <Field label="Card headline">
              <input value={form.tagline} onChange={(event) => set("tagline", event.target.value)} maxLength={80} />
            </Field>

            <Field label="About your business">
              <textarea value={form.bio} onChange={(event) => set("bio", event.target.value)} />
            </Field>

            <Field label="Business type">
              <input value={form.business_type} onChange={(event) => set("business_type", event.target.value)} placeholder="Studio, mobile, online, brick & mortar…" disabled={claimBound} />
            </Field>

            <Field label="Hours" hint={structuredHoursLocked ? "structured schedule preserved; use HEHA support to change it" : null}>
              <input value={form.hours} onChange={(event) => set("hours", event.target.value)} placeholder="Mon–Fri 8am–6pm" disabled={structuredHoursLocked} />
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
              <textarea value={form.location} onChange={(event) => set("location", event.target.value)} disabled={claimBound} />
            </Field>

            <Field label="Offerings" hint="comma-separated">
              <textarea value={form.offerings} onChange={(event) => set("offerings", event.target.value)} placeholder="Coaching, breathwork, workshops" />
            </Field>

            <Field label="Health / discovery tags" hint="comma-separated">
              <textarea value={form.tags} onChange={(event) => set("tags", event.target.value)} placeholder="movement, wellness, local" disabled={protectedCorrection} />
            </Field>

            <Field label="Price range">
              <input value={form.price_range} onChange={(event) => set("price_range", event.target.value)} placeholder="$, $$, or a short range" disabled={protectedCorrection} />
            </Field>

            <Field label="Delivery / availability days" hint="comma-separated, if applicable">
              <input value={form.delivery_days} onChange={(event) => set("delivery_days", event.target.value)} placeholder="Monday, Wednesday, Friday" />
            </Field>

            <Field label="Pricing notes">
              <textarea value={form.pricing_notes} onChange={(event) => set("pricing_notes", event.target.value)} placeholder="Optional pricing context" disabled={protectedCorrection} />
            </Field>
          </div>

          <div className="partner-cert-note">
            {protectedCorrection
              ? claimBound
                ? `${changeCount} operational profile field${changeCount === 1 ? "" : "s"} changed. Invitation-bound identity and classification stay locked; publishing stays blocked.`
                : `${changeCount} application field${changeCount === 1 ? "" : "s"} changed. Identity and category changes are collision-checked and receipt-bound; publishing stays blocked.`
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
                : protectedCorrection
                ? "Save protected correction"
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
