import { canonicalJson, sha256Utf8Hex } from "./partnerAgreementVerification.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const PRIVATE_STATUSES = new Set(["draft", "submitted", "pending", "missing_info"]);

export async function preparePartnerApplication(application) {
  const serialized = JSON.stringify(application);
  if (!serialized) throw new Error("Invalid partner application.");
  const transportApplication = JSON.parse(serialized);
  if (!transportApplication || typeof transportApplication !== "object" || Array.isArray(transportApplication)) {
    throw new Error("Invalid partner application.");
  }
  return {
    application: transportApplication,
    applicationSha256: await sha256Utf8Hex(canonicalJson(transportApplication)),
  };
}

export function validatePartnerApplicationReceipt(value, {
  actorId,
  requestKey,
  expectedApplicationSha256,
}) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid partner application receipt.");
  }

  const fields = [
    [value.id, "partner id"],
    [value.owner_id, "owner id"],
    [value.request_key, "request key"],
    [value.application_receipt_id, "application receipt id"],
  ];
  for (const [fieldValue, fieldName] of fields) {
    if (typeof fieldValue !== "string" || !UUID_PATTERN.test(fieldValue)) {
      throw new Error(`Invalid ${fieldName}.`);
    }
  }

  if (typeof value.application_sha256 !== "string"
      || !SHA256_PATTERN.test(value.application_sha256)
      || value.application_sha256 !== expectedApplicationSha256
      || value.receipt_status !== "verified"
      || value.owner_id !== actorId
      || value.request_key !== requestKey
      || typeof value.status !== "string"
      || !PRIVATE_STATUSES.has(value.status)) {
    throw new Error("Partner application receipt does not match the request.");
  }

  return {
    id: value.id,
    owner_id: value.owner_id,
    request_key: value.request_key,
    application_receipt_id: value.application_receipt_id,
    application_sha256: value.application_sha256,
    receipt_status: "verified",
    status: value.status,
  };
}

const PROFILE_CORRECTION_RECEIPT_KEYS = [
  "correction_receipt_id",
  "correction_source",
  "id",
  "owner_id",
  "previous_sha256",
  "receipt_status",
  "request_key",
  "resulting_sha256",
  "source_receipt_id",
  "status",
  "submitted_sha256",
];

export function validatePartnerProfileCorrectionReceipt(value, {
  actorId,
  partnerId,
  requestKey,
  expectedSubmittedSha256,
}) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid partner profile correction receipt.");
  }

  const actualKeys = Object.keys(value).sort();
  if (actualKeys.length !== PROFILE_CORRECTION_RECEIPT_KEYS.length
      || actualKeys.some((key, index) => key !== PROFILE_CORRECTION_RECEIPT_KEYS[index])) {
    throw new Error("Invalid partner profile correction receipt.");
  }

  for (const fieldValue of [
    value.id,
    value.owner_id,
    value.request_key,
    value.source_receipt_id,
    value.correction_receipt_id,
  ]) {
    if (typeof fieldValue !== "string" || !UUID_PATTERN.test(fieldValue)) {
      throw new Error("Invalid partner profile correction receipt.");
    }
  }

  if (!new Set(["application", "claim"]).has(value.correction_source)
      || typeof value.submitted_sha256 !== "string"
      || !SHA256_PATTERN.test(value.submitted_sha256)
      || typeof value.previous_sha256 !== "string"
      || !SHA256_PATTERN.test(value.previous_sha256)
      || typeof value.resulting_sha256 !== "string"
      || !SHA256_PATTERN.test(value.resulting_sha256)
      || value.submitted_sha256 !== expectedSubmittedSha256
      || (value.correction_source === "application"
        && value.submitted_sha256 === value.previous_sha256)
      || (value.correction_source === "claim"
        && value.previous_sha256 === value.resulting_sha256)
      || value.receipt_status !== "verified"
      || value.id !== partnerId
      || value.owner_id !== actorId
      || value.request_key !== requestKey
      || typeof value.status !== "string"
      || !PRIVATE_STATUSES.has(value.status)) {
    throw new Error("Partner profile correction receipt does not match the request.");
  }

  return {
    id: value.id,
    owner_id: value.owner_id,
    request_key: value.request_key,
    correction_source: value.correction_source,
    source_receipt_id: value.source_receipt_id,
    correction_receipt_id: value.correction_receipt_id,
    submitted_sha256: value.submitted_sha256,
    previous_sha256: value.previous_sha256,
    resulting_sha256: value.resulting_sha256,
    receipt_status: "verified",
    status: value.status,
  };
}
