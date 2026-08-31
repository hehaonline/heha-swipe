import { hasSpecificHehaLocalDestination } from "./hehaLocalRouting.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isRecord(value) {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function requiredUuid(value, field) {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new Error(`Invalid ${field}.`);
  }
  return value;
}

function nullableUuid(value, field) {
  if (value === null) return null;
  return requiredUuid(value, field);
}

function exactStatus(value, allowed, field) {
  if (typeof value !== "string" || !allowed.includes(value)) {
    throw new Error(`Invalid ${field}.`);
  }
  return value;
}

function evidenceSection(value, {
  acceptedStatus,
  field,
}) {
  if (!isRecord(value)) throw new Error(`Invalid ${field}.`);
  const status = exactStatus(value.status, [acceptedStatus, "blocked"], `${field}.status`);
  const evidenceId = nullableUuid(value.evidence_id, `${field}.evidence_id`);
  if ((status === acceptedStatus) !== Boolean(evidenceId)) {
    throw new Error(`Contradictory ${field} receipt.`);
  }
  return { status, evidence_id: evidenceId };
}

function agreementSection(value) {
  if (!isRecord(value)) throw new Error("Invalid agreement.");
  const status = exactStatus(value.status, ["accepted", "blocked"], "agreement.status");
  const acceptanceId = nullableUuid(value.acceptance_id, "agreement.acceptance_id");
  const agreementVersionId = nullableUuid(value.agreement_version_id, "agreement.agreement_version_id");
  const accepted = status === "accepted";
  if (accepted !== Boolean(acceptanceId) || accepted !== Boolean(agreementVersionId)) {
    throw new Error("Contradictory agreement receipt.");
  }
  return {
    status,
    acceptance_id: acceptanceId,
    agreement_version_id: agreementVersionId,
  };
}

function localProfileSection(value) {
  if (!isRecord(value)) throw new Error("Invalid local_profile.");
  const status = exactStatus(value.status, ["verified", "blocked"], "local_profile.status");
  const evidenceId = nullableUuid(value.evidence_id, "local_profile.evidence_id");
  const destination = value.primary_cta_destination;
  const path = value.primary_cta_path;
  const verified = status === "verified";

  if (verified) {
    if (!evidenceId
        || destination !== "local"
        || typeof path !== "string"
        || !hasSpecificHehaLocalDestination({ primary_cta_path: path })) {
      throw new Error("Contradictory local_profile receipt.");
    }
  } else if (evidenceId !== null || destination !== null || path !== null) {
    throw new Error("Contradictory blocked local_profile receipt.");
  }

  return {
    status,
    evidence_id: evidenceId,
    primary_cta_destination: verified ? destination : null,
    primary_cta_path: verified ? path : null,
  };
}

function publicationSection(value) {
  if (!isRecord(value)) throw new Error("Invalid publication.");
  const partnerConsentStatus = exactStatus(
    value.partner_consent_status,
    ["approved", "blocked"],
    "publication.partner_consent_status",
  );
  const partnerConsentEvidenceId = nullableUuid(
    value.partner_consent_evidence_id,
    "publication.partner_consent_evidence_id",
  );
  const hehaReviewStatus = exactStatus(
    value.heha_review_status,
    ["approved", "blocked"],
    "publication.heha_review_status",
  );
  const hehaReviewEvidenceId = nullableUuid(
    value.heha_review_evidence_id,
    "publication.heha_review_evidence_id",
  );
  const releaseReceiptId = nullableUuid(value.release_receipt_id, "publication.release_receipt_id");
  const swipeActivationReceiptId = nullableUuid(
    value.swipe_activation_receipt_id,
    "publication.swipe_activation_receipt_id",
  );
  const localActivationReceiptId = nullableUuid(
    value.local_activation_receipt_id,
    "publication.local_activation_receipt_id",
  );

  if (typeof value.public_swipe_visible !== "boolean"
      || typeof value.local_orderable !== "boolean") {
    throw new Error("Invalid publication booleans.");
  }
  if ((partnerConsentStatus === "approved") !== Boolean(partnerConsentEvidenceId)
      || (hehaReviewStatus === "approved") !== Boolean(hehaReviewEvidenceId)) {
    throw new Error("Contradictory publication review receipt.");
  }
  if ((value.public_swipe_visible === true)
      !== Boolean(releaseReceiptId && swipeActivationReceiptId)) {
    throw new Error("Contradictory Swipe publication receipt.");
  }
  if ((value.local_orderable === true)
      !== Boolean(releaseReceiptId && localActivationReceiptId)) {
    throw new Error("Contradictory Local activation receipt.");
  }
  if ((swipeActivationReceiptId || localActivationReceiptId) && !releaseReceiptId) {
    throw new Error("Activation receipt is missing its release receipt.");
  }

  return {
    partner_consent_status: partnerConsentStatus,
    partner_consent_evidence_id: partnerConsentEvidenceId,
    heha_review_status: hehaReviewStatus,
    heha_review_evidence_id: hehaReviewEvidenceId,
    release_receipt_id: releaseReceiptId,
    swipe_activation_receipt_id: swipeActivationReceiptId,
    local_activation_receipt_id: localActivationReceiptId,
    public_swipe_visible: value.public_swipe_visible,
    local_orderable: value.local_orderable,
  };
}

export function normalizePartnerOnboardingCapabilities(value, { partnerId, actorId }) {
  if (!isRecord(value)
      || value.projection_version !== "heha-partner-onboarding-v1"
      || requiredUuid(value.partner_id, "partner_id") !== partnerId
      || requiredUuid(value.authorized_actor_id, "authorized_actor_id") !== actorId) {
    throw new Error("Invalid partner capability projection.");
  }

  const normalized = {
    projection_version: "heha-partner-onboarding-v1",
    partner_id: value.partner_id,
    authorized_actor_id: value.authorized_actor_id,
    claim: evidenceSection(value.claim, { acceptedStatus: "verified", field: "claim" }),
    profile: evidenceSection(value.profile, { acceptedStatus: "verified", field: "profile" }),
    agreement: agreementSection(value.agreement),
    media: evidenceSection(value.media, { acceptedStatus: "approved", field: "media" }),
    compliance: evidenceSection(value.compliance, { acceptedStatus: "verified", field: "compliance" }),
    local_profile: localProfileSection(value.local_profile),
    smoke_test: evidenceSection(value.smoke_test, { acceptedStatus: "passed", field: "smoke_test" }),
    publication: publicationSection(value.publication),
  };

  if (normalized.publication.release_receipt_id) {
    const releasePrerequisitesVerified = normalized.claim.status === "verified"
      && normalized.profile.status === "verified"
      && normalized.agreement.status === "accepted"
      && normalized.media.status === "approved"
      && normalized.compliance.status === "verified"
      && normalized.local_profile.status === "verified"
      && normalized.smoke_test.status === "passed"
      && normalized.publication.partner_consent_status === "approved"
      && normalized.publication.heha_review_status === "approved";
    if (!releasePrerequisitesVerified) {
      throw new Error("Release receipt is missing a current prerequisite.");
    }
  }

  return normalized;
}

export function derivePartnerOnboardingState(capabilities) {
  const publication = capabilities?.publication;
  const smokePassed = capabilities?.smoke_test?.status === "passed"
    && Boolean(capabilities.smoke_test.evidence_id);
  const swipePublished = publication?.public_swipe_visible === true
    && Boolean(publication.swipe_activation_receipt_id);
  const localOrderable = publication?.local_orderable === true
    && Boolean(publication.local_activation_receipt_id);

  return {
    smokePassed,
    swipePublished,
    localOrderable,
    combinedLaunchReady: swipePublished && localOrderable,
  };
}
