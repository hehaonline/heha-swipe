import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const exists = (relative) => fs.existsSync(path.join(root, relative));

let checks = 0;
function assert(condition, message) {
  checks += 1;
  if (!condition) throw new Error(`Partner onboarding verification failed: ${message}`);
}

const envExample = read(".env.example");
const agreementSource = read("src/contracts/partnerAgreements.js");
const agreementFlow = read("src/components/PartnerAgreementFlow.jsx");
const agreementRepository = read("src/services/partnerAgreementRepository.js");
const agreementVerification = read("src/lib/partnerAgreementVerification.js");
const checklist = read("src/components/PartnerOnboardingChecklist.jsx");
const onboardingRepository = read("src/services/partnerOnboardingRepository.js");
const applicationRepository = read("src/services/partnerApplicationRepository.js");
const claimRepository = read("src/services/partnerClaimRepository.js");
const partnerInvite = read("src/lib/partnerInvite.js");
const partnerWizard = read("src/components/PartnerWizard.jsx");
const partnerProfileEditor = read("src/components/PartnerProfileEditor.jsx");
const routing = read("src/lib/hehaLocalRouting.js");
const main = read("src/main.jsx");
const indexHtml = read("index.html");
const serviceWorker = read("public/sw.js");
const manifest = JSON.parse(read("public/manifest.json"));
const reviewContract = read("supabase/review_only/partner_onboarding_v1/README.md");
const releaseGates = read("docs/partner-onboarding-release-gates.md");

assert(envExample.includes("VITE_ENABLE_PARTNER_AGREEMENT_ACCEPTANCE=false"), "agreement runtime defaults off");
assert(envExample.includes("VITE_ENABLE_PARTNER_ONBOARDING_CAPABILITIES=false"), "capability projection defaults off");
assert(envExample.includes("VITE_ENABLE_PROTECTED_PARTNER_APPLICATION=false"), "protected application defaults off");
assert(envExample.includes("VITE_ENABLE_PROTECTED_PARTNER_CLAIM=false"), "protected invitation claim defaults off");
assert(envExample.includes("VITE_ENABLE_HEHA_SWIPE_PWA=false"), "PWA runtime defaults off");
assert(agreementFlow.includes("serverAgreement?.document_snapshot"), "UI renders the server document when signing");
assert(agreementRepository.includes('get_partner_agreement_for_acceptance_v1'), "UI loads a server-selected category agreement");
assert(agreementRepository.includes('record_category_partner_agreement_acceptance_v1'), "UI targets the category-bound successor RPC");
assert(!agreementFlow.includes('record_partner_agreement_acceptance'), "agreement UI does not call the unsafe donor RPC");
assert(!agreementRepository.includes('rpc("record_partner_agreement_acceptance"'), "repository does not call the unsafe donor RPC");
assert(!agreementRepository.includes("throw error"), "agreement failures never expose raw RPC errors");
assert(agreementRepository.includes("GENERIC_AGREEMENT_ERROR"), "agreement failures use one privacy-preserving message");
assert(agreementVerification.includes("canonicalJson(verified.assertions_snapshot) === canonicalJson(assertions)"), "receipt assertions exact-match the request");
assert(agreementVerification.includes("verified.assertions_sha256 === expectedAssertionsSha256"), "receipt assertions hash matches the submitted canonical assertions");
assert(agreementVerification.includes("computed !== agreement.document_sha256"), "exact displayed agreement digest is recomputed");
assert(agreementVerification.includes('verified.receipt_status === "verified"'), "receipt status must be server verified");
assert(agreementFlow.includes("sessionStorage.setItem(storageKey, stableRequestKey)"), "agreement retries reuse a stable session request key");
assert(agreementFlow.includes("Acceptance never auto-publishes"), "signing does not imply publication");
assert(onboardingRepository.includes("get_partner_onboarding_capabilities_v1"), "checklist uses one owner-safe capability projection");
assert(applicationRepository.includes("create_or_resume_partner_application_v1"), "partner application uses an idempotent server RPC");
assert(!applicationRepository.includes("throw error"), "application failures never expose raw RPC errors");
assert(applicationRepository.includes("GENERIC_APPLICATION_ERROR"), "application failures use one privacy-preserving message");
assert(claimRepository.includes("claim_partner_invitation_v1"), "partner invitation uses a versioned protected claim RPC");
assert(partnerInvite.includes('params.delete("partner_invite")'), "invite fragment is removed from the visible URL");
assert(partnerInvite.includes("window.location.replace(sanitizedUrl)"), "invite cleanup has a sanitized reload fallback");
assert(partnerInvite.includes("inviteUrlHardStop = true"), "invite page hard-stops if both cleanup methods fail");
assert(partnerInvite.includes("sessionSet(SESSION_KEY, candidate)"), "valid invite remains session scoped");
assert(partnerInvite.includes("pendingPartnerInviteRequestKey"), "claim retries reuse a session-scoped request key");
assert(!partnerInvite.includes("localStorage"), "invite is never persisted to local storage");
assert(!partnerInvite.includes("console."), "invite is never logged by the token helper");
assert(partnerWizard.includes("pendingPartnerInviteToken"), "partner wizard consumes the protected invite intent");
assert(partnerWizard.includes('setListingEntrySource("claim")'), "claimed profiles retain a distinct UI outcome");
assert(partnerWizard.includes("No application was submitted by this claim"), "claim UI never misstates an existing profile as submitted");
assert(partnerProfileEditor.includes('["PrivateChef", "Private Chef"]'), "legacy private-chef profile values normalize before edit");
assert(partnerProfileEditor.includes("rawListingCategories(listing)"), "profile edits persist canonical category upgrades");
assert(!claimRepository.includes("throw error"), "claim failures never expose raw RPC errors");
assert(claimRepository.includes("GENERIC_CLAIM_ERROR"), "claim failures use one privacy-preserving message");
assert(!partnerWizard.includes('.from("partners").insert'), "wizard has no browser SELECT-then-INSERT path");
assert(!checklist.includes("listing.contract_status"), "checklist does not infer agreement readiness from legacy flat fields");
assert(!checklist.includes("listing.status"), "checklist does not infer public visibility from legacy status");

for (const key of ["restaurant", "vendor", "market", "catering", "solo_chef", "driver", "som"]) {
  assert(agreementSource.includes(`${key}: agreement({`), `category draft ${key}`);
}
assert((agreementSource.match(/status: "legal_review"/g) || []).length === 1, "all drafts inherit legal-review status");
assert(!agreementSource.includes('status: "approved"'), "no agreement is accidentally approved in source");

for (const step of [
  "Verify the business owner",
  "Complete profile, menu, pricing & capacity",
  "Review and sign the correct agreement",
  "Add logo and business photos",
  "Add HEHA Swipe and Local to the home screen",
  "Run an authenticated test order",
  "Partner approves publication; HEHA publishes",
]) {
  assert(checklist.includes(step), `checklist step ${step}`);
}

for (const generic of ["/restaurants", "/vendors", "/market", "/chef", "/group-orders"]) {
  assert(routing.includes(`"${generic}"`), `generic Local route fail-close ${generic}`);
}

assert(main.includes('VITE_ENABLE_HEHA_SWIPE_PWA === "true"'), "service-worker registration has a release gate");
assert(main.includes('addLink("manifest", "/manifest.json")'), "PWA flag controls manifest discovery");
assert(!indexHtml.includes('rel="manifest"'), "locked HTML does not expose install metadata unconditionally");
assert(!indexHtml.includes("apple-mobile-web-app-capable"), "locked HTML does not expose Apple standalone metadata unconditionally");
assert(main.includes('registration.unregister()'), "disabled release retires an older HEHA Swipe worker");
assert(main.includes('key.startsWith("heha-swipe-shell-")'), "disabled release clears only HEHA Swipe caches");
assert(main.includes('new Set(["heha-v1"])'), "disabled release clears the known legacy HEHA cache");
assert(serviceWorker.includes('key.startsWith("heha-swipe-shell-") || LEGACY_HEHA_CACHES.has(key)'), "worker activation isolates its cache cleanup");
assert(serviceWorker.includes('new Set(["heha-v1"])'), "worker activation clears the known legacy HEHA cache");
assert(serviceWorker.includes('url.pathname.startsWith("/assets/")'), "worker caches only immutable build assets and explicit shell files");
assert(!serviceWorker.includes('new Set(["script", "style", "image", "font"])'), "worker does not cache every same-origin image");
assert(envExample.includes("VITE_ENABLE_HEHA_LOCAL_INSTALL=false"), "Local install defaults off independently");
assert(manifest.id === "/", "manifest identity");
assert(manifest.short_name === "HEHA Swipe", "distinct Swipe home-screen name");
assert(manifest.icons.some((icon) => icon.purpose === "any" && icon.sizes === "512x512"), "512 any icon");
assert(manifest.icons.some((icon) => icon.purpose === "maskable" && icon.sizes === "512x512"), "512 maskable icon");

for (const icon of [
  "public/icons/icon-180.png",
  "public/icons/icon-192.png",
  "public/icons/icon-512.png",
  "public/icons/icon-maskable-192.png",
  "public/icons/icon-maskable-512.png",
]) {
  assert(exists(icon), `icon exists ${icon}`);
  assert(fs.statSync(path.join(root, icon)).size > 5000, `icon is not a truncated placeholder ${icon}`);
}

assert(reviewContract.includes("REVIEW ONLY / SIGNING DISABLED / PRODUCTION FROZEN"), "review-only database boundary");
assert(reviewContract.includes("Do not create parallel agreement tables"), "#127 donor reconciliation boundary");
assert(reviewContract.includes("A stale page cannot accept after claim"), "agreement mutation closes stale-page TOCTOU acceptance");
assert(reviewContract.includes("undefined alternate ownership path"), "claim v1 has no unproved ownership bypass");
assert(releaseGates.includes("Do not contact Sachiko with a generic"), "protected invite gate");
assert(releaseGates.includes("customer order → partner acceptance →"), "end-to-end test definition");

for (const source of [agreementSource, agreementFlow, agreementRepository, agreementVerification, checklist, onboardingRepository, applicationRepository, claimRepository, partnerInvite, partnerWizard, partnerProfileEditor, reviewContract, releaseGates]) {
  assert(!/https:\/\/[a-z0-9-]+\.supabase\.co/i.test(source), "no live Supabase endpoint");
  assert(!/\b(?:sk|rk)_(?:live|test)_[a-zA-Z0-9]/.test(source), "no Stripe secret");
  assert(!/SUPABASE_SERVICE_ROLE_KEY\s*=\s*\S+/.test(source), "no service-role credential");
}

console.log(`PASS: partner onboarding review verified ${checks}/${checks} source controls.`);
