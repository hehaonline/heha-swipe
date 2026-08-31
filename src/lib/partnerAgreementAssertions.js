export const PARTNER_AGREEMENT_ASSERTION_KEYS = Object.freeze([
  "assertions_version",
  "signer_legal_name",
  "signer_title",
  "typed_signature",
  "signer_authority_confirmed",
  "electronic_records_consent",
  "reviewed_complete_agreement",
  "assent_text",
]);

function normalizedSignerText(value) {
  return String(value || "").trim().replace(/\s+/g, " ");
}

export function buildPartnerAgreementAssertions({
  signerLegalName,
  signerTitle,
  typedSignature,
  signerAuthorityConfirmed,
  electronicRecordsConsent,
  reviewedCompleteAgreement,
  assentText,
}) {
  return {
    assertions_version: "heha-partner-acceptance-v1",
    signer_legal_name: normalizedSignerText(signerLegalName),
    signer_title: normalizedSignerText(signerTitle),
    typed_signature: normalizedSignerText(typedSignature),
    signer_authority_confirmed: signerAuthorityConfirmed === true,
    electronic_records_consent: electronicRecordsConsent === true,
    reviewed_complete_agreement: reviewedCompleteAgreement === true,
    assent_text: String(assentText || ""),
  };
}
