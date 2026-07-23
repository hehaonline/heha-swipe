const DEFAULT_HEHA_LOCAL_ORIGIN = "https://hehalocal.app";

// Temporary bridge for the three currently approved/orderable Swipe partners.
// Remove this map after the canonical public partner relationship is exposed
// directly to Swipe through the approved cross-app routing model.
const LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID = {
  "2fbe55b6-f7ba-453d-8923-72f22946fea9": "/restaurants/2961f869-915b-4fa3-82db-8c6364c2e274",
  "3f5b29bc-662b-40b9-ad06-6dcb6592b396": "/restaurants/dccd000b-49d5-43e2-b684-704698d7f934",
  "b7a71d3e-8eb7-46dd-8703-02f1cbdbd451": "/vendors/94654184-7c9d-4527-b642-f78c3f75ac24",
};

// Generic HEHA Local listing routes that do not point at a specific partner
// profile. A CTA that promises a partner's "full menu" must never resolve
// to one of these - it either has a real profile destination or it doesn't
// qualify as a HEHA Local routable partner at all.
const GENERIC_HEHA_LOCAL_LISTING_PATHS = new Set([
  "",
  "/",
  "/restaurants",
  "/restaurants/",
  "/vendors",
  "/vendors/",
]);

function localOrigin() {
  const configured = String(import.meta.env.VITE_HEHA_LOCAL_URL || "").trim();
  return (configured || DEFAULT_HEHA_LOCAL_ORIGIN).replace(/\/$/, "");
}

function legacyItemUrl(item) {
  return item?.url || item?.product_url || item?.link || null;
}

function normalizedConfiguredPath(partner) {
  const configuredPath = String(partner?.primary_cta_path || "").trim();
  if (!configuredPath) return "";
  return configuredPath.startsWith("/") ? configuredPath : `/${configuredPath}`;
}

function isGenericHehaLocalListingPath(path) {
  const normalized = String(path || "").trim();
  if (GENERIC_HEHA_LOCAL_LISTING_PATHS.has(normalized)) return true;
  return GENERIC_HEHA_LOCAL_LISTING_PATHS.has(normalized.replace(/\/$/, ""));
}

// A partner only has a "specific" HEHA Local destination when it resolves to
// an individual partner profile (e.g. /restaurants/<id> or /vendors/<id>)
// rather than a generic listing route like "/restaurants" or "/vendors".
export function hasSpecificHehaLocalDestination(partner) {
  if (LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID[partner?.id]) return true;

  const configuredPath = normalizedConfiguredPath(partner);
  if (!configuredPath) return false;
  return !isGenericHehaLocalListingPath(configuredPath);
}

export function isHehaLocalPartner(partner) {
  return Boolean(
    partner?.local_eligible
    && String(partner?.primary_cta_destination || "").toLowerCase() === "local"
    && hasSpecificHehaLocalDestination(partner),
  );
}

export function hehaLocalProfilePath(partner) {
  const mappedPath = LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID[partner?.id];
  if (mappedPath) return mappedPath;

  const configuredPath = normalizedConfiguredPath(partner);
  return configuredPath || "/restaurants";
}

export function hehaLocalProfileUrl(partner) {
  return `${localOrigin()}${hehaLocalProfilePath(partner)}`;
}

export function hehaLocalItemUrl(partner, item) {
  const url = new URL(hehaLocalProfileUrl(partner));
  // HEHA Local currently opens item details by the public product name.
  // Keep IDs on the Swipe item for lineage, but prefer the name in the URL.
  const itemIdentity = item?.name || item?.local_product_id || item?.product_id;
  if (itemIdentity) url.searchParams.set("item", String(itemIdentity));
  return url.toString();
}

export function partnerOrderUrl(partner, item = null) {
  if (isHehaLocalPartner(partner)) {
    return item ? hehaLocalItemUrl(partner, item) : hehaLocalProfileUrl(partner);
  }
  return item ? legacyItemUrl(item) : null;
}

export function partnerOrderLabel(partner, selectedItem = null) {
  if (isHehaLocalPartner(partner)) {
    const isVendor = partner?.category === "Vendor" || partner?.local_lane === "vendors";
    return selectedItem
      ? "Open item in HEHA Local"
      : isVendor
        ? "View products in HEHA Local"
        : "View full menu in HEHA Local";
  }
  return selectedItem ? "Order selected item on HEHA" : "Select an item to order";
}
