# HEHA Swipe Repository ↔ Live-Ledger Compatibility Map — 2026-08-24

Status: **DOCUMENTATION / COMPATIBILITY TRIAGE COMPLETE; EXECUTABLE BASELINE STILL BLOCKED**  
Task: `SWP-016`  
Base evidence: `main@dc8b1709b80f5cc0fe7fae79e7e980b32b085eb8`  
Extension evidence: draft PR #140 at `b8bb0f09583fa833851f69fdbc220fa6c305996d`, composed from `main@1ab63290fda9a967a36831cef50ef01b68a8c0a4` on 2026-09-03 ET

## Purpose

Account for every committed live-ledger row and every current executable migration file without treating similar names as proof of identical SQL.

This packet compares:

- the committed **96-row** live ledger;
- the current **46-file / 42-version** `supabase/migrations` tree;
- the byte-preserved historical supporter source outside the executable chain.

It does not rewrite history, infer missing SQL bodies, or authorize a baseline, migration, paid branch, Production action, Community Pass merge, Stripe action, entitlement, benefit, or launch.

## Live-ledger class codes — 96 rows

| Code | Rows | Meaning and required treatment |
|---|---:|---|
| `A` | 1 | Exact live version is byte-preserved outside the executable chain. Archive only; derive reviewed current definitions separately and never replay it to Production. |
| `N` | 18 | A current executable file has the same migration name but a different version. Compare normalized SQL/object effects before canonical use. |
| `C` | 60 | One or more current files appear related to the same object cohort. Use only as navigation for deep comparison; no body match is proven. |
| `B` | 15 | No current executable source candidate was identified. Reconstruct from sanitized current definitions while preserving the ledger row as history. |
| `D` | 2 | Two live versions share one name. Recover and compare both original SQL bodies before deciding equivalence or supersession. |

## Repository-file class codes — 46 files

| Code | Files | Canonical disposition |
|---|---:|---|
| `BC` | 37 | Candidate component only after deep metadata, normalized-effect, dependency, and security review. |
| `BS` | 6 | Useful behavior may be retained, but same-version collisions require uniquely identified canonical sections. |
| `AN` | 1 | Historical explanation, not executable reconstruction. |
| `AR` | 1 | Preserve for incident history; exclude from the future zero-build executable chain. |
| `AS` | 1 | Earlier/weaker candidate; preserve but do not select as the final definition without proof. |

## Critical conclusion

There are **zero exact version matches** between the 96 live versions and the 42 unique versions in the current executable migration tree.

Therefore:

1. the current tree is not the historical live chain;
2. name/cohort candidates are navigation aids only;
3. the future baseline must come from reviewed current definitions and explicit authority decisions;
4. the Production migration ledger remains untouched;
5. the baseline is for new data-less environments only;
6. forward changes such as Community Pass PR #128 remain separate.

## Packet

- `live-ledger-compatibility-map-2026-08-24.csv` — all 96 live versions.
- `repository-migration-disposition-map-2026-08-24.csv` — all 46 current executable files.
- `deep-metadata-capture-plan-2026-08-24.md` — staged next-evidence plan.
- `queries/deep-structure-manifest-capture.sql` — prepared, unexecuted, metadata-only first-tranche query.
- `verify-repository-ledger-map.mjs` — fail-closed verifier.
- `repository-ledger-map-manifest.sha256` — packet integrity manifest.

## Evidence boundary

Codes `N` and `C` do **not** mean SQL equivalence, complete object coverage, safe replay, final security posture, or live-to-repository provenance.

The 11 PR #140 extension rows are repository-proven forward candidates only. Blank `live_candidates` values are deliberate: no exact live-ledger edge, live equivalence, complete zero-build chain, or Production safety is claimed.

## Next bounded lane

After a separate approval, run the prepared metadata-only deep-structure capture. It must exclude application/Auth/storage rows, Vault values, secrets, provider payloads, function bodies, policy expressions, ACLs, migration-ledger contents, and all mutations.

## Source-of-truth rule

The HEHA Business Model 2026 slides are historical context only. Newest founder decisions, current operating economics, exact technical/provider evidence, current partner terms, and current legal/accounting/insurance decisions control whenever they differ.

Production impact: **NONE**.
