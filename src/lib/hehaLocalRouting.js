const DEFAULT_HEHA_LOCAL_ORIGIN = "https://hehalocal.app";

// Temporary bridge for the two currently approved/orderable Swipe partners.
// Remove this map after the canonical public partner relationship is exposed
// directly to Swipe through the approved cross-app routing model.
const LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID = {
  "2fbe55b6-f7ba-453d-8923-72f22946fea9": "/restaurants/2961f869-915b-4fa3-82db-8c6364c2e274",
  "3f5b29bc-662b-40b9-ad06-6dcb6592b396": "/restaurants/dccd000b-49d5-43e2-b684-704698d7f934",
};

function localOrigin() {
  const configured = String(import.meta.env.VITE_HEHA_LOCAL_URL || "").trim();
  return (configured || DEFAULT_HEHA_LOCAL_ORIGIN).replace(/\/$/, "");
}

function legacyItemUrl(item) {
  return item?.url || item?.product_url || item?.link || null;
}

export function isHehaLocalPartner(partner) {
  return Boolean(
    partner?.local_eligible
      && String(partner?.primary_cta_destination || "").toLowerCase() === "local",
  );
}

export function hehaLocalProfilePath(partner) {
  const mappedPath = LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID[partner?.id];
  if (mappedPath) return mappedPath;

  const configuredPath = String(partner?.primary_cta_path || "").trim();
  if (!configuredPath) return "/restaurants";
  return configuredPath.startsWith("/") ? configuredPath : `/${configuredPath}`;
}

export function hehaLocalProfileUrl(partner) {
  return `${localOrigin()}${hehaLocalProfilePath(partner)}`;
}

export function hehaLocalItemUrl(partner, item) {
  const url = new URL(hehaLocalProfileUrl(partner));
  const itemIdentity = item?.local_product_id || item?.product_id || item?.name;
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
    return selectedItem ? "Open item in HEHA Local" : "View full menu in HEHA Local";
  }
  return selectedItem ? "Order selected item on HEHA" : "Select an item to order";
}
