# HEHA Swipe Canonical Baseline Readiness Plan — 2026-08-19

Status: **DOCUMENTATION-ONLY PREPARATION / EXECUTABLE BASELINE BLOCKED**  
Task: `SWP-016`  
Authority: issue #85 and the approved canonical-baseline decision on `main`

## Objective

Prepare one reviewed, reproducible migration baseline for **new disposable and future non-Production environments** without rewriting HEHA Swipe Production history, copying business data, or treating incomplete historical scripts as safe merely because they exist.

The baseline exists to answer one practical question:

> Can a clean, data-less HEHA Swipe environment be built from zero into the reviewed current application contract, after which approved forward migrations such as Community Pass Package A can be applied and proven without collisions?

## Current evidence

1. Production currently records **96 migration versions** and **45 public base tables**.
2. The repository migration tree is corrective rather than a complete zero-build history.
3. A founder-approved ordinary Supabase branch inherited **zero application migration rows** and **zero initial application public tables**.
4. Community Pass Package A passed as an isolated additive contract on managed Supabase, but not against a lineage-faithful 45-table clone.
5. PR #69 semantically matches the live supporter/vibe object family and is a source-restoration candidate, not a complete baseline.
6. PR #131 preserves the refreshed live-ledger evidence and remains under independent review.
7. The approved architecture direction is immutable history + reviewed canonical baseline + untouched Production ledger.

## Required deliverables before executable SQL

### D1 — Current repository inventory

Refresh the repository inventory against exact `main` and record:

- file path and timestamp;
- object families touched;
- prerequisites;
- whether the file is historical, corrective, forward-only, rollback-only, duplicate-timestamp, or missing from the live ledger;
- whether the SQL body is proven to match a live object family;
- replay risk and required treatment.

### D2 — Live-ledger compatibility map

For each of the 96 live versions, record:

- version and name;
- exact repository source if known;
- semantic source match if proven;
- live objects attributable to the cohort;
- state: `recovered`, `baseline-required`, `provider-managed`, `superseded/archive-only`, or `unresolved`;
- required action.

Unknown SQL stays unknown. Do not infer equivalence from similar names.

### D3 — Sanitized live object manifest

Capture metadata only:

- schemas and extensions;
- tables, columns, defaults, generated/identity behavior and comments;
- constraints and indexes;
- sequences/types where application-required;
- views/materialized views and options;
- functions and procedures, with normalized body hashes;
- triggers and ordering;
- RLS enable/force state, policies and grants;
- storage buckets/policies, cron jobs and provider configuration required for application behavior;
- object owners and dependencies.

Never capture row contents, secrets, Vault values, Auth tokens, webhook payloads or storage objects.

### D4 — Baseline object-order plan

Order the future baseline by dependency:

1. application-required extensions and schemas;
2. types/domains/sequences;
3. identity/profile foundation and role helpers;
4. partner/catalog tables;
5. order/customer-activity tables;
6. community/event/admin/Scout tables;
7. legacy supporter/contribution compatibility objects;
8. constraints and indexes;
9. functions and trigger helpers;
10. triggers;
11. RLS policies and grants;
12. views/public projections;
13. provider configuration receipts.

The exact order must be generated from dependencies, not from this illustrative list alone.

### D5 — Legacy-to-current authority map

Explicitly separate:

- legacy `supporter_*` records and profile subscription cache;
- the new Community Pass canonical account/subscription/purchase/entitlement/event authority in PR #128;
- public/owner/internal partner states;
- HEHA Swipe identity versus future HEHA Local benefit verification.

The baseline may reproduce legacy objects for compatibility, but it must not silently make legacy supporter tables the new Community Pass authority or migrate historical customers without a separate approved mapping.

### D6 — Security review packet

For every exposed surface, prove:

- least-privilege schema/table/function grants;
- RLS and BOLA behavior for `anon`, `authenticated`, owner, internal roles, service role, Auth admin and database owner;
- SECURITY DEFINER caller binding and pinned search path;
- public view column/row minimization;
- deletion/redaction/retention behavior;
- no secret or PII leakage through definitions, errors or evidence.

### D7 — Clean-build proof specification

Before another paid branch, source-control the exact procedure:

1. create data-less disposable environment;
2. record provider/project/version metadata;
3. apply the reviewed canonical baseline once;
4. apply it again or run its approved repeatability strategy;
5. generate TypeScript types;
6. run schema diff against the reviewed manifest;
7. run security and performance advisors;
8. run structural and behavioral proofs;
9. apply approved dependent forward migrations in order;
10. rerun types, advisors, behavior, concurrency and rollback/forward-fix proofs;
11. verify zero synthetic rows/users remain;
12. destroy the branch and record actual cost.

### D8 — Production preflight

Production remains untouched until a later release package proves:

- exact baseline is for new environments only;
- Production ledger receives no rewrite or repair;
- forward migrations are additive/corrective and individually reviewed;
- backup, rollback/forward-fix and monitoring are ready;
- final founder approval names exact SHAs and actions.

## Proposed PR separation

### PR C — live-ledger refresh

Current draft PR #131. Documentation/evidence only.

### PR D — live-object manifest and baseline design

This documentation-only lane. It may contain sanitized manifests, compatibility maps, dependency plans, proof specifications and checksums. It must not contain executable canonical baseline SQL.

### PR B — executable canonical baseline

Not authorized yet. It may open only after PR C/PR D receive exact-head independent database/security approval and all required metadata is complete.

### Dependent forward PRs

Community Pass PR #128 and other partner/claim/publication migrations remain separate, review-only forward changes. They may be tested after the baseline but are not folded into it without an explicit compatibility decision.

## Review gates

PR D must receive:

1. evidence-integrity review;
2. database dependency review;
3. RLS/ACL/security review;
4. privacy/data-minimization review;
5. confirmation that no executable or Production action is hidden in the evidence lane.

The author/controller cannot self-certify independence.

## Stop conditions

Stop and escalate if:

- a required live object cannot be represented without copying business data;
- live definitions conflict materially with repository/public behavior;
- the canonical identity/project boundary changes;
- a provider-managed object cannot be reproduced safely;
- the baseline would require rewriting Production history;
- security review finds a P0/P1 access-control defect that changes the baseline contract;
- another paid environment is needed before an exact runtime/cost estimate and Geronimo approval.

## Immediate no-cost next actions

1. Independently review PRs #128, #131 and #69 at their exact heads.
2. Capture columns/constraints/indexes for the 45-table manifest in sanitized chunks.
3. Capture views/functions/triggers/policies/grants with normalized definitions and hashes.
4. Refresh repository↔96-row compatibility mapping.
5. Prepare a complete PR D evidence manifest and request independent review.
6. Only then prepare the exact executable PR B file plan and paid-branch estimate.

## Explicitly not authorized

- executable baseline SQL;
- merge of PR #128, #131 or #69;
- Production DDL/DML/configuration/ledger changes;
- live Stripe or customer billing;
- partner/customer data copy;
- Package B Checkout/provider-event work;
- HEHA Local benefit activation;
- another paid Supabase branch.

Production impact: **NONE**.
