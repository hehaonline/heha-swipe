# Historical SQL provenance — `20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql`

Status: **NON-EXECUTABLE HISTORICAL EVIDENCE**

## Purpose

This file preserves the recovered source text for the already-recorded HEHA Swipe Production migration:

- version: `20260614102924`
- ledger name: `add_supporter_payments_subscriptions_vibe_settings`
- former executable-path candidate: `supabase/migrations/20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql`
- historical-evidence path: `docs/migration-lineage/historical-sql/20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql`

It exists to restore auditable source lineage only. It is not part of the executable canonical migration chain for new environments.

## Exact source integrity

The archived SQL is byte-for-byte identical to the recovered PR #69 source at exact head:

`6d799fa323ef92b3bf2fc5211c4d12f60ca4b5fa`

Hashes of the 5,289-byte UTF-8 source, including its final newline:

- SHA-256: `6b0e1a03e3bf09661d47391c84a262526690d1c54aebe8d5f0e54d487ec08284`
- Git blob SHA-1: `7a832e48d455291c88e7941866b2eb00b412f6b6`

## Reported live catalog comparison and evidence boundary

An authorized read-only connector session on 2026-08-19 reported comparing the recovered source against:

- `public.supporter_payments`
- `public.supporter_subscriptions`
- `public.vibe_settings`
- `public.heha_set_updated_at()`
- associated checks, primary/foreign/unique constraints, indexes, update triggers, RLS state, and policies

Reported evidence counts:

- 41 column definitions
- 15 constraints
- 12 indexes
- 3 triggers
- 5 policies
- 3 RLS-state entries
- 1 supporting function definition

Reported normalized live catalog-manifest MD5:

`63eeb777fea4a31a6ebf6ea97ae0113f`

The normalized catalog rows behind that digest were not committed. The repository can therefore preserve the report but cannot independently reproduce or approve live semantic equality from the available bytes.

Current evidence conclusion:

- byte preservation of the historical SQL: **REPOSITORY-PROVEN**
- live semantic equality for canonical-baseline use: **UNKNOWN** until a sanitized live catalog and separately generated recovered-source catalog pass `verify-pr69-catalog.mjs`
- Production impact from this archive: **NONE**

This evidence correction does not reduce the safety or value of the non-executable archive. It prevents the report from being overstated as current live-schema parity proof.

## Mandatory boundaries

This archived SQL must **not** be:

- manually applied or reapplied to Production;
- placed back into an executable migration directory without a separately reviewed canonical-baseline decision;
- treated as a complete zero-to-current rebuild history;
- retimestamped and executed as a new migration;
- used to redesign the legacy supporter model inside this evidence lane;
- interpreted as approval for Community Pass billing, Stripe changes, entitlements, benefits, or launch.

The Production migration ledger remains untouched.

## Why it is outside `supabase/migrations`

HEHA Swipe's repository migration tree is corrective rather than a complete rebuild history. Production was reported to contain 45 public application tables and 96 recorded migration versions, while an ordinary disposable Supabase branch inherited neither the application schema nor the migration ledger.

Leaving one recovered historical file in the executable migration directory would create a misleading partial chain. It also would not prove current Data API grants, deterministic reapply behavior, pre-existing-object drift handling, or compatibility with later supporter-security work.

## Canonical-baseline treatment

The separately reviewed SWP-016 canonical baseline for new environments may incorporate semantics represented by this archive only after:

1. repository-to-live-ledger compatibility mapping;
2. sanitized capture and review of required live object definitions;
3. successful comparison of the live and recovered-source supporter/vibe catalogs;
4. explicit dependency and duplicate-migration decisions;
5. independent database/security review;
6. clean disposable rebuild, type generation, advisors, behavior tests, and rollback/forward-fix evidence;
7. explicit founder approval for any paid environment or live action.

Any current security, privilege, replay, or product correction belongs in reviewed forward/canonical work—not in this immutable historical source.

## Founder disposition

On 2026-08-21, Geronimo approved preserving the recovered source as non-executable historical evidence and removing it from the partial executable chain as the safer launch-readiness path.

PR #69 was squash-merged at:

`955ae8842df66fb7639b78aa5ecf54850b00d06d`

Production impact: **NONE**.
