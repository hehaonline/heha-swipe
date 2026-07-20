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
- `LP` — live-ledger-proven
- `I` — inferred
- `U` — unknown / access required

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
- `live-ledger-2026-07-19.csv` — ordered sanitized live migration ledger
- `object-dependency-map.md` — missing baseline/object families
- `duplicate-compatibility-map.md` — duplicate identifier decisions
- `canonical-baseline-decision.md` — approved strategy and PR separation
- `production-preflight.md` — no-go conditions and future proof plan
- `evidence-manifest.sha256` — file integrity manifest

## Current conclusion

- 35 migration files use 31 unique timestamps.
- The live HEHA Swipe ledger contains 92 applied entries.
- None of the 92 applied versions has an exact-version file in the current tree.
- The current migration tree is corrective, not a complete rebuild history.
- PR #82 remains draft and absent from the live ledger.
- Production remains untouched.
