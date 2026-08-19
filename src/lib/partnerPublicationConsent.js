export const PARTNER_PROFILE_CONSENT_VERSION = "wave1-profile-consent-2026-08-10";

export const PARTNER_DESTINATIONS = Object.freeze({
  swipe: "heha_swipe",
  local: "heha_local",
});

export const SWIPE_CATEGORIES = Object.freeze([
  "Restaurant",
  "Vendor",
  "Catering",
  "PrivateChef",
  "Wellness",
  "Coach",
  "Service",
  "Events",
]);

const LOCAL_CATEGORIES = new Set(["catering", "privatechef", "private chef"]);
const SWIPE_CATEGORY_KEYS = new Set([
  ...SWIPE_CATEGORIES.map((category) => category.toLowerCase()),
  "private chef",
]);
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

export function supportsHehaSwipe(categories = []) {
  return normalizedCategories(categories)
    .some((category) => SWIPE_CATEGORY_KEYS.has(category.toLowerCase()));
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
  const destinations = [];

  if (supportsHehaSwipe(categories)) {
    destinations.push({
      value: PARTNER_DESTINATIONS.swipe,
      label: "HEHA Swipe",
      description: "Let local customers discover your reviewed business profile in HEHA Swipe.",
    });
  }

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
  const swipeAllowed = supportsHehaSwipe(categories);
  return [...new Set((Array.isArray(destinations) ? destinations : [])
    .map((destination) => String(destination || "").trim())
    .filter((destination) => {
      if (!VALID_DESTINATIONS.has(destination)) return false;
      if (destination === PARTNER_DESTINATIONS.local) return localAllowed;
      return swipeAllowed;
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
  if (normalized.includes(PARTNER_DESTINATIONS.local) && !tampaBayServiceConfirmed) {
    errors.tampaBayServiceConfirmed = "Confirm that this business accepts requests in Tampa Bay.";
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
    destinations: normalized,
  };
}

export function validatePartnerPublicationWithdrawal({
  destinations = [],
  activeDestinations = [],
  representativeName = "",
  representativeTitle = "",
  withdrawalConfirmed = false,
} = {}) {
  const errors = {};
  const requested = Array.isArray(destinations) ? destinations : [];
  const active = new Set(
    (Array.isArray(activeDestinations) ? activeDestinations : [])
      .map((destination) => String(destination || "").trim())
      .filter((destination) => VALID_DESTINATIONS.has(destination))
  );
  const normalized = [...new Set(requested
    .map((destination) => String(destination || "").trim())
    .filter((destination) => VALID_DESTINATIONS.has(destination)))]
    .sort();

  if (
    !normalized.length
    || normalized.length !== requested.length
    || normalized.some((destination) => !active.has(destination))
  ) {
    errors.destinations = "Choose one or more currently approved destinations to withdraw.";
  }
  if (String(representativeName).trim().length < 2) {
    errors.representativeName = "Add the authorized representative’s full name.";
  }
  if (String(representativeTitle).trim().length < 2) {
    errors.representativeTitle = "Add the representative’s role or title.";
  }
  if (!withdrawalConfirmed) {
    errors.withdrawalConfirmed = "Confirm the selected destination withdrawal.";
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
