const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const LEGACY_CATEGORY_ALIASES = new Map([
  ["PrivateChef", "Private Chef"],
  ["FarmersMarket", "Markets"],
  ["Market", "Markets"],
  ["Grocery", "Markets"],
]);

function isRecord(value) {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function nullableText(value) {
  return String(value || "").trim() || null;
}

function parseCommaList(value) {
  const entries = Array.isArray(value) ? value : String(value || "").split(",");
  return [...new Set(entries.map((item) => String(item || "").trim()).filter(Boolean))];
}

function normalizedCategories(value) {
  return [...new Set(
    parseCommaList(value).map((item) => LEGACY_CATEGORY_ALIASES.get(item) || item),
  )];
}

function rawLockedCategories(listing) {
  if (listing?.categories === null) return null;
  if (Array.isArray(listing?.categories)) {
    if (!listing.categories.every((category) => typeof category === "string")) {
      throw new Error("Invalid locked partner categories.");
    }
    return cloneJsonValue(listing.categories, []);
  }
  throw new Error("Invalid locked partner categories.");
}

function rawLockedText(value, { nullable = false } = {}) {
  if (value === null && nullable) return null;
  if (typeof value !== "string") throw new Error("Invalid locked partner field.");
  return value;
}

function cloneJsonValue(value, fallback) {
  try {
    const cloned = JSON.parse(JSON.stringify(value));
    return cloned === undefined ? fallback : cloned;
  } catch {
    return fallback;
  }
}

function profileHours(form, listing, claimBound) {
  if (claimBound && isRecord(listing?.hours)) {
    return cloneJsonValue(listing.hours, {});
  }
  return nullableText(form.hours);
}

export function hasVerifiedPartnerClaim(capabilities, { partnerId, actorId }) {
  return Boolean(
    isRecord(capabilities)
    && capabilities.projection_version === "heha-partner-onboarding-v1"
    && capabilities.partner_id === partnerId
    && capabilities.authorized_actor_id === actorId
    && isRecord(capabilities.claim)
    && capabilities.claim.status === "verified"
    && typeof capabilities.claim.evidence_id === "string"
    && UUID_PATTERN.test(capabilities.claim.evidence_id),
  );
}

export function buildProtectedPartnerProfileSnapshot(form, listing, { claimBound }) {
  const formCategories = normalizedCategories(form.categories);
  const lockedCategories = claimBound ? rawLockedCategories(listing) : null;
  const categories = claimBound ? lockedCategories : formCategories;
  const completePct = Number(listing?.complete_pct);

  return {
    name: claimBound ? rawLockedText(listing?.name) : String(form.name || "").trim(),
    category: claimBound
      ? rawLockedText(listing?.category ?? null, { nullable: true })
      : formCategories[0] || null,
    categories,
    neighborhood: claimBound
      ? rawLockedText(listing?.neighborhood ?? null, { nullable: true })
      : nullableText(form.neighborhood),
    tagline: nullableText(form.tagline),
    bio: nullableText(form.bio),
    hours: profileHours(form, listing, claimBound),
    delivery_days: parseCommaList(form.delivery_days),
    business_type: claimBound
      ? rawLockedText(listing?.business_type ?? null, { nullable: true })
      : nullableText(form.business_type),
    phone: nullableText(form.phone),
    contact: nullableText(form.contact),
    website: nullableText(form.website),
    instagram: nullableText(String(form.instagram || "").replace(/^@/, "")),
    location: claimBound
      ? rawLockedText(listing?.location ?? null, { nullable: true })
      : nullableText(form.location),
    offerings: parseCommaList(form.offerings),
    items: cloneJsonValue(listing?.items, []),
    photo_emoji: nullableText(listing?.photo_emoji) || "🏪",
    color: nullableText(listing?.color) || "#ff8a24",
    complete_pct: Number.isFinite(completePct)
      ? Math.min(100, Math.max(0, completePct))
      : 0,
  };
}

export function claimedProfileHasStructuredHours(listing) {
  return isRecord(listing?.hours);
}
