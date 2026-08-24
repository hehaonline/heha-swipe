# SWP-016 Migration Lineage Evidence

Status: **COMPATIBILITY MAPPING IN REVIEW; EXECUTABLE CANONICAL BASELINE BLOCKED**  
Task: `SWP-016`  
Issue: https://github.com/hehaonline/heha-swipe/issues/85

## Purpose

Preserve HEHA Swipe database history, document the current live contract without copying business data, and prepare one independently reviewed canonical baseline for new data-less environments.

This directory is evidence and planning. Unless a file is explicitly approved later as executable baseline SQL, nothing here authorizes a Supabase migration, Production change, Stripe action, entitlement, benefit, deployment, or launch.

## Evidence labels

- `RP` — repository-proven
- `LP` — live-ledger or live-catalog metadata proven through authorized read-only access
- `DR` — decision-record-proven
- `I` — inference, explicitly labeled
- `U` — unknown / additional evidence required

## Current verified state

1. **PR #69 merged** at `955ae8842df66fb7639b78aa5ecf54850b00d06d`.
   - The recovered `20260614102924` supporter/vibe SQL is preserved byte-for-byte under `historical-sql/`.
   - It is outside `supabase/migrations` and must never be manually replayed to Production.

2. **PR #131 merged** at `45b5dcbd14fb68911226792b2fca5c6cb636daca`.
   - The historical 92-row and current 96-row ledger evidence, capture contracts, and fail-closed verification tooling are on `main`.
   - The 96-row artifact is internally reproducible, but its independent live-source provenance remains `U` (**unknown / blocked**) until a separately authorized recapture uses the committed query and exact byte contract. The compatibility map does not close that gate.

3. **PR #132 merged** at `dc8b1709b80f5cc0fe7fae79e7e980b32b085eb8`.
   - The sanitized top-level live-object manifest verifies 45 tables, 5 views, 39 functions, 46 triggers, 133 policies, and 6 extensions.
   - All 45 public tables report RLS enabled; zero report FORCE RLS.
   - This is structural evidence, not a BOLA or full-schema proof.

4. The committed `supabase/migrations` tree contains 35 files using 31 unique versions and is corrective rather than a complete zero-build chain.

5. A founder-approved ordinary Supabase branch inherited no HEHA application schema or application migration ledger.

6. Community Pass PR #128 passed isolated additive tests but remains separate, draft, unmerged, and blocked on lineage-faithful current-schema proof and all other launch gates.

7. The Production migration ledger remains untouched.

## Accepted architecture

Use:

1. immutable historical evidence;
2. a reviewed current-definition manifest;
3. a separately reviewed canonical baseline for new data-less environments;
4. independent forward migrations after that baseline;
5. an untouched Production ledger.

Do not reconstruct history by renaming, reordering, or blindly replaying incomplete files.

## Current packet

- `live-ledger-compatibility-map-2026-08-24.csv` — disposition for all 96 live-ledger rows.
- `repository-migration-disposition-map-2026-08-24.csv` — disposition for all 35 current executable migration files.
- `repository-disposition-expectations-2026-08-24.csv` — independently reviewed, hash-bound repository class and full candidate-edge expectations.
- `repository-ledger-compatibility-summary-2026-08-24.md` — conclusions and evidence limits.
- `deep-metadata-capture-plan-2026-08-24.md` — staged next-evidence plan.
- `queries/deep-structure-manifest-capture.sql` — prepared, unexecuted, metadata-only query for the first deep-structure tranche.
- `verify-repository-ledger-map.mjs` — fail-closed row-semantic, bidirectional-edge, and current-directory verifier.
- `test-repository-ledger-map-negative.mjs` — aggregate-preserving and edge-corruption controls that must be rejected even after fixture hashes are refreshed.
- `repository-ledger-map-manifest.sha256` — packet integrity manifest.

## Historical and supporting evidence

- `repository-inventory.csv` — 35-file repository inventory.
- `live-ledger-2026-07-19.csv` — preserved historical 92-row snapshot.
- `live-ledger-2026-08-19.csv` — current 96-row ledger evidence.
- `live-ledger-refresh-2026-08-19.md` — read-only refresh receipt.
- `live-object-manifest-summary-2026-08-19.md` — verified top-level object summary.
- `live-object-manifest-capture-2026-08-24.md` and part files — hash-bound sanitized catalog evidence.
- `object-dependency-map.md` — missing baseline/object families.
- `duplicate-compatibility-map.md` — explicit duplicate handling.
- `canonical-baseline-decision.md` — approved strategy and PR separation.
- `production-preflight.md` — no-go conditions and future proof plan.

## Remaining gates

Before executable baseline SQL or another paid branch:

1. resolve the current 96-row ledger's `U` live-source-provenance gate through a separately authorized exact-byte recapture;
2. independently approve a private/no-log execution path and server-side redaction boundary before any deep metadata read;
3. capture and verify the server-side-sanitized deep-structure inventory using presence/allowlisted flags only; raw definitions, comments, enum labels, sequence-owner role names, and public fingerprints remain blocked;
4. capture and review views, functions, triggers, RLS expressions, grants, and effective access;
5. document provider-managed Storage/Auth/cron/Edge Function requirements without secrets;
6. settle ONE HEHA identity and legacy-versus-current authority boundaries;
7. obtain independent database/security review;
8. source-control the exact zero-build and rollback/forward-fix procedure;
9. provide the expected runtime and cost;
10. obtain separate founder approval;
11. prove the build on a data-less disposable branch and delete it immediately afterward.

## Permanent no-go rules

Do not:

- alter Production or its migration ledger;
- copy customer, partner, payment, order, profile, Auth, or storage rows;
- commit secrets, tokens, credentials, Vault values, or provider payloads;
- infer SQL equivalence from similar names;
- put rollback or historical archive files into the future executable zero-build chain;
- fold Community Pass PR #128 into the baseline silently;
- create a paid environment without exact cost approval;
- activate Stripe, billing, entitlements, HEHA Credit, partner benefits, delivery waivers, or public launch through this evidence lane.

## Source-of-truth rule

The HEHA Business Model 2026 slides are historical context only. Newest explicit founder decisions, current operating economics, exact technical/provider evidence, current partner terms, and current legal/accounting/insurance decisions control whenever they differ.

Production impact: **NONE**.
