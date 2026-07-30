# SWP-016 Migration Lineage Evidence

Status: **Architecture approved for PR A only**  
Task: `SWP-016`  
Issue: https://github.com/hehaonline/heha-swipe/issues/85  
Source branch: `docs/swp-016-migration-lineage-evidence`

## Scope

This directory contains sanitized evidence and architecture decisions for repairing HEHA Swipe migration lineage.

PR A is documentation-only. It must not:

- modify `supabase/migrations`;
- add executable migration SQL;
- create a Supabase branch or project;
- alter any migration ledger;
- modify PR #82;
- access or change production data.

## Evidence labels

- `RP` — repository-proven
- `LP` — live-ledger-proven through independently reproducible live access
- `DR` — decision-record-proven
- `I` — inferred
- `U` — unknown / access required

## Evidence boundary

Repository facts can be verified at the reviewed PR head. The committed `live-ledger-2026-07-19.csv` is a sanitized 92-row snapshot, but this PR does not include independently reproducible live-ledger provenance. Its row-level live-verification labels therefore remain `U` until an authorized independent reviewer reproduces the export. The committed snapshot may be inspected as repository evidence; it must not be treated as proof of current live state.

## Accepted architecture decision

Use an immutable historical evidence archive plus a clean, reviewed canonical baseline for new environments.

This approval applies only to PR A. Canonical implementation remains blocked until:

- ADR-001 confirms the canonical project and identity boundary;
- candidate-project P0 findings are resolved or explicitly accepted;
- missing live definitions are captured and reviewed;
- duplicate migrations receive written compatibility decisions;
- an independent security review approves the executable plan;
- Geronimo approves any paid Supabase environment.

## Files

- `repository-inventory.csv` — current-tree migration inventory
- `live-ledger-2026-07-19.csv` — sanitized ledger snapshot; live provenance remains `U`
- `object-dependency-map.md` — missing baseline/object families
- `duplicate-compatibility-map.md` — duplicate identifier decisions
- `canonical-baseline-decision.md` — approved strategy and PR separation
- `production-preflight.md` — no-go conditions and future proof plan
- `evidence-manifest.sha256` — file integrity manifest

## Current conclusion

- The unchanged `supabase/migrations` tree inherited from reviewed head `d87dfde049c8d9187b531ec34132b04364fb9ca4` contains 33 migration files using 29 unique timestamps. **[RP]**
- The committed ledger snapshot contains 92 ordered entries; equality with the live Supabase ledger remains **[U]**.
- None of the 92 snapshot versions has an exact-version file in the reviewed current tree. **[RP]**
- The current migration tree is corrective, not a complete rebuild history. **[RP]**
- The two draft PR #82 migration files are excluded from the current-tree inventory and absent from the committed ledger snapshot; their live application status remains **[U]**.
- PR A contains no production change. **[RP]**
