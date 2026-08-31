import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(new URL("./PartnerProfileEditor.jsx", import.meta.url), "utf8");
const repositorySource = readFileSync(new URL("../services/partnerApplicationRepository.js", import.meta.url), "utf8");
const wizardSource = readFileSync(new URL("./PartnerWizard.jsx", import.meta.url), "utf8");

test("protected pending profiles use only the unified server-owned correction router", () => {
  for (const status of ["draft", "submitted", "pending", "missing_info"]) {
    assert.match(source, new RegExp(`\\b${status}\\b`));
  }

  assert.match(
    source,
    /const protectedCorrection = PROTECTED_APPLICATION_STATUSES\.includes\(listingStatus\)/,
  );
  assert.match(source, /if \(protectedCorrection\)[\s\S]*?await revisePartnerProfile\(/);
  assert.match(wizardSource, /applicationPartnerId[\s\S]*?await revisePartnerProfile\(/);
  assert.match(repositorySource, /supabase\.rpc\("revise_partner_profile_v1", \{/);
  assert.match(repositorySource, /p_partner_id: partnerId,[\s\S]*p_request_key: requestKey,[\s\S]*p_profile_snapshot: prepared\.application/);
  assert.match(repositorySource, /validatePartnerProfileCorrectionReceipt/);
  assert.doesNotMatch(repositorySource, /supabase\.rpc\("revise_partner_application_v1"/);
  assert.doesNotMatch(repositorySource, /supabase\.rpc\("revise_claimed_partner_profile_v1"/);
  assert.doesNotMatch(repositorySource, /correctionSource|expectedSource|profileSource/);
  assert.doesNotMatch(source, /VITE_ENABLE_PROTECTED_PARTNER_APPLICATION/);
  assert.doesNotMatch(source, /\.from\(["']partners["']\)[\s\S]{0,500}?\.update\(/);
});

test("claim-bound editor locks receipt-backed identity and preserves structured hours", () => {
  assert.match(source, /hasVerifiedPartnerClaim\(listing\?\.onboarding_capabilities/);
  assert.match(source, /disabled=\{claimBound\}/);
  assert.match(source, /claimedProfileHasStructuredHours\(listing\)/);
  assert.match(source, /buildProtectedPartnerProfileSnapshot\(form, listing, \{ claimBound \}\)/);
});

test("profile editor exposes only generic actionable save errors", () => {
  assert.doesNotMatch(source, /\.message\b/);
  assert.match(source, /PROTECTED_CORRECTION_SAVE_ERROR/);
  assert.match(source, /PROFILE_REQUEST_LOAD_ERROR/);
  assert.match(source, /PROFILE_REQUEST_SAVE_ERROR/);
});
