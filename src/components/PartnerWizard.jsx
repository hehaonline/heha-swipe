import { Children, cloneElement, isValidElement, useId, useState } from "react";
import { supabase } from "../lib/supabase";
import {
  PARTNER_DESTINATIONS,
  availablePartnerDestinations,
  createPartnerConsentRequestKey,
  publicationStatusLabel,
  supportsHehaLocal,
  validatePartnerDraftAuthorization,
} from "../lib/partnerPublicationConsent";
import {
  authorizePartnerProfilePublication,
  getMyPartnerPublicationStatus,
  submitPartnerRegistrationWithConsent,
} from "../services/partnerPublicationConsentRepository";
import PartnerPublicationPreview from "./PartnerPublicationPreview";

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

const emptyAuthorization = {
  destinations: [],
  representativeName: "",
  representativeTitle: "",
  authorityConfirmed: false,
  profileConfirmed: false,
  mediaPermissionConfirmed: false,
  tampaBayServiceConfirmed: false,
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
  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState({});
  const [form, setForm] = useState(emptyForm);
  const [authorization, setAuthorization] = useState(emptyAuthorization);
  const [submissionKey] = useState(() => createPartnerConsentRequestKey());
  const [newOffering, setNewOffering] = useState("");
  const [newItem, setNewItem] = useState({ name: "", price: "", emoji: "✦" });
  const [submittedListing, setSubmittedListing] = useState(null);
  const [statusLoading, setStatusLoading] = useState(false);
  const [statusError, setStatusError] = useState(null);
  const authorizationErrorPrefix = useId();

  const activeStep = STEPS[step];

  const focusFirstError = () => {
    window.requestAnimationFrame(() => {
      document.querySelector('[aria-invalid="true"], .wizard-error')?.focus();
    });
  };

  const set = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: null }));
  };

  const setAuthorizationField = (field, value) => {
    setAuthorization((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: null }));
  };

  const toggleDestination = (destination) => {
    setAuthorization((current) => ({
      ...current,
      destinations: current.destinations.includes(destination)
        ? current.destinations.filter((value) => value !== destination)
        : [...current.destinations, destination],
      tampaBayServiceConfirmed:
        destination === PARTNER_DESTINATIONS.local
          && current.destinations.includes(destination)
          ? false
          : current.tampaBayServiceConfirmed,
    }));
    setErrors((current) => ({
      ...current,
      destinations: null,
      ...(destination === PARTNER_DESTINATIONS.local
        ? { tampaBayServiceConfirmed: null }
        : {}),
    }));
  };

  const toggleCategory = (value) => {
    const selected = form.categories.includes(value)
      ? form.categories.filter((category) => category !== value)
      : [...form.categories, value];

    setForm((current) => ({
      ...current,
      categories: selected,
      category: selected[0] || "",
      photo_emoji: current.categories.length === 0 && selected.length === 1
        ? CATEGORY_EMOJIS[selected[0]] || current.photo_emoji
        : current.photo_emoji,
    }));

    if (!supportsHehaLocal(selected)) {
      setAuthorization((current) => ({
        ...current,
        destinations: current.destinations.filter(
          (destination) => destination !== PARTNER_DESTINATIONS.local
        ),
        tampaBayServiceConfirmed: false,
      }));
    }
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
    if (Object.keys(nextErrors).length) focusFirstError();
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
    const authorizationResult = validatePartnerDraftAuthorization({
      categories: form.categories,
      ...authorization,
    });
    if (!authorizationResult.valid) {
      setErrors((current) => ({ ...current, ...authorizationResult.errors }));
      focusFirstError();
      return;
    }

    setLoading(true);
    setErrors({});
    try {
      const data = await submitPartnerRegistrationWithConsent({
        form: {
          ...form,
          hours: operatingHoursSummary(form) || null,
          deliveryDays: orderedScheduleDays(form.scheduleDays),
          instagram: normalizeInstagram(form.instagram),
        },
        authorization: {
          ...authorization,
          destinations: authorizationResult.destinations,
        },
        submissionKey,
      });

      // SEC-002: the durable review-queue write above is the authoritative
      // review handoff. No browser-side webhook notification is sent; any
      // optional notification must come from an authenticated server-side
      // consumer with a protected secret (see issue #86).
      setSubmittedListing(data);
      setStatusError(null);
    } catch (error) {
      setErrors({ submit: error.message || "Could not submit this listing yet." });
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
        .select("id, name, category, categories, status, created_at, updated_at, complete_pct, heha_partner, swipe_eligible, local_eligible, local_lane, primary_cta_destination, primary_cta_path")
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

  if (submittedListing) {
    return (
      <PartnerSubmissionStatus
        listing={submittedListing}
        loading={statusLoading}
        error={statusError}
        authorization={{
          ...authorization,
          destinations: [...authorization.destinations].sort(),
        }}
        onRefresh={refreshSubmittedListing}
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
              <Label required>Categories</Label>
              <p className="wizard-helper-copy">Choose every category that applies. The first one selected is your primary card category.</p>
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

            <Field label="Full address" hint="optional · kept private for review and logistics">
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
              {supportsHehaLocal(form.categories) && (
                <p className="fine-print">
                  For chefs and caterers, these details stay private during Wave 1. You set the real menu or per-portion price when approving a customer quote.
                </p>
              )}
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
            <p className="wizard-helper-copy">Review the profile, choose where HEHA may prepare it, and record the authorized business representative. Nothing is published automatically.</p>
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

            <p className="eyebrow">Public profile fields</p>
            <div className="wizard-review-list">
              {[
                ["Categories", categorySummary(form.categories) || "None selected"],
                ["Public service area", form.neighborhood || "Not provided"],
                ["Hours", operatingHoursSummary(form) || "Not provided"],
                ["Business type", form.business_type || "Not provided"],
                ["Website", form.website || "Not provided"],
                ["Instagram", form.instagram ? `@${normalizeInstagram(form.instagram)}` : "Not provided"],
                ["Offerings", form.offerings.length ? form.offerings.join(", ") : "None added"],
                ...(supportsHehaLocal(form.categories)
                  ? [["Wave 1 pricing", "To be quoted — you set the food/service price"]]
                  : [["Featured items", form.items.length ? `${form.items.length} item${form.items.length === 1 ? "" : "s"}` : "None added"]]),
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong>{value}</strong>
                </div>
              ))}
            </div>

            <p className="eyebrow wizard-private-heading">Private verification and logistics</p>
            <div className="wizard-review-list wizard-private-fields">
              {[
                ["Phone", form.phone || "Not provided"],
                ["Direct contact", form.contact || "Not provided"],
                ["Full address", form.location || "Not provided"],
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong>{value}</strong>
                </div>
              ))}
            </div>
            <p className="fine-print">Private fields are not included in HEHA’s public partner views.</p>

            <div className="wizard-consent-card">
              <div>
                <p className="eyebrow">Private profile preparation</p>
                <h2>Where may HEHA prepare this profile?</h2>
                <p>Nothing is selected for you. HEHA Local is offered here only to caterers and private chefs.</p>
              </div>

              <div
                className="wizard-destination-list"
                role="group"
                aria-label="HEHA profile destinations"
                aria-describedby={errors.destinations ? `${authorizationErrorPrefix}-destinations` : undefined}
              >
                {availablePartnerDestinations(form.categories).map((destination) => (
                  <label key={destination.value} className="wizard-check-row">
                    <input
                      type="checkbox"
                      checked={authorization.destinations.includes(destination.value)}
                      onChange={() => toggleDestination(destination.value)}
                      aria-invalid={errors.destinations ? "true" : undefined}
                    />
                    <span>
                      <strong>{destination.label}</strong>
                      <small>{destination.description}</small>
                    </span>
                  </label>
                ))}
              </div>
              {errors.destinations && <Error id={`${authorizationErrorPrefix}-destinations`}>{errors.destinations}</Error>}

              <Field label="Authorized representative" required error={errors.representativeName}>
                <input
                  value={authorization.representativeName}
                  onChange={(event) => setAuthorizationField("representativeName", event.target.value)}
                  placeholder="Full name"
                  autoComplete="name"
                />
              </Field>
              <Field label="Role or title" required error={errors.representativeTitle}>
                <input
                  value={authorization.representativeTitle}
                  onChange={(event) => setAuthorizationField("representativeTitle", event.target.value)}
                  placeholder="Owner, founder, manager…"
                />
              </Field>

              <label className="wizard-check-row">
                <input
                  type="checkbox"
                  checked={authorization.authorityConfirmed}
                  onChange={(event) => setAuthorizationField("authorityConfirmed", event.target.checked)}
                  aria-invalid={errors.authorityConfirmed ? "true" : undefined}
                  aria-describedby={errors.authorityConfirmed ? `${authorizationErrorPrefix}-authorityConfirmed` : undefined}
                />
                <span>
                  <strong>I am authorized to represent this business.</strong>
                  <small>HEHA records the signed-in account and timestamp as evidence.</small>
                </span>
              </label>
              {errors.authorityConfirmed && <Error id={`${authorizationErrorPrefix}-authorityConfirmed`}>{errors.authorityConfirmed}</Error>}

              <label className="wizard-check-row">
                <input
                  type="checkbox"
                  checked={authorization.profileConfirmed}
                  onChange={(event) => setAuthorizationField("profileConfirmed", event.target.checked)}
                  aria-invalid={errors.profileConfirmed ? "true" : undefined}
                  aria-describedby={errors.profileConfirmed ? `${authorizationErrorPrefix}-profileConfirmed` : undefined}
                />
                <span>
                  <strong>HEHA may prepare a private draft for the destinations I selected.</strong>
                  <small>I will separately approve the exact profile version before HEHA may publish it.</small>
                </span>
              </label>
              {errors.profileConfirmed && <Error id={`${authorizationErrorPrefix}-profileConfirmed`}>{errors.profileConfirmed}</Error>}

              <label className="wizard-check-row">
                <input
                  type="checkbox"
                  checked={authorization.mediaPermissionConfirmed}
                  onChange={(event) => setAuthorizationField("mediaPermissionConfirmed", event.target.checked)}
                  aria-invalid={errors.mediaPermissionConfirmed ? "true" : undefined}
                  aria-describedby={errors.mediaPermissionConfirmed ? `${authorizationErrorPrefix}-mediaPermissionConfirmed` : undefined}
                />
                <span>
                  <strong>I own or have permission to use business media I supply to HEHA.</strong>
                  <small>HEHA will not treat stock placeholders as partner-supplied media.</small>
                </span>
              </label>
              {errors.mediaPermissionConfirmed && <Error id={`${authorizationErrorPrefix}-mediaPermissionConfirmed`}>{errors.mediaPermissionConfirmed}</Error>}

              {authorization.destinations.includes(PARTNER_DESTINATIONS.local) && (
                <>
                  <label className="wizard-check-row">
                    <input
                      type="checkbox"
                      checked={authorization.tampaBayServiceConfirmed}
                      onChange={(event) => setAuthorizationField("tampaBayServiceConfirmed", event.target.checked)}
                      aria-invalid={errors.tampaBayServiceConfirmed ? "true" : undefined}
                      aria-describedby={errors.tampaBayServiceConfirmed ? `${authorizationErrorPrefix}-tampaBayServiceConfirmed` : undefined}
                    />
                    <span>
                      <strong>This business accepts chef or catering requests in Tampa Bay.</strong>
                      <small>HEHA records Tampa Bay as the service area for this Wave 1 profile.</small>
                    </span>
                  </label>
                  {errors.tampaBayServiceConfirmed && <Error id={`${authorizationErrorPrefix}-tampaBayServiceConfirmed`}>{errors.tampaBayServiceConfirmed}</Error>}
                </>
              )}
            </div>

            <div className="wizard-note">
              Step 1 saves a private draft authorization. Step 2 asks you to approve this exact profile version. HEHA review and HEHA Certified status remain separate. Partner terms and privacy acknowledgements must be completed before activation.
            </div>
            {errors.submit && <Error>{errors.submit}</Error>}
            <button className="wizard-submit-button" type="button" disabled={loading} onClick={submit}>{loading ? "Saving private draft…" : "Prepare private profile"}</button>
            <button className="wizard-text-back" type="button" onClick={back}>← Back to edit</button>
          </WizardPanel>
        )}
      </section>
    </main>
  );
}

function PartnerSubmissionStatus({ listing, loading, error, authorization, onRefresh, onContinue }) {
  const status = String(listing?.status || "pending").toLowerCase();
  const certified = listing?.heha_partner === true;
  const listingCategories = Array.isArray(listing?.categories) && listing.categories.length
    ? listing.categories
    : listing?.category
    ? [listing.category]
    : [];
  const [approvalConfirmed, setApprovalConfirmed] = useState(false);
  const [approvalLoading, setApprovalLoading] = useState(false);
  const [approvalError, setApprovalError] = useState(null);
  const [approvalKey, setApprovalKey] = useState(() => createPartnerConsentRequestKey());
  const [approvalRecorded, setApprovalRecorded] = useState(false);
  const [publicationStatus, setPublicationStatus] = useState({
    prepare_destinations: authorization.destinations,
    publication_destinations: [],
    staff_review_destinations: [],
    public_destinations: [],
    profile_snapshot: listing.public_profile_snapshot,
    profile_snapshot_hash: listing.public_profile_snapshot_hash,
  });
  const publicationApproved = publicationStatusLabel(publicationStatus) === "Approved to publish";
  const previewReady = Boolean(
    publicationStatus.profile_snapshot
    && publicationStatus.profile_snapshot_hash
  );
  // This array is resolved from the final public database views. Owner consent
  // alone is deliberately not enough to report a listing as live.
  const visible = Array.isArray(publicationStatus.public_destinations)
    && publicationStatus.public_destinations.length > 0;

  const approvePublication = async () => {
    if (!approvalConfirmed || publicationApproved || !previewReady) return;
    setApprovalLoading(true);
    setApprovalError(null);
    try {
      await authorizePartnerProfilePublication({
        partnerId: listing.id,
        destinations: authorization.destinations,
        representativeName: authorization.representativeName,
        representativeTitle: authorization.representativeTitle,
        requestKey: approvalKey,
        expectedProfileSnapshotHash: publicationStatus.profile_snapshot_hash,
      });
      setApprovalRecorded(true);
      setApprovalConfirmed(false);
      setApprovalKey(createPartnerConsentRequestKey());
      try {
        const nextStatus = await getMyPartnerPublicationStatus(listing.id);
        setPublicationStatus(nextStatus);
        setApprovalRecorded(false);
      } catch (statusRefreshError) {
        setApprovalError("Publication approval was saved, but its status could not refresh. Use Refresh status; do not approve again.");
      }
    } catch (authorizationError) {
      setApprovalError(authorizationError.message || "Could not record publication approval yet.");
    } finally {
      setApprovalLoading(false);
    }
  };

  const refreshAll = async () => {
    await onRefresh();
    try {
      const nextStatus = await getMyPartnerPublicationStatus(listing.id);
      setPublicationStatus(nextStatus);
      setApprovalError(null);
      setApprovalRecorded(false);
    } catch (statusRefreshError) {
      setApprovalError(statusRefreshError.message || "Could not refresh publication permission yet.");
    }
  };

  return (
    <main className="partner-wizard-screen">
      <section className="partner-wizard-shell">
        <div className="wizard-topbar">
          <div className="wizard-logo" aria-label="HEHA Swipe">
            <span />
            <strong>HEHA</strong>
            <em>swipe</em>
          </div>
          <strong>Registration saved</strong>
        </div>

        <header className="wizard-step-header">
          <span className="wizard-step-icon">✓</span>
          <div>
            <p>Business registration</p>
            <h1>Submitted</h1>
          </div>
        </header>

        <WizardPanel>
          <p className="wizard-helper-copy">
            Your private business profile was saved. Review this exact version before granting publication permission.
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
              ["Submitted", formatDate(listing.created_at)],
              ["Completion", completionLabel(listing.complete_pct)],
              ["Profile permission", publicationStatusLabel(publicationStatus)],
              ["Destinations", authorization.destinations.map((destination) => destination === PARTNER_DESTINATIONS.local ? "HEHA Local" : "HEHA Swipe").join(", ")],
              ["Public visibility", visible ? "Visible" : "Hidden until review"],
              ["HEHA Certified", certified ? "Certified" : "Not certified yet"],
            ].map(([label, value]) => (
              <div key={label}>
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
            ))}
          </div>

          <PartnerPublicationPreview snapshot={publicationStatus.profile_snapshot || listing.public_profile_snapshot} />

          {!publicationApproved ? (
            <div className="wizard-consent-card publication-approval-card">
              <div>
                <p className="eyebrow">Final profile permission</p>
                <h2>Approve this version to publish</h2>
                <p>This does not publish the profile now. It authorizes HEHA to publish only this exact version on your selected destinations after HEHA’s separate review.</p>
              </div>
              <label className="wizard-check-row">
                <input
                  type="checkbox"
                  checked={approvalConfirmed}
                  onChange={(event) => setApprovalConfirmed(event.target.checked)}
                />
                <span>
                  <strong>I approve this exact profile version for publication.</strong>
                  <small>If the public profile changes, HEHA must ask for approval again.</small>
                </span>
              </label>
              <button
                className="wizard-submit-button"
                type="button"
                disabled={!approvalConfirmed || approvalLoading || !previewReady || approvalRecorded}
                onClick={approvePublication}
              >
                {approvalLoading ? "Recording approval…" : previewReady ? "Approve this version to publish" : "Preview required before approval"}
              </button>
            </div>
          ) : (
            <div className="wizard-success-note" role="status">
              Profile version approved for publication. HEHA review, activation, and HEHA Certified status are still separate decisions.
            </div>
          )}

          <div className="wizard-note">
            Your submission is saved. Nothing is public until HEHA completes its review and an authorized HEHA administrator activates only the destinations you approved.
          </div>

          {error && <Error>{error}</Error>}
          {approvalError && <Error>{approvalError}</Error>}

          <button className="wizard-submit-button" type="button" onClick={onContinue}>
            Continue to business profile
          </button>
          <button className="wizard-text-back" type="button" onClick={refreshAll} disabled={loading || approvalLoading}>
            {loading ? "Refreshing…" : "Refresh status"}
          </button>

          <p className="wizard-helper-copy">
            Profile editing, logo/photo upload, and listing preview are the next reviewed Partner Hub tools. Your submitted information stays saved.
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
      <button type="button" onClick={onCancel}>Exit without saving</button>
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
  const generatedId = useId();
  const errorId = `${generatedId}-error`;
  const childArray = Children.toArray(children);
  const controlIndex = childArray.findIndex((child) => isValidElement(child));
  const sourceControl = controlIndex >= 0 ? childArray[controlIndex] : null;
  const controlId = sourceControl?.props?.id || generatedId;
  const renderedChildren = childArray.map((child, index) => (
    index === controlIndex
      ? cloneElement(child, {
          id: controlId,
          "aria-invalid": error ? "true" : undefined,
          "aria-describedby": [child.props["aria-describedby"], error ? errorId : null]
            .filter(Boolean)
            .join(" ") || undefined,
        })
      : child
  ));
  return (
    <div className="wizard-field-block">
      <Label htmlFor={sourceControl ? controlId : undefined} required={required}>{label} {hint && <em>({hint})</em>}</Label>
      {renderedChildren}
      {error && <Error id={errorId}>{error}</Error>}
    </div>
  );
}

function Label({ htmlFor, required = false, children }) {
  const content = <>{children}{required && <span> *</span>}</>;
  return htmlFor
    ? <label className="wizard-label" htmlFor={htmlFor}>{content}</label>
    : <div className="wizard-label">{content}</div>;
}

function NavButtons({ onBack, backLabel = "← Back", onNext, nextLabel = "Next →" }) {
  return (
    <div className="wizard-nav-buttons">
      <button type="button" className="wizard-back-button" onClick={onBack}>{backLabel}</button>
      <button type="button" className="wizard-next-button" onClick={onNext}>{nextLabel}</button>
    </div>
  );
}

function Error({ id, children }) {
  return <div className="wizard-error" id={id} role="alert" tabIndex={-1}>{children}</div>;
}
