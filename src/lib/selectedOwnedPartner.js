// App owns selection. Child controls must never rediscover a different business.
export function selectedOwnedPartner(row, ownerId, partnerId) {
  return ownerId && partnerId && row?.id === partnerId && row?.owner_id === ownerId
    ? row
    : null;
}

export async function fetchSelectedOwnedPartner(client, ownerId, partnerId, projection) {
  if (!ownerId || !partnerId) return null;
  const { data, error } = await client
    .from("partners")
    .select(`owner_id, ${projection}`)
    .eq("owner_id", ownerId)
    .eq("id", partnerId)
    .maybeSingle();
  if (error) throw error;
  if (data && !selectedOwnedPartner(data, ownerId, partnerId)) {
    throw new Error("The selected business could not be verified for this account.");
  }
  return data || null;
}
