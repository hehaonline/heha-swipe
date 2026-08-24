# HEHA Swipe Canonical Baseline Readiness Plan — refreshed 2026-08-24

Status: **DOCUMENTATION/EVIDENCE PREPARATION / EXECUTABLE BASELINE BLOCKED**  
Task: `SWP-016`  
Authority: issue #85 and the approved canonical-baseline decision on `main`

## Objective

Create one reviewed, reproducible baseline for new data-less HEHA Swipe environments without rewriting Production history or copying business data. The baseline must let HEHA build a clean environment from zero, then apply separately approved forward migrations such as Community Pass Package A without collisions.

## Current verified state

1. PR #69 is merged: the recovered supporter/vibe SQL is preserved as non-executable historical evidence.
2. PR #131 is merged: the 92-row and reported 96-row migration-ledger evidence, capture contracts, and repository verifier are on `main`.
3. PR #132 now contains a sanitized, deterministic top-level live-object artifact verified against:
   - 45 public tables;
   - 5 public views;
   - 39 public functions;
   - 46 non-internal triggers;
   - 133 public-table RLS policies;
   - 6 installed extensions;
   - 45 RLS-enabled tables, zero FORCE-RLS tables, and zero public materialized views.
4. Production has 45 public application tables, while an ordinary disposable Supabase branch inherited no application schema or application migration ledger.
5. Community Pass PR #128 passed its isolated additive contract tests, but still lacks a lineage-faithful current-schema rebuild and remains unmerged and unapplied.
6. The Production migration ledger remains untouched.

## Remaining deliverables before executable baseline SQL

### D1 — Repository-to-ledger compatibility map

For each current repository migration and each of the 96 recorded live versions, record the source/evidence state, object cohort, replay risk, and treatment:

- `recovered`;
- `baseline-required`;
- `provider-managed`;
- `superseded/archive-only`;
- `unresolved`.

Unknown historical SQL stays explicitly unknown.

### D2 — Deep sanitized schema manifest

Capture metadata only, in separately reviewable chunks:

- table columns, data types, defaults, generated/identity behavior, comments;
- primary, foreign, unique, exclusion, and check constraints;
- complete index definitions, predicates, and expressions;
- application-required types, sequences, schemas, and extensions;
- view definitions, options, dependencies, owners, and grants;
- function body hashes, owners, security mode, search paths, ACLs, and dependencies;
- trigger definitions, ordering, and enabled state;
- RLS policy expressions plus table/schema/function grants;
- required storage, cron, and provider configuration receipts.

Never capture business rows, Auth rows, storage objects, Vault values, tokens, webhook payloads, or secrets.

### D3 — Authority and identity map

Explicitly separate:

- legacy `supporter_*` records and profile caches;
- new Community Pass accounts, subscriptions, purchases, entitlements, acceptances, events, and provider inbox;
- partner listing/claim/partnership/contract/publication states;
- canonical ONE HEHA identity and the future Swipe-to-Local benefit check.

No legacy record becomes Community Pass authority without a separate approved migration and customer-protection plan.

### D4 — Security review packet

Prove least privilege, RLS/BOLA behavior, SECURITY DEFINER caller binding, public-view minimization, deletion/redaction/retention, and no secret or PII leakage for every exposed surface.

### D5 — Clean-build proof

Before any new paid branch:

1. source-control the exact baseline and proof plan;
2. provide the expected runtime and cost;
3. obtain explicit founder approval;
4. create a data-less disposable environment;
5. apply the baseline and approved repeatability strategy;
6. generate TypeScript types and compare the schema to the reviewed manifest;
7. run security/performance advisors and behavioral/concurrency tests;
8. apply approved forward migrations in order;
9. verify zero synthetic rows/users remain;
10. delete the branch and record actual cost.

## PR separation

- **Merged PR #69:** historical supporter/vibe source archive only.
- **Merged PR #131:** ledger evidence and verification tooling.
- **PR #132:** top-level object evidence and canonical-baseline readiness plan; no executable baseline.
- **Future executable baseline PR:** not authorized until the remaining evidence and security review pass.
- **PR #128 and other product migrations:** separate forward changes, not silently folded into the baseline.

## Current next action after PR #132

Complete the repository-to-ledger compatibility map and define the next deep-metadata capture packet. Do not open executable baseline SQL or request another paid branch until that packet is source-controlled and reviewed.

## Stop conditions

Stop and escalate if the work would require business data, secrets, a Production ledger rewrite, a changed canonical identity/project boundary, an unreviewed provider dependency, or a P0/P1 access-control change.

## Explicitly not authorized

- executable baseline or Production migration;
- Production DDL/DML/configuration/ledger changes;
- business-data copy;
- live Stripe products, Checkout, subscriptions, charges, refunds, or billing;
- Community Pass entitlement or benefit activation;
- HEHA Local benefit activation;
- another paid Supabase branch without a separate cost estimate and founder approval.

The HEHA Business Model 2026 slides are historical context, not current operating authority.

Production impact: **NONE**.
