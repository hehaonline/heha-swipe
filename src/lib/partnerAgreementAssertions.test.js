import test from "node:test";
import assert from "node:assert/strict";
import {
  buildPartnerAgreementAssertions,
  PARTNER_AGREEMENT_ASSERTION_KEYS,
} from "./partnerAgreementAssertions.js";

test("builds exactly the eight server-approved legal assertions", () => {
  const assertions = buildPartnerAgreementAssertions({
    signerLegalName: "  Sachiko   Example ",
    signerTitle: " Owner ",
    typedSignature: "Sachiko Example",
    signerAuthorityConfirmed: true,
    electronicRecordsConsent: true,
    reviewedCompleteAgreement: true,
    assentText: "I agree.",
  });

  assert.deepEqual(Object.keys(assertions), PARTNER_AGREEMENT_ASSERTION_KEYS);
  assert.equal(assertions.signer_legal_name, "Sachiko Example");
  assert.equal(assertions.signer_title, "Owner");
  assert.equal(assertions.typed_signature, "Sachiko Example");
  assert.equal("terms_opened_at_client" in assertions, false);
  assert.equal("terms_downloaded_at_client" in assertions, false);
  assert.equal("timezone_client" in assertions, false);
  assert.equal("locale_client" in assertions, false);
});
