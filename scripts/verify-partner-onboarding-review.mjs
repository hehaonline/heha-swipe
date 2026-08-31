import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const exists = (relative) => fs.existsSync(path.join(root, relative));

let checks = 0;
function assert(condition, message) {
  checks += 1;
  if (!condition) throw new Error(`Partner onboarding verification failed: ${message}`);
}

function functionSection(sql, qualifiedName) {
  const escaped = qualifiedName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const startPattern = new RegExp(
    `create\\s+or\\s+replace\\s+function\\s+${escaped}\\s*\\(`,
    "i",
  );
  const match = startPattern.exec(sql);
  assert(Boolean(match), `database function ${qualifiedName}`);
  if (!match) return "";

  const remainder = sql.slice(match.index);
  const next = remainder.slice(match[0].length).search(/\ncreate\s+or\s+replace\s+function\s+/i);
  return next === -1
    ? remainder
    : remainder.slice(0, match[0].length + next);
}

function viewSection(sql, qualifiedName) {
  const escaped = qualifiedName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(
    `create(?:\\s+or\\s+replace)?\\s+view\\s+${escaped}\\b`,
    "i",
  ).exec(sql);
  assert(Boolean(match), `database view ${qualifiedName}`);
  if (!match) return "";

  const end = sql.indexOf(";", match.index);
  assert(end >= 0, `database view ${qualifiedName} terminates`);
  return end >= 0 ? sql.slice(match.index, end + 1) : sql.slice(match.index);
}

function declaredPublicFunctionSignatures(sql) {
  const signatures = [];
  const declaration = /create\s+(?:or\s+replace\s+)?function\s+(public|"public")\s*\.\s*([a-z0-9_]+|"[^"]+")\s*\(([\s\S]*?)\)\s*returns\b/gi;
  for (const match of sql.matchAll(declaration)) {
    const argumentTypes = match[3].trim() === ""
      ? []
      : match[3].split(",").map((argument) => {
        const tokens = argument.trim().split(/\s+/);
        return tokens.at(-1).toLowerCase();
      });
    signatures.push(`public.${match[2].toLowerCase()}(${argumentTypes.join(",")})`);
  }
  return signatures.sort();
}

const plainPublicFunctionPattern = /create\s+function\s+(?:public|"public")\s*\./i;
const publicProcedurePattern = /create\s+(?:or\s+replace\s+)?procedure\s+(?:public|"public")\s*\./i;
const quotedPublicRoutinePattern = /create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+(?:"public"\s*\.|public\s*\.\s*")/i;
assert(plainPublicFunctionPattern.test("CREATE FUNCTION public.unreviewed() RETURNS void"), "public-routine detector catches plain CREATE FUNCTION");
assert(publicProcedurePattern.test("CREATE OR REPLACE PROCEDURE public.unreviewed()"), "public-routine detector catches CREATE PROCEDURE");
assert(quotedPublicRoutinePattern.test('CREATE OR REPLACE FUNCTION "public"."unreviewed"() RETURNS void'), "public-routine detector catches quoted identifiers");

function hasCanonicalReviewGuard(guardBody) {
  const settingCheck = String.raw`coalesce\s*\(\s*(?:pg_catalog\.)?current_setting\s*\(\s*'heha\.review_only'\s*,\s*true\s*\)\s*,\s*''\s*\)\s*<>\s*'on'`;
  const databaseCheck = String.raw`(?:pg_catalog\.)?current_database\s*\(\s*\)\s*<>\s*'partner_onboarding_review'`;
  const serverAddress = String.raw`(?:pg_catalog\.)?inet_server_addr\s*\(\s*\)`;
  const serverHost = String.raw`(?:pg_catalog\.)?host\s*\(\s*${serverAddress}\s*\)`;
  const loopbackList = String.raw`\(\s*'127\.0\.0\.1'\s*,\s*'::1'\s*\)`;
  const addressCheck = String.raw`coalesce\s*\(\s*${serverHost}\s*,\s*''\s*\)\s+not\s+in\s*${loopbackList}`;
  const completeGuard = new RegExp(
    String.raw`^\s*begin\s+if\s+${settingCheck}\s+or\s+${databaseCheck}\s+or\s+${addressCheck}\s+then\s+raise\s+exception\s+'HEHA_REVIEW_ONLY_GUARD'\s+using\s+errcode\s*=\s*'42501'\s*,\s*hint\s*=\s*'[^']+'\s*;\s*end\s+if\s*;\s*end\s*;?\s*$`,
    "i",
  );
  return completeGuard.test(guardBody);
}

function assertExternallyGuardedTransaction(sql, label) {
  const uncommented = sql
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*--.*$/gm, "")
    .trimStart();
  const guardMatch = /^begin\s*;\s*do\s+\$review_only_guard\$([\s\S]*?)\$review_only_guard\$\s*;/i.exec(uncommented);
  assert(Boolean(guardMatch), `${label} starts a transaction with the complete review-only guard first`);
  const guardBody = guardMatch?.[1] || "";
  assert(
    hasCanonicalReviewGuard(guardBody),
    `${label} requires the exact loopback disposable database`,
  );
  assert(
    !/\bset\s+(?:(?:local|session)\s+)?heha\.review_only\b/i.test(uncommented)
      && !/\bset_config\s*\([^)]*['"]heha\.review_only['"]/i.test(uncommented)
      && !/\balter\s+(?:role|database|system)\b[\s\S]{0,240}?\bset\s+heha\.review_only\b/i.test(uncommented),
    `${label} cannot self-authorize the external review-only guard`,
  );
}

const outsideOnlyGuardFixture = `
begin;
do $review_only_guard$
begin
  null;
end;
$review_only_guard$;
select 'current_setting(''heha.review_only'', true) <> on current_database() <> partner_onboarding_review inet_server_addr() 127.0.0.1 ::1 HEHA_REVIEW_ONLY_GUARD 42501';
`;
const outsideOnlyBody = /^begin\s*;\s*do\s+\$review_only_guard\$([\s\S]*?)\$review_only_guard\$\s*;/i.exec(outsideOnlyGuardFixture)?.[1] || "";
assert(!outsideOnlyBody.includes("current_database()"), "review guard verifier ignores lookalike tokens outside the guard body");
assert(
  !hasCanonicalReviewGuard(`begin
    null; -- current_setting('heha.review_only', true) <> 'on' current_database() <> 'partner_onboarding_review'
  end;`),
  "review guard verifier ignores lookalike tokens in inline comments",
);
assert(
  !hasCanonicalReviewGuard(`begin
    perform 'if coalesce(current_setting(''heha.review_only'', true), '''') <> ''on'' then raise exception';
  end;`),
  "review guard verifier ignores lookalike tokens in SQL string literals",
);
assert(
  !hasCanonicalReviewGuard(`begin
    if coalesce(current_setting('heha.review_only', true), '') <> 'on'
       or current_database() <> 'partner_onboarding_review'
       or coalesce(inet_server_addr()::text, '') not in ('127.0.0.1', '::1') then
      raise exception 'HEHA_REVIEW_ONLY_GUARD'
        using errcode = '42501', hint = 'old text cast';
    end if;
  end;`),
  "review guard verifier rejects CIDR-bearing inet text casts",
);

const directPartnerInsertPattern = /\.from\s*\(\s*(["'])partners\1\s*\)\s*\.insert\s*\(/i;
const partnerTableAccessPattern = /\.from\s*\(\s*(["'])partners\1\s*\)/i;
const unsafeAgreementRpcPattern = /\.rpc\s*\(\s*(["'])record_partner_agreement_acceptance\1\s*[,)]/i;
const approvedAgreementStatusPattern = /\bstatus\s*:\s*(["'])approved\1/i;
const legalReviewAgreementStatusPattern = /\bstatus\s*:\s*(["'])legal_review\1/gi;
function hasManifestLink(html) {
  return (html.match(/<link\b[^>]*>/gi) || []).some((tag) => (
    /\brel\s*=\s*(?:"[^"]*\bmanifest\b[^"]*"|'[^']*\bmanifest\b[^']*'|[^\s>]*\bmanifest\b[^\s>]*)/i.test(tag)
  ));
}
assert(directPartnerInsertPattern.test("client.from ( 'partners' ) .insert (payload)"), "direct-write detector is quote and whitespace independent");
assert(unsafeAgreementRpcPattern.test("client.rpc ( 'record_partner_agreement_acceptance', args )"), "unsafe-RPC detector is quote and whitespace independent");
assert(approvedAgreementStatusPattern.test("status : 'approved'"), "agreement-status detector is quote and whitespace independent");
assert(hasManifestLink("<LINK href='/manifest.json' REL='MANIFEST'>"), "manifest detector is case, quote, and attribute-order independent");

const envExample = read(".env.example");
const agreementSource = read("src/contracts/partnerAgreements.js");
const agreementFlow = read("src/components/PartnerAgreementFlow.jsx");
const agreementRepository = read("src/services/partnerAgreementRepository.js");
const agreementVerification = read("src/lib/partnerAgreementVerification.js");
const checklist = read("src/components/PartnerOnboardingChecklist.jsx");
const onboardingRepository = read("src/services/partnerOnboardingRepository.js");
const onboardingCapabilities = read("src/lib/partnerOnboardingCapabilities.js");
const onboardingCapabilitiesTest = read("src/lib/partnerOnboardingCapabilities.test.js");
const onboardingAssignments = read("src/lib/partnerOnboardingAssignments.js");
const onboardingAssignmentsTest = read("src/lib/partnerOnboardingAssignments.test.js");
const applicationRepository = read("src/services/partnerApplicationRepository.js");
const applicationReceipt = read("src/lib/partnerApplicationReceipt.js");
const applicationReceiptTest = read("src/lib/partnerApplicationReceipt.test.js");
const partnerProfileCorrection = read("src/lib/partnerProfileCorrection.js");
const partnerProfileCorrectionTest = read("src/lib/partnerProfileCorrection.test.js");
const claimRepository = read("src/services/partnerClaimRepository.js");
const partnerInvite = read("src/lib/partnerInvite.js");
const partnerWizard = read("src/components/PartnerWizard.jsx");
const partnerProfileEditor = read("src/components/PartnerProfileEditor.jsx");
const routing = read("src/lib/hehaLocalRouting.js");
const routingTest = read("src/lib/hehaLocalRouting.test.js");
const clientOrderRoutingSourceTest = read("src/lib/clientOrderRoutingSource.test.js");
const main = read("src/main.jsx");
const indexHtml = read("index.html");
const serviceWorker = read("public/sw.js");
const manifest = JSON.parse(read("public/manifest.json"));
const packageJson = JSON.parse(read("package.json"));
const reviewContract = read("supabase/review_only/partner_onboarding_v1/README.md");
const releaseGates = read("docs/partner-onboarding-release-gates.md");
const reviewWorkflow = read(".github/workflows/partner-onboarding-review.yml");

const databasePaths = {
  baseline: "supabase/review_only/partner_onboarding_v1/000_minimal_baseline.sql",
  foundation: "supabase/review_only/partner_onboarding_v1/001_partner_onboarding_foundation.sql",
  transitions: "supabase/review_only/partner_onboarding_v1/002_partner_onboarding_transitions.sql",
  release: "supabase/review_only/partner_onboarding_v1/003_partner_release_gate.sql",
  proof: "supabase/review_only/partner_onboarding_v1/proof/001_partner_onboarding.proof.sql",
  concurrency: "supabase/review_only/partner_onboarding_v1/proof/concurrency_two_client.sh",
  rollback: "supabase/review_only/partner_onboarding_v1/rollback/001_partner_onboarding.rollback.sql",
};

for (const filePath of Object.values(databasePaths)) {
  assert(exists(filePath), `required disposable database file ${filePath}`);
  assert(!filePath.startsWith("supabase/migrations/"), `review SQL stays outside migrations: ${filePath}`);
}

const database = Object.fromEntries(
  Object.entries(databasePaths).map(([key, filePath]) => [key, read(filePath)]),
);

for (const [documentSnapshot, expectedSha256] of [
  [
    "SYNTHETIC DOCUMENT -- NO LEGAL EFFECT",
    "1d6f45eae21a6538bce2b0b172f6c024937f230d87122783bbf897f3dd103786",
  ],
  [
    "SYNTHETIC SUCCESSOR DOCUMENT -- NO LEGAL EFFECT",
    "baf033d7708656202534ee6293a88afd73fa2ae0cfbe3709ecf67460a5fb3145",
  ],
]) {
  assert(
    createHash("sha256").update(documentSnapshot, "utf8").digest("hex") === expectedSha256,
    `synthetic agreement document has the reviewed SHA-256 vector: ${documentSnapshot}`,
  );
  assert(database.proof.includes(`'${expectedSha256}'`), `database proof embeds the reviewed document digest: ${documentSnapshot}`);
}
assert(
  !/partner_onboarding_private\.sha256_text\(\s*'SYNTHETIC(?: SUCCESSOR)? DOCUMENT -- NO LEGAL EFFECT'/i.test(database.proof),
  "role-scoped agreement proof never calls a private hash helper from an authenticated expression",
);

for (const [layerName, sql] of Object.entries({
  baseline: database.baseline,
  foundation: database.foundation,
  transitions: database.transitions,
  release: database.release,
  proof: database.proof,
  rollback: database.rollback,
})) {
  assertExternallyGuardedTransaction(sql, layerName);
}

assert(envExample.includes("VITE_ENABLE_PARTNER_AGREEMENT_ACCEPTANCE=false"), "agreement runtime defaults off");
assert(envExample.includes("VITE_ENABLE_PARTNER_ONBOARDING_CAPABILITIES=false"), "capability projection defaults off");
assert(envExample.includes("VITE_ENABLE_PROTECTED_PARTNER_APPLICATION=false"), "protected application defaults off");
assert(envExample.includes("VITE_ENABLE_PROTECTED_PARTNER_CLAIM=false"), "protected invitation claim defaults off");
assert(envExample.includes("VITE_ENABLE_HEHA_SWIPE_PWA=false"), "PWA runtime defaults off");
assert(agreementFlow.includes("serverAgreement?.document_snapshot"), "UI renders the server document when signing");
assert(agreementRepository.includes('get_partner_agreement_for_acceptance_v1'), "UI loads a server-selected category agreement");
assert(agreementRepository.includes('record_category_partner_agreement_acceptance_v1'), "UI targets the category-bound successor RPC");
assert(!unsafeAgreementRpcPattern.test(agreementFlow), "agreement UI does not call the unsafe donor RPC");
assert(!unsafeAgreementRpcPattern.test(agreementRepository), "repository does not call the unsafe donor RPC");
assert(!agreementRepository.includes("throw error"), "agreement failures never expose raw RPC errors");
assert(agreementRepository.includes("GENERIC_AGREEMENT_ERROR"), "agreement failures use one privacy-preserving message");
assert(agreementVerification.includes("canonicalJson(verified.assertions_snapshot) === canonicalJson(assertions)"), "receipt assertions exact-match the request");
assert(agreementVerification.includes("verified.assertions_sha256 === expectedAssertionsSha256"), "receipt assertions hash matches the submitted canonical assertions");
assert(agreementVerification.includes("computed !== agreement.document_sha256"), "exact displayed agreement digest is recomputed");
assert(agreementVerification.includes('verified.receipt_status === "verified"'), "receipt status must be server verified");
assert(agreementFlow.includes("sessionStorage.setItem(storageKey, stableRequestKey)"), "agreement retries reuse a stable session request key");
assert(agreementFlow.includes("Acceptance never auto-publishes"), "signing does not imply publication");
assert(onboardingRepository.includes("get_partner_onboarding_capabilities_v1"), "checklist uses one owner-safe capability projection");
assert(!onboardingRepository.includes("throw error"), "capability failures never expose raw RPC errors");
assert(onboardingRepository.includes("GENERIC_CAPABILITY_ERROR"), "capability failures use one privacy-preserving message");
assert(onboardingRepository.includes("normalizePartnerOnboardingCapabilities"), "capability RPC result crosses the strict normalizer");
assert(onboardingRepository.includes("list_my_partner_onboarding_assignments_v1"), "operator/signer discovery uses the BOLA-safe assignment RPC");
assert(onboardingRepository.includes("normalizePartnerOnboardingAssignments"), "assignment RPC result crosses the strict normalizer");
assert(onboardingRepository.includes("GENERIC_ASSIGNMENT_ERROR"), "assignment failures use one privacy-preserving message");
assert(onboardingAssignments.includes('new Set(["operator", "authorized_signer"])'), "client assignment roles are allowlisted");
assert(onboardingAssignments.includes("authorized_actor_id"), "client assignments bind the authenticated actor");
assert(onboardingAssignments.includes("assignments.length > 100"), "client assignments enforce the server result ceiling");
assert(onboardingAssignments.includes("Partner assignments are not deterministically ordered."), "client rejects reordered assignment rows");
assert(onboardingAssignmentsTest.includes("actor mismatch"), "assignment tests cover actor-bound BOLA failure");
assert(onboardingAssignmentsTest.includes("unauthorized role"), "assignment tests cover role escalation failure");
assert(onboardingAssignmentsTest.includes("duplicate"), "assignment tests cover duplicate and conflicting rows");
assert(packageJson.scripts?.test?.includes("src/lib/partnerOnboardingAssignments.test.js"), "Node tests include assignment BOLA regressions");
assert(applicationRepository.includes("create_or_resume_partner_application_v1"), "partner application uses an idempotent server RPC");
assert(applicationRepository.includes("revise_partner_profile_v1"), "partner correction uses the unified protected server RPC");
assert(!applicationRepository.includes("revise_partner_application_v1"), "browser code cannot call the source-specific application mutator");
assert(!applicationRepository.includes("throw error"), "application failures never expose raw RPC errors");
assert(applicationRepository.includes("GENERIC_APPLICATION_ERROR"), "application failures use one privacy-preserving message");
assert(applicationRepository.includes("preparePartnerApplication"), "application transport is canonicalized before the RPC");
assert(applicationRepository.includes("validatePartnerApplicationReceipt"), "application RPC result crosses the receipt validator");
assert(applicationRepository.includes("validatePartnerProfileCorrectionReceipt"), "profile correction crosses the unified receipt validator");
assert(/sha256Utf8Hex\s*\(\s*canonicalJson\s*\(/.test(applicationReceipt), "application request digest uses canonical SHA-256");
assert(applicationReceipt.includes("application_receipt_id"), "application response requires an immutable receipt ID");
assert(applicationReceipt.includes("application_sha256"), "application response requires the stored payload digest");
assert(applicationReceipt.includes("expectedApplicationSha256"), "application receipt binds the exact submitted digest");
assert(applicationReceipt.includes('receipt_status !== "verified"'), "application response requires verified receipt status");
assert(applicationReceipt.includes("owner_id !== actorId"), "application receipt binds the authenticated owner");
assert(applicationReceipt.includes("request_key !== requestKey"), "application receipt binds the idempotency key");
assert(applicationReceipt.includes("PROFILE_CORRECTION_RECEIPT_KEYS"), "profile correction rejects unknown receipt fields");
assert(applicationReceipt.includes('new Set(["application", "claim"])'), "profile correction source is exactly allowlisted");
assert(applicationReceipt.includes("expectedSubmittedSha256"), "profile correction receipt binds the exact submitted digest");
assert(
  applicationReceipt.includes('value.correction_source === "application"')
    && applicationReceipt.includes("value.submitted_sha256 === value.previous_sha256"),
  "application correction receipt rejects a no-op application digest",
);
assert(
  applicationReceipt.includes('value.correction_source === "claim"')
    && applicationReceipt.includes("value.previous_sha256 === value.resulting_sha256"),
  "claimed correction receipt rejects a no-op stored-profile digest",
);
for (const profileReceiptField of [
  "correction_source",
  "source_receipt_id",
  "correction_receipt_id",
  "submitted_sha256",
  "previous_sha256",
  "resulting_sha256",
  "receipt_status",
]) {
  assert(applicationReceipt.includes(`"${profileReceiptField}"`), `profile correction validator requires ${profileReceiptField}`);
  assert(applicationReceiptTest.includes(profileReceiptField), `profile correction tests cover ${profileReceiptField}`);
}
assert(applicationReceiptTest.includes("preparePartnerApplication"), "application receipt tests cover canonical request preparation");
assert(applicationReceiptTest.includes("validatePartnerApplicationReceipt"), "application receipt tests exercise the validator");
assert(applicationReceiptTest.includes("validatePartnerProfileCorrectionReceipt"), "profile correction tests exercise the unified validator");
assert(applicationReceiptTest.includes("previous_sha256: prepared.applicationSha256"), "profile correction tests reject application no-op receipts");
assert(applicationReceiptTest.includes("resulting_sha256: correction.previous_sha256"), "profile correction tests reject claimed no-op receipts");
for (const receiptField of ["application_receipt_id", "application_sha256", "receipt_status", "owner_id", "request_key"]) {
  assert(applicationReceiptTest.includes(receiptField), `application receipt tests reject an invalid ${receiptField}`);
}
assert(packageJson.scripts?.test?.includes("src/lib/partnerApplicationReceipt.test.js"), "Node tests include application receipt regressions");
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
assert(partnerProfileEditor.includes('const PROTECTED_APPLICATION_STATUSES = ["draft", "submitted", "pending", "missing_info"]'), "all private application statuses use protected corrections");
assert(partnerProfileEditor.includes("const PROTECTED_APPLICATION_CATEGORIES = CATEGORIES.slice(0, 5)"), "protected edits expose only the five commercial relationship types");
assert(
  partnerProfileEditor.includes("if (protectedCorrection)")
    && partnerProfileEditor.includes("await revisePartnerProfile"),
  "private pending and claimed edits route through the unified correction RPC",
);
assert(!partnerTableAccessPattern.test(partnerProfileEditor), "profile editor never writes the raw partners table");
assert(!/\.message\b/.test(partnerProfileEditor), "profile editor never renders a backend error message");
assert(partnerProfileCorrection.includes("heha-partner-onboarding-v1"), "claimed-profile helper requires the versioned server capability projection");
assert(partnerProfileCorrection.includes("authorized_actor_id === actorId"), "claimed-profile helper binds the authenticated actor");
assert(partnerProfileCorrection.includes('capabilities.claim.status === "verified"'), "claimed-profile helper requires a verified current claim");
for (const immutableProfileField of ["name", "category", "categories", "business_type", "location", "neighborhood"]) {
  assert(partnerProfileCorrectionTest.includes(immutableProfileField), `claimed-profile client test preserves ${immutableProfileField}`);
}
assert(partnerProfileCorrectionTest.includes("preserves raw locked identity"), "claimed-profile client proof preserves raw legal identity fields");
assert(packageJson.scripts?.test?.includes("src/lib/partnerProfileCorrection.test.js"), "Node tests include claimed-profile correction regressions");
assert(reviewContract.includes("only the `operator_only` role"), "onboarding contract keeps operational claims operator-only");
assert(
  reviewContract.includes("append-only business-key history")
    && reviewContract.includes("every prior identity key remains reserved")
    && reviewContract.includes("revise_partner_profile_v1"),
  "onboarding contract documents the unified receipt-bound identity correction path",
);
assert(!claimRepository.includes("throw error"), "claim failures never expose raw RPC errors");
assert(claimRepository.includes("GENERIC_CLAIM_ERROR"), "claim failures use one privacy-preserving message");
assert(!directPartnerInsertPattern.test(partnerWizard), "wizard has no browser SELECT-then-INSERT path");
assert(!checklist.includes("listing.contract_status"), "checklist does not infer agreement readiness from legacy flat fields");
assert(!checklist.includes("listing.status"), "checklist does not infer public visibility from legacy status");
assert(checklist.includes("derivePartnerOnboardingState"), "checklist derives readiness only from normalized receipts");
for (const receiptField of ["release_receipt_id", "swipe_activation_receipt_id", "local_activation_receipt_id"]) {
  assert(onboardingCapabilities.includes(receiptField), `capability normalizer requires ${receiptField}`);
  assert(onboardingCapabilitiesTest.includes(receiptField), `capability tests cover ${receiptField}`);
}
assert(onboardingCapabilities.includes("Contradictory Swipe publication receipt."), "Swipe visibility cannot contradict its receipts");
assert(onboardingCapabilities.includes("Contradictory Local activation receipt."), "Local orderability cannot contradict its receipts");
assert(onboardingCapabilities.includes("Activation receipt is missing its release receipt."), "surface activation cannot exist without release");
assert(onboardingCapabilities.includes("Release receipt is missing a current prerequisite."), "release receipt requires every current prerequisite");
assert(onboardingCapabilities.includes("hasSpecificHehaLocalDestination"), "Local readiness requires a specific fail-closed route");
assert(onboardingCapabilitiesTest.includes("normalizePartnerOnboardingCapabilities"), "capability tests exercise normalization");
assert(onboardingCapabilitiesTest.includes("derivePartnerOnboardingState"), "capability tests exercise derived readiness");
assert(packageJson.scripts?.test?.includes("src/lib/partnerOnboardingCapabilities.test.js"), "Node tests include capability receipt regressions");

for (const key of ["restaurant", "vendor", "market", "catering", "solo_chef", "driver", "som"]) {
  assert(agreementSource.includes(`${key}: agreement({`), `category draft ${key}`);
}
assert((agreementSource.match(legalReviewAgreementStatusPattern) || []).length === 1, "all drafts inherit legal-review status");
assert(!approvedAgreementStatusPattern.test(agreementSource), "no agreement is accidentally approved in source");

for (const step of [
  "Verify the business relationship",
  "Complete profile, menu, pricing & capacity",
  "Review and sign the correct agreement",
  "Add logo and business photos",
  "Add HEHA Swipe and Local to the home screen",
  "Run an authenticated test order",
  "Activate Swipe publication and Local ordering",
]) {
  assert(checklist.includes(step), `checklist step ${step}`);
}

for (const generic of ["/restaurants", "/vendors", "/market", "/chef", "/group-orders"]) {
  assert(routing.includes(`"${generic}"`), `generic Local route fail-close ${generic}`);
}
assert(!routing.includes("LOCAL_PROFILE_PATH_BY_SWIPE_PARTNER_ID"), "legacy Swipe-to-Local ID map stays removed");
assert(!routing.includes("item?.url") && !routing.includes("item.url"), "arbitrary legacy item URLs never become order routes");
assert(routingTest.includes("legacy IDs and arbitrary item URLs never bypass"), "Local routing regression covers both legacy bypasses");
assert(clientOrderRoutingSourceTest.includes("SwipeCard order CTA has no arbitrary item URL fallback"), "SwipeCard source regression blocks legacy item URLs");
assert(packageJson.scripts?.test?.includes("src/lib/clientOrderRoutingSource.test.js"), "Node tests include SwipeCard order-routing regression");

assert(main.includes('VITE_ENABLE_HEHA_SWIPE_PWA === "true"'), "service-worker registration has a release gate");
assert(main.includes('addLink("manifest", "/manifest.json")'), "PWA flag controls manifest discovery");
assert(!hasManifestLink(indexHtml), "locked HTML does not expose install metadata unconditionally");
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

assert(reviewWorkflow.includes('ref: ${{ github.event.pull_request.head.sha }}'), "workflow checks out the literal pull-request head");
assert(reviewWorkflow.includes("PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}"), "workflow pins the pull-request base SHA");
assert(reviewWorkflow.includes("PR_HEAD_SHA: ${{ github.event.pull_request.head.sha }}"), "workflow pins the pull-request head SHA");
assert((reviewWorkflow.match(/persist-credentials: false/g) || []).length === 2, "workflow checkouts cannot push");
assert(reviewWorkflow.includes("npm ci --ignore-scripts"), "dependency installation cannot execute package lifecycle scripts");
assert(
  reviewWorkflow.indexOf("node scripts/verify-partner-onboarding-review.mjs") < reviewWorkflow.indexOf("npm ci --ignore-scripts"),
  "source verifier runs before package-controlled code",
);
assert(reviewWorkflow.includes("git diff --exit-code"), "workflow rejects tracked-file mutation after tests and build");
assert((reviewWorkflow.match(/node scripts\/verify-partner-onboarding-review\.mjs/g) || []).length === 2, "workflow reverifies source after tests and build");
const exactNodeTestFiles = [
  "src/contracts/partnerAgreements.test.js",
  "src/components/PartnerProfileEditor.source.test.js",
  "src/lib/clientOrderRoutingSource.test.js",
  "src/lib/hehaLocalRouting.test.js",
  "src/lib/partnerAgreementAssertions.test.js",
  "src/lib/partnerAgreementVerification.test.js",
  "src/lib/partnerApplicationReceipt.test.js",
  "src/lib/partnerInvite.test.js",
  "src/lib/partnerOnboardingAssignments.test.js",
  "src/lib/partnerOnboardingCapabilities.test.js",
  "src/lib/partnerProfileCorrection.test.js",
];
assert(reviewWorkflow.includes("node --test"), "workflow invokes the Node test runner directly");
for (const testFile of exactNodeTestFiles) {
  assert((reviewWorkflow.match(new RegExp(testFile.replaceAll(".", "\\."), "g")) || []).length === 1, `workflow directly executes ${testFile}`);
}
assert(packageJson.scripts?.test?.includes("src/components/PartnerProfileEditor.source.test.js"), "package tests include protected profile-editor source regressions");
assert(!reviewWorkflow.includes("run: npm test"), "workflow cannot delegate proof to a PR-controlled test script");
assert(reviewWorkflow.includes("run: ./node_modules/.bin/vite build"), "workflow invokes the pinned Vite binary directly");
assert(!reviewWorkflow.includes("run: npm run build"), "workflow cannot delegate build proof to a PR-controlled script");
assert(reviewWorkflow.includes('postgres: ["15", "17"]'), "workflow proves PostgreSQL 15 and 17");
assert(reviewWorkflow.includes("PGOPTIONS: -c heha.review_only=on"), "every database connection carries the external disposable-database guard");
const databaseJobHeader = reviewWorkflow.slice(
  reviewWorkflow.indexOf("  database-review:"),
  reviewWorkflow.indexOf("    steps:", reviewWorkflow.indexOf("  database-review:")),
);
const containerBindingStep = reviewWorkflow.slice(
  reviewWorkflow.indexOf("      - name: Bind exact disposable database service container"),
  reviewWorkflow.indexOf("\n      - name:", reviewWorkflow.indexOf("      - name: Bind exact disposable database service container") + 1),
);
assert(!databaseJobHeader.includes("job.services"), "job-level environment never uses the unavailable job.services context");
assert(
  containerBindingStep.includes("SERVICE_CONTAINER_ID: ${{ job.services.postgres.id }}")
    && containerBindingStep.includes("POSTGRES_CONTAINER=%s")
    && containerBindingStep.includes("$GITHUB_ENV"),
  "a step-level context binds the exact disposable service container for later steps",
);
assert(reviewWorkflow.includes("postgresql://postgres:postgres@127.0.0.1:5432/partner_onboarding_review"), "database clients use loopback inside the disposable container");
assert(!/^\s+ports\s*:/m.test(reviewWorkflow), "disposable PostgreSQL is not published to the runner network");
assert(reviewWorkflow.includes("docker cp") && reviewWorkflow.includes("docker exec --workdir /review"), "exact-head proof executes inside the disposable PostgreSQL network namespace");
assert(reviewWorkflow.includes("supabase/migrations/*|supabase/functions/*"), "workflow rejects executable Supabase scope");
assert((reviewWorkflow.match(/git diff --no-renames --name-only -z/g) || []).length === 2, "both jobs inventory raw NUL-delimited source and destination paths");
assert((reviewWorkflow.match(/mapfile -d '' -t changed_files/g) || []).length === 2, "both jobs preserve literal changed paths in arrays");
assert(!/git diff[^\n]*--name-only[^\n]*\|/.test(reviewWorkflow), "workflow never parses quoted newline-delimited Git paths");
assert(reviewWorkflow.includes("Environment file entered the review-only lane"), "workflow rejects non-example environment files");
assert(reviewWorkflow.includes("Provider or infrastructure configuration entered the review-only lane"), "workflow rejects provider configuration");
assert(/^on:\s*\n\s+pull_request:\s*$/m.test(reviewWorkflow) && !/^\s+paths:/m.test(reviewWorkflow), "scope gate runs on every pull request without path-filter bypasses");
assert(reviewWorkflow.includes("vercel\\.json") && reviewWorkflow.includes("(\\.vercel|\\.supabase|infra|terraform)/"), "workflow rejects nested provider configuration");
assert(
  reviewWorkflow.includes('file_lower="${file,,}"')
    && reviewWorkflow.includes('case "$file_lower"')
    && reviewWorkflow.includes(".env*|*/.env*"),
  "workflow rejects every real environment-file spelling case-insensitively",
);
assert(reviewWorkflow.includes("Another GitHub workflow entered the partner review lane"), "workflow rejects parallel workflow changes");
assert(
  reviewWorkflow.includes("PR controls both files")
    && reviewWorkflow.includes("trusted-base branch protection")
    && reviewWorkflow.includes("CODEOWNERS"),
  "workflow documents that PR-controlled evidence is not a trusted enforcement boundary",
);
assert(reviewWorkflow.includes("security_invoker=true"), "workflow rechecks restored legacy view execution semantics");
assert(reviewWorkflow.includes("restored unsafe ACL/options"), "workflow rechecks restored legacy view ACLs");
assert(reviewWorkflow.includes("relation.relrowsecurity") && reviewWorkflow.includes("relation.relforcerowsecurity"), "workflow rechecks restored raw-table RLS");
assert(reviewWorkflow.includes("pg_get_expr(policy.polqual"), "workflow rechecks restored legacy policy semantics");
assert(!reviewWorkflow.includes('"${#files[@]}" -eq'), "workflow does not depend on a brittle exact changed-file count");
assert(
  reviewWorkflow.includes("Final exact-file rebuild left the legacy write bypass open")
    && reviewWorkflow.indexOf("Roll back disposable partner-onboarding objects")
      < reviewWorkflow.indexOf("Final exact-file rebuild left the legacy write bypass open"),
  "post-rollback exact-file rebuild re-closes the legacy write bypass",
);
for (const filePath of Object.values(databasePaths)) {
  assert(reviewWorkflow.includes(filePath), `workflow executes or watches ${filePath}`);
}

assert(database.baseline.includes("Synthetic PostgreSQL baseline"), "database proof uses a synthetic baseline");
assert(database.baseline.includes("current_setting('heha.review_only', true)"), "synthetic baseline refuses an unguarded database");
assert(database.baseline.includes("HEHA_REVIEW_ONLY_GUARD"), "synthetic baseline has a stable review-only denial");
assert(database.baseline.includes("example.invalid"), "synthetic baseline uses non-routable identities");
assert(database.baseline.includes("create table if not exists auth.users"), "synthetic Auth boundary");
assert(database.baseline.includes("create or replace function auth.uid()"), "synthetic auth.uid boundary");
assert(database.baseline.includes("create extension if not exists pgcrypto"), "synthetic SHA-256 dependency");
assert(!/create\s+extension[\s\S]{0,120}\bversion\b/i.test(database.baseline), "extension version is not pinned");
assert(/grant\s+insert,\s*update\s+on\s+table\s+public\.partners\s+to\s+authenticated/i.test(database.baseline), "baseline models the legacy authenticated-owner write bypass");
for (const legacyWritePolicy of [
  "Legacy partner owner inserts pending profile",
  "Legacy partner owner updates pending profile",
]) {
  assert(database.baseline.includes(`create policy "${legacyWritePolicy}"`), `baseline models legacy write policy ${legacyWritePolicy}`);
  assert(database.foundation.includes(`drop policy if exists "${legacyWritePolicy}"`), `foundation removes legacy write policy ${legacyWritePolicy}`);
}
assert(/revoke\s+insert,\s*update\s+on\s+table\s+public\.partners\s+from\s+authenticated/i.test(database.foundation), "foundation revokes direct authenticated partner writes");
assert(reviewWorkflow.includes("legacy authenticated-owner write bypass"), "database workflow proves the synthetic legacy write bypass exists");
assert(reviewWorkflow.includes("foundation closed the legacy partner write bypass"), "database workflow proves foundation direct-write closure");
for (const viewName of ["public_partner_directory", "public_swipe_partners", "public_local_partners"]) {
  assert(database.baseline.includes(`create or replace view public.${viewName}`), `synthetic legacy view ${viewName}`);
}
assert((database.baseline.match(/security_invoker\s*=\s*true/gi) || []).length >= 3, "synthetic legacy views are security invokers");

assert(database.foundation.includes("create schema if not exists partner_onboarding_private"), "private partner-onboarding schema");
assert(database.foundation.includes("current_setting('heha.review_only', true)"), "foundation refuses an unguarded database before DDL");
assert(database.foundation.includes("HEHA_REVIEW_ONLY_GUARD"), "foundation has a stable review-only denial");
for (const [layerName, layerSql] of [["transitions", database.transitions], ["release", database.release]]) {
  assert(layerSql.includes("current_setting('heha.review_only', true)"), `${layerName} refuses an unguarded database before DDL`);
  assert(layerSql.includes("HEHA_REVIEW_ONLY_GUARD"), `${layerName} has a stable review-only denial`);
}
assert(database.foundation.includes("partner_onboarding_private.canonical_json"), "recursive canonical JSON contract");
assert(database.foundation.includes("partner_onboarding_private.sha256_text"), "server SHA-256 contract");
for (const runtimeSwitch of [
  "claim_enabled",
  "application_enabled",
  "acceptance_enabled",
  "release_enabled",
  "swipe_publication_enabled",
  "local_ordering_enabled",
]) {
  assert(
    new RegExp(`${runtimeSwitch}\\s+boolean\\s+not\\s+null\\s+default\\s+false`, "i").test(database.foundation),
    `server runtime defaults off: ${runtimeSwitch}`,
  );
}
for (const receiptTable of [
  "partner_claims",
  "partner_claim_profile_corrections",
  "partner_profile_correction_requests",
  "partner_agreement_acceptances",
  "partner_evidence_receipts",
  "partner_release_receipts",
  "partner_release_revocations",
  "partner_surface_activation_receipts",
  "partner_surface_activation_revocations",
]) {
  assert(database.foundation.includes(`partner_onboarding_private.${receiptTable}`), `private receipt boundary ${receiptTable}`);
}
assert(database.foundation.includes("enable row level security"), "private tables enable RLS");
assert(database.foundation.includes("force row level security"), "private tables force RLS");
assert(database.foundation.includes("revoke all on all tables in schema partner_onboarding_private"), "private table ACLs fail closed");
assert(database.foundation.includes("reject_append_only_mutation"), "receipt and revocation records are append-only");
assert(database.foundation.includes("partner_onboarding_private.partner_reclassification_resets"), "foundation stores append-only reclassification reset receipts");
assert(database.foundation.includes("partner_onboarding_private.partner_claim_profile_corrections"), "foundation stores immutable claim-bound profile correction receipts");
assert(database.foundation.includes("partner_onboarding_private.partner_profile_correction_requests"), "foundation stores the immutable unified correction request ledger");
assert(database.proof.includes("partner_claim_profile_corrections"), "runtime proof inventories claim-bound profile correction receipts under forced RLS");
assert(database.rollback.includes("partner_claim_profile_corrections"), "rollback inventories claim-bound profile correction receipts");
assert(database.proof.includes("partner_profile_correction_requests"), "runtime proof inventories unified correction requests under forced RLS");
assert(database.rollback.includes("partner_profile_correction_requests"), "rollback inventories unified correction requests");
assert(/reclassification_pending\s+boolean\s+not\s+null\s+default\s+false/i.test(database.foundation), "partner reclassification defaults fail closed");
assert(database.proof.includes("partner_reclassification_resets"), "runtime proof inventories reclassification reset receipts under forced RLS");
assert(database.rollback.includes("partner_reclassification_resets"), "rollback inventories reclassification reset receipts");
assert(!/\b(?:raw_)?invite_token\s+(?:text|bytea|varchar)/i.test(database.foundation), "raw invitation token is never stored");
const issueInvitationSection = functionSection(
  database.transitions,
  "partner_onboarding_private.issue_partner_invitation_v1",
);
const claimInvitationSection = functionSection(
  database.transitions,
  "public.claim_partner_invitation_v1",
);
for (const [section, parameter, label] of [
  [issueInvitationSection, "p_raw_token", "invitation issuance"],
  [claimInvitationSection, "p_invite_token", "invitation claim"],
]) {
  assert(
    section.includes(`pg_catalog.octet_length(${parameter}) not between 32 and 512`),
    `${label} enforces the exact token byte-length boundary outside PostgreSQL regex bounds`,
  );
  assert(
    section.includes(`${parameter} !~ '^[A-Za-z0-9_-]+$'`),
    `${label} enforces the opaque ASCII token allowlist`,
  );
  assert(!section.includes("{32,512}"), `${label} avoids unsupported PostgreSQL repetition bounds`);
}
for (const boundaryLabel of [
  "31-byte invitation token denied",
  "513-byte invitation token denied",
  "non-ASCII-allowlist invitation token denied",
  "31-byte claim token denied",
  "513-byte claim token denied",
  "non-ASCII-allowlist claim token denied",
]) {
  assert(database.proof.includes(boundaryLabel), `runtime proof covers ${boundaryLabel}`);
}
assert(/unique\s*\(\s*surface\s*,\s*target_receipt_id\s*\)/i.test(database.foundation), "surface receipt replay has a stable uniqueness boundary");
assert(!/unique\s*\(\s*surface\s*,\s*target_partner_id\s*\)/i.test(database.foundation), "historical target IDs can be reused by a successor release");

const clientRpcNames = [
  "claim_partner_invitation_v1",
  "create_or_resume_partner_application_v1",
  "revise_partner_profile_v1",
  "get_partner_agreement_for_acceptance_v1",
  "record_category_partner_agreement_acceptance_v1",
  "get_partner_onboarding_capabilities_v1",
  "list_my_partner_onboarding_assignments_v1",
];

const expectedPublicReviewFunctions = [
  "public.claim_partner_invitation_v1(text,uuid)",
  "public.create_or_resume_partner_application_v1(uuid,jsonb)",
  "public.get_partner_agreement_for_acceptance_v1(uuid)",
  "public.get_partner_onboarding_capabilities_v1(uuid)",
  "public.get_partner_orderability_receipt_v1(uuid)",
  "public.list_my_partner_onboarding_assignments_v1()",
  "public.partner_card_is_current_v1(uuid,text,uuid,uuid)",
  "public.partner_has_current_release_v1(uuid,text)",
  "public.record_category_partner_agreement_acceptance_v1(uuid,uuid,text,uuid,jsonb)",
  "public.revise_partner_application_v1(uuid,uuid,jsonb)",
  "public.revise_partner_profile_v1(uuid,uuid,jsonb)",
].sort();
const reviewDatabaseSql = [
  database.baseline,
  database.foundation,
  database.transitions,
  database.release,
  database.proof,
  database.rollback,
].join("\n");
assert(!plainPublicFunctionPattern.test(reviewDatabaseSql), "review SQL uses idempotent OR REPLACE for every public function");
assert(!publicProcedurePattern.test(reviewDatabaseSql), "review SQL declares no public procedure escape hatch");
assert(!quotedPublicRoutinePattern.test(reviewDatabaseSql), "review SQL declares no quoted public routine escape hatch");
const declaredPublicReviewFunctions = declaredPublicFunctionSignatures(reviewDatabaseSql);
assert(
  declaredPublicReviewFunctions.join("\n") === expectedPublicReviewFunctions.join("\n"),
  "review SQL declares exactly the allowlisted public function names and overloads",
);
for (const signature of expectedPublicReviewFunctions) {
  const functionName = signature.slice("public.".length, signature.indexOf("("));
  assert(database.rollback.includes(`public.${functionName}`), `rollback inventories public function ${functionName}`);
  assert(reviewWorkflow.includes(`'${functionName}'`), `clean teardown rejects public function ${functionName}`);
}
assert(database.proof.includes("PUBLIC_FUNCTION_CATALOG_EXACT"), "runtime proof inventories the exact public function catalog and ACLs");
assert(reviewWorkflow.includes("verify-partner-public-routines.sh"), "workflow compares the exact public routine catalog to the synthetic baseline");
assert(reviewWorkflow.includes("pg_get_functiondef") && reviewWorkflow.includes("prokind"), "workflow snapshots public routine definitions and metadata");
assert(reviewWorkflow.includes("public.revise_partner_profile_v1(uuid,uuid,jsonb)"), "workflow inventories the unified profile correction RPC");
assert(reviewWorkflow.includes("Expected 11 HEHA public functions"), "workflow rejects an unreviewed public routine overload");
for (const oidAllowlistPrimitive of [
  "v_oid = any(v_public_read_oids)",
  "v_oid = any(v_client_oids)",
  "v_oid = any(v_stable_oids)",
]) {
  assert(database.proof.includes(oidAllowlistPrimitive), `runtime proof classifies public functions by OID via ${oidAllowlistPrimitive}`);
}
assert(!database.proof.includes("v_signature = any(v_public_read_input)"), "runtime proof never compares rendered regprocedure text to a qualified ACL allowlist");
assert(!database.proof.includes("v_signature = any(v_client_input)"), "runtime proof never compares rendered regprocedure text to a qualified client allowlist");
assert(database.proof.includes("v_oid = any(v_authenticated_oids)"), "private function ACL proof classifies authenticated functions by OID");
assert(!database.proof.includes("v_signature = any(v_authenticated)"), "private ACL proof never compares rendered regprocedure text to an allowlist");
for (const exactAclPrimitive of ["aclexplode", "acl.grantor", "acl.is_grantable", "pg_roles"]) {
  assert(reviewWorkflow.includes(exactAclPrimitive), `workflow rejects unexpected public-function ACL metadata via ${exactAclPrimitive}`);
  assert(database.proof.includes(exactAclPrimitive), `runtime proof rejects unexpected public-function ACL metadata via ${exactAclPrimitive}`);
}
for (const exactRoutineMetadataPrimitive of [
  "pg_get_function_result",
  "pg_language",
  "proisstrict",
  "provolatile",
  "proparallel",
  "proretset",
  "procost",
  "prorows",
  "prosupport",
]) {
  assert(reviewWorkflow.includes(exactRoutineMetadataPrimitive), `workflow validates public-function metadata via ${exactRoutineMetadataPrimitive}`);
  assert(database.proof.includes(exactRoutineMetadataPrimitive), `runtime proof validates public-function metadata via ${exactRoutineMetadataPrimitive}`);
}
assert(
  reviewWorkflow.includes("partner-public-routines-reviewed.tsv")
    && reviewWorkflow.includes("cmp \"$reviewed_snapshot\" \"$reviewed_delta\"")
    && reviewWorkflow.includes("--snapshot-reviewed"),
  "workflow byte-compares full public routine metadata and definitions after every rebuild",
);
for (const catalogPrimitive of [
  "prokind",
  "pg_get_function_identity_arguments",
  "prosecdef",
  "proconfig",
  "has_function_privilege",
  "supabase_auth_admin",
]) {
  assert(database.proof.includes(catalogPrimitive), `public function catalog proof verifies ${catalogPrimitive}`);
}

for (const rpcName of clientRpcNames) {
  const section = functionSection(database.transitions, `public.${rpcName}`);
  assert(/security\s+definer/i.test(section), `${rpcName} uses a protected definer boundary`);
  assert(/set\s+search_path\s*=\s*''/i.test(section), `${rpcName} pins an empty search path`);
  assert(section.includes("HEHA_PARTNER_REQUEST_DENIED"), `${rpcName} exposes only the generic denial`);
  assert(section.includes("P0001"), `${rpcName} locks the generic denial SQLSTATE`);
  assert(!/sqlerrm/i.test(section), `${rpcName} never returns raw database errors`);
  assert(
    new RegExp(`revoke\\s+all\\s+on\\s+function\\s+public\\.${rpcName}\\s*\\(`, "i").test(database.transitions),
    `${rpcName} revokes default function execution`,
  );
  assert(
    new RegExp(`grant\\s+execute\\s+on\\s+function\\s+public\\.${rpcName}\\s*\\([\\s\\S]*?\\)\\s+to\\s+authenticated`, "i").test(database.transitions),
    `${rpcName} grants only the authenticated client boundary`,
  );
  assert(
    !new RegExp(`grant\\s+execute\\s+on\\s+function\\s+public\\.${rpcName}\\s*\\([\\s\\S]*?\\)\\s+to\\s+(?:public|anon|service_role|supabase_auth_admin)`, "i").test(database.transitions),
    `${rpcName} is not client-callable outside authenticated`,
  );
  assert(database.proof.includes(rpcName), `runtime proof covers ${rpcName}`);
}

const applicationSection = functionSection(
  database.transitions,
  "public.create_or_resume_partner_application_v1",
);
for (const receiptField of ["application_receipt_id", "application_sha256", "receipt_status"]) {
  assert(applicationSection.includes(`'${receiptField}'`), `application RPC returns ${receiptField} on every verified replay`);
}
assert(applicationSection.includes("'verified'"), "application RPC marks its immutable receipt verified");

const applicationCorrectionSection = functionSection(
  database.transitions,
  "public.revise_partner_application_v1",
);
for (const receiptField of [
  "application_receipt_id",
  "correction_receipt_id",
  "application_sha256",
  "previous_application_sha256",
  "receipt_status",
]) {
  assert(applicationCorrectionSection.includes(`'${receiptField}'`), `application-correction RPC returns ${receiptField}`);
}
assert(applicationCorrectionSection.includes("for update"), "application correction locks the exact pending partner and application");
assert(applicationCorrectionSection.includes("application_enabled"), "application correction remains behind the server kill switch");
assert(
  /revoke\s+all\s+on\s+function\s+public\.revise_partner_application_v1\s*\(\s*uuid\s*,\s*uuid\s*,\s*jsonb\s*\)\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role\s*,\s*supabase_auth_admin/i.test(database.transitions),
  "the source-specific application mutator revokes every platform role",
);
assert(
  !/grant\s+execute\s+on\s+function\s+public\.revise_partner_application_v1\s*\(/i.test(database.transitions),
  "the source-specific application mutator is never client granted",
);

const claimedProfileCorrectionSection = functionSection(
  database.transitions,
  "partner_onboarding_private.revise_claimed_partner_profile_v1",
);
const claimedProfileHashSection = functionSection(
  database.transitions,
  "partner_onboarding_private.claim_editable_profile_sha256_v1",
);
assert(claimedProfileHashSection.includes("partner_onboarding_private.canonical_json"), "claimed-profile resulting hash is canonical");
for (const boundProfileField of [
  "partner_id",
  "name",
  "category",
  "categories",
  "business_type",
  "location",
  "neighborhood",
  "contact",
  "instagram",
  "website",
  "bio",
  "complete_pct",
  "hours",
  "offerings",
  "tagline",
  "items",
  "phone",
  "photo_emoji",
  "color",
  "delivery_days",
]) {
  assert(claimedProfileHashSection.includes(`'${boundProfileField}'`), `claimed-profile resulting hash binds ${boundProfileField}`);
}
assert(database.rollback.includes("partner_onboarding_private.claim_editable_profile_sha256_v1"), "rollback removes the claimed-profile hash helper");
assert(/security\s+definer/i.test(claimedProfileCorrectionSection), "claimed-profile correction uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(claimedProfileCorrectionSection), "claimed-profile correction pins an empty search path");
assert(claimedProfileCorrectionSection.includes("current_claim_receipt_id_v1"), "claimed-profile correction binds the current claim receipt");
assert(claimedProfileCorrectionSection.includes("partner_business_identity_is_current_v1"), "claimed-profile correction requires the current business identity");
assert(claimedProfileCorrectionSection.includes("partner_claim_profile_corrections"), "claimed-profile correction records an immutable receipt");
assert(/set\s+release_epoch\s*=\s*release_epoch\s*\+\s*1/i.test(claimedProfileCorrectionSection), "claimed-profile correction invalidates the current release epoch");
assert(
  !/grant\s+execute\s+on\s+function\s+partner_onboarding_private\.revise_claimed_partner_profile_v1\s*\(/i.test(database.transitions),
  "claimed-profile child mutator is never granted to a platform role",
);
const rawPartnerUpdatePattern = /\bupdate\s+(?:"?public"?\s*\.\s*)?"?partners"?(?=\s)/gi;
assert(
  [...`update public.partners set contact = null; update "public"."partners" set "name" = 'blocked';`.matchAll(rawPartnerUpdatePattern)].length === 2,
  "claimed-profile update detector catches multiple and quoted raw-table updates",
);
assert(/\bset\s*\(/i.test("update public.partners set (name, contact) = ('blocked', null)"), "claimed-profile update detector catches row assignment targets");
const claimedPartnerUpdates = [...claimedProfileCorrectionSection.matchAll(rawPartnerUpdatePattern)];
assert(claimedPartnerUpdates.length === 1, "claimed-profile correction has exactly one raw partner update");
const claimedPartnerUpdateStart = claimedPartnerUpdates[0]?.index ?? -1;
const claimedPartnerUpdateEnd = claimedPartnerUpdateStart >= 0
  ? claimedProfileCorrectionSection.indexOf(";", claimedPartnerUpdateStart)
  : -1;
const claimedPartnerUpdate = claimedPartnerUpdateEnd > claimedPartnerUpdateStart
  ? claimedProfileCorrectionSection.slice(claimedPartnerUpdateStart, claimedPartnerUpdateEnd + 1)
  : "";
assert(/^update\s+public\.partners\s+set\b/i.test(claimedPartnerUpdate), "claimed-profile correction uses the reviewed unquoted update boundary");
assert(!/\bset\s*\(/i.test(claimedPartnerUpdate), "claimed-profile correction cannot hide a row-assignment target list");
const claimedPartnerUpdateTargets = [
  ...claimedPartnerUpdate.matchAll(/(?:\bset|,)\s*"?([a-z_][a-z0-9_]*)"?\s*=/gi),
].map((match) => match[1].toLowerCase());
const expectedClaimedPartnerUpdateTargets = [
  "contact",
  "instagram",
  "website",
  "bio",
  "complete_pct",
  "hours",
  "offerings",
  "tagline",
  "items",
  "phone",
  "photo_emoji",
  "color",
  "delivery_days",
  "updated_at",
];
assert(
  claimedPartnerUpdateTargets.join("\n") === expectedClaimedPartnerUpdateTargets.join("\n"),
  "claimed-profile correction updates only the exact reviewed operational columns",
);

const unifiedProfileCorrectionSection = functionSection(
  database.transitions,
  "public.revise_partner_profile_v1",
);
assert(unifiedProfileCorrectionSection.includes("revise_claimed_partner_profile_v1"), "unified correction routes current operators through the claimed-profile child");
assert(unifiedProfileCorrectionSection.includes("revise_partner_application_v1"), "unified correction routes self-applicants through the application child");
assert(unifiedProfileCorrectionSection.includes("partner_profile_correction_requests"), "unified correction records and replays one immutable request ledger row");
assert(unifiedProfileCorrectionSection.includes("request_fingerprint"), "unified correction binds replay to the full request fingerprint");
for (const receiptField of [
  "id",
  "owner_id",
  "request_key",
  "correction_source",
  "source_receipt_id",
  "correction_receipt_id",
  "submitted_sha256",
  "previous_sha256",
  "resulting_sha256",
  "receipt_status",
  "status",
]) {
  assert(unifiedProfileCorrectionSection.includes(`'${receiptField}'`), `unified profile correction returns ${receiptField}`);
}
assert(
  /select\s+'application_revision_first'\s*,\s*public\.revise_partner_profile_v1\s*\(/i.test(database.proof),
  "proof executes an owner-bound application correction through the unified router",
);
assert(
  /select\s+'application_revision_replay'\s*,\s*public\.revise_partner_profile_v1\s*\(/i.test(database.proof),
  "proof executes the exact application-correction replay through the unified router",
);
for (const correctionProofMarker of [
  "application_revision_receipt",
  "application revision conflicting replay denied generically",
  "application revision cross-owner BOLA denied generically",
  "application revision switch off denied generically",
  "APPLICATION_REVISION_STALE_AFTER_INVITE",
]) {
  assert(database.proof.includes(correctionProofMarker), `application-correction proof covers ${correctionProofMarker}`);
}
assert(database.proof.includes("BUSINESS_KEY_A_B_A_RECOVERY"), "application correction proves A-to-B-to-A root recovery");
assert(
  /partner_business_identity_is_current_v1\(\s*v_partner_id\s*,\s*v_alias\s*\)\s+is\s+distinct\s+from\s+false/i.test(database.proof),
  "A-to-B-to-A proof distinguishes the immutable root from a reserved historical alias",
);
assert(
  database.proof.includes("corrected application business alias remains globally reserved"),
  "historical application aliases remain reserved against a different partner",
);
for (const claimedCorrectionProofMarker of [
  "claimed_profile_revision_first",
  "claimed_profile_revision_replay",
  "profile_correction_cross_provenance_replay",
  "claimed_profile_revision_receipt",
  "claimed_profile_revision_conflicting_replay_denied",
  "claimed_profile_revision_cross_tenant_denied",
  "claimed_profile_revision_revoked_claim_denied",
  "claimed_profile_revision_stale_claim_denied",
  "claimed_profile_revision_release_epoch_invalidated",
  "claimed_profile_revision_identity_immutable",
]) {
  assert(database.proof.includes(claimedCorrectionProofMarker), `claimed-profile proof covers ${claimedCorrectionProofMarker}`);
}
for (const nullableProfileField of [
  "name",
  "category",
  "categories",
  "business_type",
  "location",
  "neighborhood",
]) {
  assert(
    new RegExp(`coalesce\\(\\s*pg_catalog\\.to_jsonb\\(partner\\.${nullableProfileField}\\)\\s*,\\s*'null'::jsonb\\)\\s+is\\s+not\\s+distinct\\s+from\\s+v_before\\s*->\\s*'${nullableProfileField}'`, "i").test(database.proof),
    `claimed-profile proof binds SQL NULL ${nullableProfileField} as canonical JSON null`,
  );
}
assert(
  /coalesce\(\s*partner\.hours\s*,\s*'null'::jsonb\)\s+is\s+not\s+distinct\s+from\s+v_before\s*->\s*'hours'/i.test(database.proof),
  "claimed-profile proof binds SQL NULL hours as canonical JSON null",
);
for (const appendOnlyProofLabel of [
  "application profile correction router receipt is append-only",
  "claimed profile correction receipt is immutable",
  "claimed profile router receipt is append-only",
  "unclaimed reclassification reset receipt is append-only",
  "agreement document append-only",
  "acceptance assertions append-only",
]) {
  const escapedLabel = appendOnlyProofLabel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  assert(
    new RegExp(`expect_sqlstate\\(\\s*'${escapedLabel}'\\s*,\\s*'42501'`, "i").test(database.proof),
    `append-only proof locks SQLSTATE 42501 for ${appendOnlyProofLabel}`,
  );
}

const capabilitySection = functionSection(
  database.transitions,
  "public.get_partner_onboarding_capabilities_v1",
);
for (const receiptField of [
  "release_receipt_id",
  "swipe_activation_receipt_id",
  "local_activation_receipt_id",
]) {
  assert(capabilitySection.includes(`'${receiptField}'`), `capability projection returns ${receiptField}`);
}

const issueEvidenceSection = functionSection(
  database.transitions,
  "partner_onboarding_private.issue_partner_evidence_v1",
);
for (const smokeBoolean of ["passed", "order_path_passed"]) {
  assert(
    new RegExp(`evidence_snapshot\\s*->\\s*'${smokeBoolean}'[\\s\\S]*?'true'::jsonb`, "i").test(issueEvidenceSection),
    `evidence issuance requires the release-grade ${smokeBoolean} boolean`,
  );
  assert(
    new RegExp(`v_smoke_test\\.evidence_snapshot\\s*->\\s*'${smokeBoolean}'[\\s\\S]*?'true'::jsonb`, "i").test(capabilitySection),
    `capability readiness requires the release-grade ${smokeBoolean} boolean`,
  );
}
assert(
  /evidence\.evidence_snapshot\s*@>\s*'\{"passed":true,"order_path_passed":true\}'::jsonb/i.test(database.release),
  "release finalization atomically requires both release-grade smoke booleans",
);
for (const smokeReceiptField of [
  "customer_order_receipt_id",
  "partner_acceptance_receipt_id",
  "driver_receipt_id",
  "delivery_receipt_id",
]) {
  assert(issueEvidenceSection.includes(`'${smokeReceiptField}'`), `evidence issuance requires nonblank ${smokeReceiptField}`);
  assert(capabilitySection.includes(`'${smokeReceiptField}'`), `capability readiness requires nonblank ${smokeReceiptField}`);
  assert(database.release.includes(`'${smokeReceiptField}'`), `release finalization requires nonblank ${smokeReceiptField}`);
}
for (const reviewedEvidenceType of ["partner_consent", "heha_review"]) {
  assert(issueEvidenceSection.includes(`'${reviewedEvidenceType}'`), `evidence issuance handles ${reviewedEvidenceType}`);
  assert(
    issueEvidenceSection.includes("evidence_snapshot -> 'approved'")
      && issueEvidenceSection.includes("'true'::jsonb"),
    `${reviewedEvidenceType} issuance requires an exact approved boolean`,
  );
}
assert(
  (database.release.match(/evidence\.evidence_snapshot\s*@>\s*'\{"approved":true\}'::jsonb/gi) || []).length >= 2,
  "release finalization requires the approved boolean for consent and HEHA review",
);
for (const reviewedCapability of ["v_partner_consent", "v_heha_review"]) {
  assert(
    new RegExp(`${reviewedCapability}\\.subject_sha256[\\s\\S]{0,160}partner_preview_sha256\\s*\\(\\s*p_partner_id\\s*\\)`, "i").test(capabilitySection),
    `${reviewedCapability} capability remains bound to the current preview digest`,
  );
}
for (const capabilityFlag of ["v_smoke_test_current", "v_partner_consent_current", "v_heha_review_current"]) {
  assert(new RegExp(`case\\s+when\\s+${capabilityFlag}\\b`, "i").test(capabilitySection), `capability projection fail-closes ${capabilityFlag}`);
}
assert(
  onboardingCapabilities.includes("Release receipt is missing a current prerequisite.")
    && checklist.includes("derivePartnerOnboardingState"),
  "the client checklist cannot green an unreleasable server capability snapshot",
);

const assignmentSection = functionSection(
  database.transitions,
  "public.list_my_partner_onboarding_assignments_v1",
);
assert(assignmentSection.includes("heha-partner-assignments-v1"), "assignment projection is versioned");
assert(assignmentSection.includes("authorized_actor_id"), "assignment projection binds the authenticated actor");
assert(assignmentSection.includes("authorized_signer"), "assignment projection supports an independently authorized signer");
assert(database.proof.includes("other_tenant_assignments"), "assignment proof includes a different partner tenant");
assert(
  database.proof.indexOf("select 'other_tenant_assignments'")
    > database.proof.indexOf("select 'legacy_live_profile_claim'"),
  "different-tenant assignment snapshot is captured after its claim becomes current",
);
assert(
  /v_other_tenant\s*#>>\s*'\{assignments,0,partner_id\}'\s+is\s+distinct\s+from\s*'10000000-0000-4000-8000-0000000000d4'/i.test(database.proof),
  "different-tenant projection is exact-bound to only its own partner",
);
assert(database.proof.includes("unassigned_actor_assignments"), "assignment proof includes a verified actor with no partner role");
assert(
  /v_unassigned\s*->>\s*'authorized_actor_id'\s+is\s+distinct\s+from\s*'00000000-0000-4000-8000-0000000000e5'/i.test(database.proof),
  "empty assignment projection remains bound to the exact unassigned actor",
);
assert(assignmentSection.includes("verified_email"), "signer discovery rechecks the current confirmed email");

const applicationQueueSection = functionSection(
  database.transitions,
  "partner_onboarding_private.list_pending_partner_applications_v1",
);
assert(/security\s+definer/i.test(applicationQueueSection), "application review queue uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(applicationQueueSection), "application review queue pins an empty search path");
assert(applicationQueueSection.includes("heha-partner-application-review-queue-v1"), "application review queue is versioned");
assert(applicationQueueSection.includes("evidence_reviewer") && applicationQueueSection.includes("security_admin"), "application review queue requires explicit reviewer authority");
assert(applicationQueueSection.includes("HEHA_PARTNER_REQUEST_DENIED") && applicationQueueSection.includes("P0001"), "application review queue exposes one generic denial");
assert(
  /revoke\s+all\s+on\s+all\s+functions\s+in\s+schema\s+partner_onboarding_private/i.test(database.transitions),
  "application review queue is covered by the private-function default revoke",
);
assert(applicationQueueSection.includes("auth.uid()") && applicationQueueSection.includes("verified_auth_email_v1"), "application review queue binds the current confirmed human reviewer");
assert(database.proof.includes("list_pending_partner_applications_v1"), "proof covers the authorized human application review queue");

const acceptanceRevocationSection = functionSection(
  database.transitions,
  "partner_onboarding_private.revoke_partner_agreement_acceptance_v1",
);
assert(/security\s+definer/i.test(acceptanceRevocationSection), "agreement revocation uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(acceptanceRevocationSection), "agreement revocation pins an empty search path");
assert(acceptanceRevocationSection.includes("legal_admin"), "agreement revocation requires current legal-admin authority");
assert(acceptanceRevocationSection.includes("HEHA_PARTNER_REQUEST_DENIED") && acceptanceRevocationSection.includes("P0001"), "agreement revocation exposes one generic denial");
assert(
  !database.proof.includes("ACCEPTANCE_REVOCATION_RECOVERY_INSERTION_POINT"),
  "agreement-revocation proof has no unfinished insertion marker",
);
assert(
  /select\s+'acceptance_revocation_first'\s*,\s*partner_onboarding_private\.revoke_partner_agreement_acceptance_v1\s*\(/i.test(database.proof),
  "proof executes legal agreement revocation",
);
assert(
  /select\s+'acceptance_revocation_replay'\s*,\s*partner_onboarding_private\.revoke_partner_agreement_acceptance_v1\s*\(/i.test(database.proof),
  "proof replays legal agreement revocation idempotently",
);
assert(database.proof.includes("acceptance_revocation_fail_closed"), "agreement revocation proves release and orderability fail closed");
assert(database.proof.includes("acceptance_relationship_recovery"), "agreement revocation proves a fresh relationship recovery");

const humanStaffRpcSignatures = [
  ["grant_staff_authority_v1", "uuid,\\s*text,\\s*uuid"],
  ["revoke_staff_authority_v1", "uuid,\\s*uuid,\\s*text"],
  ["reconcile_partner_business_registry_v1", "uuid"],
  ["set_runtime_config_v1", "boolean,\\s*boolean,\\s*boolean,\\s*boolean,\\s*boolean,\\s*boolean,\\s*text,\\s*uuid"],
  ["list_pending_partner_applications_v1", "uuid,\\s*integer"],
  ["issue_partner_invitation_v1", "uuid,\\s*uuid,\\s*text,\\s*text,\\s*text,\\s*timestamptz,\\s*uuid"],
  ["revoke_partner_invitation_v1", "uuid,\\s*uuid,\\s*text"],
  ["reset_unclaimed_partner_reclassification_v1", "uuid,\\s*text,\\s*uuid,\\s*uuid"],
  ["revoke_partner_claim_v1", "uuid,\\s*uuid,\\s*text"],
  ["grant_partner_signer_authority_v1", "uuid,\\s*uuid,\\s*text,\\s*text,\\s*uuid"],
  ["revoke_partner_signer_authority_v1", "uuid,\\s*uuid,\\s*text"],
  ["register_partner_agreement_version_v1", "text,\\s*text,\\s*text,\\s*timestamptz,\\s*text,\\s*text,\\s*text,\\s*jsonb,\\s*text,\\s*uuid,\\s*timestamptz"],
  ["select_partner_agreement_version_v1", "uuid,\\s*uuid"],
  ["revoke_partner_agreement_acceptance_v1", "uuid,\\s*uuid,\\s*text"],
  ["issue_partner_evidence_v1", "uuid,\\s*text,\\s*text,\\s*jsonb,\\s*uuid,\\s*uuid"],
  ["revoke_partner_evidence_v1", "uuid,\\s*uuid,\\s*text"],
];

for (const [staffRpc, signature] of humanStaffRpcSignatures) {
  const staffSection = functionSection(database.transitions, `partner_onboarding_private.${staffRpc}`);
  assert(/security\s+definer/i.test(staffSection), `${staffRpc} uses a protected definer boundary`);
  assert(/set\s+search_path\s*=\s*''/i.test(staffSection), `${staffRpc} pins an empty search path`);
  assert(
    staffSection.includes("require_active_staff_authority_v1")
      || (staffSection.includes("auth.uid()") && staffSection.includes("verified_auth_email_v1")),
    `${staffRpc} binds the current confirmed human and active authority`,
  );
  assert(
    new RegExp(`grant\\s+execute\\s+on\\s+function\\s+partner_onboarding_private\\.${staffRpc}\\s*\\(\\s*${signature}\\s*\\)\\s+to\\s+authenticated`, "i").test(database.transitions),
    `${staffRpc} is callable only at the authenticated human boundary`,
  );
  assert(
    !new RegExp(`grant\\s+execute\\s+on\\s+function\\s+partner_onboarding_private\\.${staffRpc}\\s*\\(\\s*${signature}\\s*\\)\\s+to\\s+(?:public|anon|service_role|supabase_auth_admin)`, "i").test(database.transitions),
    `${staffRpc} is unavailable to anonymous and machine roles`,
  );
  assert(database.proof.includes(staffRpc), `proof covers ${staffRpc}`);
  assert(database.rollback.includes(`partner_onboarding_private.${staffRpc}`), `rollback inventories ${staffRpc}`);
}

const grantStaffAuthoritySection = functionSection(
  database.transitions,
  "partner_onboarding_private.grant_staff_authority_v1",
);
assert(
  /p_granted_by\s*=\s*p_user_id[\s\S]{0,100}p_authority_type\s+is\s+distinct\s+from\s+'security_admin'/i.test(grantStaffAuthoritySection),
  "security administrators cannot self-assign an operational review or attestation role",
);
assert(
  /active_grant\.user_id\s*=\s*p_user_id[\s\S]{0,300}staff_authority_revocations/i.test(grantStaffAuthoritySection),
  "staff authority grants enforce one active authority type per user",
);

const staffActorByAuthority = new Map([
  ["security_admin", "00000000-0000-4000-8000-0000000000e5"],
  ["legal_admin", "00000000-0000-4000-8000-000000000104"],
  ["evidence_reviewer", "00000000-0000-4000-8000-000000000105"],
  ["release_reviewer", "00000000-0000-4000-8000-000000000106"],
  ["swipe_attestor", "00000000-0000-4000-8000-000000000101"],
  ["website_attestor", "00000000-0000-4000-8000-000000000102"],
  ["local_attestor", "00000000-0000-4000-8000-000000000103"],
]);
for (const [authorityType, actorId] of staffActorByAuthority) {
  assert(database.baseline.includes(`'${actorId}'`), `synthetic Auth contains distinct ${authorityType} actor`);
  const lifecycleGrantPattern = authorityType === "security_admin"
    ? new RegExp(`bootstrap_staff_authority_v1\\s*\\(\\s*'${actorId}'\\s*,\\s*'${authorityType}'`, "i")
    : new RegExp(`grant_staff_authority_v1\\s*\\(\\s*'${actorId}'\\s*,\\s*'${authorityType}'\\s*,\\s*'00000000-0000-4000-8000-0000000000e5'`, "i");
  assert(lifecycleGrantPattern.test(database.proof), `lifecycle proof assigns ${authorityType} only to ${actorId}`);
}
assert(database.proof.includes("security admin operational self-grant denied generically"), "proof denies a security-admin operational self-grant");
assert(database.proof.includes("STAFF_SEPARATION_OF_DUTIES"), "proof verifies one active authority per synthetic staff actor");

const reclassificationResetSection = functionSection(
  database.transitions,
  "partner_onboarding_private.reset_unclaimed_partner_reclassification_v1",
);
assert(reclassificationResetSection.includes("legal_admin"), "reclassification reset requires current legal-admin authority");
assert(reclassificationResetSection.includes("reclassification_pending"), "reclassification reset leaves the partner fail-closed pending a new classification");
assert(reclassificationResetSection.includes("HEHA_PARTNER_REQUEST_DENIED") && reclassificationResetSection.includes("P0001"), "reclassification reset exposes only the generic denial");
for (const staleArtifact of [
  "partner_claims",
  "partner_agreement_acceptances",
  "partner_evidence_receipts",
  "partner_release_receipts",
  "partner_surface_activation_receipts",
]) {
  assert(reclassificationResetSection.includes(staleArtifact), `reclassification reset refuses a partner with current ${staleArtifact}`);
}

const runtimeConfigSection = functionSection(
  database.transitions,
  "partner_onboarding_private.set_runtime_config_v1",
);
for (const receiptField of [
  "config_generation",
  "release_epoch_invalidation_applied",
  "release_epoch_invalidated_partner_count",
]) {
  assert(runtimeConfigSection.includes(`'${receiptField}'`), `runtime configuration returns ${receiptField}`);
}
for (const disablingSwitch of [
  "claim_enabled",
  "acceptance_enabled",
  "release_enabled",
  "swipe_publication_enabled",
  "local_ordering_enabled",
]) {
  assert(
    runtimeConfigSection.includes(`v_config.${disablingSwitch} and not p_${disablingSwitch}`),
    `disabling ${disablingSwitch} invalidates the release generation`,
  );
}
assert(/update\s+partner_onboarding_private\.partner_state\s+set\s+release_epoch\s*=\s*release_epoch\s*\+\s*1/i.test(runtimeConfigSection), "kill-switch shutdown invalidates every partner release epoch");

const bootstrapSection = functionSection(
  database.transitions,
  "partner_onboarding_private.bootstrap_staff_authority_v1",
);
assert(/security\s+definer/i.test(bootstrapSection), "staff bootstrap uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(bootstrapSection), "staff bootstrap pins an empty search path");
assert(bootstrapSection.includes("staff_bootstrap_authorizations"), "staff bootstrap requires a DB-owner-seeded authorization");
assert(
  /from\s+partner_onboarding_private\.staff_bootstrap_authorizations\s+bootstrap_auth\b/i.test(bootstrapSection)
    && !/staff_bootstrap_authorizations\s+authorization\b/i.test(bootstrapSection),
  "staff bootstrap avoids the reserved AUTHORIZATION relation alias",
);
assert(bootstrapSection.includes("auth.uid()") && bootstrapSection.includes("verified_auth_email_v1"), "staff bootstrap exact-binds the preauthorized confirmed user");
assert(
  /grant\s+execute\s+on\s+function\s+partner_onboarding_private\.bootstrap_staff_authority_v1\s*\(\s*uuid,\s*text\s*\)\s+to\s+authenticated/i.test(database.transitions),
  "preauthorized staff bootstrap uses the authenticated human boundary",
);
assert(
  !/grant\s+execute\s+on\s+function\s+partner_onboarding_private\.bootstrap_staff_authority_v1\s*\(\s*uuid,\s*text\s*\)\s+to\s+(?:public|anon|service_role|supabase_auth_admin)/i.test(database.transitions),
  "staff bootstrap is unavailable to anonymous and machine callers",
);
assert(database.proof.includes("bootstrap_staff_authority_v1"), "proof covers secure one-time staff bootstrap");
assert(database.rollback.includes("partner_onboarding_private.bootstrap_staff_authority_v1"), "rollback inventories secure staff bootstrap");
assert(database.foundation.includes("partner_onboarding_private.staff_bootstrap_authorizations"), "foundation stores exact staff-bootstrap preauthorizations privately");
assert(database.proof.includes("staff_bootstrap_authorizations"), "proof inventories staff-bootstrap preauthorization records");
assert(database.rollback.includes("staff_bootstrap_authorizations"), "rollback inventories staff-bootstrap preauthorization records");

const requiredStaffAuthoritySection = functionSection(
  database.transitions,
  "partner_onboarding_private.require_active_staff_authority_v1",
);
assert(/security\s+definer/i.test(requiredStaffAuthoritySection), "staff-authority guard uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(requiredStaffAuthoritySection), "staff-authority guard pins an empty search path");
assert(
  !/grant\s+execute\s+on\s+function\s+partner_onboarding_private\.require_active_staff_authority_v1\s*\(/i.test(database.transitions),
  "staff-authority guard remains internal-only",
);
assert(database.proof.includes("require_active_staff_authority_v1"), "proof inventories the internal staff-authority guard");
assert(database.rollback.includes("partner_onboarding_private.require_active_staff_authority_v1"), "rollback inventories the internal staff-authority guard");

assert(database.transitions.includes("HEHA_PARTNER_REQUEST_DENIED"), "protected RPCs share one external denial");
assert(database.transitions.includes("P0001"), "protected RPC denials use the locked SQLSTATE");
assert(
  !/pg_catalog\.(?:coalesce|nullif|least|greatest)\s*\(/i.test(reviewDatabaseSql),
  "PostgreSQL conditional expressions are never schema-qualified in the review package",
);
assert(
  !/\b(?:get\s+stacked\s+diagnostics|returned_sqlstate|message_text|raise\s+notice|HEHA_REVIEW_(?:APPLICATION|PROFILE)|v_review_error_)\b/i.test(
    `${database.transitions}\n${database.proof}`,
  ),
  "temporary correction diagnostics are absent from the review package",
);
assert((database.transitions.match(/partner-onboarding:business:/g) || []).length >= 2, "invitation and application share the normalized business-key lock");
assert(database.foundation.includes("partner_onboarding_private.partner_business_key_corrections"), "foundation stores append-only business-key corrections");
for (const helperName of [
  "current_partner_business_key_v1",
  "partner_business_identity_is_current_v1",
  "guard_partner_business_key_correction_v1",
  "guard_partner_business_identity_update_v1",
]) {
  const helperSection = functionSection(database.transitions, `partner_onboarding_private.${helperName}`);
  assert(/security\s+definer/i.test(helperSection), `${helperName} uses a protected definer boundary`);
  assert(/set\s+search_path\s*=\s*''/i.test(helperSection), `${helperName} pins an empty search path`);
  assert(
    !new RegExp(`grant\\s+execute\\s+on\\s+function\\s+partner_onboarding_private\\.${helperName}\\s*\\(`, "i").test(database.transitions),
    `${helperName} remains internal-only`,
  );
  assert(database.proof.includes(helperName), `proof inventories ${helperName}`);
  assert(database.rollback.includes(`partner_onboarding_private.${helperName}`), `rollback inventories ${helperName}`);
}
assert(database.transitions.includes("create trigger guard_partner_business_key_correction_v1"), "business-key correction inserts have a fail-closed identity trigger");
assert(database.proof.includes("trigger.tgname = 'guard_partner_business_key_correction_v1'"), "proof verifies the business-key correction trigger is live");
assert(database.rollback.includes("drop trigger if exists guard_partner_business_key_correction_v1"), "rollback removes the business-key correction trigger");
assert(database.transitions.includes("create trigger guard_partner_business_identity_update_v1"), "raw partner identity changes have a fail-closed trigger");
assert(database.rollback.includes("drop trigger if exists guard_partner_business_identity_update_v1"), "rollback removes the business-identity trigger");
const registryReconciliationSection = functionSection(
  database.transitions,
  "partner_onboarding_private.reconcile_partner_business_registry_v1",
);
assert(registryReconciliationSection.includes("heha-partner-business-registry-reconciliation-v1"), "business-registry reconciliation is versioned");
assert(registryReconciliationSection.includes("'status', 'verified'"), "business-registry reconciliation returns verified status");
assert(registryReconciliationSection.includes("partner-onboarding:business-registry"), "business-registry reconciliation takes the global identity lock");
for (const reconciliationMarker of [
  "business-registry actor UUID impersonation denied",
  "non-admin cannot reconcile the business registry",
  "business_registry_reconciliation_first",
  "business_registry_reconciliation_replay",
]) {
  assert(database.proof.includes(reconciliationMarker), `business-registry proof covers ${reconciliationMarker}`);
}
assert(
  database.proof.indexOf("insert into public.partners")
    < database.proof.indexOf("business_registry_reconciliation_first")
    && database.proof.indexOf("security_admin_grant")
      < database.proof.indexOf("business_registry_reconciliation_first")
    && database.proof.indexOf("business_registry_reconciliation_first")
      < database.proof.indexOf("select partner_onboarding_private.set_runtime_config_v1"),
  "proof reconciles synthetic identities after secure bootstrap and before enabling applications",
);
assert(database.transitions.includes("heha-partner-onboarding-v1"), "capability projection is versioned");
assert(database.transitions.includes("receipt_status"), "protected RPCs return explicit receipt status");
assert(database.transitions.includes("verified"), "successful protected RPC receipts are verified");
for (const [relationship, lane, route] of [
  ["restaurant", "meals", "restaurants"],
  ["vendor", "vendors", "vendors"],
  ["market", "market", "market"],
  ["solo_chef", "chef", "chef"],
  ["catering", "group_orders", "group-orders"],
]) {
  assert(database.transitions.includes(`when '${relationship}' then '${lane}'`), `${relationship} binds canonical Local lane ${lane}`);
  assert(database.transitions.includes(`when '${relationship}' then '${route}'`), `${relationship} binds canonical Local route ${route}`);
}

const releaseSection = functionSection(
  database.release,
  "partner_onboarding_private.finalize_partner_release_v1",
);
assert(/security\s+definer/i.test(releaseSection), "release finalization uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(releaseSection), "release finalization pins an empty search path");
const epochReleaseSection = functionSection(
  database.release,
  "partner_onboarding_private.epoch_release_receipt_id_v1",
);
assert(/security\s+definer/i.test(epochReleaseSection), "epoch release lookup uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(epochReleaseSection), "epoch release lookup pins an empty search path");
assert(
  /revoke\s+all\s+on\s+function\s+partner_onboarding_private\.epoch_release_receipt_id_v1\s*\(uuid\)/i.test(database.release),
  "epoch release lookup revokes every external role",
);
assert(
  !/grant\s+execute\s+on\s+function\s+partner_onboarding_private\.epoch_release_receipt_id_v1\s*\(uuid\)/i.test(database.release),
  "epoch release lookup remains internal-only",
);
const profileInvalidationSection = functionSection(
  database.release,
  "partner_onboarding_private.invalidate_release_after_partner_change_v1",
);
assert(/security\s+definer/i.test(profileInvalidationSection), "profile-change invalidation uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(profileInvalidationSection), "profile-change invalidation pins an empty search path");
assert(database.release.includes("invalidate_partner_release_after_reviewed_change"), "reviewed partner fields have an invalidation trigger");
assert(database.release.includes("release_epoch = release_epoch + 1"), "reviewed partner changes invalidate the current release epoch");
assert(
  /revoke\s+all\s+on\s+function\s+partner_onboarding_private\.invalidate_release_after_partner_change_v1\s*\(\)/i.test(database.release),
  "profile-change invalidation revokes every external role",
);
assert(
  !/grant\s+execute\s+on\s+function\s+partner_onboarding_private\.invalidate_release_after_partner_change_v1\s*\(\)/i.test(database.release),
  "profile-change invalidation remains trigger-only",
);

const releaseStaffRpcSignatures = [
  ["finalize_partner_release_v1", "uuid,\\s*text,\\s*uuid,\\s*uuid"],
  ["record_partner_surface_activation_v1", "uuid,\\s*uuid,\\s*text,\\s*uuid,\\s*text,\\s*jsonb,\\s*uuid,\\s*uuid"],
  ["revoke_partner_release_v1", "uuid,\\s*uuid,\\s*text"],
  ["revoke_partner_surface_activation_v1", "uuid,\\s*uuid,\\s*text"],
];
const releaseFunctionRevokeStatements = [...database.release.matchAll(/revoke\s+all\s+on\s+function[\s\S]*?;/gi)]
  .map((match) => match[0]);
assert(releaseFunctionRevokeStatements.length > 0, "release SQL explicitly revokes function defaults");
for (const revokeStatement of releaseFunctionRevokeStatements) {
  assert(revokeStatement.includes("supabase_auth_admin"), "every release function revoke explicitly includes auth-admin");
}
for (const [releaseRpc, signature] of releaseStaffRpcSignatures) {
  const section = functionSection(database.release, `partner_onboarding_private.${releaseRpc}`);
  assert(/security\s+definer/i.test(section), `${releaseRpc} uses a protected definer boundary`);
  assert(/set\s+search_path\s*=\s*''/i.test(section), `${releaseRpc} pins an empty search path`);
  assert(section.includes("require_active_staff_authority_v1"), `${releaseRpc} rechecks current staff authority`);
  assert(
    new RegExp(`grant\\s+execute\\s+on\\s+function\\s+partner_onboarding_private\\.${releaseRpc}\\s*\\(\\s*${signature}\\s*\\)\\s+to\\s+authenticated`, "i").test(database.release),
    `${releaseRpc} is authenticated-human only`,
  );
  assert(
    !new RegExp(`grant\\s+execute\\s+on\\s+function\\s+partner_onboarding_private\\.${releaseRpc}\\s*\\(\\s*${signature}\\s*\\)\\s+to\\s+(?:public|anon|service_role|supabase_auth_admin)`, "i").test(database.release),
    `${releaseRpc} is unavailable to anonymous, machine, and auth-admin roles`,
  );
  assert(
    new RegExp(`revoke\\s+all\\s+on\\s+function\\s+partner_onboarding_private\\.${releaseRpc}\\s*\\(\\s*${signature}\\s*\\)\\s+from[\\s\\S]{0,180}\\bsupabase_auth_admin\\b`, "i").test(database.release),
    `${releaseRpc} explicitly revokes auth-admin execution`,
  );
  assert(database.proof.includes(releaseRpc), `runtime proof covers ${releaseRpc}`);
  assert(database.rollback.includes(`partner_onboarding_private.${releaseRpc}`), `rollback inventories ${releaseRpc}`);
}

const orderabilityReceiptSection = functionSection(
  database.release,
  "public.get_partner_orderability_receipt_v1",
);
assert(/security\s+definer/i.test(orderabilityReceiptSection), "orderability read uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(orderabilityReceiptSection), "orderability read pins an empty search path");
assert(
  /grant\s+execute\s+on\s+function\s+public\.get_partner_orderability_receipt_v1\s*\(uuid\)\s+to\s+service_role/i.test(database.release),
  "orderability receipt read remains service-role only",
);
assert(
  !/grant\s+execute\s+on\s+function\s+public\.get_partner_orderability_receipt_v1\s*\(uuid\)\s+to\s+(?:public|anon|authenticated|supabase_auth_admin)/i.test(database.release),
  "orderability receipt read is unavailable to browser and auth-admin roles",
);
assert(
  /revoke\s+all\s+on\s+function\s+public\.get_partner_orderability_receipt_v1\s*\(uuid\)\s+from[\s\S]{0,180}\bsupabase_auth_admin\b/i.test(database.release),
  "orderability receipt read explicitly revokes auth-admin execution",
);
for (const [policyHelper, signature] of [
  ["partner_has_current_release_v1", "uuid,\\s*text"],
  ["partner_card_is_current_v1", "uuid,\\s*text,\\s*uuid,\\s*uuid"],
]) {
  assert(
    new RegExp(`revoke\\s+all\\s+on\\s+function\\s+public\\.${policyHelper}\\s*\\(\\s*${signature}\\s*\\)\\s+from[\\s\\S]{0,180}\\bsupabase_auth_admin\\b`, "i").test(database.release),
    `${policyHelper} explicitly revokes auth-admin execution`,
  );
  assert(
    new RegExp(`grant\\s+execute\\s+on\\s+function\\s+public\\.${policyHelper}\\s*\\(\\s*${signature}\\s*\\)\\s+to\\s+anon\\s*,\\s*authenticated`, "i").test(database.release),
    `${policyHelper} is exposed only to receipt-view callers`,
  );
}
assert(/for\s+update/i.test(database.release), "release finalization locks current evidence");
assert(database.release.includes("release_enabled"), "release finalization checks its server kill switch");
assert(database.release.includes("swipe_publication_enabled"), "Swipe publication checks its independent switch");
assert(database.release.includes("local_ordering_enabled"), "Local orderability checks its independent switch");
assert(database.release.includes("partner_release_receipts"), "release gate requires an immutable release receipt");
assert(database.release.includes("partner_release_revocations"), "release gate checks receipt revocation");
assert(database.release.includes("partner_surface_activation_receipts"), "surface publication requires an activation receipt");
assert(database.release.includes("partner_surface_activation_revocations"), "surface publication checks activation revocation");
assert(database.release.includes("target_receipt_id"), "surface activation binds the exact target receipt");
assert(database.release.includes("'surface'"), "surface activation snapshot binds its surface");
assert(database.release.includes("'environment'"), "surface activation snapshot binds its environment");
assert(database.release.includes("'test'"), "review-only activation stays in the test environment");
assert(database.release.includes("security_invoker = true"), "receipt-backed public views use security-invoker semantics");
assert(database.release.includes("public.partner_public_cards_v1"), "public cards are receipt-bound activation snapshots");
assert(database.release.includes('create policy "Released public partner cards only"'), "public cards require the current release policy");
assert(database.release.includes("public.partner_has_current_release_v1"), "public-card RLS rechecks the current receipt chain");
const cardCurrentSection = functionSection(database.release, "public.partner_card_is_current_v1");
assert(/security\s+definer/i.test(cardCurrentSection), "public-card policy helper uses a protected definer boundary");
assert(/set\s+search_path\s*=\s*''/i.test(cardCurrentSection), "public-card policy helper pins an empty search path");
assert(database.release.includes("public.partner_card_is_current_v1("), "public-card RLS binds both release and activation receipt IDs");
assert(database.release.includes("revoke select on table public.partners from anon"), "legacy base-table public access is removed");
assert(database.release.includes("public.get_partner_orderability_receipt_v1"), "Local receives a server-only orderability receipt boundary");
for (const viewName of ["public_partner_directory", "public_swipe_partners", "public_local_partners"]) {
  const receiptBackedView = viewSection(database.release, `public.${viewName}`);
  assert(receiptBackedView.includes("partner_public_cards_v1"), `${viewName} reads only receipt-backed public snapshots`);
  assert(/security_invoker\s*=\s*true/i.test(receiptBackedView), `${viewName} uses caller RLS and ACLs`);
}

assert(database.proof.includes("has_function_privilege"), "proof checks function ACLs");
assert(database.proof.includes("has_table_privilege"), "proof checks table ACLs");
assert(database.proof.includes("relrowsecurity"), "proof checks RLS is enabled");
assert(database.proof.includes("relforcerowsecurity"), "proof checks RLS is forced");
assert(database.proof.includes("partner_release_receipts"), "proof exercises final release receipts");
assert(database.proof.includes("partner_surface_activation_receipts"), "proof exercises surface activation receipts");
assert(database.proof.includes("relationship_type_for_application_v1"), "proof covers server/client category-classification parity");
assert(database.proof.includes('"local_lane":"meals"'), "proof accepts the canonical restaurant Local lane");
assert(database.proof.includes('"local_lane":"restaurants"'), "proof rejects a route segment masquerading as the Local lane");
assert(database.proof.includes('"primary_cta_path":"/vendors/'), "proof rejects a category-mismatched Local route");
assert(database.proof.includes("epoch_release_receipt_id_v1"), "proof inventories the internal epoch release lookup");
assert(database.proof.includes("invalidate_partner_release_after_reviewed_change"), "proof exercises the reviewed-profile invalidation trigger");
assert(database.proof.includes("invalidate_release_after_partner_change_v1"), "proof inventories the internal profile invalidator");
const killSwitchDisableIndex = database.proof.indexOf("KILL_SWITCH_BARE_DISABLE");
const killSwitchNoResurrectionIndex = database.proof.indexOf("KILL_SWITCH_BARE_REENABLE_NO_RESURRECTION");
const killSwitchRecoveryIndex = database.proof.indexOf("KILL_SWITCH_FRESH_GENERATION_RECOVERY");
assert(
  killSwitchDisableIndex >= 0
    && killSwitchDisableIndex < killSwitchNoResurrectionIndex
    && killSwitchNoResurrectionIndex < killSwitchRecoveryIndex,
  "proof orders bare kill-switch disable, no-resurrection re-enable, and fresh-generation recovery",
);
const bareKillSwitchSegment = killSwitchDisableIndex >= 0 && killSwitchNoResurrectionIndex > killSwitchDisableIndex
  ? database.proof.slice(killSwitchDisableIndex, killSwitchNoResurrectionIndex)
  : "";
assert(
  !/revoke_partner_(?:release|surface_activation)_v1\s*\(/i.test(bareKillSwitchSegment),
  "bare kill-switch off-to-on proof has no intervening receipt revocation",
);
assert(
  (bareKillSwitchSegment.match(/set_runtime_config_v1\s*\(/gi) || []).length >= 2,
  "bare kill-switch proof disables and re-enables through the authoritative runtime transition",
);
for (const staleSurfaceMarker of [
  "release_epoch",
  "partner_public_cards_v1",
  "get_partner_orderability_receipt_v1",
]) {
  assert(database.proof.slice(killSwitchNoResurrectionIndex, killSwitchRecoveryIndex).includes(staleSurfaceMarker), `bare re-enable keeps ${staleSurfaceMarker} stale`);
}
assert(database.proof.includes("rollback;"), "proof fixtures roll back");
assert(database.proof.includes("current_setting('heha.review_only', true)"), "proof refuses an unguarded database before fixtures");
assert(database.proof.includes("HEHA_REVIEW_ONLY_GUARD"), "proof has a stable review-only denial");

assert(database.concurrency.includes('DATABASE_URL'), "two-client proof targets only the disposable database");
assert(database.concurrency.includes("HEHA_REVIEW_ONLY_GUARD"), "two-client proof has a stable review-only denial");
assert(database.concurrency.includes("current_setting('heha.review_only', true)"), "two-client proof verifies the external database guard");
assert(/pg_catalog\.host\s*\(\s*pg_catalog\.inet_server_addr\s*\(\s*\)\s*\)/i.test(database.concurrency) && database.concurrency.includes("127.0.0.1") && database.concurrency.includes("::1"), "two-client proof normalizes the server address before accepting only loopback");
assert(!/(?:^|\n)\s*(?:export\s+)?PGOPTIONS\s*=/.test(database.concurrency), "two-client proof cannot self-authorize the review-only guard");
assert(database.concurrency.includes('mktemp -d'), "two-client proof isolates its output");
assert(database.concurrency.includes("trap"), "two-client proof cleans temporary output");
assert(database.concurrency.includes("&"), "two-client proof starts concurrent clients");
assert(database.concurrency.includes("wait"), "two-client proof waits for both clients");
const concurrencySeedStart = database.concurrency.indexOf('"${PSQL[@]}" <<SQL');
const concurrencySeedEnd = database.concurrency.indexOf("\nSQL", concurrencySeedStart);
const concurrencySeed = concurrencySeedStart >= 0 && concurrencySeedEnd > concurrencySeedStart
  ? database.concurrency.slice(concurrencySeedStart, concurrencySeedEnd)
  : "";
assert(
  /begin;[\s\S]*insert\s+into\s+partner_onboarding_private\.staff_bootstrap_authorizations[\s\S]*set\s+local\s+role\s+authenticated;[\s\S]*set_config\s*\(\s*'request\.jwt\.claim\.sub'[\s\S]*\$REVIEWER[\s\S]*bootstrap_staff_authority_v1\s*\(\s*'\$REVIEWER'\s*,\s*'security_admin'\s*\)[\s\S]*commit;/i.test(concurrencySeed),
  "database-owner preauthorization precedes authenticated reviewer bootstrap in one seed transaction",
);
assert(!/^\s*run_service\s+["']/m.test(database.concurrency), "two-client proof never invokes staff mutators through service_role");
for (const [authorityType, actorId] of staffActorByAuthority) {
  const variableName = {
    security_admin: "REVIEWER",
    legal_admin: "LEGAL_ADMIN",
    evidence_reviewer: "EVIDENCE_REVIEWER",
    release_reviewer: "RELEASE_REVIEWER",
    swipe_attestor: "SWIPE_ATTESTOR",
    website_attestor: "WEBSITE_ATTESTOR",
    local_attestor: "LOCAL_ATTESTOR",
  }[authorityType];
  assert(database.concurrency.includes(`${variableName}='${actorId}'`), `two-client proof binds ${authorityType} to its distinct actor`);
}
assert(database.concurrency.includes("claim_partner_invitation_v1"), "two-client proof races protected claims");
assert(database.concurrency.includes("record_category_partner_agreement_acceptance_v1"), "two-client proof races agreement acceptance");
assert(database.concurrency.includes("finalize_partner_release_v1"), "two-client proof races release finalization");
assert(database.concurrency.includes("'local_lane', 'meals'"), "two-client restaurant evidence uses the canonical Local lane");
assert(database.concurrency.includes("record_partner_surface_activation_v1"), "two-client proof races activation replay and target collision");
assert(database.concurrency.includes("CROSS_SOURCE_LOCAL_TARGET_COLLISION"), "two-client proof races two source partners for one Local target");
assert(database.concurrency.includes("revoke_partner_surface_activation_v1"), "two-client proof races idempotent surface revocation");
assert(/update\s+public\.partners/i.test(database.concurrency), "two-client proof races a watched profile edit against release finalization");

const rollbackStatements = database.rollback
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/^\s*--.*$/gm, "");
assert(rollbackStatements.includes("drop schema if exists partner_onboarding_private cascade"), "rollback removes the private review schema");
assert((rollbackStatements.match(/drop\s+schema\b/gi) || []).length === 1, "rollback drops exactly one review schema");
assert((rollbackStatements.match(/drop\s+table\b/gi) || []).length === 1, "rollback drops only the receipt-backed public-card table");
assert(/drop\s+table\s+if\s+exists\s+public\.partner_public_cards_v1\b/i.test(rollbackStatements), "rollback table drop is the receipt-backed public-card table");
assert(!/drop\s+schema\s+(?:if\s+exists\s+)?public\b/i.test(rollbackStatements), "rollback never drops the public schema");
assert(!/drop\s+table\s+(?:if\s+exists\s+)?public\.partners\b/i.test(rollbackStatements), "rollback never drops the legacy partners table");
assert(!/\btruncate\b/i.test(rollbackStatements), "rollback never truncates any table");
const rollbackMutationScan = rollbackStatements
  .replace(/\bgrant\s+insert\s*,\s*update\s+on\s+table\s+public\.partners\s+to\s+authenticated\b/gi, "")
  .replace(/\bfor\s+(?:insert|update)\b/gi, "");
assert(!/\b(?:insert|update)\b/i.test(rollbackMutationScan), "rollback cannot rewrite rows while restoring exact legacy write policies");
assert(!/\bexecute\b/i.test(rollbackStatements), "rollback cannot dynamically execute teardown");
assert(!/\b(?:drop\s+owned|reassign\s+owned)\b/i.test(rollbackStatements), "rollback cannot perform ownership-wide teardown");
const partnerCleanupStatements = rollbackStatements.match(/delete\s+from\s+public\.partners\b/gi) || [];
assert(partnerCleanupStatements.length === 1, "rollback has one bounded synthetic-partner cleanup");
assert((rollbackStatements.match(/delete\s+from\b/gi) || []).length === 1, "rollback has no other row-deletion path");
const cleanupStatement = /delete\s+from\s+public\.partners[\s\S]*?;/i.exec(rollbackStatements)?.[0] || "";
const cleanupUuids = [...cleanupStatement.matchAll(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi)]
  .map((match) => match[0].toLowerCase());
const allowedCleanupUuids = new Set([
  "00000000-0000-4000-8000-0000000000c3",
  "00000000-0000-4000-8000-0000000000d4",
  "91000000-0000-4000-8000-000000000001",
  "91000000-0000-4000-8000-000000000002",
  "91000000-0000-4000-8000-000000000003",
]);
const expectedCleanupUuids = [
  "00000000-0000-4000-8000-0000000000c3",
  "00000000-0000-4000-8000-0000000000d4",
  "91000000-0000-4000-8000-000000000001",
  "91000000-0000-4000-8000-000000000002",
  "91000000-0000-4000-8000-000000000003",
].sort();
assert(
  cleanupUuids.every((id) => allowedCleanupUuids.has(id))
    && cleanupUuids.slice().sort().join("\n") === expectedCleanupUuids.join("\n"),
  "rollback cleanup uses only the exact fixed partners and two synthetic applicant owners",
);
for (const [partnerId, partnerName] of [
  ["91000000-0000-4000-8000-000000000001", "Synthetic Concurrency One Reviewed"],
  ["91000000-0000-4000-8000-000000000002", "Synthetic Concurrency Two"],
  ["91000000-0000-4000-8000-000000000003", "Synthetic Concurrency Existing Invite"],
]) {
  assert(
    new RegExp(`id\\s*=\\s*'${partnerId}'[\\s\\S]{0,160}?name\\s*=\\s*'${partnerName}'`, "i").test(cleanupStatement),
    `rollback bounds fixed synthetic partner ${partnerId} by its exact name`,
  );
}
assert(
  /owner_id\s+in\s*\([\s\S]*?00000000-0000-4000-8000-0000000000c3[\s\S]*?00000000-0000-4000-8000-0000000000d4[\s\S]*?regexp_replace[\s\S]*?synthetic concurrency business race[\s\S]*?regexp_replace[\s\S]*?tampa, fl/i.test(cleanupStatement),
  "rollback bounds its dynamic cleanup by both synthetic owners and normalized business identity",
);
assert(reviewWorkflow.includes("normalized business-race profile behind"), "workflow proves normalized concurrency cleanup after rollback");
assert(database.rollback.includes("current_setting('heha.review_only', true)"), "rollback refuses an unguarded database before teardown");
assert(database.rollback.includes("HEHA_REVIEW_ONLY_GUARD"), "rollback has a stable review-only denial");
assert(database.rollback.includes("partner_onboarding_private.epoch_release_receipt_id_v1"), "rollback inventories the internal epoch release lookup");
assert(database.rollback.includes("invalidate_partner_release_after_reviewed_change"), "rollback removes the profile invalidation trigger");
assert(database.rollback.includes("partner_onboarding_private.invalidate_release_after_partner_change_v1"), "rollback inventories the private profile invalidator");
assert(database.rollback.includes("partner_onboarding_private.list_pending_partner_applications_v1"), "rollback inventories the private application review queue");
assert(database.rollback.includes("partner_onboarding_private.revoke_partner_agreement_acceptance_v1"), "rollback inventories legal agreement revocation");
for (const rpcName of clientRpcNames) {
  assert(database.rollback.includes(`public.${rpcName}`), `rollback removes public RPC ${rpcName}`);
}
assert(database.rollback.includes("public.partner_public_cards_v1"), "rollback removes receipt-backed public snapshots");
assert(database.rollback.includes("public.partner_has_current_release_v1"), "rollback removes the public receipt-policy helper");
assert(database.rollback.includes("public.partner_card_is_current_v1"), "rollback removes the exact-card receipt-policy helper");
assert(database.rollback.includes("public.get_partner_orderability_receipt_v1"), "rollback removes the Local receipt boundary");
for (const viewName of ["public_partner_directory", "public_swipe_partners", "public_local_partners"]) {
  assert(database.rollback.includes(`create or replace view public.${viewName}`), `rollback restores legacy view ${viewName}`);
}

const securityScanFiles = execFileSync(
  "git",
  ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
  { cwd: root },
).toString("utf8").split("\0").filter((filePath) => {
  if (!filePath) return false;
  const absolute = path.join(root, filePath);
  return fs.existsSync(absolute) && fs.lstatSync(absolute).isFile();
});

const supabaseEndpointPattern = /\b(?:https?|wss?|postgres(?:ql)?):\/\/[^\s"'`]*(?:\.supabase\.co|\.pooler\.supabase\.com)\b/i;
const stripeSecretPattern = /\b(?:(?:sk|rk)_(?:live|test)|whsec)_[a-zA-Z0-9_-]{8,}/;
const supabaseSecretPattern = /\bsb_secret_[a-zA-Z0-9_-]{8,}/i;
const serviceRoleAssignmentPattern = /\bsupabase_service_role_key\b["']?\s*(?:=|:)\s*["']?(?!YOUR[_-]|<|\$\{)[a-zA-Z0-9._~-]{8,}/i;

function containsServiceRoleJwt(source) {
  const jwtCandidates = source.match(/\b[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\b/g) || [];
  return jwtCandidates.some((candidate) => {
    try {
      const payload = JSON.parse(Buffer.from(candidate.split(".")[1], "base64url").toString("utf8"));
      return payload?.role === "service_role";
    } catch {
      return false;
    }
  });
}

const serviceRoleJwtVector = [
  Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ role: "service_role", ref: "review-only" })).toString("base64url"),
  Buffer.from("review-signature").toString("base64url"),
].join(".");
const anonJwtVector = [
  Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ role: "anon", ref: "review-only" })).toString("base64url"),
  Buffer.from("review-signature").toString("base64url"),
].join(".");
assert(containsServiceRoleJwt(serviceRoleJwtVector), "secret scanner decodes legacy service-role JWTs");
assert(!containsServiceRoleJwt(anonJwtVector), "secret scanner does not misclassify anon JWTs as service credentials");

for (const [label, candidate, pattern] of [
  ["HTTPS Supabase endpoint", "https://" + "review-project.supabase.co", supabaseEndpointPattern],
  ["WebSocket Supabase endpoint", "wss://" + "review-project.supabase.co/realtime", supabaseEndpointPattern],
  ["PostgreSQL Supabase endpoint", "postgresql://postgres:review-password@" + "db.review-project.supabase.co/postgres", supabaseEndpointPattern],
  ["Supabase pooler endpoint", "postgresql://postgres:review-password@" + "aws-0-us-east-1.pooler.supabase.com:6543/postgres", supabaseEndpointPattern],
  ["Stripe API secret", "sk_" + "test_reviewSecret123", stripeSecretPattern],
  ["Stripe webhook secret", "whsec_" + "reviewWebhook123", stripeSecretPattern],
  ["Supabase secret key", "sb_" + "secret_reviewSecret123", supabaseSecretPattern],
  ["environment service-role assignment", "supabase_" + "service_role_key=eyJreviewservicecredential", serviceRoleAssignmentPattern],
  ["JSON service-role assignment", '"SUPABASE_' + 'SERVICE_ROLE_KEY": "eyJreviewservicecredential"', serviceRoleAssignmentPattern],
]) {
  assert(pattern.test(candidate), `secret scanner detects ${label}`);
}

const binarySecretVector = Buffer.concat([
  Buffer.from([0, 255, 0]),
  Buffer.from("whsec_" + "binaryReviewSecret123", "ascii"),
]).toString("latin1");
assert(stripeSecretPattern.test(binarySecretVector), "secret scanner detects credentials embedded in binary blobs");

for (const filePath of securityScanFiles) {
  const source = fs.readFileSync(path.join(root, filePath)).toString("latin1")
    .replaceAll("https://YOUR-PROJECT.supabase.co", "");
  assert(!supabaseEndpointPattern.test(source), `no live Supabase endpoint in ${filePath}`);
  assert(!stripeSecretPattern.test(source), `no Stripe secret in ${filePath}`);
  assert(!supabaseSecretPattern.test(source), `no Supabase secret key in ${filePath}`);
  assert(!serviceRoleAssignmentPattern.test(source), `no service-role credential in ${filePath}`);
  assert(!containsServiceRoleJwt(source), `no legacy service-role JWT in ${filePath}`);
}

console.log(`PASS: partner onboarding review verified ${checks}/${checks} source controls.`);
