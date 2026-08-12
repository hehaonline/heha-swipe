# Hybrid partner successor — read-only preflight and Production freeze

## Exact base receipt

| Ref | SHA | Receipt |
|---|---|---|
| Available integration checkout | `82ec41a27150847f3d461716bc58636e24babfe6` | Local `work` branch created from `FETCH_HEAD` |
| Remote `main` | **UNRESOLVED** | No remote/ref; GitHub transport returned HTTP 403 |
| PR #72 head | **UNRESOLVED** | No PR ref/object and GitHub unavailable |
| PR #117 head | **UNRESOLVED** | No PR ref/object and GitHub unavailable |

The available integration checkout is the only safe implementable base. This is not
an assertion that it equals remote `main`. Nova/ChatGPT must compare this successor
with the exact three heads before readiness. PRs #72 and #117 were not modified.

## Dependency and collision inventory

`public.partners` is a missing-baseline object: no migration creates it. Current
migrations touch it through routing columns/constraints and public routing views
(`20260705001100`–`01700`), owner RLS and the default-deny future-column guard
(`20260706093000`, replaced by `20260720093000`), approval RPC hardening
(`20260626120000`, replaced by `20260707045848`), profile/media/offer request tables
and triggers (`20260706122000`, `143000`, `160000`), and multi-category view repair
(`20260720093100`). Frontend dependencies read `owner_id`, legacy `status`, and
`heha_partner` in `CommunityPassTab`, `ProfileTab`, `PartnerWizard`, and partner
profile/media/offer editors. The legacy fields are retained for compatibility.

There are two distinct files at timestamp `20260705001400`; timestamp alone cannot
prove order. The repository ledger also records unknown live definitions, grants,
extensions, and applied-history state. No remote open-PR collision inventory could
be obtained. These are release blockers, not reasons to rewrite history.

## Forward mapping (no history rewrite)

| Existing evidence | Claim | Partnership | Contract | Listing |
|---|---|---|---|---|
| `owner_id is null` | `unclaimed` | unchanged/default | unchanged/default | mapped below |
| `owner_id is not null` | `claimed` | unchanged/default | unchanged/default | mapped below |
| `heha_partner=false/null` | as above | `not_requested` | `not_required` | mapped below |
| `heha_partner=true` | as above | `under_review` | `not_signed` | mapped below |
| status `live/listed/approved` | as above | as above | as above | `listed` |
| status `removed/rejected` | as above | as above | as above | `removed` |
| any other/unknown status | as above | as above | as above | `hidden` (fail closed) |

Legacy certification never infers a signed contract or Official Partner status.
The permanent `partners.id` is neither replaced nor deleted. Unknown donor-only
values from #72/#117 must be added to this mapping or rejected in exact-head review.

## Proof matrix and unresolved gates

The SQL proof checks grants, object presence, state constraints, and absence of
owner policies on secrets/audit. RPCs lock rows in invitation→partner order, bind a
single-use SHA-256 token to a verified JWT email, preserve the partner ID, keep a
claim independent from partnership, and reserve review/approval for internal roles.
The shell proof uses two actual `psql` sessions.

Still blocked without a lineage-faithful disposable database and donor heads:
migration clean apply/re-apply; complete fixture transition matrix; Business A/B
RLS execution; deletion→reclaim with real `auth.users` cascades; duplicate/split
fixture execution; multi-session execution; and donor-specific value mapping.

## Explicit Production freeze

Do not apply this migration to Production; change Auth; create/rotate secrets;
activate claims; merge duplicates; transfer media; deploy; mark ready; merge;
enable auto-merge; or close the issue. Stop after the draft successor PR for
Nova/ChatGPT exact-head review and Geronimo-only Production decisions.
