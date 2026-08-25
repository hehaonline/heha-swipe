import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  PARTNER_DESTINATIONS,
  SUPPORTED_PARTNER_CATEGORIES,
  availablePartnerDestinations,
  deriveWave1LocalLane,
  normalizePartnerDestinations,
  publicationApprovalDestinationCandidates,
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

test("every supported partner category can authorize Swipe and arbitrary categories cannot", () => {
  assert.deepEqual(SUPPORTED_PARTNER_CATEGORIES, [
    "Restaurant",
    "Vendor",
    "Catering",
    "PrivateChef",
    "Wellness",
    "Coach",
    "Service",
    "Events",
  ]);

  for (const category of SUPPORTED_PARTNER_CATEGORIES) {
    assert.equal(supportsHehaSwipe([category]), true, `${category} should support Swipe`);
    assert.ok(
      availablePartnerDestinations([category])
        .some(({ value }) => value === PARTNER_DESTINATIONS.swipe),
      `${category} should offer Swipe`
    );
    assert.deepEqual(
      normalizePartnerDestinations([PARTNER_DESTINATIONS.swipe], [category]),
      [PARTNER_DESTINATIONS.swipe]
    );
  }

  assert.equal(supportsHehaSwipe(["ArbitraryLegacyCategory"]), false);
  assert.deepEqual(availablePartnerDestinations(["ArbitraryLegacyCategory"]), []);
  assert.deepEqual(
    normalizePartnerDestinations(
      [PARTNER_DESTINATIONS.swipe],
      ["ArbitraryLegacyCategory"]
    ),
    []
  );
});

test("Tampa Bay attestation is required only when HEHA Local is selected", () => {
  const base = {
    categories: ["Catering"],
    representativeName: "Avery Example",
    representativeTitle: "Owner",
    authorityConfirmed: true,
    profileConfirmed: true,
    mediaPermissionConfirmed: true,
  };

  const swipeOnly = validatePartnerDraftAuthorization({
    ...base,
    destinations: [PARTNER_DESTINATIONS.swipe],
  });
  assert.equal(swipeOnly.valid, true);
  assert.equal(swipeOnly.errors.tampaBayServiceConfirmed, undefined);

  const local = validatePartnerDraftAuthorization({
    ...base,
    destinations: [PARTNER_DESTINATIONS.local],
  });
  assert.equal(local.valid, false);
  assert.match(local.errors.tampaBayServiceConfirmed, /Tampa Bay/);
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

test("ProfileTab offers Swipe preparation to non-Local categories", async () => {
  const source = await readFile(
    new URL("../components/ProfileTab.jsx", import.meta.url),
    "utf8"
  );
  const heading = source.indexOf("Choose where HEHA may prepare this profile");
  const destinationList = source.indexOf("activeListingDestinations.map", heading);

  assert.ok(heading >= 0, "the existing-owner preparation form must remain present");
  assert.ok(destinationList > heading, "the form must render the category-scoped destinations");
  assert.doesNotMatch(source, /permission flow currently covers Tampa Bay chefs and caterers only/);
  assert.match(source, /preparationRequiresTampaBay[\s\S]*PARTNER_DESTINATIONS\.local/);
  assert.match(source, /preparationConfirmationFields/);
});

test("ProfileTab final approval is explicit and cannot re-grant every prepared destination", async () => {
  const source = await readFile(
    new URL("../components/ProfileTab.jsx", import.meta.url),
    "utf8"
  );
  const handlerStart = source.indexOf("const approveCurrentPartnerProfile = async () => {");
  const handlerEnd = source.indexOf("const togglePublicationApprovalDestination", handlerStart);
  const handler = source.slice(handlerStart, handlerEnd);

  assert.deepEqual(
    publicationApprovalDestinationCandidates({
      prepare_destinations: [PARTNER_DESTINATIONS.swipe, PARTNER_DESTINATIONS.local],
      publication_destinations: [PARTNER_DESTINATIONS.swipe],
    }),
    [PARTNER_DESTINATIONS.local],
    "withdrawing Local must not make Swipe an approval candidate again"
  );
  assert.deepEqual(
    publicationApprovalDestinationCandidates({
      prepare_destinations: [PARTNER_DESTINATIONS.swipe],
      publication_destinations: [],
    }),
    [PARTNER_DESTINATIONS.swipe],
    "after category drift filters stale Local preparation, Swipe remains approvable"
  );
  assert.match(
    source,
    /publicationApprovalCandidates\.map\(\(destination\) =>/,
    "the approval checkboxes must come from the prepared-minus-current candidates"
  );
  assert.match(source, /Prepared destinations to approve/);
  assert.match(source, /destinations:\s*\[\]/);
  assert.match(handler, /publicationApproval\.destinations/);
  assert.doesNotMatch(
    handler,
    /const destinations = publicationStatus\?\.prepare_destinations/,
    "approval must not silently authorize every prepared destination"
  );
});

test("ProfileTab prunes hidden preparation destinations and reloads same-listing status", async () => {
  const source = await readFile(
    new URL("../components/ProfileTab.jsx", import.meta.url),
    "utf8"
  );
  const pruneEffect = source.slice(
    source.indexOf("const allowed = new Set(activeListingDestinations"),
    source.indexOf("const resetPublicationApprovalSelection")
  );
  const statusEffect = source.slice(
    source.indexOf("const loadPublicationStatus = async () =>"),
    source.indexOf("const certifiedCount")
  );
  const preparationReset = source.slice(
    source.indexOf("const resetPreparationAuthorizationForm = () =>"),
    source.indexOf("const allowed = new Set(activeListingDestinations")
  );

  assert.match(preparationReset, /destinations:\s*\[\]/);
  assert.match(preparationReset, /representativeName:\s*""/);
  assert.match(preparationReset, /authorityConfirmed:\s*false/);
  assert.match(preparationReset, /tampaBayServiceConfirmed:\s*false/);
  assert.match(preparationReset, /setPreparationRequestKey\(createPartnerConsentRequestKey\(\)\)/);
  assert.match(preparationReset, /\[activeListing\?\.id, user\?\.id\]/);
  assert.match(pruneEffect, /current\.destinations\.filter\(\(destination\) => allowed\.has\(destination\)\)/);
  assert.match(pruneEffect, /tampaBayServiceConfirmed:\s*localRemoved \? false/);
  assert.match(pruneEffect, /tampaBayServiceConfirmed:\s*null/);
  assert.match(statusEffect, /activeListing\?\.updated_at/);
  assert.match(statusEffect, /activeListingCategoryKey/);
});

test("registration shows Tampa attestation only for a selected Local destination", async () => {
  const source = await readFile(
    new URL("../components/PartnerWizard.jsx", import.meta.url),
    "utf8"
  );
  const attestationCopy = source.indexOf(
    "This business accepts chef or catering requests in Tampa Bay."
  );
  const attestationGate = source.slice(
    Math.max(0, attestationCopy - 900),
    attestationCopy
  );

  assert.ok(attestationCopy >= 0, "the Local service-area attestation must remain present");
  assert.match(
    attestationGate,
    /authorization\.destinations\.includes\(PARTNER_DESTINATIONS\.local\)\s*&&/
  );
  assert.match(
    source,
    /destination === PARTNER_DESTINATIONS\.local[\s\S]*tampaBayServiceConfirmed/
  );
});

test("registration shows the Local pricing note before destination selection", async () => {
  const source = await readFile(
    new URL("../components/PartnerWizard.jsx", import.meta.url),
    "utf8"
  );
  const noteCopy = source.indexOf(
    "For chefs and caterers, these details stay private during Wave 1."
  );
  const noteGate = source.slice(Math.max(0, noteCopy - 300), noteCopy);

  assert.ok(noteCopy >= 0, "the Local featured-item privacy note must remain present");
  assert.match(noteGate, /supportsHehaLocal\(form\.categories\)\s*&&/);
  assert.doesNotMatch(noteGate, /authorization\.destinations/);
});
