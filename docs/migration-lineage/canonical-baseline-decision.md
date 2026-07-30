# Canonical Baseline Decision

Decision status: **Approved for PR A only**

## Decision

HEHA Swipe will use:

1. immutable historical evidence;
2. a separately reviewed canonical migration baseline for new environments;
3. a dual-tree transition until the canonical chain is proven;
4. no production ledger rewrite during the initial repair.

## Itemized architecture decision

### 1. Historical strategy — APPROVED

Archive and checksum historical migration evidence. Do not delete or rewrite it.

### 2. Production ledger — APPROVED

The production migration ledger remains untouched.

### 3. Baseline source — APPROVED WITH CONDITIONS

The future baseline may be derived from a sanitized live-schema/object manifest plus reviewed application and security behavior rather than replaying all 92 scripts byte-for-byte, provided that:

- tables, constraints, indexes, functions, triggers, views, RLS policies, grants, extensions and approved storage configuration are captured;
- every ledger cohort receives a semantic compatibility mapping;
- ledger-only unknown SQL remains explicitly unknown;
- no customer, partner, payment or operational rows are copied.

### 4. Duplicate handling — APPROVED

- archive rollback SQL outside the executable canonical chain;
- assign unique canonical treatment to same-timestamp files;
- retain duplicate analytics entries until SQL classification;
- preserve all historical evidence.

### 5. PR separation — APPROVED

- PR A: evidence and architecture only.
- PR B: executable canonical-chain implementation only after remaining gates.

### 6. ADR dependency — MODIFIED

PR A may proceed before ADR-001 because it is non-executable. PR B, PR #82 merge/apply, disposable cloud QA and production remain blocked until ADR-001 and candidate-project P0 decisions are resolved.

### 7. Cost gate — APPROVED

No paid Supabase branch without a cost estimate and explicit Geronimo approval.

## PR A branch

`docs/swp-016-migration-lineage-evidence`

## Proposed PR B branch

`feat/swp-016-canonical-migration-chain`

PR B is not authorized by this document.
