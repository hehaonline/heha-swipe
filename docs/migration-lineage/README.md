# SWP-016 Migration Lineage Evidence

Status: **Corrective documentation review required; architecture approval remains PR A only**  
Task: `SWP-016`  
Issue: https://github.com/hehaonline/heha-swipe/issues/85  
Corrective branch: `agent/swp-016-inventory-correction`  
Reviewed tree anchor: merge commit `7b32ae605840e50ff1085372e988c980ab538498`

## Scope

This directory contains sanitized evidence and architecture decisions for repairing HEHA Swipe migration lineage.

PR A and this corrective package are documentation-only. They must not:

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

`repository-inventory.csv` is anchored to the exact repository tree at merge commit `7b32ae605840e50ff1085372e988c980ab538498`. The committed `live-ledger-2026-07-19.csv` is a sanitized 92-row snapshot, but this package does not include independently reproducible live-ledger provenance. Its row-level live-verification labels therefore remain `U` until an authorized independent reviewer reproduces the export. The committed snapshot may be inspected as repository evidence; it must not be treated as proof of current live state.

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

- `repository-inventory.csv` — 35-file current-tree migration inventory anchored to merge commit `7b32ae605840e50ff1085372e988c980ab538498`
- `live-ledger-2026-07-19.csv` — sanitized ledger snapshot; live provenance remains `U`
- `object-dependency-map.md` — missing baseline/object families, rechecked against all 35 current-tree migrations
- `duplicate-compatibility-map.md` — duplicate identifier decisions
- `canonical-baseline-decision.md` — approved strategy and PR separation
- `production-preflight.md` — no-go conditions and future proof plan
- `evidence-manifest.sha256` — file integrity manifest

## Current conclusion

- The `supabase/migrations` tree at merge commit `7b32ae605840e50ff1085372e988c980ab538498` contains 35 migration files using 31 unique timestamps. **[RP]**
- The inventory includes `20260720093000_partner_multi_categories.sql` and `20260720093100_partner_multi_categories_view_security_invoker.sql`. **[RP]**
- The committed ledger snapshot contains 92 ordered entries; equality with the live Supabase ledger remains **[U]**.
- None of the 92 snapshot versions has an exact-version file in the reviewed current tree. **[RP]**
- The current migration tree is corrective, not a complete rebuild history. **[RP]**
- The two draft PR #82 migration files are excluded from the current-tree inventory and absent from the committed ledger snapshot; their live application status remains **[U]**.
- PR A and this correction contain no production change. **[RP]**
