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

A new authorized read-only connector session on 2026-08-19 reported the current live migration ledger. `live-ledger-2026-08-19.csv` records 96 internally consistent rows with evidence label `LP`; `live-ledger-refresh-2026-08-19.md` records the evidence boundary, counts, duplicate-name result, the earlier supporter-catalog claim and zero-Production-impact receipt. The exact query contract and offline verifier were added on 2026-08-20. Independent live provenance remains blocked until a sanitized recapture is committed and checked.

PR #69 was squash-merged on 2026-08-21 at merge commit `955ae8842df66fb7639b78aa5ecf54850b00d06d`. It preserves the recovered supporter/vibe SQL byte-for-byte under `docs/migration-lineage/historical-sql/` as **non-executable historical evidence**. That repository preservation is `RP`. The earlier connector claim that the archived source equals the live catalog is not independently reproducible from committed normalized bytes and remains `U` for canonical-baseline use.

Neither ledger snapshot nor the historical SQL archive is a schema dump or a complete canonical rebuild chain. Ledger presence proves recorded ordering/name metadata, not that every historical SQL body is available or safe to replay.

## 2026-08-19 live refresh

Reported live evidence established:

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
- a prior connector receipt reported that the recovered supporter/vibe SQL matched live definitions, but the normalized rows behind its digest are not committed; independent equality is **[U]** pending a new sanitized capture;
- the approved canonical-baseline strategy remains necessary because the archived PR #69 source alone cannot reproduce the 45-table Production schema. **[DR + LP]**

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
- `live-ledger-2026-08-19.csv` — reported current 96-row live ledger; evidence label `LP`, with fresh independent recapture still pending
- `live-ledger-refresh-2026-08-19.md` — read-only live refresh receipt, disposable-branch finding and corrected supporter-catalog evidence boundary
- `historical-sql/20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql` — byte-preserved, non-executable historical source merged by PR #69
- `historical-sql/20260614102924_add_supporter_payments_subscriptions_vibe_settings.provenance.md` — source hashes, founder disposition and corrected evidence boundary
- `queries/live-ledger-capture.sql` — exact read-only ledger query and deterministic CSV capture contract
- `queries/pr69-supporter-catalog-capture.sql` — bounded read-only supporter/vibe catalog query and deterministic JSONL contract
- `verify-evidence.mjs` — dependency-free offline ledger/delta/duplicate/manifest verifier; repository evidence only
- `verify-pr69-catalog.mjs` — fail-closed two-artifact comparator for future sanitized live and recovered-source catalogs; synthetic self-test only until both artifacts exist
- `object-dependency-map.md` — missing baseline/object families, rechecked against the historical 35-file tree
- `duplicate-compatibility-map.md` — duplicate identifier decisions
- `canonical-baseline-decision.md` — approved strategy and PR separation
- `production-preflight.md` — no-go conditions and future proof plan
- `evidence-manifest.sha256` — SHA-256 manifest for historical and current evidence files; it must be recalculated against the exact review head before merge

## Current conclusion

- The committed 2026-08-19 ledger contains 96 rows / 96 distinct versions and passes repository-consistency checks. **[RP]**
- Its live-source provenance remains pending a fresh authorized recapture under the committed query contract. **[U]**
- The reported live ledger begins with corrective migrations rather than a complete initial-schema baseline. **[LP + DR]**
- The repository tree remains corrective rather than a complete rebuild history. **[RP]**
- PR #69 is merged as non-executable historical evidence; its SQL bytes and hashes are repository-proven. **[RP]**
- Semantic equality between that archive and the current live supporter/vibe catalog remains **UNKNOWN** until two sanitized catalog artifacts pass `verify-pr69-catalog.mjs`. **[U]**
- The archived SQL must not be manually applied to the already-recorded Production project. **[DR + RP]**
- A normal disposable branch did not reproduce the reported live migration ledger or application schema. **[LP]**
- The smallest safe path remains: preserve history, capture current definitions, create a separately reviewed canonical baseline for new environments, prove it in a disposable branch, and leave Production history untouched. **[DR]**
- This documentation refresh creates no runtime or Production authorization. **[RP]**
