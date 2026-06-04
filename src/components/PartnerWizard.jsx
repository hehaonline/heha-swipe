import { useState } from "react";
import { supabase } from "../lib/supabase";

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

const emptyForm = {
  name: "",
  category: "",
  neighborhood: "",
  tagline: "",
  bio: "",
  hours: "",
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

export default function PartnerWizard({ user, onComplete, onCancel }) {
  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState({});
  const [form, setForm] = useState(emptyForm);
  const [newOffering, setNewOffering] = useState("");
  const [newItem, setNewItem] = useState({ name: "", price: "", emoji: "✦" });

  const activeStep = STEPS[step];

  const set = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: null }));
  };

  const validate = () => {
    const nextErrors = {};
    if (step === 0) {
      if (!form.name.trim()) nextErrors.name = "Business name is required.";
      if (!form.category) nextErrors.category = "Choose the closest category.";
      if (!form.neighborhood.trim()) nextErrors.neighborhood = "Neighborhood is required.";
      if (!form.tagline.trim()) nextErrors.tagline = "Add a short card headline.";
    }
    if (step === 1 && !form.bio.trim()) nextErrors.bio = "Tell people what makes your business special.";
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
      const completePct = [
        form.name,
        form.category,
        form.neighborhood,
        form.tagline,
        form.bio,
        form.phone || form.contact,
        form.website,
        form.instagram,
        form.offerings.length > 0,
        form.items.length > 0,
      ].filter(Boolean).length * 10;

      const { data, error } = await supabase.from("partners").insert({
        owner_id: user.id,
        name: form.name.trim(),
        category: form.category,
        neighborhood: form.neighborhood.trim(),
        tagline: form.tagline.trim(),
        bio: form.bio.trim(),
        hours: form.hours.trim() || null,
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
        status: "pending",
        complete_pct: completePct,
        heha_partner: false,
      }).select().single();

      if (error) throw error;

      try {
        const webhookUrl = import.meta.env.VITE_MAKE_PARTNER_APPROVAL_WEBHOOK;
        if (webhookUrl) {
          await fetch(webhookUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              partner_id: data.id,
              partner_name: data.name,
              category: data.category,
              neighborhood: data.neighborhood,
              owner_email: user.email || user.phone,
              status: "pending_review",
            }),
          });
        }
      } catch {
        // Webhook issues should not block the user from submitting their listing.
      }

      onComplete(data);
    } catch (error) {
      setErrors({ submit: error.message || "Could not submit this listing yet." });
    } finally {
      setLoading(false);
    }
  };

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
              <Label required>Category</Label>
              <div className="wizard-chip-grid">
                {CATEGORIES.map((category) => (
                  <button
                    type="button"
                    key={category.value}
                    className={form.category === category.value ? "selected" : ""}
                    onClick={() => set("category", category.value)}
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

            <Field label="Hours" hint="optional">
              <input value={form.hours} onChange={(event) => set("hours", event.target.value)} placeholder="Mon–Fri 8am–6pm, Sat 9am–3pm" />
            </Field>

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
                <p>{CATEGORY_LABELS[form.category] || "Category"} · {form.neighborhood || "Tampa Bay"}</p>
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
                  <p>{CATEGORY_LABELS[form.category] || form.category} · {form.neighborhood}</p>
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
                ["Phone", form.phone || "Not provided"],
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
            <button className="wizard-submit-button" type="button" disabled={loading} onClick={submit}>{loading ? "Submitting…" : "Submit for review"}</button>
            <button className="wizard-text-back" type="button" onClick={back}>← Back to edit</button>
          </WizardPanel>
        )}
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
      <button type="button" onClick={onCancel}>Save & exit</button>
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
