const DEFAULT_HEHA_LOCAL_ORIGIN = "https://hehalocal.app";
const APPROVED_HEHA_LOCAL_ORIGINS = new Set([DEFAULT_HEHA_LOCAL_ORIGIN]);

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
  "/market",
  "/market/",
  "/chef",
  "/chef/",
  "/group-orders",
  "/group-orders/",
]);

const SPECIFIC_HEHA_LOCAL_PROFILE_PATH = /^\/(?:restaurants|vendors|market|chef|group-orders)\/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function approvedConfiguredOrigin(configuredValue) {
  const configured = String(configuredValue || "").trim();
  if (!configured) return null;
  try {
    const parsed = new URL(configured);
    if (parsed.protocol !== "https:"
        || !APPROVED_HEHA_LOCAL_ORIGINS.has(parsed.origin)
        || !["", "/"].includes(parsed.pathname)
        || parsed.search
        || parsed.hash) {
      return null;
    }
    return parsed.origin;
  } catch {
    return null;
  }
}

function localOrigin() {
  return approvedConfiguredOrigin(import.meta.env.VITE_HEHA_LOCAL_URL)
    || DEFAULT_HEHA_LOCAL_ORIGIN;
}

export function isApprovedHehaLocalInstallConfiguration({ enabled, configuredUrl }) {
  return enabled === true && Boolean(approvedConfiguredOrigin(configuredUrl));
}

export function isHehaLocalInstallEnabled() {
  return isApprovedHehaLocalInstallConfiguration({
    enabled: import.meta.env.VITE_ENABLE_HEHA_LOCAL_INSTALL === "true",
    configuredUrl: import.meta.env.VITE_HEHA_LOCAL_URL,
  });
}

export function hehaLocalInstallUrl() {
  if (!isHehaLocalInstallEnabled()) return null;
  return `${approvedConfiguredOrigin(import.meta.env.VITE_HEHA_LOCAL_URL)}/`;
}

export function hehaLocalHomeUrl() {
  return `${localOrigin()}/`;
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
  const configuredPath = normalizedConfiguredPath(partner);
  if (!configuredPath) return false;
  if (isGenericHehaLocalListingPath(configuredPath)) return false;
  return SPECIFIC_HEHA_LOCAL_PROFILE_PATH.test(configuredPath);
}

export function isHehaLocalPartner(partner) {
  return Boolean(
    partner?.local_eligible
    && String(partner?.primary_cta_destination || "").toLowerCase() === "local"
    && hasSpecificHehaLocalDestination(partner),
  );
}

export function hehaLocalProfilePath(partner) {
  const configuredPath = normalizedConfiguredPath(partner);
  return hasSpecificHehaLocalDestination(partner) ? configuredPath : null;
}

export function hehaLocalProfileUrl(partner) {
  const path = hehaLocalProfilePath(partner);
  return path ? `${localOrigin()}${path}` : null;
}

export function hehaLocalItemUrl(partner, item) {
  const profileUrl = hehaLocalProfileUrl(partner);
  if (!profileUrl) return null;
  const url = new URL(profileUrl);
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
  return null;
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
  return "Ordering unavailable";
}
