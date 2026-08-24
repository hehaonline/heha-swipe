# HEHA Swipe Live Object Manifest Summary — refreshed 2026-08-24

Status: **VERIFIED TOP-LEVEL METADATA CAPTURE / NO PRODUCTION CHANGE**  
Task: `SWP-016`  
Related: issue #85, merged PRs #69 and #131, PRs #128 and #132

## Evidence boundary

On 2026-08-24, an authorized read-only query was executed against the canonical HEHA Swipe Supabase project using the committed contract:

`docs/migration-lineage/queries/live-object-manifest-capture.sql`

The query read only `pg_catalog`, `pg_policies`, and extension metadata. It did not read customer, partner, payment, profile, order, waitlist, Auth, storage, Vault, provider, message, review, save, or other business rows. It did not read function bodies, policy expressions, ACLs, secrets, credentials, tokens, webhook payloads, or storage objects.

No DDL, DML, configuration, migration-ledger, Auth, storage, Edge Function, Stripe, or provider mutation occurred.

## Captured artifact

The deterministic JSONL capture is committed as eight ordered parts:

`docs/migration-lineage/live-object-manifest-2026-08-24.part-001.jsonl` through `part-008.jsonl`

Concatenated in filename order, the artifact has:

- **274 rows**
- **71,078 UTF-8 bytes**
- SHA-256: `d33beb6850fc8398ad69611b7894ac026dd6766447996dbea560ccdced573a8b`

The part hashes are bound by:

`docs/migration-lineage/live-object-manifest-2026-08-24.parts.sha256`

The exact capture receipt is:

`docs/migration-lineage/live-object-manifest-capture-2026-08-24.md`

## Verified top-level inventory

| Object class | Verified count |
|---|---:|
| Public base tables | 45 |
| Public views | 5 |
| Public functions | 39 |
| Non-internal triggers on public tables | 46 |
| Public-table RLS policies | 133 |
| Installed extensions | 6 |

Additional verified structural facts:

- RLS enabled: **45 / 45 public tables**
- FORCE RLS enabled: **0 / 45 public tables**
- Public materialized views: **0**
- Every row is strictly ordered and has a unique object identity within its class.

## What this proves

This closes the missing-evidence gap for the top-level object inventory. The exact names, owners, function signatures/security mode, trigger attachments, policy names/roles/commands, table RLS state, view kind, and extension versions are now reproducible from committed sanitized bytes.

## What this does not prove

This is not a complete schema dump, executable baseline, security approval, or current-schema rebuild PASS. A canonical baseline still requires separately reviewed evidence for:

1. table columns, defaults, generated/identity behavior, comments, constraints, and indexes;
2. view definitions, options, dependencies, and grants;
3. function bodies or normalized body hashes, search paths, ACLs, and dependencies;
4. trigger definitions and ordering;
5. complete RLS `USING` / `WITH CHECK` expressions and table/schema/function grants;
6. required non-public schemas, types, sequences, storage configuration, cron jobs, and provider-managed settings;
7. repository-to-live-ledger compatibility mapping;
8. clean data-less rebuild, generated types, advisors, behavior tests, rollback/forward-fix evidence, and branch deletion.

## Authority boundary

The HEHA Business Model 2026 slides remain historical context only. Current founder decisions, current runtime/provider evidence, current economics, current partner terms, and current legal/accounting/insurance decisions control whenever they differ.

Community Pass PR #128 remains a separate additive draft. This evidence does not authorize its merge, Supabase application, Stripe Checkout, billing, entitlements, benefits, HEHA Credit, delivery waivers, or public launch.

Production impact: **NONE**.
