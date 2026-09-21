import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";
import { usePartnerDialogFocus } from "../lib/usePartnerDialogFocus";

const CATEGORIES = [
  { value: "Restaurant", label: "Restaurants", emoji: "🥗" },
  { value: "Vendor", label: "Markets", emoji: "🛒" },
  { value: "Catering", label: "Catering", emoji: "🍱" },
  { value: "PrivateChef", label: "Private Chefs", emoji: "👨‍🍳" },
  { value: "Wellness", label: "Wellness", emoji: "🧘" },
  { value: "Coach", label: "Coaches", emoji: "🏆" },
  { value: "Service", label: "Services", emoji: "💆" },
  { value: "Events", label: "Events", emoji: "🎉" },
];

const ARRAY_FIELDS = new Set(["categories", "tags", "offerings", "delivery_days"]);
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

function listingCategories(listing) {
  if (Array.isArray(listing?.categories) && listing.categories.length) return listing.categories;
  return listing?.category ? [listing.category] : [];
}

function initialForm(listing) {
  return {
    name: listing?.name || "",
    categories: listingCategories(listing),
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
  if (field === "categories") return listingCategories(listing);
  if (ARRAY_FIELDS.has(field)) return Array.isArray(listing?.[field]) ? listing[field] : [];
  if (field === "instagram") return String(listing?.instagram || "").trim().replace(/^@/, "") || null;
  return String(listing?.[field] || "").trim() || null;
}

function buildChanges(form, listing) {
  const changes = EDITABLE_FIELDS.reduce((nextChanges, field) => {
    const nextValue = normalizedValue(field, form[field]);
    const existingValue = currentValue(field, listing);
    if (JSON.stringify(nextValue) !== JSON.stringify(existingValue)) {
      nextChanges[field] = nextValue;
    }
    return nextChanges;
  }, {});

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

  return changes;
}

function formatStatus(value) {
  return String(value || "submitted")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

export default function PartnerProfileEditor(props) {
  // A different owner/card gets its own draft and pending-request state.
  return <ScopedPartnerProfileEditor key={`${props.user?.id || ""}:${props.listing?.id || ""}`} {...props} />;
}

function ScopedPartnerProfileEditor({ user, listing, onClose, onSaved }) {
  const dialogRef = usePartnerDialogFocus(onClose);
  const [form, setForm] = useState(() => initialForm(listing));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);
  const [requestState, setRequestState] = useState(null);
  const [lookupVersion, setLookupVersion] = useState(0);
  // A replacement authenticated user object invalidates readiness even for the
  // same ID. Preserve that owner's draft while the new context is checked.
  const scope = useMemo(() => ({ user, ownerId: user?.id, partnerId: listing?.id }), [user, user?.id, listing?.id]);
  const currentScope = useRef(scope);
  currentScope.current = scope;
  const saving = useRef(false);
  const lookupGeneration = useRef(0);
  const canCheck = Boolean(scope.ownerId && scope.partnerId);
  const requestReady = canCheck && requestState?.scope === scope && requestState.status === "ready";
  const lookupFailed = requestState?.scope === scope && requestState.status === "failed";
  const requestLoading = canCheck && !requestReady && !lookupFailed;
  const latestRequest = requestReady ? requestState.latest : null;

  const changes = useMemo(() => buildChanges(form, listing), [form, listing]);
  const changeCount = Object.keys(changes).length;
  const alreadyAwaitingReview = latestRequest?.status === "submitted";

  useEffect(() => {
    let cancelled = false;
    currentScope.current = scope;
    const generation = ++lookupGeneration.current;
    setRequestState({ scope, status: "loading" });
    if (!canCheck) return;
    const isCurrent = () => !cancelled && currentScope.current === scope && lookupGeneration.current === generation;
    Promise.resolve().then(() => supabase
      .from("partner_profile_change_requests")
      .select("id, status, submitted_at, review_note")
      .eq("partner_id", scope.partnerId)
      .eq("owner_id", scope.ownerId)
      .order("submitted_at", { ascending: false })
      .limit(1)
      .maybeSingle())
      .then(({ data, error: requestError }) => {
        if (!isCurrent()) return;
        if (requestError) throw requestError;
        setRequestState({ scope, status: "ready", latest: data || null });
      })
      .catch(() => {
        if (isCurrent()) setRequestState({ scope, status: "failed" });
      });
    return () => {
      cancelled = true;
      currentScope.current = null;
    };
  }, [scope, lookupVersion, canCheck]);

  const retryRequestCheck = () => {
    if (!lookupFailed || saving.current) return;
    lookupGeneration.current += 1;
    setRequestState({ scope, status: "loading" });
    setLookupVersion((version) => version + 1);
  };

  const set = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
    setError(null);
    setMessage(null);
  };

  const toggleCategory = (value) => {
    setForm((current) => ({
      ...current,
      categories: current.categories.includes(value)
        ? current.categories.filter((category) => category !== value)
        : [...current.categories, value],
    }));
    setError(null);
    setMessage(null);
  };

  const save = async () => {
    if (!requestReady || alreadyAwaitingReview || saving.current || currentScope.current !== scope) return;
    saving.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);

    let mutationStarted = false;
    try {
      if (!form.categories.length) {
        setError("Choose at least one business category.");
        return;
      }

      if (!changeCount) {
        setMessage("No profile changes to save yet.");
        return;
      }

      if (alreadyAwaitingReview) {
        setMessage("You already have profile changes waiting for HEHA review.");
        return;
      }

      mutationStarted = true;
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
      if (currentScope.current !== scope) return;
      setRequestState({ scope, status: "ready", latest: data });
      await onSaved?.(listing, "Profile changes submitted for HEHA review. Your current public listing stays unchanged until approved.");
    } catch (saveError) {
      if (currentScope.current === scope) setError(saveError.message || "Could not save these business profile changes yet.");
    } finally {
      // A same-owner/card session replacement must not release this lock while
      // the insert is unresolved. Once it settles, even an earlier empty read
      // in the replacement session cannot authorize a second submission.
      saving.current = false;
      if (currentScope.current) {
        setBusy(false);
        if (mutationStarted) {
          lookupGeneration.current += 1;
          setRequestState({ scope: currentScope.current, status: "loading" });
          setLookupVersion((version) => version + 1);
        }
      }
    }
  };

  return (
    <div
      ref={dialogRef}
      tabIndex={-1}
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
            Your current listing stays unchanged while HEHA reviews submitted profile edits.
          </p>

          {latestRequest && (
            <div className="partner-cert-note">
              Latest change request: <strong>{formatStatus(latestRequest.status)}</strong>
              {latestRequest.review_note ? ` — ${latestRequest.review_note}` : ""}
            </div>
          )}

          <div className="profile-form partner-editor-form">
            <Field label="Business name">
              <input value={form.name} onChange={(event) => set("name", event.target.value)} />
            </Field>

            <Field label="Categories" hint="choose one or more; first selected is primary" group>
              <div className="wizard-chip-grid">
                {CATEGORIES.map((category) => (
                  <button
                    type="button"
                    key={category.value}
                    className={form.categories.includes(category.value) ? "selected" : ""}
                    onClick={() => toggleCategory(category.value)}
                    aria-pressed={form.categories.includes(category.value)}
                  >
                    <span>{category.emoji}</span>
                    {category.label}
                  </button>
                ))}
              </div>
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
            {changeCount} profile fields changed. Saving submits edits for HEHA review; it does not change the live listing immediately.
          </div>

          {requestLoading && <div className="cp-billing-note">Checking your latest change request…</div>}
          {!canCheck && <div className="error-banner" role="alert">Your business access changed. Reopen the profile from your signed-in business workspace.</div>}
          {lookupFailed && <div className="error-banner" role="alert">
            We couldn't check your latest change request. Your edits are kept here. Retry the check before submitting.
            <button className="secondary-button" type="button" onClick={retryRequestCheck} disabled={busy}>Retry request check</button>
          </div>}
          {message && <div className="success-banner">{message}</div>}
          {error && <div className="error-banner">{error}</div>}

          <div className="preview-actions">
            <button
              className="primary-button"
              type="button"
              onClick={save}
              disabled={busy || !requestReady || alreadyAwaitingReview}
            >
              {busy
                ? "Saving…"
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

function Field({ label, hint, children, group = false }) {
  if (group) return (
    <fieldset className="field-block partner-editor-categories">
      <legend>{label}{hint ? ` · ${hint}` : ""}</legend>
      {children}
    </fieldset>
  );
  return (
    <label className="field-block">
      <span>{label}{hint ? ` · ${hint}` : ""}</span>
      {children}
    </label>
  );
}
