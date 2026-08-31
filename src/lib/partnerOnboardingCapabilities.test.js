import test from "node:test";
import assert from "node:assert/strict";
import {
  derivePartnerOnboardingState,
  normalizePartnerOnboardingCapabilities,
} from "./partnerOnboardingCapabilities.js";

const partnerId = "00000000-0000-4000-8000-000000000001";
const actorId = "00000000-0000-4000-8000-000000000002";
const receiptIds = {
  claim: "00000000-0000-4000-8000-000000000011",
  profile: "00000000-0000-4000-8000-000000000012",
  acceptance: "00000000-0000-4000-8000-000000000013",
  agreement: "00000000-0000-4000-8000-000000000014",
  media: "00000000-0000-4000-8000-000000000015",
  compliance: "00000000-0000-4000-8000-000000000016",
  local: "00000000-0000-4000-8000-000000000017",
  smoke: "00000000-0000-4000-8000-000000000018",
  consent: "00000000-0000-4000-8000-000000000019",
  review: "00000000-0000-4000-8000-000000000020",
  release: "00000000-0000-4000-8000-000000000021",
  swipe: "00000000-0000-4000-8000-000000000022",
  localActivation: "00000000-0000-4000-8000-000000000023",
};

function blockedProjection() {
  return {
    projection_version: "heha-partner-onboarding-v1",
    partner_id: partnerId,
    authorized_actor_id: actorId,
    claim: { status: "blocked", evidence_id: null },
    profile: { status: "blocked", evidence_id: null },
    agreement: { status: "blocked", acceptance_id: null, agreement_version_id: null },
    media: { status: "blocked", evidence_id: null },
    compliance: { status: "blocked", evidence_id: null },
    local_profile: {
      status: "blocked",
      evidence_id: null,
      primary_cta_destination: null,
      primary_cta_path: null,
    },
    smoke_test: { status: "blocked", evidence_id: null },
    publication: {
      partner_consent_status: "blocked",
      partner_consent_evidence_id: null,
      heha_review_status: "blocked",
      heha_review_evidence_id: null,
      release_receipt_id: null,
      swipe_activation_receipt_id: null,
      local_activation_receipt_id: null,
      public_swipe_visible: false,
      local_orderable: false,
    },
  };
}

function releasedProjection() {
  const projection = blockedProjection();
  projection.claim = { status: "verified", evidence_id: receiptIds.claim };
  projection.profile = { status: "verified", evidence_id: receiptIds.profile };
  projection.agreement = {
    status: "accepted",
    acceptance_id: receiptIds.acceptance,
    agreement_version_id: receiptIds.agreement,
  };
  projection.media = { status: "approved", evidence_id: receiptIds.media };
  projection.compliance = { status: "verified", evidence_id: receiptIds.compliance };
  projection.local_profile = {
    status: "verified",
    evidence_id: receiptIds.local,
    primary_cta_destination: "local",
    primary_cta_path: "/market/00000000-0000-4000-8000-000000000031",
  };
  projection.smoke_test = { status: "passed", evidence_id: receiptIds.smoke };
  projection.publication = {
    ...projection.publication,
    partner_consent_status: "approved",
    partner_consent_evidence_id: receiptIds.consent,
    heha_review_status: "approved",
    heha_review_evidence_id: receiptIds.review,
    release_receipt_id: receiptIds.release,
  };
  return projection;
}

test("normalizes a valid combined-ready projection and derives exact target states", () => {
  const projection = releasedProjection();
  projection.publication.swipe_activation_receipt_id = receiptIds.swipe;
  projection.publication.local_activation_receipt_id = receiptIds.localActivation;
  projection.publication.public_swipe_visible = true;
  projection.publication.local_orderable = true;

  const normalized = normalizePartnerOnboardingCapabilities(projection, { partnerId, actorId });
  assert.deepEqual(derivePartnerOnboardingState(normalized), {
    smokePassed: true,
    swipePublished: true,
    localOrderable: true,
    combinedLaunchReady: true,
  });
});

test("keeps a valid Swipe-only activation distinct from pending Local orderability", () => {
  const projection = releasedProjection();
  projection.publication.swipe_activation_receipt_id = receiptIds.swipe;
  projection.publication.public_swipe_visible = true;

  const normalized = normalizePartnerOnboardingCapabilities(projection, { partnerId, actorId });
  assert.deepEqual(derivePartnerOnboardingState(normalized), {
    smokePassed: true,
    swipePublished: true,
    localOrderable: false,
    combinedLaunchReady: false,
  });
});

test("rejects activation IDs without a release and booleans without matching receipts", () => {
  const activationWithoutRelease = blockedProjection();
  activationWithoutRelease.publication.swipe_activation_receipt_id = receiptIds.swipe;
  assert.throws(() => normalizePartnerOnboardingCapabilities(
    activationWithoutRelease,
    { partnerId, actorId },
  ));

  const trueWithoutReceipt = blockedProjection();
  trueWithoutReceipt.publication.public_swipe_visible = true;
  assert.throws(() => normalizePartnerOnboardingCapabilities(
    trueWithoutReceipt,
    { partnerId, actorId },
  ));
});

test("rejects a release receipt when compliance or another current prerequisite is missing", () => {
  const projection = releasedProjection();
  projection.compliance = { status: "blocked", evidence_id: null };
  assert.throws(() => normalizePartnerOnboardingCapabilities(projection, { partnerId, actorId }));
});

test("rejects blocked Local projections that leak a route or malformed receipt IDs", () => {
  const leakedRoute = blockedProjection();
  leakedRoute.local_profile.primary_cta_destination = "local";
  leakedRoute.local_profile.primary_cta_path = "/restaurants/00000000-0000-4000-8000-000000000031";
  assert.throws(() => normalizePartnerOnboardingCapabilities(leakedRoute, { partnerId, actorId }));

  const truthyReceipt = blockedProjection();
  truthyReceipt.claim = { status: "verified", evidence_id: "yes" };
  assert.throws(() => normalizePartnerOnboardingCapabilities(truthyReceipt, { partnerId, actorId }));
});
