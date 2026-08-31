import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  canonicalJson,
  sha256Utf8Hex,
  validateAcceptanceReceipt,
  validateAgreementEnvelope,
  verifyAgreementDocumentDigest,
} from "./partnerAgreementVerification.js";

const partnerId = "11111111-1111-4111-8111-111111111111";
const actorId = "22222222-2222-4222-8222-222222222222";
const ownerId = "33333333-3333-4333-8333-333333333333";
const versionId = "44444444-4444-4444-8444-444444444444";
const requestKey = "55555555-5555-4555-8555-555555555555";
const hashA = "a".repeat(64);
const hashB = "b".repeat(64);

function assertionsHash(value) {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

test("canonical assertions match the server golden vector", () => {
  const assertions = {
    typed_signature: "Signer B",
    signer_title: "Authorized Representative",
    assent_text: "I agree to the synthetic terms.",
    signer_legal_name: "Signer B",
    assertions_version: "heha-partner-acceptance-v1",
    electronic_records_consent: true,
    signer_authority_confirmed: true,
    reviewed_complete_agreement: true,
  };
  const canonical = '{"assent_text":"I agree to the synthetic terms.","assertions_version":"heha-partner-acceptance-v1","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}';

  assert.equal(canonicalJson(assertions), canonical);
  assert.equal(assertionsHash(assertions), "5327bdf5a2d33cdc26368ead401444941f8ef5cdb88f0d4ef0d4b8def19947f6");
});

function envelope(overrides = {}) {
  return {
    partner_id: partnerId,
    agreement_version_id: versionId,
    accepted_owner_id: ownerId,
    authorized_actor_id: actorId,
    legal_relationship_type: "restaurant",
    agreement_version: "RESTAURANT-2026-01",
    title: "Restaurant Agreement",
    legal_approval_reference: "COUNSEL-2026-01",
    effective_at: "2026-08-30T12:00:00.000Z",
    document_snapshot: "Exact approved terms",
    document_sha256: hashA,
    assent_text: "I agree.",
    signer_email: "verified@example.com",
    signer_email_verified: true,
    authorized_signer: true,
    acceptance_enabled: true,
    ...overrides,
  };
}

function receipt(assertions, overrides = {}) {
  return {
    receipt_status: "verified",
    acceptance_id: "66666666-6666-4666-8666-666666666666",
    partner_id: partnerId,
    agreement_version_id: versionId,
    accepted_owner_id: ownerId,
    accepted_by: actorId,
    request_key: requestKey,
    legal_relationship_type: "restaurant",
    agreement_version: "RESTAURANT-2026-01",
    document_sha256: hashA,
    assertions_sha256: assertionsHash(assertions),
    assertions_snapshot: assertions,
    accepted_at: "2026-08-30T12:01:00.000Z",
    ...overrides,
  };
}

test("agreement envelope requires the exact partner, signer, counsel approval, and enabled server gate", () => {
  assert.equal(validateAgreementEnvelope(envelope(), partnerId, actorId).document_sha256, hashA);
  assert.throws(() => validateAgreementEnvelope(envelope({ legal_approval_reference: "" }), partnerId, actorId));
  assert.throws(() => validateAgreementEnvelope(envelope({ authorized_actor_id: ownerId }), partnerId, actorId));
  assert.throws(() => validateAgreementEnvelope(envelope({ acceptance_enabled: false }), partnerId, actorId));
});

test("exact displayed agreement snapshot must match its SHA-256 digest", async () => {
  const documentSnapshot = "Exact approved terms";
  const documentSha256 = await sha256Utf8Hex(documentSnapshot);
  const agreement = validateAgreementEnvelope(envelope({ document_snapshot: documentSnapshot, document_sha256: documentSha256 }), partnerId, actorId);
  assert.equal((await verifyAgreementDocumentDigest(agreement)).document_sha256, documentSha256);
  await assert.rejects(() => verifyAgreementDocumentDigest({ ...agreement, document_snapshot: "Tampered terms" }));
});

test("verified receipt exact-matches immutable assertions and every binding field", () => {
  const assertions = {
    signer_legal_name: "Synthetic Signer",
    signer_authority_confirmed: true,
    electronic_records_consent: true,
  };
  const agreement = validateAgreementEnvelope(envelope(), partnerId, actorId);
  const reordered = {
    electronic_records_consent: true,
    signer_authority_confirmed: true,
    signer_legal_name: "Synthetic Signer",
  };
  assert.equal(validateAcceptanceReceipt(receipt(reordered), {
    partnerId, actorId, agreement, requestKey, assertions, expectedAssertionsSha256: assertionsHash(assertions),
  }).receipt_status, "verified");

  assert.throws(() => validateAcceptanceReceipt(receipt({ ...assertions, signer_legal_name: "Tampered" }), {
    partnerId, actorId, agreement, requestKey, assertions, expectedAssertionsSha256: assertionsHash(assertions),
  }));
  assert.throws(() => validateAcceptanceReceipt(receipt(assertions, { document_sha256: hashB }), {
    partnerId, actorId, agreement, requestKey, assertions, expectedAssertionsSha256: assertionsHash(assertions),
  }));
  assert.throws(() => validateAcceptanceReceipt(receipt(assertions, { request_key: ownerId }), {
    partnerId, actorId, agreement, requestKey, assertions, expectedAssertionsSha256: assertionsHash(assertions),
  }));
  assert.throws(() => validateAcceptanceReceipt(receipt(assertions, { assertions_sha256: hashB }), {
    partnerId, actorId, agreement, requestKey, assertions, expectedAssertionsSha256: assertionsHash(assertions),
  }));
});
