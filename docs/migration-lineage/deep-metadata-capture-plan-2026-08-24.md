# HEHA Swipe Deep Sanitized Metadata Capture Plan — 2026-08-24

Status: **SOURCE-CONTROLLED PREPARATION / LIVE CAPTURE NOT YET AUTHORIZED BY THIS FILE**  
Task: `SWP-016`

## Objective

Capture enough current structural metadata to design a reproducible, data-less HEHA Swipe baseline while keeping customer data, secrets, provider payloads, and Production behavior untouched.

This plan follows the verified top-level inventory on `main` and the repository↔live-ledger compatibility map. It does not authorize executable baseline SQL.

## Tranche 1 — deep structure

Prepared query:

`docs/migration-lineage/queries/deep-structure-manifest-capture.sql`

Target schemas:

- `public`
- `app_private`

Captured record classes:

1. table columns, ordinal position, formatted type, nullability, identity/generated state, collation, and default expression;
2. table constraints and normalized `pg_get_constraintdef` output;
3. indexes and normalized `pg_get_indexdef` output;
4. enum labels and order;
5. domains, base types, nullability, and defaults;
6. sequences and structural parameters.

The query reads catalog metadata only. It does not select from application tables.

### Stop before commit if

- any default, constraint, or index definition contains a credential, token, secret, private URL, personal data, or provider payload;
- an unexpected schema appears;
- the result cannot be deterministically sorted;
- the output is too large for bounded review;
- current object counts conflict with the verified top-level manifest.

If a stop condition occurs, preserve the raw result outside source control, redact only through a documented rule, and recapture a hash-bound sanitized artifact. Never silently edit evidence bytes.

## Tranche 2 — views, functions, and triggers

Prepare only after Tranche 1 passes.

Capture:

- view definitions, `security_invoker` / `security_barrier` options, owner, dependencies, and grants;
- function identity, language, volatility, parallel safety, security mode, owner, pinned search path, EXECUTE ACL, normalized body hash, and dependencies;
- trigger timing, event mask, update-column set, enabled state, function identity, and deterministic ordering.

Do not commit raw function bodies until a secret scan and independent review confirm that the bodies contain no credentials, tokens, private endpoints, or customer data.

## Tranche 3 — RLS and effective access

Prepare only after Tranche 2 passes.

Capture:

- schema/table/function grants;
- RLS `USING` and `WITH CHECK` expressions;
- permissive/restrictive mode and roles;
- effective access matrices for `anon`, `authenticated`, owner, internal roles, service role, Auth admin, and database owner;
- SECURITY DEFINER caller binding and search-path behavior.

This tranche is security-sensitive. A count of policies or the presence of RLS is not a BOLA proof.

## Tranche 4 — provider-managed behavior

Capture sanitized configuration receipts for:

- application-required extensions;
- Storage buckets and policies, without objects or signed URLs;
- cron schedules and function names, without secret arguments;
- Edge Function names/configuration boundaries, without environment values;
- Auth settings required for the app contract;
- provider versions and branch behavior.

Provider-managed schemas must not be recreated blindly by baseline SQL.

## Tranche 5 — authority and identity

Document and prove:

- canonical ONE HEHA account identity;
- legacy `supporter_*` records and profile cache boundaries;
- new Community Pass account/subscription/purchase/entitlement/event authority;
- HEHA Swipe → HEHA Local server-to-server benefit verification;
- deletion, redaction, retention, and email-reuse behavior.

No legacy supporter row becomes Community Pass authority without a separately approved customer-protection mapping.

## Review and build sequence

1. source-control the exact read-only query;
2. receive one explicit authorization for the bounded live metadata read;
3. execute against the named canonical environment;
4. preserve exact UTF-8/LF bytes;
5. commit the sanitized artifact, capture receipt, and SHA-256;
6. run a fail-closed verifier;
7. perform database dependency, privacy, and security review;
8. draft—but do not run—the executable canonical baseline;
9. estimate runtime and cost for a data-less disposable branch;
10. obtain separate founder approval;
11. prove zero-to-current rebuild, generated types, advisors, behavior, concurrency, rollback/forward-fix, and complete cleanup;
12. delete the branch and record actual cost.

## No-go conditions

Do not:

- read or copy customer, partner, payment, order, profile, Auth, or storage rows;
- commit secrets or provider credentials;
- alter Production or its migration ledger;
- fold Community Pass PR #128 into the baseline silently;
- treat same-name migration candidates as SQL equivalence;
- create a paid branch without exact cost approval;
- activate Stripe, billing, entitlements, credits, benefits, delivery waivers, or public launch.

Production impact: **NONE**.
