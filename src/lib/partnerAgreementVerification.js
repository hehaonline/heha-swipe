const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^(?:\\x)?[0-9a-f]{64}$/i;

export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export async function sha256Utf8Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(String(value)));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function verifyAgreementDocumentDigest(agreement) {
  const computed = await sha256Utf8Hex(agreement.document_snapshot);
  if (computed !== agreement.document_sha256) {
    throw new Error("The exact agreement document does not match its server digest.");
  }
  return agreement;
}

function requiredString(value, field) {
  const normalized = String(value || "").trim();
  if (!normalized) throw new Error(`The agreement service omitted ${field}.`);
  return normalized;
}

function requiredUuid(value, field) {
  const normalized = requiredString(value, field);
  if (!UUID_PATTERN.test(normalized)) throw new Error(`The agreement service returned an invalid ${field}.`);
  return normalized;
}

function requiredSha(value, field) {
  const normalized = requiredString(value, field).toLowerCase().replace(/^\\x/, "");
  if (!SHA256_PATTERN.test(normalized)) throw new Error(`The agreement service returned an invalid ${field}.`);
  return normalized;
}

export function validateAgreementEnvelope(envelope, partnerId, actorId) {
  if (!envelope || typeof envelope !== "object") {
    throw new Error("No server-approved agreement is available for this partner.");
  }
  const verified = {
    ...envelope,
    partner_id: requiredUuid(envelope.partner_id, "partner_id"),
    agreement_version_id: requiredUuid(envelope.agreement_version_id, "agreement_version_id"),
    accepted_owner_id: requiredUuid(envelope.accepted_owner_id, "accepted_owner_id"),
    authorized_actor_id: requiredUuid(envelope.authorized_actor_id, "authorized_actor_id"),
    legal_relationship_type: requiredString(envelope.legal_relationship_type, "legal_relationship_type"),
    agreement_version: requiredString(envelope.agreement_version, "agreement_version"),
    title: requiredString(envelope.title, "title"),
    legal_approval_reference: requiredString(envelope.legal_approval_reference, "legal_approval_reference"),
    effective_at: requiredString(envelope.effective_at, "effective_at"),
    document_snapshot: requiredString(envelope.document_snapshot, "document_snapshot"),
    document_sha256: requiredSha(envelope.document_sha256, "document_sha256"),
    assent_text: requiredString(envelope.assent_text, "assent_text"),
    signer_email: requiredString(envelope.signer_email, "signer_email"),
  };

  if (verified.partner_id !== partnerId || verified.authorized_actor_id !== actorId) {
    throw new Error("The agreement service returned a record for a different partner or signer.");
  }
  if (!Number.isFinite(Date.parse(verified.effective_at))) {
    throw new Error("The agreement service returned an invalid effective_at.");
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(verified.signer_email)) {
    throw new Error("The agreement service returned an invalid verified signer email.");
  }
  if (verified.acceptance_enabled !== true
      || verified.authorized_signer !== true
      || verified.signer_email_verified !== true) {
    throw new Error("Agreement acceptance is not enabled for this verified signer and relationship.");
  }
  return verified;
}

export function validateAcceptanceReceipt(receipt, {
  partnerId,
  actorId,
  agreement,
  requestKey,
  assertions,
  expectedAssertionsSha256,
}) {
  if (!receipt || typeof receipt !== "object") {
    throw new Error("The agreement service did not return a receipt.");
  }
  const verified = {
    ...receipt,
    acceptance_id: requiredUuid(receipt.acceptance_id, "acceptance_id"),
    partner_id: requiredUuid(receipt.partner_id, "partner_id"),
    agreement_version_id: requiredUuid(receipt.agreement_version_id, "agreement_version_id"),
    accepted_owner_id: requiredUuid(receipt.accepted_owner_id, "accepted_owner_id"),
    accepted_by: requiredUuid(receipt.accepted_by, "accepted_by"),
    request_key: requiredUuid(receipt.request_key, "request_key"),
    legal_relationship_type: requiredString(receipt.legal_relationship_type, "legal_relationship_type"),
    agreement_version: requiredString(receipt.agreement_version, "agreement_version"),
    document_sha256: requiredSha(receipt.document_sha256, "document_sha256"),
    assertions_sha256: requiredSha(receipt.assertions_sha256, "assertions_sha256"),
    accepted_at: requiredString(receipt.accepted_at, "accepted_at"),
    assertions_snapshot: receipt.assertions_snapshot,
  };

  if (!verified.assertions_snapshot || typeof verified.assertions_snapshot !== "object") {
    throw new Error("The server receipt omitted the immutable assertions snapshot.");
  }

  const exactMatch = verified.receipt_status === "verified"
    && verified.partner_id === partnerId
    && verified.accepted_by === actorId
    && verified.accepted_owner_id === agreement.accepted_owner_id
    && verified.agreement_version_id === agreement.agreement_version_id
    && verified.legal_relationship_type === agreement.legal_relationship_type
    && verified.agreement_version === agreement.agreement_version
    && verified.document_sha256 === agreement.document_sha256
    && verified.request_key === requestKey
    && canonicalJson(verified.assertions_snapshot) === canonicalJson(assertions)
    && verified.assertions_sha256 === expectedAssertionsSha256
    && Number.isFinite(Date.parse(verified.accepted_at));

  if (!exactMatch) {
    throw new Error("The server receipt did not exactly match the agreement acceptance request.");
  }
  return verified;
}
