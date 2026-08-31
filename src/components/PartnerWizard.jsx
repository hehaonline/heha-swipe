import { useState } from "react";
import { supabase } from "../lib/supabase";
import {
  createOrResumePartnerApplication,
  revisePartnerProfile,
} from "../services/partnerApplicationRepository";
import { claimPartnerInvitation } from "../services/partnerClaimRepository";
import {
  clearPendingPartnerInviteToken,
  pendingPartnerInviteRequestKey,
  pendingPartnerInviteToken,
} from "../lib/partnerInvite";

const CATEGORIES = [
  { value: "Restaurant", label: "Restaurants", emoji: "🥗" },
  { value: "Vendor", label: "Product vendors", emoji: "🛍️" },
  { value: "Markets", label: "Grocery & farmers markets", emoji: "🛒" },
  { value: "Catering", label: "Catering", emoji: "🍱" },
  { value: "Private Chef", label: "Private Chefs", emoji: "👨‍🍳" },
];

const CATEGORY_EMOJIS = Object.fromEntries(CATEGORIES.map((category) => [category.value, category.emoji]));
const CATEGORY_LABELS = Object.fromEntries(CATEGORIES.map((category) => [category.value, category.label]));

const CARD_COLORS = ["#ff8a24", "#ffb85c", "#114f35", "#2f7651", "#f2efe7", "#2d5f73", "#8b6f43", "#1f1f1f"];
const STEPS = [
  { id: "basics", label: "Basics", icon: "□" },
  { id: "details", label: "Details", icon: "✎" },
  { id: "contact", label: "Contact", icon: "☎" },
  { id: "offerings", label: "Offerings", icon: "✦" },
  { id: "style", label: "Style", icon: "◇" },
  { id: "review", label: "Review", icon: "✓" },
];

const ICONS = ["🥗", "🍜", "☕", "🥤", "🧃", "🍱", "👨‍🍳", "🏋️", "🧘", "💆", "🌿", "🏪", "🛍️", "🏆", "💪", "🌱", "🥦", "🫙", "🧴", "🎉"];
const PUBLIC_STATUSES = ["approved", "live"];

const DAY_OPTIONS = [
  { value: "Mon", label: "Mon" },
  { value: "Tue", label: "Tue" },
  { value: "Wed", label: "Wed" },
  { value: "Thu", label: "Thu" },
  { value: "Fri", label: "Fri" },
  { value: "Sat", label: "Sat" },
  { value: "Sun", label: "Sun" },
];
const WEEKDAYS = DAY_OPTIONS.slice(0, 5).map((day) => day.value);

function orderedScheduleDays(days = []) {
  return DAY_OPTIONS.map((day) => day.value).filter((day) => days.includes(day));
}

function formatClock(value) {
  const [hourText, minute = "00"] = String(value || "").split(":");
  const hour = Number(hourText);
  if (!Number.isFinite(hour)) return "";
  const suffix = hour >= 12 ? "PM" : "AM";
  const hour12 = hour % 12 || 12;
  return `${hour12}:${minute} ${suffix}`;
}

function operatingHoursSummary(form) {
  const days = orderedScheduleDays(form.scheduleDays);
  if (!days.length || !form.opensAt || !form.closesAt) return "";

  let daySummary = days.join(", ");
  if (days.length === 7) daySummary = "Daily";
  if (days.join(",") === WEEKDAYS.join(",")) daySummary = "Mon–Fri";
  if (days.join(",") === "Sat,Sun") daySummary = "Sat–Sun";

  return `${daySummary} · ${formatClock(form.opensAt)}–${formatClock(form.closesAt)}`;
}

const emptyForm = {
  name: "",
  category: "",
  categories: [],
  neighborhood: "",
  tagline: "",
  bio: "",
  scheduleDays: [...WEEKDAYS],
  opensAt: "09:00",
  closesAt: "17:00",
  business_type: "",
  phone: "",
  contact: "",
  website: "",
  instagram: "",
  location: "",
  offerings: [],
  items: [],
  photo_emoji: "🏪",
  color: "#ff8a24",
};

function normalizeInstagram(value) {
  return value.trim().replace(/^@/, "");
}

function formatStatus(value) {
  const status = String(value || "pending").trim();
  return status.replace(/_/g, " ").replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function completionLabel(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return "0%";
  return `${Math.round(numeric)}%`;
}

function categorySummary(categories = []) {
  return categories.map((category) => CATEGORY_LABELS[category] || category).join(", ");
}

export default function PartnerWizard({ user, onComplete, onCancel }) {
  const protectedApplicationEnabled = import.meta.env.VITE_ENABLE_PROTECTED_PARTNER_APPLICATION === "true";
  const protectedClaimEnabled = import.meta.env.VITE_ENABLE_PROTECTED_PARTNER_CLAIM === "true";
  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState({});
  const [form, setForm] = useState(emptyForm);
  const [newOffering, setNewOffering] = useState("");
  const [newItem, setNewItem] = useState({ name: "", price: "", emoji: "✦" });
  const [submittedListing, setSubmittedListing] = useState(null);
  const [listingEntrySource, setListingEntrySource] = useState(null);
  const [statusLoading, setStatusLoading] = useState(false);
  const [statusError, setStatusError] = useState(null);
  const [applicationRequestKey, setApplicationRequestKey] = useState(() => crypto.randomUUID());
  const [applicationPartnerId, setApplicationPartnerId] = useState(null);
  const [claimRequestKey] = useState(pendingPartnerInviteRequestKey);
  const [inviteToken] = useState(pendingPartnerInviteToken);

  const activeStep = STEPS[step];

  const set = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: null }));
  };

  const toggleCategory = (value) => {
    setForm((current) => {
      const selected = current.categories.includes(value) ? [] : [value];

      return {
        ...current,
        categories: selected,
        category: selected[0] || "",
        photo_emoji: current.categories.length === 0 && selected.length === 1
          ? CATEGORY_EMOJIS[selected[0]] || current.photo_emoji
          : current.photo_emoji,
      };
    });
    setErrors((current) => ({ ...current, category: null }));
  };

  const validate = () => {
    const nextErrors = {};
    if (step === 0) {
      if (!form.name.trim()) nextErrors.name = "Business name is required.";
      if (!form.categories.length) nextErrors.category = "Choose at least one category.";
      if (!form.neighborhood.trim()) nextErrors.neighborhood = "Neighborhood is required.";
      if (!form.tagline.trim()) nextErrors.tagline = "Add a short card headline.";
    }
    if (step === 1) {
      if (!form.bio.trim()) nextErrors.bio = "Tell people what makes your business special.";
      if (form.scheduleDays.length > 0 && form.opensAt >= form.closesAt) {
        nextErrors.schedule = "Closing time must be after opening time.";
      }
    }
    if (step === 2 && !form.phone.trim() && !form.contact.trim()) nextErrors.phone = "Add at least a phone number or email.";
    setErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  };

  const next = () => {
    if (validate()) setStep((current) => Math.min(current + 1, STEPS.length - 1));
  };

  const back = () => setStep((current) => Math.max(current - 1, 0));

  const addOffering = () => {
    const value = newOffering.trim();
    if (!value) return;
    if (!form.offerings.includes(value)) set("offerings", [...form.offerings, value]);
    setNewOffering("");
  };

  const addItem = () => {
    const itemName = newItem.name.trim();
    if (!itemName) return;
    set("items", [...form.items, { ...newItem, name: itemName, id: Date.now() }]);
    setNewItem({ name: "", price: "", emoji: "✦" });
  };

  const submit = async () => {
    setLoading(true);
    setErrors({});
    try {
      if (!protectedApplicationEnabled) {
        throw new Error("Protected partner applications are still in review. Existing businesses must use their verified invitation link.");
      }

      const completePct = [
        form.name,
        form.categories.length > 0,
        form.neighborhood,
        form.tagline,
        form.bio,
        form.phone || form.contact,
        form.website,
        form.instagram,
        form.offerings.length > 0,
        form.items.length > 0,
      ].filter(Boolean).length * 10;

      const application = {
          name: form.name.trim(),
          category: form.categories[0],
          categories: form.categories,
          neighborhood: form.neighborhood.trim(),
          tagline: form.tagline.trim(),
          bio: form.bio.trim(),
          hours: operatingHoursSummary(form) || null,
          delivery_days: orderedScheduleDays(form.scheduleDays),
          business_type: form.business_type.trim() || null,
          phone: form.phone.trim() || null,
          contact: form.contact.trim() || null,
          website: form.website.trim() || null,
          instagram: normalizeInstagram(form.instagram) || null,
          location: form.location.trim() || null,
          offerings: form.offerings,
          items: form.items,
          photo_emoji: form.photo_emoji,
          color: form.color,
          complete_pct: completePct,
      };
      const data = applicationPartnerId
        ? await revisePartnerProfile({
          actorId: user.id,
          partnerId: applicationPartnerId,
          requestKey: applicationRequestKey,
          profileSnapshot: application,
        })
        : await createOrResumePartnerApplication({
          actorId: user.id,
          requestKey: applicationRequestKey,
          application,
        });

      setListingEntrySource("application");
      setApplicationPartnerId(data.id);
      setSubmittedListing({
        ...data,
        name: application.name,
        category: application.category,
        categories: application.categories,
        complete_pct: application.complete_pct,
      });
    } catch (error) {
      setErrors({ submit: error.message || "Could not submit this listing yet." });
    } finally {
      setLoading(false);
    }
  };

  const editSubmittedApplication = () => {
    setApplicationRequestKey(crypto.randomUUID());
    setSubmittedListing(null);
    setStep(0);
    setErrors({});
  };

  const claimInvite = async () => {
    if (!inviteToken || !claimRequestKey || !protectedClaimEnabled) return;
    setLoading(true);
    setErrors({});
    try {
      const listing = await claimPartnerInvitation({
        actorId: user.id,
        requestKey: claimRequestKey,
        inviteToken,
      });
      clearPendingPartnerInviteToken();
      setListingEntrySource("claim");
      setSubmittedListing(listing);
    } catch (error) {
      setErrors({ submit: error.message || "The protected invitation could not be verified." });
    } finally {
      setLoading(false);
    }
  };

  const refreshSubmittedListing = async () => {
    if (!submittedListing?.id || !user?.id) return;
    setStatusLoading(true);
    setStatusError(null);
    try {
      const { data, error } = await supabase
        .from("partners")
        .select("id, name, category, categories, status, created_at, updated_at, complete_pct, heha_partner")
        .eq("id", submittedListing.id)
        .eq("owner_id", user.id)
        .maybeSingle();
      if (error) throw error;
      if (data) setSubmittedListing(data);
    } catch (error) {
      setStatusError(error.message || "Could not refresh your registration status yet.");
    } finally {
      setStatusLoading(false);
    }
  };

  if (!submittedListing && inviteToken) {
    return (
      <PartnerAccessGate
        title="Verify your private business invitation"
        copy="This one-time link must match your signed-in account and the intended HEHA business profile. It cannot create a second profile or publish anything."
        enabled={protectedClaimEnabled}
        loading={loading}
        error={errors.submit}
        onContinue={claimInvite}
        onCancel={onCancel}
        buttonLabel="Verify invitation and continue"
      />
    );
  }

  if (!submittedListing && !protectedApplicationEnabled) {
    return (
      <PartnerAccessGate
        title="Protected partner applications are in review"
        copy="The older browser create path is disabled. New businesses unlock after server duplicate-prevention and authorization proof; invited businesses should reopen their private link."
        enabled={false}
        loading={false}
        error={null}
        onContinue={null}
        onCancel={onCancel}
        buttonLabel="Application not yet available"
      />
    );
  }

  if (submittedListing) {
    return (
      <PartnerSubmissionStatus
        listing={submittedListing}
        entrySource={listingEntrySource}
        loading={statusLoading}
        error={statusError}
        onRefresh={refreshSubmittedListing}
        onEdit={listingEntrySource === "application" ? editSubmittedApplication : null}
        onContinue={() => onComplete(submittedListing)}
      />
    );
  }

  return (
    <main className="partner-wizard-screen">
      <section className="partner-wizard-shell">
        <WizardTopbar onCancel={onCancel} />
        <Progress step={step} />
        <header className="wizard-step-header">
          <span className="wizard-step-icon">{activeStep.icon}</span>
          <div>
            <p>Step {step + 1} of {STEPS.length}</p>
            <h1>{activeStep.label}</h1>
          </div>
        </header>

        {step === 0 && (
          <WizardPanel>
            <Field label="Business name" required error={errors.name}>
              <input value={form.name} onChange={(event) => set("name", event.target.value)} placeholder="e.g. Pure Kitchen" />
            </Field>

            <div className="wizard-field-block">
              <Label required>Partner relationship</Label>
              <p className="wizard-helper-copy">Choose one relationship for this profile. Each relationship uses its own agreement and review requirements.</p>
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
              {errors.category && <Error>{errors.category}</Error>}
            </div>

            <Field label="Neighborhood" required error={errors.neighborhood}>
              <input value={form.neighborhood} onChange={(event) => set("neighborhood", event.target.value)} placeholder="e.g. South Tampa, Hyde Park, Ybor City" />
            </Field>

            <Field label="Card headline" required hint="one clean line" error={errors.tagline}>
              <input value={form.tagline} onChange={(event) => set("tagline", event.target.value)} placeholder="e.g. Organic vegan bowls and meal prep" maxLength={80} />
              <small>{form.tagline.length}/80</small>
            </Field>

            <NavButtons onBack={onCancel} backLabel="Cancel" onNext={next} />
          </WizardPanel>
        )}

        {step === 1 && (
          <WizardPanel>
            <Field label="About your business" required error={errors.bio}>
              <textarea value={form.bio} onChange={(event) => set("bio", event.target.value)} placeholder="Tell customers what makes you special…" />
            </Field>

            <Field label="Business type" hint="optional">
              <input value={form.business_type} onChange={(event) => set("business_type", event.target.value)} placeholder="Brick & mortar, mobile, pop-up, online…" />
            </Field>

            <div className="wizard-field-block">
              <Label>Operating days <em>(optional)</em></Label>
              <p className="wizard-helper-copy">Tap the days your business is normally available.</p>
              <div className="wizard-day-picker" aria-label="Operating days">
                {DAY_OPTIONS.map((day) => {
                  const selected = form.scheduleDays.includes(day.value);
                  return (
                    <button
                      key={day.value}
                      type="button"
                      className={selected ? "selected" : ""}
                      aria-pressed={selected}
                      onClick={() => set(
                        "scheduleDays",
                        selected
                          ? form.scheduleDays.filter((value) => value !== day.value)
                          : orderedScheduleDays([...form.scheduleDays, day.value])
                      )}
                    >
                      {day.label}
                    </button>
                  );
                })}
              </div>

              <div className="wizard-time-grid">
                <label className="wizard-time-field">
                  <span>Opens</span>
                  <input type="time" value={form.opensAt} onChange={(event) => set("opensAt", event.target.value)} />
                </label>
                <label className="wizard-time-field">
                  <span>Closes</span>
                  <input type="time" value={form.closesAt} onChange={(event) => set("closesAt", event.target.value)} />
                </label>
              </div>

              {operatingHoursSummary(form) && (
                <p className="wizard-schedule-summary">{operatingHoursSummary(form)}</p>
              )}
              {errors.schedule && <Error>{errors.schedule}</Error>}
            </div>

            <NavButtons onBack={back} onNext={next} />
          </WizardPanel>
        )}

        {step === 2 && (
          <WizardPanel>
            <Field label="Phone" required error={errors.phone}>
              <input value={form.phone} onChange={(event) => set("phone", event.target.value)} placeholder="(813) 555-0101" type="tel" />
            </Field>

            <Field label="Email" hint="optional">
              <input value={form.contact} onChange={(event) => set("contact", event.target.value)} placeholder="hello@yourbusiness.com" type="email" />
            </Field>

            <Field label="Website" hint="optional">
              <input value={form.website} onChange={(event) => set("website", event.target.value)} placeholder="yourbusiness.com" />
            </Field>

            <Field label="Instagram" hint="optional">
              <div className="wizard-prefix-input">
                <span>@</span>
                <input value={form.instagram} onChange={(event) => set("instagram", event.target.value)} placeholder="yourbusiness" />
              </div>
            </Field>

            <Field label="Full address" hint="optional">
              <input value={form.location} onChange={(event) => set("location", event.target.value)} placeholder="123 Main St, Tampa, FL 33601" />
            </Field>

            <NavButtons onBack={back} onNext={next} />
          </WizardPanel>
        )}

        {step === 3 && (
          <WizardPanel>
            <div className="wizard-field-block">
              <Label>What do you offer? <em>(add tags)</em></Label>
              <div className="wizard-add-row">
                <input
                  value={newOffering}
                  onChange={(event) => setNewOffering(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      addOffering();
                    }
                  }}
                  placeholder="Meal prep, acai bowls, breathwork…"
                />
                <button type="button" onClick={addOffering}>+</button>
              </div>
              <div className="wizard-tag-list">
                {form.offerings.map((offering) => (
                  <span key={offering}>
                    {offering}
                    <button type="button" onClick={() => set("offerings", form.offerings.filter((item) => item !== offering))}>×</button>
                  </span>
                ))}
                {form.offerings.length === 0 && <p>No offerings added yet.</p>}
              </div>
            </div>

            <div className="wizard-field-block">
              <Label>Featured items <em>(optional)</em></Label>
              <div className="wizard-item-row">
                <input value={newItem.name} onChange={(event) => setNewItem((current) => ({ ...current, name: event.target.value }))} placeholder="Item name" />
                <input value={newItem.price} onChange={(event) => setNewItem((current) => ({ ...current, price: event.target.value }))} placeholder="$0" />
              </div>
              <button type="button" className="wizard-dashed-button" onClick={addItem}>+ Add item</button>
              <div className="wizard-item-list">
                {form.items.map((item) => (
                  <div key={item.id}>
                    <span>{item.emoji || "✦"} {item.name}</span>
                    <strong>{item.price}</strong>
                    <button type="button" onClick={() => set("items", form.items.filter((listed) => listed.id !== item.id))}>×</button>
                  </div>
                ))}
              </div>
            </div>

            <NavButtons onBack={back} onNext={next} />
          </WizardPanel>
        )}

        {step === 4 && (
          <WizardPanel>
            <p className="wizard-helper-copy">Choose a simple visual style for how your card appears in HEHA Swipe.</p>
            <div className="wizard-card-preview" style={{ "--preview-color": form.color }}>
              <div className="wizard-preview-strip" />
              <div className="wizard-preview-image">
                <span>{form.photo_emoji}</span>
              </div>
              <div className="wizard-preview-body">
                <p>{categorySummary(form.categories) || "Categories"} · {form.neighborhood || "Tampa Bay"}</p>
                <h2>{form.name || "Your Business"}</h2>
                <span>{form.tagline || "Your clean HEHA Swipe headline"}</span>
              </div>
            </div>

            <div className="wizard-field-block">
              <Label>Card icon</Label>
              <div className="wizard-icon-grid">
                {ICONS.map((icon) => (
                  <button type="button" key={icon} className={form.photo_emoji === icon ? "selected" : ""} onClick={() => set("photo_emoji", icon)}>{icon}</button>
                ))}
              </div>
            </div>

            <div className="wizard-field-block">
              <Label>Card accent</Label>
              <div className="wizard-color-grid">
                {CARD_COLORS.map((color) => (
                  <button type="button" key={color} className={form.color === color ? "selected" : ""} style={{ background: color }} onClick={() => set("color", color)} />
                ))}
              </div>
            </div>

            <NavButtons onBack={back} onNext={next} nextLabel="Review →" />
          </WizardPanel>
        )}

        {step === 5 && (
          <WizardPanel>
            <p className="wizard-helper-copy">Everything look good? HEHA will review your listing before it appears publicly.</p>
            <div className="wizard-review-card">
              <div className="wizard-review-top" style={{ "--preview-color": form.color }}>
                <span>{form.photo_emoji}</span>
                <div>
                  <p>{categorySummary(form.categories) || "Categories"} · {form.neighborhood}</p>
                  <h2>{form.name}</h2>
                </div>
              </div>
              <div className="wizard-review-body">
                <p>“{form.tagline}”</p>
                {form.bio && <small>{form.bio.slice(0, 110)}{form.bio.length > 110 ? "…" : ""}</small>}
              </div>
            </div>

            <div className="wizard-review-list">
              {[
                ["Categories", categorySummary(form.categories) || "None selected"],
                ["Phone", form.phone || "Not provided"],
                ["Hours", operatingHoursSummary(form) || "Not provided"],
                ["Website", form.website || "Not provided"],
                ["Instagram", form.instagram ? `@${normalizeInstagram(form.instagram)}` : "Not provided"],
                ["Offerings", form.offerings.length ? form.offerings.join(", ") : "None added"],
                ["Featured items", form.items.length ? `${form.items.length} item${form.items.length === 1 ? "" : "s"}` : "None added"],
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong>{value}</strong>
                </div>
              ))}
            </div>

            <div className="wizard-note">Listings are submitted as pending review. HEHA approval/verification is not automatic.</div>
            {errors.submit && <Error>{errors.submit}</Error>}
            <button className="wizard-submit-button" type="button" disabled={loading || !protectedApplicationEnabled} onClick={submit}>{loading ? "Submitting…" : "Submit for review"}</button>
            {!protectedApplicationEnabled && (
              <div className="wizard-note">
                Submission is in protected review. Existing invited businesses must use their verified, recipient-bound link;
                new self-applications unlock after idempotency, duplicate-prevention, and authorization proof pass.
              </div>
            )}
            <button className="wizard-text-back" type="button" onClick={back}>← Back to edit</button>
          </WizardPanel>
        )}
      </section>
    </main>
  );
}

function PartnerAccessGate({ title, copy, enabled, loading, error, onContinue, onCancel, buttonLabel }) {
  return (
    <main className="partner-wizard-screen">
      <section className="partner-wizard-shell">
        <WizardTopbar onCancel={onCancel} />
        <header className="wizard-step-header">
          <span className="wizard-step-icon">⌁</span>
          <div><p>Partner access</p><h1>{title}</h1></div>
        </header>
        <WizardPanel>
          <p className="wizard-helper-copy">{copy}</p>
          {!enabled && (
            <div className="wizard-note">
              Nothing has been claimed, submitted, published, or sent. HEHA will provide one protected resumable link after the release proof passes.
            </div>
          )}
          {error && <Error>{error}</Error>}
          <button className="wizard-submit-button" type="button" disabled={!enabled || loading} onClick={onContinue}>
            {loading ? "Verifying…" : buttonLabel}
          </button>
        </WizardPanel>
      </section>
    </main>
  );
}

function PartnerSubmissionStatus({ listing, entrySource, loading, error, onRefresh, onEdit, onContinue }) {
  const status = String(listing?.status || "pending").toLowerCase();
  const visible = PUBLIC_STATUSES.includes(status);
  const certified = listing?.heha_partner === true;
  const connectedByInvite = entrySource === "claim";
  const awaitingReview = ["submitted", "pending"].includes(status);
  const listingCategories = Array.isArray(listing?.categories) && listing.categories.length
    ? listing.categories
    : listing?.category
    ? [listing.category]
    : [];

  return (
    <main className="partner-wizard-screen">
      <section className="partner-wizard-shell">
        <div className="wizard-topbar">
          <div className="wizard-logo" aria-label="HEHA Swipe">
            <span />
            <strong>HEHA</strong>
            <em>swipe</em>
          </div>
          <strong>{connectedByInvite ? "Business connected" : "Application saved"}</strong>
        </div>

        <header className="wizard-step-header">
          <span className="wizard-step-icon">✓</span>
          <div>
            <p>{connectedByInvite ? "Private business invitation" : "Business application"}</p>
            <h1>{connectedByInvite ? "Verified" : awaitingReview ? "Sent for review" : "Saved privately"}</h1>
          </div>
        </header>

        <WizardPanel>
          <p className="wizard-helper-copy">
            {connectedByInvite
              ? "Your signed-in account is connected to this existing private business profile. No application was submitted by this claim."
              : awaitingReview
              ? "Your private business application is waiting for HEHA review."
              : "Your private business application is saved and needs more information before HEHA review."}
          </p>

          <div className="wizard-review-card">
            <div className="wizard-review-top" style={{ "--preview-color": "#114f35" }}>
              <span>✓</span>
              <div>
                <p>{categorySummary(listingCategories) || "Business"}</p>
                <h2>{listing.name || "Your business"}</h2>
              </div>
            </div>
          </div>

          <div className="wizard-review-list">
            {[
              ["Status", formatStatus(status)],
              ["Profile created", formatDate(listing.created_at)],
              ["Completion", completionLabel(listing.complete_pct)],
              ["Public visibility", visible ? "Visible" : "Hidden until review"],
              ["HEHA Certified", certified ? "Certified" : "Not certified yet"],
            ].map(([label, value]) => (
              <div key={label}>
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
            ))}
          </div>

          <div className="wizard-note">
            {connectedByInvite
              ? "Connecting your account did not submit, publish, certify, or make this business orderable."
              : "Saving an application does not publish, certify, or make this business orderable."}
          </div>

          {error && <Error>{error}</Error>}

          <button className="wizard-submit-button" type="button" onClick={onContinue}>
            Continue partner setup
          </button>
          <button className="wizard-text-back" type="button" onClick={onRefresh} disabled={loading}>
            {loading ? "Refreshing…" : "Refresh status"}
          </button>
          {onEdit && (
            <button className="wizard-text-back" type="button" onClick={onEdit} disabled={loading}>
              Correct saved application
            </button>
          )}

          <p className="wizard-helper-copy">
            Your Partner Hub keeps the complete sequence in one place: business verification, profile/menu, the correct agreement,
            photos, both home-screen installs, test order, and final publication approval. Your information stays saved.
          </p>
        </WizardPanel>
      </section>
    </main>
  );
}

function WizardTopbar({ onCancel }) {
  return (
    <div className="wizard-topbar">
      <div className="wizard-logo" aria-label="HEHA Swipe">
        <span />
        <strong>HEHA</strong>
        <em>swipe</em>
      </div>
      <button type="button" onClick={onCancel}>Exit setup</button>
    </div>
  );
}

function Progress({ step }) {
  return (
    <div className="wizard-progress" aria-label={`Step ${step + 1} of ${STEPS.length}`}>
      {STEPS.map((item, index) => <span key={item.id} className={index <= step ? "active" : ""} />)}
    </div>
  );
}

function WizardPanel({ children }) {
  return <div className="wizard-panel">{children}</div>;
}

function Field({ label, hint, required = false, error, children }) {
  return (
    <div className="wizard-field-block">
      <Label required={required}>{label} {hint && <em>({hint})</em>}</Label>
      {children}
      {error && <Error>{error}</Error>}
    </div>
  );
}

function Label({ required = false, children }) {
  return <label className="wizard-label">{children}{required && <span> *</span>}</label>;
}

function NavButtons({ onBack, backLabel = "← Back", onNext, nextLabel = "Next →" }) {
  return (
    <div className="wizard-nav-buttons">
      <button type="button" className="wizard-back-button" onClick={onBack}>{backLabel}</button>
      <button type="button" className="wizard-next-button" onClick={onNext}>{nextLabel}</button>
    </div>
  );
}

function Error({ children }) {
  return <div className="wizard-error">{children}</div>;
}
