# SWP-016 fresh deep-structure capture — public receipt

Status: **CAPTURED PRIVATELY — HASH/COUNTS ONLY**

On 2026-08-25, the source-controlled read-only query at:

- commit `39b908e5ed42a5db8e72266c1518fbce9aed0afa`
- path `docs/migration-lineage/queries/deep-structure-manifest-capture.sql`
- Git blob `37855e6cfb20636664d99547bde7cdd856507645`

was executed against the canonical `HEHA SWIPE` Supabase project under an explicit founder approval for a fresh private metadata-only capture.

## Public result

- Total deterministic JSONL records: **1,072**
- Columns: **688**
- Constraints: **223**
- Indexes: **116**
- Table comment-presence records: **45**
- Deterministic plaintext bytes: **435,610**
- Deterministic plaintext SHA-256: `9bbdec7dd4299824d3d35ffaf832672a35d67c6d435e4ff2fb0512d793587299`
- Server-side decrypt-and-rehash verification: **PASS**

The full capture is retained only in private HEHA Control draft PR **#58**. It is not included, linked, or reproduced in this public repository.

## Data-minimization boundary

The query read PostgreSQL catalog metadata only for `public` and `app_private`. It emitted allowlisted structure and presence flags while withholding raw defaults, constraint/index expressions, comments, enum labels, role names, and sequence owners.

It did **not** read application, customer, partner, order, payment, Auth, or Storage rows; Vault/provider payloads; credentials; function bodies; or policy expressions.

## Change boundary

No DDL, DML, migration, migration-ledger change, Supabase configuration change, Stripe action, billing change, entitlement, customer action, application-code change, deployment authorization, or launch authorization occurred.

This receipt proves custody and integrity of one fresh structural snapshot. It is evidence for later canonical-baseline and collision analysis; it is not executable baseline SQL and does not authorize the next metadata tranche.
