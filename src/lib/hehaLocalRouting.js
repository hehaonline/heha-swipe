const DEFAULT_HEHA_LOCAL_ORIGIN = "https://hehalocal.app";
const LOCAL_ROUTE_PARSE_ORIGIN = "https://local-route.invalid";

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
  "/",
  "/restaurants",
  "/market",
  "/vendors",
  "/chef",
  "/chef/match",
  "/group-orders",
]);

const SPECIFIC_LOCAL_PROFILE_PATH = /^\/(restaurants|vendors|market)\/[^/?#]+$/i;
const UUID_TEXT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function localOrigin() {
  const configured = String(import.meta.env.VITE_HEHA_LOCAL_URL || "").trim();
  return (configured || DEFAULT_HEHA_LOCAL_ORIGIN).replace(/\/$/, "");
}

function legacyItemUrl(item) {
  return item?.url || item?.product_url || item?.link || null;
}

function configuredLocalRoute(partner) {
  const configuredPath = String(partner?.primary_cta_path || "").trim();
  if (!configuredPath) return null;
  if (/^[a-z][a-z0-9+.-]*:/i.test(configuredPath)) return null;
  if (configuredPath.startsWith("//") || configuredPath.includes("\\")) return null;
  if (/[\u0000-\u001f\u007f]/.test(configuredPath)) return null;

  try {
    const parsed = new URL(
      configuredPath.startsWith("/") ? configuredPath : `/${configuredPath}`,
      LOCAL_ROUTE_PARSE_ORIGIN,
    );
    if (parsed.origin !== LOCAL_ROUTE_PARSE_ORIGIN) return null;
    // Canonical profile routes use literal lane names and UUIDs. Reject encoded
    // path bytes so decoded generic roots cannot bypass the fail-closed set.
    if (parsed.pathname.includes("%")) return null;

    const canonicalPathname = parsed.pathname === "/"
      ? "/"
      : parsed.pathname.replace(/\/{2,}/g, "/").replace(/\/+$/, "");
    return {
      canonicalPathname,
      path: `${parsed.pathname}${parsed.search}${parsed.hash}`,
    };
  } catch {
    return null;
  }
}

function isGenericHehaLocalListingPath(route) {
  return !route || GENERIC_HEHA_LOCAL_LISTING_PATHS.has(route.canonicalPathname);
}

// A partner only has a "specific" HEHA Local destination when it resolves to
// an individual partner profile (e.g. /restaurants/<id> or /vendors/<id>)
// rather than a generic lane root emitted by partner_cta_path_for_lane().
export function hasSpecificHehaLocalDestination(partner) {
  if (LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID[partner?.id]) return true;

  const configuredRoute = configuredLocalRoute(partner);
  if (!configuredRoute) return false;
  const configuredPath = configuredRoute.path;
  const partnerId = String(partner?.id || "").trim();
  const lane = String(partner?.local_lane || "").trim();
  const isWave1Route = lane === "chef"
    || lane === "group_orders"
    || configuredPath.startsWith("/chef")
    || configuredPath.startsWith("/group-orders");

  if (isWave1Route) {
    if (!UUID_TEXT.test(partnerId)) return false;
    if (lane === "chef") {
      return configuredPath.split("?", 1)[0] === `/chef/${partnerId}`
        || configuredPath === `/chef/match?swipePartnerId=${partnerId}&service=private_chef`;
    }
    if (lane === "group_orders") {
      return configuredPath === `/chef/match?swipePartnerId=${partnerId}&service=catering`;
    }
    return false;
  }

  if (isGenericHehaLocalListingPath(configuredRoute)) return false;
  return SPECIFIC_LOCAL_PROFILE_PATH.test(configuredRoute.canonicalPathname);
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

  const configuredRoute = configuredLocalRoute(partner);
  return configuredRoute?.path || "/restaurants";
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
    if (partner?.local_lane === "chef") return "Request this chef";
    if (partner?.local_lane === "group_orders") return "Request catering quote";
    const isVendor = partner?.category === "Vendor" || partner?.local_lane === "vendors";
    return selectedItem
      ? "Open item in HEHA Local"
      : isVendor
        ? "View products in HEHA Local"
        : "View full menu in HEHA Local";
  }
  return selectedItem ? "Order selected item on HEHA" : "Select an item to order";
}

export function partnerLocalRequestCopy(partner) {
  if (!isHehaLocalPartner(partner)) return null;

  if (partner?.local_lane === "chef") {
    return {
      eyebrow: "HEHA Local request",
      heading: "Request this chef",
      body: "Open HEHA Local to share your event details and request availability and a quote from this chef.",
    };
  }

  if (partner?.local_lane === "group_orders") {
    return {
      eyebrow: "HEHA Local request",
      heading: "Request catering quote",
      body: "Open HEHA Local to share your group-order details and request a catering quote from this partner.",
    };
  }

  return null;
}
