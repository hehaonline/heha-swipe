export const STORE_PUBLIC_PARTNER_FIELDS = Object.freeze([
  "id",
  "name",
  "category",
  "categories",
  "tagline",
  "bio",
  "neighborhood",
  "tags",
  "offerings",
  "image_url",
  "photo_emoji",
  "heha_partner",
  "created_at",
]);

const WEB_ONLY_PUBLIC_PARTNER_FIELDS = Object.freeze([
  "location",
  "color",
  "items",
  "gallery_urls",
  "website",
  "instagram",
  "price_range",
  "local_eligible",
  "local_lane",
  "primary_cta_destination",
  "primary_cta_path",
]);

export const WEB_PUBLIC_PARTNER_FIELDS = Object.freeze([
  ...STORE_PUBLIC_PARTNER_FIELDS,
  ...WEB_ONLY_PUBLIC_PARTNER_FIELDS,
]);

export const WEB_PUBLIC_ITEM_FIELDS = Object.freeze([
  "name",
  "emoji",
  "url",
  "product_url",
  "link",
  "local_product_id",
  "product_id",
]);

export const STORE_PUBLIC_PARTNER_RPC = "list_public_swipe_partner_cards";
export const WEB_PUBLIC_PARTNER_RPC = "list_public_swipe_partner_details";
const hasOwn = (value, field) => Object.prototype.hasOwnProperty.call(value, field);
const WEB_PUBLIC_ITEM_URL_FIELDS = new Set(["url", "product_url", "link"]);
const WEB_PUBLIC_ITEM_ID_FIELDS = new Set(["local_product_id", "product_id"]);
const ABSOLUTE_PUBLIC_HTTP_URL = /^https?:\/\/[a-z0-9.-]+(?::[0-9]{1,5})?(?:[/?#][^\s\u0000-\u001f\u007f]*)?$/i;

function projectionForChannel(channel) {
  switch (channel) {
    case "store":
      return { fields: STORE_PUBLIC_PARTNER_FIELDS, rpc: STORE_PUBLIC_PARTNER_RPC };
    case "web":
      return { fields: WEB_PUBLIC_PARTNER_FIELDS, rpc: WEB_PUBLIC_PARTNER_RPC };
    default:
      throw new TypeError("Public partner channel must be exactly 'store' or 'web'.");
  }
}

function publicScalar(value) {
  return typeof value === "string" || (typeof value === "number" && Number.isFinite(value))
    ? value
    : null;
}

function publicHttpUrl(value) {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (!candidate || !ABSOLUTE_PUBLIC_HTTP_URL.test(candidate)) return null;

  try {
    const parsed = new URL(candidate);
    if (!(["http:", "https:"].includes(parsed.protocol))) return null;
    if (parsed.username || parsed.password) return null;
    return candidate;
  } catch {
    return null;
  }
}

function publicItemValue(field, value) {
  if (WEB_PUBLIC_ITEM_URL_FIELDS.has(field)) return publicHttpUrl(value);
  if (WEB_PUBLIC_ITEM_ID_FIELDS.has(field)) return publicScalar(value);
  return typeof value === "string" ? value : null;
}

function toPublicItem(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return null;

  const publicItem = Object.fromEntries(
    WEB_PUBLIC_ITEM_FIELDS
      .map((field) => [
        field,
        publicItemValue(field, hasOwn(item, field) ? item[field] : null),
      ])
      .filter(([, value]) => value !== null),
  );
  return Object.keys(publicItem).length ? publicItem : null;
}

function toPublicGallery(value) {
  if (!Array.isArray(value)) return [];
  return value.filter((image) => typeof image === "string" && image.trim().length > 0);
}

export function toPublicPartner(row = {}, options = {}) {
  // The caller must select a reviewed channel explicitly. Missing or unknown
  // configuration stops before data is returned instead of widening a build.
  const channel = options?.channel;
  const { fields } = projectionForChannel(channel);
  const partner = Object.fromEntries(fields.map((field) => [
    field,
    hasOwn(row, field) ? row[field] ?? null : null,
  ]));

  if (channel === "web") {
    partner.items = Array.isArray(row.items)
      ? row.items.map(toPublicItem).filter(Boolean)
      : [];
    partner.gallery_urls = toPublicGallery(row.gallery_urls);
  }

  return partner;
}

export async function fetchPublicPartners(client, options = {}) {
  const channel = options?.channel;
  const { rpc } = projectionForChannel(channel);
  const { data, error } = await client.rpc(rpc);

  if (error) throw error;
  if (data !== null && data !== undefined && !Array.isArray(data)) {
    throw new TypeError("Public partner RPC returned a non-array payload.");
  }
  return (data || []).map((row) => toPublicPartner(row, { channel }));
}
