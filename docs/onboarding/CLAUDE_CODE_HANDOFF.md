# Claude Code Handoff — HEHA Swipe Canonical Onboarding

## Current status

This handoff is for planning and later implementation of the partner onboarding integration that remains user-facing inside HEHA Swipe.

Do not begin canonical database writes until:

- HEHA-ARCH-000 wording is accepted.
- Candidate-project P0 security remediation is complete.
- Migration baseline reconciliation is complete.
- ADR-001 is signed.
- Swipe ownership/account-linking strategy is approved.

## Read first

1. `docs/onboarding/HEHA_SWIPE_CANONICAL_ONBOARDING_BLUEPRINT.md`
2. `docs/onboarding/TICKET_SEQUENCE.md`
3. `docs/HEHA_SWIPE_ORDER_HUB_INTEGRATION.md`
4. Current implementations:
   - `src/components/PartnerWizard.jsx`
   - `src/components/PartnerProfileEditor.jsx`
   - `src/components/PartnerMediaManager.jsx`
5. Build 1.2 governance documents in `hehaonline/heha-order-hub`.
6. Accepted HEHA-ARCH-000 audit and remediations.

## Permanent product boundary

- HEHA Swipe remains the onboarding and discovery interface.
- HEHA Local / Order Hub handles menu, orders, operations, payouts, and Restaurant Assurance Balance.
- One HEHA ID and one canonical business record connect both.
- Do not create a second partner registration flow in Order Hub.

## First safe future implementation ticket

### HEHA-ONB-ADAPTER-001 — Isolate Swipe onboarding data access

Goal:

Introduce repository/service adapters around the current Swipe partner data calls without changing behavior or moving data yet.

Scope:

- Add:
  - `src/services/partnerOnboardingRepository.js`
  - `src/services/partnerProfileRepository.js`
  - `src/services/partnerMediaRepository.js`
- Move current Supabase queries from:
  - `PartnerWizard.jsx`
  - `PartnerProfileEditor.jsx`
  - `PartnerMediaManager.jsx`
  into the adapters.
- Preserve current table names, payloads, status behavior, media bucket, and Make.com webhook behavior.
- Add characterization tests for successful submission, direct edit, reviewed edit request, media upload request, and failed webhook behavior.
- Do not add canonical tables or dual writes.
- Do not alter live Supabase.
- Do not modify public copy except where required for testing accessibility.

Acceptance criteria:

- Existing onboarding behavior is unchanged.
- UI components no longer contain direct table queries for the covered operations.
- Webhook failure remains nonblocking.
- Current public content remains live during reviewed edits.
- Media remains private pending review.
- Tests prove user-visible behavior and error states.
- No production deployment.

## Later implementation order

1. `HEHA-ONB-ADAPTER-001` — repository boundary.
2. `HEHA-ONB-DRAFT-001` — resumable server-side onboarding drafts.
3. `HEHA-ONB-CLAIM-001` — find/claim/duplicate routing.
4. `HEHA-ONB-GOALS-001` — capability selection.
5. `HEHA-ONB-STATUS-001` — four-state Partner Hub task model.
6. `HEHA-ONB-ID-001` — canonical ID/account-linking integration.
7. `HEHA-ONB-CANONICAL-001` — canonical business write path.
8. `HEHA-ONB-ORDERS-001` — Receive Orders continuation into Local.
9. `HEHA-ONB-MIGRATE-001` — existing Swipe partner activation and migration.
10. `HEHA-ONB-LEGACY-001` — validate and retire legacy Swipe-only writes.

## Hard restrictions

- One ticket per branch and PR.
- Never edit production directly.
- Never write to both Swipe and canonical tables as a permanent target state.
- Never silently merge businesses or user accounts.
- Never force an existing partner to recreate a complete profile.
- Never mix marketing consent with order notifications.
- Never require banking for basic discovery listing.
- Never place Restaurant Assurance Balance in the basic listing form.
- Never bypass review for ownership, allergens, health claims, certification, or financial changes.
- Never expose raw internal statuses to partners.

## Evidence discipline

For each PR, distinguish:

- Repository verified.
- Live verified.
- Inferred.
- Inaccessible.

Do not claim canonical migration readiness unless the accepted audit and account-linking prerequisites support it.
