import test from "node:test";
import assert from "node:assert/strict";
import {
  PARTNER_AGREEMENT_DRAFTS,
  agreementKeyForListing,
  renderAgreementText,
} from "./partnerAgreements.js";

test("maps each supported legal relationship without conflating vendors and markets", () => {
  assert.equal(agreementKeyForListing({ category: "Restaurant" }), "restaurant");
  assert.equal(agreementKeyForListing({ category: "Vendor", business_type: "Product maker" }), "vendor");
  assert.equal(agreementKeyForListing({ category: "Markets" }), "market");
  assert.equal(agreementKeyForListing({ category: "Vendor", business_type: "Farmers market" }), "market");
  assert.equal(agreementKeyForListing({ category: "Catering" }), "catering");
  assert.equal(agreementKeyForListing({ category: "Private Chef" }), "solo_chef");
  assert.equal(agreementKeyForListing({ category: "Driver" }), "driver");
  assert.equal(agreementKeyForListing({ category: "SOM" }), "som");
});

test("keeps all seven category drafts locked for legal review", () => {
  assert.deepEqual(Object.keys(PARTNER_AGREEMENT_DRAFTS).sort(), [
    "catering",
    "driver",
    "market",
    "restaurant",
    "solo_chef",
    "som",
    "vendor",
  ]);

  for (const template of Object.values(PARTNER_AGREEMENT_DRAFTS)) {
    assert.equal(template.status, "legal_review");
    assert.match(template.version, /^DRAFT-/);
    assert.ok(template.sections.length >= 5);
    assert.ok(template.activationGates.length >= 3);
  }

  assert.equal(
    new Set(Object.values(PARTNER_AGREEMENT_DRAFTS).map((template) => template.version)).size,
    7,
    "each legal relationship has a distinct draft version",
  );
});

test("restaurant draft visibly carries Florida delivery-network safeguards", () => {
  const text = renderAgreementText(PARTNER_AGREEMENT_DRAFTS.restaurant, "Synthetic Restaurant");
  for (const required of [
    "express written or electronic consent",
    "every restaurant-paid or restaurant-absorbed fee",
    "which party collects and remits each applicable tax",
    "may not require the restaurant to indemnify HEHA",
    "may not impose an unreasonable limit on restaurant disputes",
    "price-change permissions",
  ]) {
    assert.ok(text.includes(required), `missing restaurant safeguard: ${required}`);
  }
});

test("unsupported discovery categories never guess a legal agreement", () => {
  assert.equal(agreementKeyForListing({ category: "Wellness" }), null);
  assert.equal(agreementKeyForListing({ category: "Coach" }), null);
  assert.equal(agreementKeyForListing({ categories: [] }), null);
  assert.equal(agreementKeyForListing({ categories: ["Restaurant", "Catering"] }), null);
});
