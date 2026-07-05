export const EVENT_TYPES = new Set([
  "event_partner",
  "event_venue",
  "event_vendor",
  "sponsor",
  "artist_musician",
  "community_organization",
]);

export const LEAD_TYPES = [
  ["potential_partner", "Potential partner"],
  ["heha_swipe_business", "HEHA Swipe business"],
  ["event_partner", "Event partner"],
  ["event_venue", "Event venue / space"],
  ["event_vendor", "Event vendor"],
  ["sponsor", "Sponsor"],
  ["artist_musician", "Artist / musician"],
  ["community_organization", "Community organization"],
  ["app_affiliate_partner", "App / affiliate partner"],
];

export const PIPELINE_STATUSES = [
  ["new_visit", "New visit"],
  ["researching", "Researching"],
  ["contact_ready", "Contact ready"],
  ["outreach", "Outreach"],
  ["responded", "Responded"],
  ["onboarding", "Onboarding"],
  ["partner", "Partner"],
  ["paused", "Paused"],
  ["not_a_fit", "Not a fit"],
];

export const READINESS_STATUS = {
  new_visit: "new_lead",
  researching: "new_lead",
  contact_ready: "new_lead",
  outreach: "contacted",
  responded: "interested",
  onboarding: "application_started",
  partner: "listed_not_certified",
  paused: "paused",
  not_a_fit: "rejected",
};

export const EMPTY_CONTACT = {
  contact_name: "",
  contact_role: "",
  phone: "",
  email: "",
  instagram: "",
  linkedin: "",
  notes: "",
};

export function blankForm(lens = "admin") {
  return {
    business_name: "",
    lead_type: lens === "events" ? "event_partner" : "potential_partner",
    heha_pillar: "",
    business_category: "",
    address: "",
    city: "",
    state: "",
    postal_code: "",
    phone: "",
    email: "",
    website: "",
    instagram: "",
    google_maps_url: "",
    primary_contact_name: "",
    primary_contact_role: "",
    visit_notes: "",
    first_impression: "",
    heha_fit_notes: "",
    fit_score: "",
    products_services: "",
    potential_offer: "",
    image_url: "",
    event_capacity: "",
    indoor_outdoor: "",
    parking_notes: "",
    food_vendor_policy: "",
    alcohol_policy: "",
    music_noise_policy: "",
    power_notes: "",
    restroom_notes: "",
    rental_cost_notes: "",
    availability_notes: "",
  };
}

export function nullIfBlank(value) {
  if (typeof value !== "string") return value;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

export function labelFor(options, value) {
  return options.find(([key]) => key === value)?.[1] || value;
}

export function leadPayload(form, userId) {
  const payload = {};
  Object.entries(form).forEach(([key, value]) => {
    payload[key] = nullIfBlank(value);
  });
  payload.fit_score = form.fit_score ? Number(form.fit_score) : null;
  payload.created_by = userId;
  payload.updated_by = userId;
  payload.source = "field_visit";
  return payload;
}
