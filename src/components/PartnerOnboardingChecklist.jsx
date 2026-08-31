import { hehaLocalProfileUrl, isHehaLocalPartner } from "../lib/hehaLocalRouting";
import { derivePartnerOnboardingState } from "../lib/partnerOnboardingCapabilities";

const DEVICE_INSTALL_KEY = "heha_partner_install_device_v1";

function readInstallProgress(listingId) {
  if (!listingId) return {};
  try {
    return JSON.parse(localStorage.getItem(DEVICE_INSTALL_KEY) || "{}");
  } catch {
    return {};
  }
}

function statusClass(status) {
  if (status === "done") return "complete";
  if (status === "blocked") return "blocked";
  return "next";
}

function statusLabel(status) {
  if (status === "done") return "Complete";
  if (status === "blocked") return "Blocked";
  return "Next";
}

export default function PartnerOnboardingChecklist({
  listing,
  onEditProfile,
  onReviewAgreement,
  onAddMedia,
  onInstallApps,
  onPreview,
}) {
  if (!listing) return null;

  const installProgress = readInstallProgress(listing.id);
  const capabilities = listing.onboarding_capabilities || null;
  const profileEstimate = Math.round(Number(listing.complete_pct || 0));
  const relationshipClaimed = capabilities?.claim?.status === "verified" && Boolean(capabilities.claim.evidence_id);
  const profileComplete = capabilities?.profile?.status === "verified" && Boolean(capabilities.profile.evidence_id);
  const agreementSigned = capabilities?.agreement?.status === "accepted"
    && Boolean(capabilities.agreement.acceptance_id)
    && Boolean(capabilities.agreement.agreement_version_id);
  const mediaReady = capabilities?.media?.status === "approved" && Boolean(capabilities.media.evidence_id);
  const complianceReady = capabilities?.compliance?.status === "verified"
    && Boolean(capabilities.compliance.evidence_id);
  const deviceSetup = Boolean(installProgress.swipeConfirmed && installProgress.localConfirmed);
  const localProfile = capabilities?.local_profile || null;
  const localPartner = localProfile ? {
    id: listing.id,
    local_eligible: localProfile.status === "verified" && Boolean(localProfile.evidence_id),
    primary_cta_destination: localProfile.primary_cta_destination,
    primary_cta_path: localProfile.primary_cta_path,
  } : null;
  const localProfileReady = Boolean(localPartner && isHehaLocalPartner(localPartner));
  const releaseVerified = Boolean(capabilities?.publication?.release_receipt_id);
  const partnerConsentApproved = capabilities?.publication?.partner_consent_status === "approved"
    && Boolean(capabilities.publication.partner_consent_evidence_id);
  const hehaReviewApproved = capabilities?.publication?.heha_review_status === "approved"
    && Boolean(capabilities.publication.heha_review_evidence_id);
  const publicationApproved = partnerConsentApproved && hehaReviewApproved;
  const {
    smokePassed,
    swipePublished,
    localOrderable,
    combinedLaunchReady,
  } = derivePartnerOnboardingState(capabilities);

  const publicationCopy = combinedLaunchReady
    ? "Swipe is publicly visible and Local reports this exact partner orderable; both target activation receipts are current."
    : swipePublished
    ? "Swipe is publicly visible, but Local ordering remains blocked until Local returns its separate activation receipt."
    : localOrderable
    ? "Local orderability is activated, but the partner remains private in Swipe until Swipe returns its publication receipt."
    : releaseVerified
    ? "HEHA authorized this exact evidence set; Swipe publication and Local ordering still need separate target activation receipts."
    : publicationApproved
    ? "Partner consent and HEHA review are recorded; the exact release receipt is still pending."
    : partnerConsentApproved
    ? "Partner publication consent is recorded; HEHA review is still pending."
    : hehaReviewApproved
    ? "HEHA review is recorded; the partner's final publication consent is still pending."
    : "Nothing goes public until the partner sees the final preview, approves it, and HEHA verifies every launch gate.";

  const steps = [
    {
      id: "claim",
      title: "Verify the business relationship",
      copy: relationshipClaimed
        ? "A current recipient-bound claim connects the verified operator account to this business profile."
        : "Not connected: use a recipient-bound, expiring, single-use HEHA invitation. A generic signup, self-attestation, or self-created profile is not proof.",
      status: relationshipClaimed ? "done" : "blocked",
      action: null,
    },
    {
      id: "profile",
      title: "Complete profile, menu, pricing & capacity",
      copy: profileComplete
        ? "A server readiness receipt verifies the required profile, menu, pricing, hours, and capacity fields."
        : `${profileEstimate}% is present in the current Swipe draft; it is not launch-ready until a server readiness receipt verifies the full category checklist.`,
      status: profileComplete ? "done" : "next",
      action: { label: "Edit profile", handler: onEditProfile },
    },
    {
      id: "agreement",
      title: "Review and sign the correct agreement",
      copy: agreementSigned
        ? "An immutable, category-bound acceptance receipt is linked to this partner."
        : "Not connected: the server must verify signer authority, legal relationship, counsel approval, exact document, assertions, and receipt before in-app signing unlocks.",
      status: agreementSigned ? "done" : relationshipClaimed ? "next" : "blocked",
      action: { label: "Review agreement", handler: onReviewAgreement },
    },
    {
      id: "media",
      title: "Add logo and business photos",
      copy: mediaReady
        ? "A media-review receipt approves the logo, cover, and category-required photos."
        : "Upload a logo, cover image, and helpful menu/product photos for private HEHA review; file presence alone is not approval.",
      status: mediaReady ? "done" : "next",
      action: { label: "Add photos", handler: onAddMedia },
    },
    {
      id: "compliance",
      title: "Complete category compliance review",
      copy: complianceReady
        ? "A current server receipt verifies the required category-specific compliance evidence."
        : "HEHA must verify the licenses, insurance, permits, and other requirements that apply to this partner category.",
      status: complianceReady ? "done" : relationshipClaimed ? "next" : "blocked",
      action: null,
    },
    {
      id: "install",
      title: "Add HEHA Swipe and Local to the home screen",
      copy: deviceSetup
        ? "This device has both installs self-confirmed."
        : "Follow the iPhone or Android pictures and confirm each icon on this device.",
      status: deviceSetup ? "done" : "next",
      action: { label: "Install apps", handler: onInstallApps },
    },
    {
      id: "test",
      title: "Run an authenticated test order",
      copy: smokePassed
        ? localOrderable
          ? "The exact customer → partner → driver → delivery path passed, and Local currently reports this partner orderable."
          : "The authenticated end-to-end smoke test passed; Local activation is still a separate pending gate."
        : localProfileReady
        ? "A specific Local profile exists; the full customer → partner → driver → delivery flow still needs a recorded test."
        : "No verified partner-specific HEHA Local order path is connected yet.",
      status: smokePassed ? "done" : localProfileReady ? "next" : "blocked",
      action: localProfileReady
        ? { label: "Open Local profile", handler: () => window.open(hehaLocalProfileUrl(localPartner), "_blank", "noopener,noreferrer") }
        : null,
    },
    {
      id: "publish",
      title: "Activate Swipe publication and Local ordering",
      copy: publicationCopy,
      status: combinedLaunchReady
        ? "done"
        : (releaseVerified || swipePublished || localOrderable || publicationApproved || partnerConsentApproved || hehaReviewApproved)
        ? "next"
        : "blocked",
      action: { label: "Preview listing", handler: onPreview },
    },
  ];

  const doneCount = steps.filter((step) => step.status === "done").length;

  return (
    <section className="partner-onboarding-checklist card-like" aria-label="Partner launch checklist">
      <div className="partner-checklist-heading">
        <div>
          <p className="eyebrow">One guided setup</p>
          <h2>From private profile to orderable partner</h2>
        </div>
        <strong>{doneCount}/{steps.length}</strong>
      </div>
      <div className="partner-checklist-progress" role="progressbar" aria-valuemin="0" aria-valuemax={steps.length} aria-valuenow={doneCount}>
        <span style={{ width: `${(doneCount / steps.length) * 100}%` }} />
      </div>

      {(!capabilities || listing.release_gate_error) && (
        <div className="agreement-gate warning" role="alert">
          The owner-safe server capability projection is not connected, so claim, agreement, profile, media,
          compliance, test-order, publication, and orderability gates remain blocked.
        </div>
      )}

      <ol className="partner-checklist-steps">
        {steps.map((step, index) => (
          <li key={step.id} className={statusClass(step.status)}>
            <span className="partner-checklist-number">{step.status === "done" ? "✓" : index + 1}</span>
            <div>
              <div className="partner-checklist-title-row">
                <h3>{step.title}</h3>
                <span>{statusLabel(step.status)}</span>
              </div>
              <p>{step.copy}</p>
              {step.action?.handler && (
                <button className="text-button" type="button" onClick={step.action.handler}>{step.action.label} →</button>
              )}
            </div>
          </li>
        ))}
      </ol>

      <p className="partner-checklist-fineprint">
        Home-screen confirmation is device guidance, not publication proof. Agreement, compliance, orderability,
        test-order, partner-consent, and HEHA-review receipts remain separate fail-closed gates.
      </p>
    </section>
  );
}
