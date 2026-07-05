import { EVENT_TYPES, LEAD_TYPES } from "./scoutConfig";
import ScoutEventFields from "./ScoutEventFields";

const CORE_FIELDS = [
  ["business_name", "Business / lead name"],
  ["business_category", "Business category", "Restaurant, yoga, market…"],
  ["address", "Address"],
  ["city", "City"],
  ["state", "State"],
  ["postal_code", "ZIP"],
  ["phone", "Phone"],
  ["email", "Email"],
  ["website", "Website"],
  ["instagram", "Instagram"],
  ["google_maps_url", "Google Maps URL"],
  ["primary_contact_name", "Person I spoke with"],
  ["primary_contact_role", "Their role", "Owner, manager…"],
  ["image_url", "Image URL"],
];

const NOTE_FIELDS = [
  ["products_services", "What do they offer?"],
  ["visit_notes", "Visit notes"],
  ["first_impression", "First impression"],
  ["heha_fit_notes", "Why could this fit HEHA?"],
  ["potential_offer", "Potential deal / discount / contribution"],
];

export default function ScoutLeadForm({ form, setForm, eventOnly, saving, onSubmit }) {
  const set = (key) => (event) => setForm({ ...form, [key]: event.target.value });
  const visibleTypes = LEAD_TYPES.filter(([type]) => !eventOnly || EVENT_TYPES.has(type));

  return (
    <form className="scout-form" onSubmit={onSubmit}>
      <div className="scout-section-heading">
        <div><p className="internal-eyebrow">Field visit intake</p><h2>Add what you noticed</h2></div>
        <span>Everything below is optional.</span>
      </div>

      <div className="scout-form-grid">
        <label>Lead type<select value={form.lead_type} onChange={set("lead_type")}>{visibleTypes.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <label>HEHA pillar<select value={form.heha_pillar} onChange={set("heha_pillar")}><option value="">Not chosen</option><option value="nourish">Nourish</option><option value="educate">Educate</option><option value="relax">Relax</option><option value="elevate">Elevate</option></select></label>
        <label>HEHA fit 1–5<select value={form.fit_score} onChange={set("fit_score")}><option value="">Not scored</option>{[1, 2, 3, 4, 5].map((score) => <option key={score} value={score}>{score}</option>)}</select></label>
        {CORE_FIELDS.map(([key, label, placeholder]) => (
          <label key={key} className={key === "address" || key === "google_maps_url" ? "wide" : ""}>
            {label}<input placeholder={placeholder || ""} value={form[key]} onChange={set(key)} />
          </label>
        ))}
        {NOTE_FIELDS.map(([key, label]) => (
          <label className="wide" key={key}>{label}<textarea value={form[key]} onChange={set(key)} /></label>
        ))}
      </div>

      {EVENT_TYPES.has(form.lead_type) && <ScoutEventFields form={form} setForm={setForm} />}

      <div className="scout-form-actions">
        <button className="scout-primary-button" type="submit" disabled={saving}>
          {saving ? "Saving lead…" : "Save as potential lead"}
        </button>
        <p>Public HEHA Swipe approval stays with Admin.</p>
      </div>
    </form>
  );
}
