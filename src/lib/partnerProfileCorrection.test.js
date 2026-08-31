import assert from "node:assert/strict";
import test from "node:test";
import {
  buildProtectedPartnerProfileSnapshot,
  claimedProfileHasStructuredHours,
  hasVerifiedPartnerClaim,
} from "./partnerProfileCorrection.js";

const partnerId = "00000000-0000-4000-8000-000000000001";
const actorId = "00000000-0000-4000-8000-000000000002";
const claimId = "00000000-0000-4000-8000-000000000003";

const form = {
  name: "Changed identity",
  categories: ["Markets"],
  neighborhood: "Changed neighborhood",
  tagline: "Fresh every weekend",
  bio: "Updated bio",
  hours: "Saturday 8–2",
  delivery_days: "Saturday, Sunday",
  business_type: "Changed type",
  phone: "813-555-0100",
  contact: "market@example.com",
  website: "https://example.com",
  instagram: "@market",
  location: "Changed address",
  offerings: "Produce, Bread",
};

const listing = {
  id: partnerId,
  name: " Legacy Market ",
  category: "FarmersMarket",
  categories: ["FarmersMarket"],
  neighborhood: "Ybor City",
  business_type: "Farmers market",
  location: "Tampa, FL",
  hours: {
    summary: "Saturday 9–1",
    saturday: { opens: "09:00", closes: "13:00" },
  },
  items: [{ id: "tomatoes", name: "Tomatoes" }],
  photo_emoji: "🥬",
  color: "#114f35",
  complete_pct: 70,
};

test("recognizes only a partner- and actor-bound verified claim capability", () => {
  const capabilities = {
    projection_version: "heha-partner-onboarding-v1",
    partner_id: partnerId,
    authorized_actor_id: actorId,
    claim: { status: "verified", evidence_id: claimId },
  };
  assert.equal(hasVerifiedPartnerClaim(capabilities, { partnerId, actorId }), true);
  assert.equal(hasVerifiedPartnerClaim(capabilities, { partnerId, actorId: partnerId }), false);
  assert.equal(hasVerifiedPartnerClaim({ ...capabilities, claim: { status: "blocked", evidence_id: null } }, { partnerId, actorId }), false);
  assert.equal(hasVerifiedPartnerClaim({ ...capabilities, claim: { status: "verified", evidence_id: "yes" } }, { partnerId, actorId }), false);
});

test("claim correction preserves raw locked identity, aliases, items, and structured hours", () => {
  const snapshot = buildProtectedPartnerProfileSnapshot(form, listing, { claimBound: true });
  assert.deepEqual(Object.keys(snapshot).sort(), [
    "bio",
    "business_type",
    "categories",
    "category",
    "color",
    "complete_pct",
    "contact",
    "delivery_days",
    "hours",
    "instagram",
    "items",
    "location",
    "name",
    "neighborhood",
    "offerings",
    "phone",
    "photo_emoji",
    "tagline",
    "website",
  ]);
  assert.equal(snapshot.name, listing.name);
  assert.equal(snapshot.category, "FarmersMarket");
  assert.deepEqual(snapshot.categories, ["FarmersMarket"]);
  assert.equal(snapshot.business_type, listing.business_type);
  assert.equal(snapshot.location, listing.location);
  assert.equal(snapshot.neighborhood, listing.neighborhood);
  assert.deepEqual(snapshot.hours, listing.hours);
  assert.notEqual(snapshot.hours, listing.hours);
  assert.deepEqual(snapshot.items, listing.items);
  assert.notEqual(snapshot.items, listing.items);
  assert.equal(snapshot.bio, "Updated bio");
  assert.deepEqual(snapshot.offerings, ["Produce", "Bread"]);
  assert.equal(claimedProfileHasStructuredHours(listing), true);
});

test("application correction may canonicalize and update identity fields", () => {
  const snapshot = buildProtectedPartnerProfileSnapshot(form, listing, { claimBound: false });
  assert.equal(snapshot.name, "Changed identity");
  assert.equal(snapshot.category, "Markets");
  assert.deepEqual(snapshot.categories, ["Markets"]);
  assert.equal(snapshot.business_type, "Changed type");
  assert.equal(snapshot.location, "Changed address");
  assert.equal(snapshot.neighborhood, "Changed neighborhood");
  assert.equal(snapshot.hours, "Saturday 8–2");
});

test("claim correction fails closed on malformed locked classification", () => {
  assert.throws(() => buildProtectedPartnerProfileSnapshot(form, {
    ...listing,
    categories: ["FarmersMarket", null],
  }, { claimBound: true }));
});

test("claim correction preserves a nullable scalar category beside valid raw categories", () => {
  const snapshot = buildProtectedPartnerProfileSnapshot(form, {
    ...listing,
    category: null,
    categories: ["Grocery"],
  }, { claimBound: true });
  assert.equal(snapshot.category, null);
  assert.deepEqual(snapshot.categories, ["Grocery"]);
});

test("claim correction preserves nullable raw categories beside a scalar category", () => {
  const snapshot = buildProtectedPartnerProfileSnapshot(form, {
    ...listing,
    category: "Market",
    categories: null,
  }, { claimBound: true });
  assert.equal(snapshot.category, "Market");
  assert.equal(snapshot.categories, null);
});
