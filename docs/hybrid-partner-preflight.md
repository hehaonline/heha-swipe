# Hybrid partner successor — exact-head reconciliation receipt

## Exact refs reviewed

| Ref | SHA | Role |
|---|---|---|
| current `main` | `82ec41a27150847f3d461716bc58636e24babfe6` | integration base |
| PR #72 | `b76c3d47c476b81f7be1b6f2b7aafcc6e16f240d` | partnership-interest / contract donor |
| PR #117 | `5282d4ae676dbda57b196fd92f756cca839ab99d` | secure claim / ACL / deletion / concurrency donor |
| PR #120 original blocked head | `17f80c241ac11ef27d5896523511ee19210f9ac9` | superseded review snapshot |
| PR #120 pre-repair head | `cef9af2bc8785ea9732a1dca2de052b3995f1ca9` | head the P1/P2 and agreement-evidence findings were raised against, and the head both exploits were reproduced on |

PRs #72 and #117 remain donor-only and are not to be merged independently.
PR #120 is the only active hybrid implementation lane.

### Repair provenance

The repairs in this round were **recreated from the PR review findings**, not
transferred from a local commit. The referenced local repair commit
`124e12380af293aabd8fdb2d554a64aaa58d2bf4` was not reachable in this environment:
the working clone was created fresh from the remote, `git cat-file -t` reports no
such object, `git fsck --lost-found` finds no dangling objects, and the reflog
contains only fetch entries. Nothing was cherry-picked or replayed from an
unverified source. Each repair below is instead tied to the specific review thread
it closes, and each was reproduced as a failing case before being fixed.

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

## Agreement evidence model

`Official Partner requires a signed agreement` is now a structural property, not a
convention. `20260811090500_hybrid_partner_agreement_evidence.sql` adds:

| Object | Role |
|---|---|
| `public.partner_agreement_versions` | Immutable, versioned agreement documents. Retirement is one-way; a partial unique index allows exactly one current version. |
| `public.partner_agreement_acceptances` | Immutable owner acceptance evidence: partner, agreement version, owner snapshot, signer, acceptance time, signature source, evidence digest. |
| `public.partners.contract_evidence_id` | Composite FK `(contract_evidence_id, id) -> (id, partner_id)`, so evidence on a partner row provably belongs to that same partner. |
| `partners_signed_requires_evidence` | Validated CHECK: `contract_status='signed'` is unreachable without evidence. |
| `partners_official_requires_evidence` | Validated CHECK: `partnership_status='official_partner'` is unreachable without evidence. |

Two fields carry deliberately different lifetimes. `accepted_owner_id` has **no**
foreign key: it is the immutable snapshot of who owned the profile at acceptance
time and must survive Auth deletion as evidence. `accepted_by` **does** carry
`ON DELETE SET NULL`: when the accepting account is deleted the evidence stops
being attributable to a live signer and the approval gate refuses it.

`approve_heha_partnership` now takes `(p_partner_id, p_agreement_acceptance_id)`.
The evidence-free single-argument entry point is **dropped outright**, so no caller
retains a path to `signed` / `official_partner` without an acceptance record. The
RPC locks partner-first then evidence, and refuses evidence that is missing, for a
different partner, revoked, terminated, signed by a different owner than the current
one, signed by a now-deleted account, or bound to a superseded agreement version.
`contract_signed_at` is copied from the evidence rather than invented with `now()`.
Lifecycle audit rows reference the acceptance and version by ID only and never copy
the agreement document digest or the acceptance digest.

Revoking evidence that a partner is currently relying on immediately unwinds that
partner's signed contract and Official Partner flag: a signed contract cannot
outlive the evidence that produced it.

**Still an explicit Geronimo/legal gate:** what qualifies as a legally valid
signature, and the retention / anonymization policy for terminal evidence. This
migration models and enforces the evidence chain; it does not decide those.

The combined partner-publication RC also stores append-only HEHA publication
review events. Each event retains immutable snapshots of the current partner
owner UUID and the approving/rejecting `super_admin` or `pm_admin` UUID, alongside
the exact reviewed public-profile snapshot and SHA-256 hash. Those identifiers
are private and never enter a public view, but their legal retention and any
future anonymization procedure remain an explicit release-approval gate. They
must not be erased ad hoc because doing so would destroy the evidence chain that
keeps owner consent separate from HEHA staff publication review.

## Caller-supplied context is never authorization

Two review findings against head `cef9af2bc8785ea9732a1dca2de052b3995f1ca9` were
reproduced against a disposable database before repair, and are closed by
`20260811090600_hybrid_partner_context_authenticity.sql`:

- **P1 — `owner_release` bypassed the capability requirement.** The gate exempted
  that one literal context value. An authenticated owner of a pre-approval profile
  could set `app.hybrid_partner_context='owner_release'`, change any non-lifecycle
  protected column, have the gate return early because no lifecycle field changed,
  and have `guard_partner_owner_self_service` accept the write on the same trusted
  string. Reproduced: `rating` 0 -> 5 and `routing_status` `suggested` -> `approved`
  both succeeded with the context set, and were denied without it.
- **P2 — owner-authored provenance erasure read as Auth FK cleanup.** The cleanup
  exemption was satisfied by any UPDATE that nulled `claimed_by` and changed nothing
  else, which is exactly what an owner can issue through the owner UPDATE policy.
  Reproduced: `claimed_by` went to NULL while `claim_status` stayed `claimed` and
  `owner_id` stayed live.

The repair makes every non-empty context, `owner_release` included, require a
private capability row keyed to `(backend_pid, transaction_id, partner_id)`.
`authorize_partner_lifecycle_mutation` still refuses to mint `owner_release`, so the
only producer is the gate itself, and only on structural evidence that the
referenced Auth account is genuinely gone (`not exists (select 1 from auth.users
...)`) — a condition a live owner's UPDATE cannot satisfy. The status guard, the
owner self-service guard and the owner-release provenance trigger all verify the
capability rather than the GUC string.

Because later corrective migrations supersede earlier definitions of the same
functions, **corrective re-apply must stay in lexical order**; `090600` is the last
file to define the gate and both guards. CI replays the corrective set with a sorted
glob and reruns the full behavioral proof afterwards, so convergence is proved
rather than assumed.

## Executable proof package

PR #120 now carries an isolated GitHub Actions proof using pinned Supabase CLI
`2.112.0` and a synthetic current-main-shaped fixture. It executes:

- migration apply and corrective re-apply, with the behavioral proof rerun after
  re-apply to prove the converged state;
- seven-privilege claim-table and agreement-evidence ACL assertions, including that
  neither `authenticated` nor `service_role` holds direct DML on evidence tables;
- verified/unverified/wrong/deleted recipient cases;
- canonical Partner ID + saves/swipes preservation;
- owner self-promotion and direct owner-assignment denial;
- **every caller-supplied lifecycle context value, `owner_release` included, is
  rejected without a private capability** (P1 regression);
- **owner-authored `claimed_by` erasure is denied and never audited as a release,
  while genuine Auth-deletion cleanup still succeeds** (P2 regression);
- partnership-interest consent and a Business A / Business B authorization matrix:
  cross-business read of interest requests and lifecycle audit rows, cross-business
  opt-out, review, listing-status, claim-invite and agreement-version calls, and a
  cross-business partner UPDATE that must match zero rows under RLS;
- agreement evidence: immutability of versions and acceptances, version
  supersession, and **negative approval cases for missing, null, wrong-partner,
  stale/superseded-version, revoked, terminated, wrong-owner and deleted-signer
  evidence**, each asserted to leave no signed state and no approval audit row;
- a positive exact-head approval where `contract_signed_at` is taken from the
  evidence, plus proof that direct SQL cannot manufacture a signed contract and
  that a reclaiming owner cannot inherit the prior owner's evidence;
- public compatibility and immediate opt-out removal;
- account-deletion/claim provenance behavior with evidence retention;
- genuine multi-session partner-first lock races: replacement-vs-claim,
  revoke-vs-claim, claim-wins-vs-revoke, and **redeem-vs-redeem in both a held-lock
  interleaving and a six-session simultaneous contention run, each asserting no
  `40P01`, exactly one successful claim and exactly one `claim_redeemed` audit
  event**;
- build, diff check and evidence sensitivity scan;
- an exact-head gate that fails the run unless the proved tree is, or contains, the
  PR head commit.

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
