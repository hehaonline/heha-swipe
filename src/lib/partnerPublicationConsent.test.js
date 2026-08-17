import assert from "node:assert/strict";
import test from "node:test";

import {
  PARTNER_DESTINATIONS,
  availablePartnerDestinations,
  deriveWave1LocalLane,
  normalizePartnerDestinations,
  publicationStatusLabel,
  supportsHehaLocal,
  validatePartnerDraftAuthorization,
} from "./partnerPublicationConsent.js";

test("Catering and PrivateChef unlock HEHA Local with the correct lane", () => {
  assert.equal(supportsHehaLocal(["Catering"]), true);
  assert.equal(supportsHehaLocal(["PrivateChef"]), true);
  assert.equal(deriveWave1LocalLane(["Catering"]), "group_orders");
  assert.equal(deriveWave1LocalLane(["PrivateChef"]), "chef");
  assert.equal(deriveWave1LocalLane(["Catering", "PrivateChef"]), "group_orders");
  assert.equal(deriveWave1LocalLane(["PrivateChef", "Catering"]), "chef");
});

test("non-food categories cannot authorize HEHA Local", () => {
  assert.equal(supportsHehaLocal(["Wellness"]), false);
  assert.deepEqual(
    availablePartnerDestinations(["Wellness"]).map(({ value }) => value),
    [PARTNER_DESTINATIONS.swipe]
  );
  assert.deepEqual(
    normalizePartnerDestinations(
      [PARTNER_DESTINATIONS.swipe, PARTNER_DESTINATIONS.local],
      ["Wellness"]
    ),
    [PARTNER_DESTINATIONS.swipe]
  );
});

test("authorization is explicit and nothing is preselected", () => {
  const result = validatePartnerDraftAuthorization({ categories: ["Catering"] });
  assert.equal(result.valid, false);
  assert.match(result.errors.destinations, /Choose at least one/);
  assert.ok(result.errors.representativeName);
  assert.ok(result.errors.representativeTitle);
  assert.ok(result.errors.authorityConfirmed);
  assert.ok(result.errors.profileConfirmed);
  assert.ok(result.errors.mediaPermissionConfirmed);
  assert.ok(result.errors.tampaBayServiceConfirmed);
});

test("complete authorization accepts Swipe and Local for a chef", () => {
  const result = validatePartnerDraftAuthorization({
    categories: ["PrivateChef"],
    destinations: [PARTNER_DESTINATIONS.local, PARTNER_DESTINATIONS.swipe],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    authorityConfirmed: true,
    profileConfirmed: true,
    mediaPermissionConfirmed: true,
    tampaBayServiceConfirmed: true,
  });

  assert.equal(result.valid, true);
  assert.deepEqual(result.destinations, [PARTNER_DESTINATIONS.local, PARTNER_DESTINATIONS.swipe]);
});

test("status labels keep preparation and final publication separate", () => {
  assert.equal(publicationStatusLabel(null), "Permission needed");
  assert.equal(publicationStatusLabel({
    prepare_destinations: [PARTNER_DESTINATIONS.swipe],
    publication_destinations: [],
  }), "Awaiting profile approval");
  assert.equal(publicationStatusLabel({
    prepare_destinations: [PARTNER_DESTINATIONS.swipe],
    publication_destinations: [PARTNER_DESTINATIONS.swipe],
  }), "Approved to publish");
  assert.equal(publicationStatusLabel({
    prepare_destinations: [PARTNER_DESTINATIONS.swipe],
    publication_destinations: [PARTNER_DESTINATIONS.local],
  }), "Awaiting profile approval");
});
