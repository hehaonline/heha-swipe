# SWP-016 Live-Ledger Refresh Receipt — 2026-08-19

Status: **READ-ONLY LIVE EVIDENCE REFRESH / NO PRODUCTION CHANGE**

Related:

- issue #85 (`SWP-016`)
- merged PR #69 (non-executable supporter migration source archive)
- Community Pass Package A PR #128

## Scope and method

An authorized read-only Supabase connector session inspected migration metadata and schema catalogs for the canonical HEHA SWIPE Production project. The work did not query customer, partner, payment, order, profile or other business rows.

The evidence collected was limited to:

- `supabase_migrations.schema_migrations` version/name metadata;
- `information_schema` and `pg_catalog` definitions for the three supporter/vibe tables and their supporting function;
- table-count comparison between Production and the founder-approved disposable Package A branch;
- no secrets, credentials, raw webhook payloads or personally identifiable fixture data.

Production received no DDL, DML, configuration, function, policy, grant, migration-ledger or provider mutation.

## Current live migration ledger

Read-only live result reported at the 2026-08-19 checkpoint:

- **96 migration rows**;
- **96 distinct versions**;
- first version: `20260531101429`;
- latest version: `20260812220624`;
- one duplicated migration **name**, represented by two distinct versions:
  - `analytics_triggers_for_partner_counters`
  - `20260602213920`
  - `20260602220224`.

The previous committed `live-ledger-2026-07-19.csv` contains 92 rows and ended at `20260710030952`. The reported current ledger adds four later rows:

1. `20260720132527,partner_multi_categories`
2. `20260720132617,partner_multi_categories_view_security_invoker`
3. `20260805123842,sec002_revoke_public_execute_on_trigger_functions`
4. `20260812220624,update_founding_neighbor_pass_preferences`

`live-ledger-2026-08-19.csv` records the reported 96-row result with evidence label `LP`. The committed artifact is internally reproducible; independent live-source provenance remains blocked until a separately authorized recapture uses the exact query and byte contract in `queries/live-ledger-capture.sql`.

## Disposable-branch finding

The founder-approved temporary Supabase branch used for Community Pass Package A returned:

- zero inherited application migration rows;
- zero initial application tables in `public`;
- seven `public` tables only after the additive Package A chain was replayed.

Production was reported to have **45 public base tables**.

Conclusion: ordinary branch creation did not reproduce the current application schema or migration ledger. Package A passed genuine managed-Supabase additive behavior, but a fresh branch is not a representative current-schema collision environment until the approved canonical baseline is applied.

## Supporter/vibe historical source disposition

The recovered historical source is:

`20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql`

PR #69 was corrected and squash-merged on 2026-08-21 at merge commit:

`955ae8842df66fb7639b78aa5ecf54850b00d06d`

The SQL now exists only at:

`docs/migration-lineage/historical-sql/20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql`

It is byte-preserved, non-executable historical evidence. It is no longer inside `supabase/migrations` and cannot be mistaken for a complete executable rebuild chain.

### Earlier reported live catalog comparison

The 2026-08-19 connector receipt reported comparison of:

- `public.supporter_payments`;
- `public.supporter_subscriptions`;
- `public.vibe_settings`;
- `public.heha_set_updated_at()`;
- associated constraints, indexes, triggers, RLS state and policies.

Reported inventory:

- 41 column entries;
- 15 constraint entries;
- 12 index entries;
- 3 trigger entries;
- 5 policy entries;
- 3 RLS-state entries;
- 1 supporting function entry.

Historically reported catalog-manifest MD5:

`63eeb777fea4a31a6ebf6ea97ae0113f`

The normalized rows behind that digest were not committed. Repository evidence therefore cannot independently reproduce the semantic-equality claim. The result remains **UNKNOWN / BLOCKED FOR CANONICAL-BASELINE USE** until a sanitized live artifact and a separately generated recovered-source artifact pass `verify-pr69-catalog.mjs`.

This uncertainty does not undo the safety of preserving the SQL as non-executable historical evidence. It does prevent the archived SQL from being treated as current live-schema parity proof or an executable canonical baseline.

## Reproducibility repair — 2026-08-20 to 2026-08-21

This branch includes no-live-data evidence tooling:

- `queries/live-ledger-capture.sql` — exact sorted, read-only ledger query and CSV capture contract;
- `queries/pr69-supporter-catalog-capture.sql` — exact sanitized supporter/vibe catalog query and JSONL ordering contract;
- `verify-evidence.mjs` — dependency-free verification of both committed ledgers, the 92→96 delta, duplicate-name result, archive hashes and every manifest-listed SHA-256;
- `verify-pr69-catalog.mjs` — fail-closed exact-row comparator for a future sanitized live capture and a separately generated recovered-source catalog.

The repository verifier reports repository consistency and unresolved provenance separately. The catalog comparator passes only its synthetic self-test until both real artifacts are supplied. No Production, Supabase, Auth, storage, provider or business-row access was used for this repair.

## Architecture consequence

The approved SWP-016 strategy remains correct:

1. preserve immutable historical evidence;
2. keep recovered historical SQL outside the executable migration chain;
3. capture and review current live definitions without copying business data;
4. build a separately reviewed canonical baseline for new environments;
5. keep the Production migration ledger untouched;
6. maintain a dual-tree transition until a clean disposable rebuild and schema/behavior parity proof pass.

## Remaining gates

PR B / executable canonical baseline remains blocked until:

- the current 96-row ledger and repository inventory receive an updated compatibility map;
- all live object families required by the reported 45-table Production schema are captured without copying data;
- duplicate-name treatment is recorded;
- ADR/ONE HEHA identity boundaries are reconciled;
- an independent security/database reviewer approves the baseline diff;
- a fresh disposable branch builds from zero, passes schema/advisor/type/proof checks and is destroyed;
- no-go and rollback/forward-fix evidence is complete.

## Production impact

**NONE.**
