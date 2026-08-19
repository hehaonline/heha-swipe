# SWP-016 Migration Lineage Evidence

Status: **Corrective documentation review required; executable canonical baseline remains blocked**  
Task: `SWP-016`  
Issue: https://github.com/hehaonline/heha-swipe/issues/85  
Reviewed historical tree anchor: merge commit `7b32ae605840e50ff1085372e988c980ab538498`

## Scope

This directory contains sanitized evidence and architecture decisions for repairing HEHA Swipe migration lineage.

The evidence package and this refresh are documentation-only. They must not:

- modify `supabase/migrations`;
- add executable migration SQL;
- alter any Production schema, configuration, data or migration ledger;
- apply any draft migration;
- copy customer, partner, payment or operational rows.

## Evidence labels

- `RP` — repository-proven
- `LP` — live-ledger-proven through independently reproducible live access
- `DR` — decision-record-proven
- `I` — inferred
- `U` — unknown / access required

## Evidence boundary

`repository-inventory.csv` is anchored to the exact repository tree at merge commit `7b32ae605840e50ff1085372e988c980ab538498` and remains a historical repository snapshot.

The committed `live-ledger-2026-07-19.csv` is a historical 92-row snapshot whose live provenance was originally `U`. It remains preserved rather than rewritten.

A new authorized read-only connector session on 2026-08-19 independently reproduced the current live migration ledger. `live-ledger-2026-08-19.csv` records 96 rows with evidence label `LP`; `live-ledger-refresh-2026-08-19.md` records the query boundary, counts, duplicate-name result, PR #69 catalog comparison and zero-Production-impact receipt.

Neither ledger snapshot is a schema dump or a complete canonical rebuild chain. Ledger presence proves recorded ordering/name metadata, not that every historical SQL body is available or safe to replay.

## 2026-08-19 live refresh

Direct live evidence now establishes:

- 96 migration rows and 96 distinct versions; **[LP]**
- first version `20260531101429`; latest version `20260812220624`; **[LP]**
- one duplicate migration name, `analytics_triggers_for_partner_counters`, at versions `20260602213920` and `20260602220224`; **[LP]**
- four rows added after the old 92-row snapshot:
  - `20260720132527_partner_multi_categories`;
  - `20260720132617_partner_multi_categories_view_security_invoker`;
  - `20260805123842_sec002_revoke_public_execute_on_trigger_functions`;
  - `20260812220624_update_founding_neighbor_pass_preferences`; **[LP]**
- Production has 45 public base tables; **[LP]**
- a founder-approved disposable Supabase branch inherited zero application migration rows and zero initial application public tables; **[LP]**
- PR #69's recovered supporter/vibe migration matches the corresponding live columns, constraints, indexes, triggers, policies, RLS state and supporting function semantically; **[LP + RP]**
- the approved canonical-baseline strategy remains necessary because restoring PR #69 alone cannot reproduce the 45-table Production schema. **[DR + LP]**

## Accepted architecture decision

Use an immutable historical evidence archive plus a clean, reviewed canonical baseline for new environments.

Canonical implementation remains blocked until:

- the current repository and 96-row live ledger receive an updated compatibility map;
- required live object definitions are captured and reviewed without copying business data;
- duplicate migrations receive written compatibility decisions;
- the canonical project and ONE HEHA identity boundary are confirmed;
- an independent security/database review approves the executable plan;
- a clean disposable branch builds from zero and passes schema/type/advisor/behavior/rollback proof;
- Geronimo separately approves any future paid environment and final live action.

## Files

- `repository-inventory.csv` — 35-file historical migration inventory anchored to merge commit `7b32ae605840e50ff1085372e988c980ab538498`
- `live-ledger-2026-07-19.csv` — preserved 92-row historical snapshot; original provenance remains `U`
- `live-ledger-2026-08-19.csv` — directly reproduced current 96-row live ledger; evidence `LP`
- `live-ledger-refresh-2026-08-19.md` — read-only live refresh, disposable-branch finding and PR #69 semantic catalog verification
- `object-dependency-map.md` — missing baseline/object families, rechecked against the historical 35-file tree
- `duplicate-compatibility-map.md` — duplicate identifier decisions
- `canonical-baseline-decision.md` — approved strategy and PR separation
- `production-preflight.md` — no-go conditions and future proof plan
- `evidence-manifest.sha256` — historical evidence-file integrity manifest; a refreshed manifest must be generated and independently checked before this successor may merge

## Current conclusion

- The 2026-08-19 live ledger contains 96 rows / 96 distinct versions. **[LP]**
- The live ledger still begins with corrective migrations rather than a complete initial-schema baseline. **[LP + DR]**
- The repository tree remains corrective rather than a complete rebuild history. **[RP]**
- PR #69 is semantically consistent with its corresponding live supporter/vibe object family and is suitable for source-lineage restoration after its own exact-head review. **[LP + RP]**
- PR #69 must not be manually applied to the already-recorded Production project. **[LP]**
- A normal disposable branch did not reproduce the live migration ledger or application schema. **[LP]**
- The smallest safe path remains: preserve history, restore verified missing source, create a separately reviewed canonical baseline for new environments, prove it in a disposable branch, and leave Production history untouched. **[DR]**
- This documentation refresh creates no runtime or Production authorization. **[RP]**
