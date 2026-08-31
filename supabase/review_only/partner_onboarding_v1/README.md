# Partner Onboarding V1 — Review-Only Database Contract

Status: **REVIEW ONLY / SIGNING DISABLED / PRODUCTION FROZEN**

This directory deliberately contains no executable migration. The repository's
`SWP-016` migration-lineage gate currently prohibits new files under
`supabase/migrations`. The UI in this branch therefore keeps
`VITE_ENABLE_PARTNER_AGREEMENT_ACCEPTANCE` off by default.

It now contains an executable **disposable PostgreSQL proof packet** outside the
migration chain. GitHub Actions may apply it only to a synthetic PostgreSQL 15
or 17 service, reapply it, run negative-role/lifecycle/two-client checks, roll it
back, and rebuild it. These files are not a deployable migration and do not
authorize a Supabase branch, preview database, staging database, or Production
change.

## Review-only proof packet

- `000_minimal_baseline.sql` recreates only the representative Auth/partner
  boundary and the legacy status-only public views needed to prove the bypass.
- `001_partner_onboarding_foundation.sql` defines private, RLS-forced,
  append-only claim, application, signer-authority, agreement, evidence,
  release, revocation, and target-surface receipt records.
- `002_partner_onboarding_transitions.sql` implements the protected client and
  service transitions with default-off server switches, recipient binding,
  BOLA checks, deterministic locks, idempotency, and generic denials.
- `003_partner_release_gate.sql` replaces synthetic legacy visibility with an
  allowlisted public-card projection. A release receipt authorizes activation
  but does not itself claim that Swipe is visible or Local is orderable.
- `proof/` and `rollback/` hold exact lifecycle, negative-role, concurrency,
  revocation, teardown, and clean-rebuild evidence.

All seven category documents in the application remain legal-review drafts.
The proof may register only clearly synthetic test documents and approval
references; it cannot make any agreement legally approved or signable in a live
environment.

## Existing donor contract

Draft PR #127 (`codex/partner-publication-integration-rc`, reviewed at
`c8c832305edcc4f8efdb98fac4b50801bb2c77d6`) already owns these names:

- `public.partner_agreement_versions`
- `public.partner_agreement_acceptances`
- `public.record_partner_agreement_acceptance(uuid,text,text,bytea)`

Do not create parallel agreement tables or deploy the donor RPC as the new
category-signing path. Treat #127 as a frozen data-model donor that must be
reconciled onto the future canonical baseline before a versioned successor.

## Required successor changes

The #127 donor proves important owner binding, immutability, revocation, and
agreement-gated partnership rules, but it is not yet sufficient for the in-app
category agreement requested here. A reviewed successor must add or prove:

1. `legal_relationship_type` on the canonical partner relationship, separate
   from mutable discovery categories.
2. One immutable current agreement per relationship type: restaurant, vendor,
   grocery/farmers market, catering, solo chef/meal prep, driver, and SOM.
3. Complete accepted document snapshot, title, effective date, category,
   version, SHA-256, incorporated schedule/policy versions, and legal approval
   reference/date.
4. Signer legal name, title, verified account/email, authority attestation,
   separate electronic-records consent, exact assent text, typed signature,
   server timestamp, minimized server-captured request evidence, and receipt ID.
5. Downloadable accepted copy and a trusted delivery receipt. No trusted email
   delivery service is proven in the current repository.
6. Append-only/BOLA/idempotency/concurrency proofs and a new acceptance when the
   agreement or legal relationship type materially changes.
7. A fail-closed publication/orderability transition requiring the current
   agreement receipt, business claim, licenses/insurance/tax checks, approved
   media, partner-specific Local profile, exact test-order receipt, final partner
   publication consent, and HEHA admin approval.
8. Separate target-system activation receipts. Swipe public visibility requires
   a Swipe activation acknowledgement bound to the current release receipt.
   Local orderability remains false until HEHA Local returns its own exact
   partner-identity/order-guard acknowledgement. A Local URL, eligibility flag,
   smoke-test receipt, or Swipe release cannot substitute for that response.

## Required versioned RPC boundary

The locked client intentionally references endpoints that do not exist on the
current baseline. Signing may be enabled only after exact-head database proof
implements them:

- `get_partner_agreement_for_acceptance_v1(partner_id)` derives the immutable
  legal relationship and signer authority on the server and returns the exact
  approved document snapshot, document hash, assent, legal approval reference,
  verified account email, owner/signer IDs, and server kill-switch state.
- `record_category_partner_agreement_acceptance_v1(partner_id,
  agreement_version_id, expected_document_sha256, request_key, assertions)`
  starts one transaction and locks the partner, current relationship, claim,
  signer authority, agreement version, and server acceptance kill switch. It
  atomically re-checks that every value is still current and enabled—including
  the loaded document hash—before canonicalizing and storing the full assertions
  and exact document append-only, injecting authoritative actor/time, and
  returning one receipt. A stale page cannot accept after claim, authority,
  version, approval, or kill-switch revocation. Identical request-key replays
  return the same receipt; conflicting replays fail.
- `get_partner_onboarding_capabilities_v1(partner_id)` returns one owner-safe
  projection with evidence IDs for claim, profile, media, agreement, exact Local
  identity, smoke test, partner consent, HEHA review, actual public visibility,
  and actual Local orderability. Legacy status or profile percentages never
  substitute for these receipts.
- `create_or_resume_partner_application_v1(request_key, application)` performs
  one server-locked, idempotent self-application transaction with an owner
  uniqueness rule and protected handling for known/invited businesses. The
  browser must never SELECT-then-INSERT a partner or convert a self-created row
  into evidence of ownership. The mutation re-checks a server-owned application
  kill switch inside the transaction; EXECUTE remains revoked until an approved
  release explicitly enables it. Identical authenticated actor/request-key
  replays return the same private result, conflicting replays fail uniformly,
  and direct-RPC BOLA, duplicate, known-invite, concurrency, revocation, and
  replay proofs are required independently of the browser flag.
- `revise_partner_profile_v1(partner_id, request_key, profile_snapshot)` is the
  sole browser edit RPC. The server selects exactly one current provenance:
  unclaimed applicant or invitation-bound operator. A router-wide append-only
  request ledger prevents the same actor/request key from crossing those modes.
  Applicant corrections may repair a typo through collision-checked,
  append-only business-key history; every prior identity key remains reserved.
  Claimed corrections keep the invitation-bound name, location, category,
  category array, and classification exact while allowing receipt-bound
  operational fields and preserving structured hours. The source-specific
  child mutators are not executable by browser roles, and raw profile updates
  cannot bypass either receipt path or drift registered identity.
- `claim_partner_invitation_v1(invite_token, request_key)` consumes an opaque,
  recipient-bound, expiring, single-use invitation and returns a private claim
  receipt for the authenticated intended operator. It must reject wrong-account,
  expired, reused, conflicting-replay, duplicate-business, and cross-tenant
  attempts without exposing whether another business or recipient exists. An
  identical replay by the same authenticated actor with the same token and
  request key returns the original receipt; every conflicting replay fails with
  the same external error. A server-owned claim kill switch must be enabled for
  the RPC to accept anything and must support immediate revocation independent
  of the client build flag.

Every protected RPC returns one privacy-preserving external denial for missing,
wrong-recipient, wrong-partner, duplicate, expired, revoked, disabled, stale,
and conflicting requests. Specific failure details belong only in a minimized,
access-controlled server audit record and must never reach the browser.

The acceptance receipt must return its immutable assertions snapshot. The
client canonical-compares that snapshot with the submitted assertions and
computes SHA-256 over UTF-8 JSON with recursively sorted object keys; the server
must use that same documented canonical representation for `assertions_sha256`.
The client then exact-compares the returned assertions digest, partner, actor,
owner, legal relationship, agreement/version, document hash, request key, and
server timestamp before showing success.

V1 claim evidence must be an opaque, recipient-bound, expiring, single-use
invite—not a generic signup, a self-attestation, manual owner_id backfill, or an
undefined alternate ownership path. Any future alternate verification method
requires its own versioned RPC, reauthentication, evidence, uniqueness,
idempotency, audit, revocation, BOLA, and independent release proof before use.
The browser receives the invite in a URL fragment, removes it from the visible
URL before rendering, retains it only in session storage, never logs it, and
sends it only to the versioned claim RPC. The server stores only the minimum
one-way token verifier and audit evidence required by the approved design.
The model must allow a verified operator such as Sachiko to complete onboarding
while preserving a separately verified authorized signer when Kyoko or another
legal representative must execute the agreement. Operational profile control
never implies legal ownership or signing authority; V1 invitation claims grant
only the `operator_only` role.

Human staff transitions are authenticated staff actions. The signed-in
`auth.uid()` must equal the recorded actor, have a verified email, and retain
the required unrevoked authority at the linearization point. A service key may
not nominate an arbitrary staff UUID. Machine-only target acknowledgements stay
separate and least-privileged.

Commercial self-application currently exposes restaurant, vendor, grocery or
farmers market, catering, and solo-chef relationships. Driver and SOM are
separate invite-only flows until their product, classification, compensation,
and legal controls are approved; they must not appear as public self-onboarding
choices merely because contract review drafts exist.

Authenticated reviewer and dedicated target-principal functions separately
authorize a release and record target acknowledgements. Their recorded actor
must be the verified signed-in principal with the current least-privilege role;
a broad service key cannot attribute a mutation to a supplied human UUID.
`get_partner_orderability_receipt_v1` is the read-only service contract for
Local's atomic order guard; it returns nothing unless
the current release and the current Local activation receipt both survive every
claim, agreement, evidence, profile-hash, and revocation check. This Swipe
packet can prove that contract, but only a matching Local-repository change and
disposable Local order proof can certify real order admission.

The target acknowledgement in this packet is still an attestor assertion; this
repository cannot independently inspect Local's storage or execute Local's
order transaction. Therefore neither a green Swipe proof nor an orderability
receipt is launch evidence by itself. Local must verify/import the receipt and
prove customer order, partner acceptance, driver handoff, delivery, cancellation,
and receipt behavior against its own disposable database before any smoke test.

The GitHub workflow and its verifier are changed by this same draft PR. Their
green result is useful exact-head evidence, not an independent trusted control,
until the repository enforces a protected base-branch workflow or SHA-pinned
reusable workflow with required review/branch protection.

## Release sequence

1. Close SWP-016 canonical baseline gates.
2. Reconcile #127 on that exact baseline without copying its blocked migration
   chain into Production.
3. Review and implement the category successor above in a disposable data-less
   environment.
4. Obtain Florida counsel/CPA/insurance approvals and register exact document
   hashes.
5. Run authenticated two-user, BOLA, immutability, replay, revocation, mobile,
   and receipt-retention tests.
6. Obtain separate founder approval before any deploy, migration, signing,
   partner invitation, publication, order activation, or Production change.

Production impact of this review-only packet: **NONE**.
