# Hybrid partner successor — exact-head reconciliation receipt

## Exact refs reviewed

| Ref | SHA | Role |
|---|---|---|
| current `main` | `82ec41a27150847f3d461716bc58636e24babfe6` | integration base |
| PR #72 | `b76c3d47c476b81f7be1b6f2b7aafcc6e16f240d` | partnership-interest / contract donor |
| PR #117 | `5282d4ae676dbda57b196fd92f756cca839ab99d` | secure claim / ACL / deletion / concurrency donor |
| PR #120 original blocked head | `17f80c241ac11ef27d5896523511ee19210f9ac9` | superseded review snapshot |

PRs #72 and #117 remain donor-only and are not to be merged independently.
PR #120 is the only active hybrid implementation lane.

## Current-main dependencies reconciled

Current main uses:

- the default-deny future-column owner guard from `20260720093000_partner_multi_categories.sql`;
- `public.public_swipe_partners` from `20260720093100_partner_multi_categories_view_security_invoker.sql`;
- legacy `status` for review/publication workflow;
- legacy `heha_partner` in public/client rendering;
- nullable `owner_id` as the existing profile-owner link.

The hybrid successor therefore preserves the current owner guard behavior while adding
narrow private workflow contexts, adds `listing_status='listed'` as an additional
fail-closed public-view gate, and makes public/legacy `heha_partner` a compatibility
mirror of `partnership_status='official_partner'` rather than a second relationship
source of truth.

## Donor reconciliation

### PR #117 claim contract retained

The authoritative object is `public.partner_claim_invites`, not the superseded
`partner_claim_invitations` draft name. The successor retains:

- SHA-256-only token storage;
- `intended_user_id` / normalized-email exclusive recipient binding;
- verified `auth.users.email_confirmed_at` resolution;
- `ON DELETE SET NULL` recipient tombstones;
- 15-minute to 30-day expiry limits;
- deterministic table/function ACL reset;
- canonical `partners.id` preservation;
- `partner_id ON DELETE RESTRICT`;
- partner-first, invitation-second lock ordering;
- replace/revoke/redeem serialization;
- no direct owner transfer outside verified claim context.

### PR #72 evidence model retained

The successor retains `public.partner_interest_requests` and its consent-bearing
owner questionnaire, one-active-request protection, owner/internal RLS split and
internal approval concept. It maps the relationship state into the founder-approved
independent `partnership_status` and `contract_status` fields rather than retaining
#72's overloaded relationship field.

## Hybrid state mapping

| Existing evidence | Claim | Partnership | Contract | Listing |
|---|---|---|---|---|
| `owner_id is null` | `unclaimed` unless donor invite evidence says `claim_invited` | mapped below | mapped below | mapped below |
| `owner_id is not null` | `claimed` | mapped below | mapped below | mapped below |
| legacy `heha_partner=false/null` | as above | `not_requested` | `not_required` | mapped below |
| legacy `heha_partner=true` without signed-contract evidence | as above | `under_review` | `not_signed` | mapped below |
| #72 `partnership_requested` | as above | `requested` | `not_signed` | mapped below |
| #72 `official_partner` + signed contract + owner | `claimed` | `official_partner` | `signed` | mapped below |
| #117 `opted_out` | as above | no automatic partnership inference | no automatic contract inference | `opted_out` |
| #117 `removed` | as above | no automatic partnership inference | no automatic contract inference | `removed` |
| legacy status `approved/live/listed` | as above | as above | as above | `listed` |
| legacy status `removed/rejected` | as above | as above | as above | `removed` |
| unknown/ambiguous publication evidence | as above | fail closed | fail closed | `hidden` |

A claim never creates partnership approval. A partnership request never publishes,
certifies or makes Local orderable. Official Partner requires a claimed profile plus
a signed agreement in this soft-launch contract.

## Executable proof package

PR #120 now carries an isolated GitHub Actions proof using pinned Supabase CLI
`2.112.0` and a synthetic current-main-shaped fixture. It executes:

- migration apply and re-apply;
- seven-privilege claim-table ACL assertions;
- verified/unverified/wrong/deleted recipient cases;
- canonical Partner ID + saves/swipes preservation;
- owner self-promotion and direct owner-assignment denial;
- partnership-interest consent and Business A/B BOLA behavior;
- internal review + super-admin approval;
- public compatibility and immediate opt-out removal;
- account-deletion/claim provenance behavior;
- genuine multi-session partner-first lock races: replacement-vs-claim,
  revoke-vs-claim and claim-wins-vs-revoke;
- build, diff check and evidence sensitivity scan.

The repository-wide SWP-016 clean-history replay remains a separate migration-lineage
blocker; this focused fixture proves the exact affected integration surface but does
not pretend the historical repository can yet reconstruct from migration zero.

## Still intentionally blocked

- SWP-016 canonical migration baseline / historical replay;
- automatic duplicate/split-profile reconciliation (must remain manual/fail-closed);
- media-rights decisions and any media transfer;
- final retention/anonymization policy for terminal evidence;
- ADR/cutover approval and all Production actions.

## Explicit Production freeze

Do not apply this migration to Production; change Auth; create or rotate secrets;
activate real claims; merge duplicates; transfer media; activate the Local bridge;
promote a Vercel Production deployment; mark this PR ready; merge; or enable
auto-merge. A successful disposable proof is evidence for exact-head review, not
Production authorization.
