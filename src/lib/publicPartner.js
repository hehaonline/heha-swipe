export const PUBLIC_PARTNER_FIELDS = Object.freeze([
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

export const PUBLIC_PARTNER_SELECT = PUBLIC_PARTNER_FIELDS.join(",");
export const PUBLIC_PARTNER_RPC = "list_public_swipe_partner_cards";

export function toPublicPartner(row = {}) {
  return Object.fromEntries(PUBLIC_PARTNER_FIELDS.map((field) => [field, row[field] ?? null]));
}

export async function fetchPublicPartners(client) {
  const { data, error } = await client.rpc(PUBLIC_PARTNER_RPC);

  if (error) throw error;
  return (data || []).map(toPublicPartner);
}
