# HEHA Swipe Canonical Onboarding Ticket Sequence

This sequence preserves HEHA Swipe as the partner-facing onboarding interface while moving identity and business data toward the approved canonical HEHA architecture.

One approved ticket → one branch → one pull request → one acceptance-test set.

## Current gating work outside this sequence

Before canonical integration:

- Accept HEHA-ARCH-000 wording.
- Complete ARCH-000-R1 nutrition RLS remediation.
- Complete ARCH-000-R2 public-view safety review.
- Complete ARCH-000-R3 migration-baseline reconciliation.
- Complete recovery/ingest Edge Function authorization review.
- Obtain Shahid backup/PITR/reliability statement.
- Approve ADR-001.

## Phase A — Safe preparation

### HEHA-ONB-DOC-001 — Current onboarding field and workflow inventory

Document:

- Every field used by PartnerWizard.
- Every editable PartnerProfileEditor field.
- Every media type and review status.
- Existing RLS and ownership assumptions.
- Existing Make.com webhook payload.
- Existing public profile dependencies.

Acceptance:

- Exact source file and table column for every field.
- Public/private/risk classification.
- No code or database change.

### HEHA-ONB-ADAPTER-001 — Isolate onboarding data access

Create repository adapters while preserving current behavior.

Blocked until the active code branch and test strategy are approved, but it may occur before canonical writes because it does not change the data target.

### HEHA-ONB-TEST-001 — Characterization test foundation

Add test runner and coverage for:

- Partner submission.
- Validation.
- Nonblocking Make webhook failure.
- Direct preapproval edit.
- Approved-profile change request.
- Media upload request.
- Media removal request.
- Ownership filtering.

## Phase B — Better onboarding on current data model

### HEHA-ONB-DRAFT-001 — Resumable onboarding drafts

Requirements:

- Server-side draft.
- Auto-save.
- Current step.
- Last saved indicator.
- Resume across devices.
- Retry after save failure.
- Safe optional deferral.

Do not publish a draft.

### HEHA-ONB-DUPLICATE-001 — Find and duplicate warning

Search existing partner records before creating a new one.

Possible outcomes:

- Continue own draft.
- Claim existing business.
- Request access.
- Register new business.
- Route uncertainty to HEHA review.

Never auto-merge.

### HEHA-ONB-CLAIM-001 — Business claim and authorization workflow

Collect relationship and least-burdensome evidence.

Internal statuses:

- unverified
- submitted
- needs_information
- verified_representative
- disputed
- rejected

Partner-facing mapping remains the four approved states.

### HEHA-ONB-GOALS-001 — Capability selection

Capabilities:

- Get discovered.
- Receive orders.
- Create Community Offer.
- Join marketing opportunities.
- Start certification review.

No optional capability is preselected.

## Phase C — Partner Hub simplification

### HEHA-ONB-TASKS-001 — Needs Your Attention queue

One queue containing:

- Ownership requests.
- Missing profile fields.
- Media corrections.
- Review corrections.
- Order-readiness setup.
- Payout setup.
- Marketing approvals.

Each task has one owner, one explanation, one next action, and one resolution condition.

### HEHA-ONB-STATUS-001 — Four partner-facing states

Map all raw statuses to:

- Draft.
- Needs You.
- HEHA Is Reviewing.
- Ready / Live.

Do not expose queue, migration, webhook, or retry enums.

### HEHA-ONB-PREVIEW-001 — Destination previews

Provide:

- Swipe preview.
- Website preview when available.
- Local readiness preview when Receive Orders is selected.

## Phase D — Canonical identity and business integration

Blocked until ADR-001 and HEHA ID architecture are accepted.

### HEHA-ONB-ID-001 — Existing Swipe account linking

- Link existing auth user to HEHA ID.
- Detect duplicate email/provider identities.
- Preserve current profile.
- Require current Terms/Privacy acceptance.
- Do not inherit stale marketing consent.

### HEHA-ONB-BUSINESS-001 — Canonical business identifiers

- Map source partner IDs to canonical business IDs.
- Store source-system provenance.
- Preserve public URL mapping.
- Avoid treating current owner_id as complete ownership proof.

### HEHA-ONB-CANONICAL-001 — Canonical draft writes

Switch adapter implementation from legacy Swipe tables to approved canonical business-draft APIs.

Required:

- Feature flag.
- Rollback path.
- Comparison logging without secrets.
- No permanent dual-write.
- Public output equivalence tests.

### HEHA-ONB-PROJECTION-001 — Swipe reads public projections

Discovery cards and profiles read only approved public-safe projections.

## Phase E — Receive Orders continuation

### HEHA-ONB-ORDERS-001 — Order-readiness capability card

Inside Swipe Partner Hub:

> Receive orders through HEHA

Show progress for:

- Location.
- Hours.
- Fulfillment.
- Menu.
- Ingredients/allergens.
- Notification method.
- Agreement.
- Payout setup.
- Optional Restaurant Assurance Balance.

### HEHA-ONB-LOCAL-001 — Shared-session handoff to Local

- No second login.
- No second business registration.
- Preserve current business and task context.
- Return to Partner Hub after completion.
- Handle expired session safely.

## Phase F — Existing-partner migration

### HEHA-ONB-MIGRATE-001 — Partner migration dry run

- Map all partner records.
- Classify owner-linked, unowned, duplicate, needs-split, and inactive records.
- Inventory external media.
- Produce no live write.

### HEHA-ONB-MIGRATE-002 — Trusted pilot migration

Pilot a small set with:

- Known owner.
- Current consent.
- Profile comparison.
- Media-right confirmation.
- Rollback plan.

### HEHA-ONB-MIGRATE-003 — Batch migration and activation

Migrate profile data, invite users to activate/link accounts, and route conflicts to review.

### HEHA-ONB-LEGACY-001 — Retire legacy writes

Only after:

- Canonical writes are stable.
- Public projections match.
- Rollback window passes.
- Migration reconciliation completes.

## Definition of completion

The onboarding integration is finished only when:

- HEHA Swipe remains the clear onboarding home.
- A business enters information once.
- Drafts resume.
- Existing businesses can be claimed safely.
- One HEHA account works across Swipe and Local.
- Public profiles remain stable during edits.
- Receive Orders continues into Local without duplicate registration.
- Existing partners retain their profiles and history.
- No permanent dual-write remains.
