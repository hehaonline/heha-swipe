export const PARTNER_PROFILE_CONSENT_VERSION = "wave1-profile-consent-2026-08-10";

export const PARTNER_DESTINATIONS = Object.freeze({
  swipe: "heha_swipe",
  local: "heha_local",
});

const LOCAL_CATEGORIES = new Set(["catering", "privatechef", "private chef"]);
const VALID_DESTINATIONS = new Set(Object.values(PARTNER_DESTINATIONS));

function normalizedCategories(categories = []) {
  return [...new Set((Array.isArray(categories) ? categories : [])
    .map((category) => String(category || "").trim())
    .filter(Boolean))];
}

export function supportsHehaLocal(categories = []) {
  return normalizedCategories(categories)
    .some((category) => LOCAL_CATEGORIES.has(category.toLowerCase()));
}

export function deriveWave1LocalLane(categories = []) {
  const values = normalizedCategories(categories).map((category) => category.toLowerCase());
  for (const value of values) {
    if (value === "privatechef" || value === "private chef") return "chef";
    if (value === "catering") return "group_orders";
  }
  return null;
}

export function availablePartnerDestinations(categories = []) {
  const destinations = [
    {
      value: PARTNER_DESTINATIONS.swipe,
      label: "HEHA Swipe",
      description: "Let local customers discover your reviewed business profile in HEHA Swipe.",
    },
  ];

  if (supportsHehaLocal(categories)) {
    destinations.push({
      value: PARTNER_DESTINATIONS.local,
      label: "HEHA Local",
      description: "Prepare a Tampa Bay catering or private-chef profile for HEHA Local requests.",
    });
  }

  return destinations;
}

export function normalizePartnerDestinations(destinations = [], categories = []) {
  const localAllowed = supportsHehaLocal(categories);
  return [...new Set((Array.isArray(destinations) ? destinations : [])
    .map((destination) => String(destination || "").trim())
    .filter((destination) => {
      if (!VALID_DESTINATIONS.has(destination)) return false;
      return destination !== PARTNER_DESTINATIONS.local || localAllowed;
    }))]
    .sort();
}

export function validatePartnerDraftAuthorization({
  categories = [],
  destinations = [],
  representativeName = "",
  representativeTitle = "",
  authorityConfirmed = false,
  profileConfirmed = false,
  mediaPermissionConfirmed = false,
  tampaBayServiceConfirmed = false,
} = {}) {
  const errors = {};
  const normalized = normalizePartnerDestinations(destinations, categories);

  if (!normalized.length || normalized.length !== destinations.length) {
    errors.destinations = "Choose at least one available HEHA destination.";
  }
  if (String(representativeName).trim().length < 2) {
    errors.representativeName = "Add the authorized representative’s full name.";
  }
  if (String(representativeTitle).trim().length < 2) {
    errors.representativeTitle = "Add the representative’s role or title.";
  }
  if (!authorityConfirmed) {
    errors.authorityConfirmed = "Confirm that you are authorized to represent this business.";
  }
  if (!profileConfirmed) {
    errors.profileConfirmed = "Confirm that HEHA may prepare a private profile for review.";
  }
  if (!mediaPermissionConfirmed) {
    errors.mediaPermissionConfirmed = "Confirm that supplied business media may be used for the reviewed profile.";
  }
  if (supportsHehaLocal(categories) && !tampaBayServiceConfirmed) {
    errors.tampaBayServiceConfirmed = "Confirm that this business accepts requests in Tampa Bay.";
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
    destinations: normalized,
  };
}

export function createPartnerConsentRequestKey() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();

  // UUIDv4-compatible fallback for older embedded browsers. The server still
  // validates the value as a UUID and uses it only as an idempotency key.
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

export function publicationStatusLabel(status) {
  const prepared = new Set(
    Array.isArray(status?.prepare_destinations) ? status.prepare_destinations : []
  );
  const approved = new Set(
    Array.isArray(status?.publication_destinations) ? status.publication_destinations : []
  );
  const matches = prepared.size === approved.size
    && [...prepared].every((destination) => approved.has(destination));

  if (prepared.size > 0 && matches) return "Approved to publish";
  if (prepared.size > 0) return "Awaiting profile approval";
  return "Permission needed";
}
