import assert from "node:assert/strict";
import test from "node:test";

import {
  PARTNER_DESTINATIONS,
  SWIPE_CATEGORIES,
  availablePartnerDestinations,
  deriveWave1LocalLane,
  normalizePartnerDestinations,
  publicationStatusLabel,
  supportsHehaLocal,
  supportsHehaSwipe,
  validatePartnerDraftAuthorization,
  validatePartnerPublicationWithdrawal,
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
  assert.equal(supportsHehaSwipe(["Wellness"]), true);
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

test("every declared Swipe category can authorize Swipe without a Tampa attestation", () => {
  for (const category of SWIPE_CATEGORIES) {
    assert.equal(supportsHehaSwipe([category]), true, `${category} should support Swipe`);
    const result = validatePartnerDraftAuthorization({
      categories: [category],
      destinations: [PARTNER_DESTINATIONS.swipe],
      representativeName: "Avery Example",
      representativeTitle: "Owner",
      authorityConfirmed: true,
      profileConfirmed: true,
      mediaPermissionConfirmed: true,
      tampaBayServiceConfirmed: false,
    });
    assert.equal(result.valid, true, `${category} should not require a Tampa attestation for Swipe`);
    assert.equal(result.errors.tampaBayServiceConfirmed, undefined);
  }
});

test("Wellness and Restaurant are valid Swipe-only preparation categories", () => {
  for (const category of ["Wellness", "Restaurant"]) {
    assert.deepEqual(
      availablePartnerDestinations([category]).map(({ value }) => value),
      [PARTNER_DESTINATIONS.swipe]
    );
  }
  assert.deepEqual(availablePartnerDestinations(["UnsupportedCategory"]), []);
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
  assert.equal(result.errors.tampaBayServiceConfirmed, undefined);
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

test("Tampa attestation is required only when Local is selected", () => {
  const swipeOnly = validatePartnerDraftAuthorization({
    categories: ["Catering"],
    destinations: [PARTNER_DESTINATIONS.swipe],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    authorityConfirmed: true,
    profileConfirmed: true,
    mediaPermissionConfirmed: true,
    tampaBayServiceConfirmed: false,
  });
  assert.equal(swipeOnly.valid, true);

  const local = validatePartnerDraftAuthorization({
    categories: ["Catering"],
    destinations: [PARTNER_DESTINATIONS.local],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    authorityConfirmed: true,
    profileConfirmed: true,
    mediaPermissionConfirmed: true,
    tampaBayServiceConfirmed: false,
  });
  assert.equal(local.valid, false);
  assert.ok(local.errors.tampaBayServiceConfirmed);
});

test("withdrawal requires an explicit subset of currently approved destinations", () => {
  const localOnly = validatePartnerPublicationWithdrawal({
    destinations: [PARTNER_DESTINATIONS.local],
    activeDestinations: [PARTNER_DESTINATIONS.swipe, PARTNER_DESTINATIONS.local],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    withdrawalConfirmed: true,
  });
  assert.equal(localOnly.valid, true);
  assert.deepEqual(localOnly.destinations, [PARTNER_DESTINATIONS.local]);

  const implicitAll = validatePartnerPublicationWithdrawal({
    destinations: [],
    activeDestinations: [PARTNER_DESTINATIONS.swipe, PARTNER_DESTINATIONS.local],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    withdrawalConfirmed: true,
  });
  assert.equal(implicitAll.valid, false);
  assert.ok(implicitAll.errors.destinations);

  const inactive = validatePartnerPublicationWithdrawal({
    destinations: [PARTNER_DESTINATIONS.local],
    activeDestinations: [PARTNER_DESTINATIONS.swipe],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    withdrawalConfirmed: true,
  });
  assert.equal(inactive.valid, false);
  assert.ok(inactive.errors.destinations);
});

test("withdrawal requires representative details and explicit confirmation", () => {
  const result = validatePartnerPublicationWithdrawal({
    destinations: [PARTNER_DESTINATIONS.swipe],
    activeDestinations: [PARTNER_DESTINATIONS.swipe],
  });
  assert.equal(result.valid, false);
  assert.ok(result.errors.representativeName);
  assert.ok(result.errors.representativeTitle);
  assert.ok(result.errors.withdrawalConfirmed);
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
