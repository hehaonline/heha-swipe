import test from "node:test";
import assert from "node:assert/strict";
import {
  preparePartnerApplication,
  validatePartnerApplicationReceipt,
  validatePartnerProfileCorrectionReceipt,
} from "./partnerApplicationReceipt.js";

const partnerId = "00000000-0000-4000-8000-000000000001";
const actorId = "00000000-0000-4000-8000-000000000002";
const requestKey = "00000000-0000-4000-8000-000000000003";
const receiptId = "00000000-0000-4000-8000-000000000004";
const correctionReceiptId = "00000000-0000-4000-8000-000000000005";

function receipt(applicationSha256, overrides = {}) {
  return {
    id: partnerId,
    owner_id: actorId,
    request_key: requestKey,
    application_receipt_id: receiptId,
    application_sha256: applicationSha256,
    receipt_status: "verified",
    status: "pending",
    ...overrides,
  };
}

test("canonical application hashing is stable across reordered object keys", async () => {
  const left = await preparePartnerApplication({
    name: "Pure Kitchen",
    categories: ["Restaurant"],
    location: "Tampa",
    hours: { close: "17:00", open: "09:00" },
  });
  const right = await preparePartnerApplication({
    hours: { open: "09:00", close: "17:00" },
    location: "Tampa",
    categories: ["Restaurant"],
    name: "Pure Kitchen",
  });
  assert.equal(left.applicationSha256, right.applicationSha256);
});

test("accepts only a receipt bound to the exact canonical application digest", async () => {
  const prepared = await preparePartnerApplication({
    name: "Pure Kitchen",
    categories: ["Restaurant"],
    location: "Tampa",
  });
  const result = validatePartnerApplicationReceipt(receipt(prepared.applicationSha256), {
    actorId,
    requestKey,
    expectedApplicationSha256: prepared.applicationSha256,
  });
  assert.equal(result.application_sha256, prepared.applicationSha256);

  const wrongDigest = `${prepared.applicationSha256.slice(0, -1)}${prepared.applicationSha256.endsWith("0") ? "1" : "0"}`;
  assert.throws(() => validatePartnerApplicationReceipt(receipt(wrongDigest), {
    actorId,
    requestKey,
    expectedApplicationSha256: prepared.applicationSha256,
  }));
});

test("rejects invalid receipt IDs, hash, status, owner, and request key", async () => {
  const prepared = await preparePartnerApplication({ name: "Pure Kitchen" });
  const validate = (overrides) => validatePartnerApplicationReceipt(
    receipt(prepared.applicationSha256, overrides),
    { actorId, requestKey, expectedApplicationSha256: prepared.applicationSha256 },
  );

  assert.throws(() => validate({ application_receipt_id: "not-a-uuid" }));
  assert.throws(() => validate({ application_sha256: "a".repeat(63) }));
  assert.throws(() => validate({ receipt_status: "unverified" }));
  assert.throws(() => validate({ status: "PENDING" }));
  assert.throws(() => validate({ owner_id: partnerId }));
  assert.throws(() => validate({ request_key: partnerId }));
});

function profileCorrectionReceipt(submittedSha256, overrides = {}) {
  return {
    id: partnerId,
    owner_id: actorId,
    request_key: requestKey,
    correction_source: "application",
    source_receipt_id: receiptId,
    correction_receipt_id: correctionReceiptId,
    submitted_sha256: submittedSha256,
    previous_sha256: "b".repeat(64),
    resulting_sha256: "c".repeat(64),
    receipt_status: "verified",
    status: "pending",
    ...overrides,
  };
}

test("accepts both server-selected correction sources bound to the submitted digest", async () => {
  const prepared = await preparePartnerApplication({
    name: "Pure Kitchen",
    categories: ["Restaurant"],
    neighborhood: "Tampa",
  });
  for (const correctionSource of ["application", "claim"]) {
    const result = validatePartnerProfileCorrectionReceipt(
      profileCorrectionReceipt(prepared.applicationSha256, { correction_source: correctionSource }),
      {
        actorId,
        partnerId,
        requestKey,
        expectedSubmittedSha256: prepared.applicationSha256,
      },
    );
    assert.equal(result.correction_source, correctionSource);
    assert.equal(result.submitted_sha256, prepared.applicationSha256);
  }
});

test("rejects malformed, unbound, contradictory, or expanded profile correction receipts", async () => {
  const prepared = await preparePartnerApplication({ name: "Pure Kitchen" });
  const correction = profileCorrectionReceipt(prepared.applicationSha256);
  const validate = (candidate) => validatePartnerProfileCorrectionReceipt(candidate, {
    actorId,
    partnerId,
    requestKey,
    expectedSubmittedSha256: prepared.applicationSha256,
  });

  for (const overrides of [
    { id: actorId },
    { owner_id: partnerId },
    { request_key: partnerId },
    { correction_source: "APPLICATION" },
    { correction_source: "invitation" },
    { source_receipt_id: "not-a-uuid" },
    { correction_receipt_id: "not-a-uuid" },
    { submitted_sha256: "a".repeat(64) },
    { previous_sha256: "short" },
    { resulting_sha256: "A".repeat(64) },
    { receipt_status: "unverified" },
    { status: "live" },
  ]) {
    assert.throws(() => validate({ ...correction, ...overrides }));
  }

  assert.throws(() => validate(null));
  assert.throws(() => validate([]));
  assert.throws(() => validate({ ...correction, unexpected: true }));
  assert.throws(() => validate({
    ...correction,
    correction_source: "application",
    previous_sha256: prepared.applicationSha256,
  }));
  assert.throws(() => validate({
    ...correction,
    correction_source: "claim",
    resulting_sha256: correction.previous_sha256,
  }));
  const missingSource = { ...correction };
  delete missingSource.correction_source;
  assert.throws(() => validate(missingSource));
});
