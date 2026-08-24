# HEHA Swipe live-object manifest capture receipt — 2026-08-24

Status: **READ-ONLY SANITIZED METADATA CAPTURE / VERIFIED / NO PRODUCTION CHANGE**  
Task: `SWP-016`  
PR: `#132`

## Source and scope

The capture used the committed query:

`docs/migration-lineage/queries/live-object-manifest-capture.sql`

Target: canonical HEHA Swipe Supabase project `rqpdvgmewoyaigzquqmj`.

The query read only PostgreSQL catalog, policy, and extension metadata. It did not read application rows, Auth rows, storage objects, Vault values, function bodies, policy expressions, ACLs, configuration secrets, credentials, tokens, webhook payloads, or provider data.

No DDL, DML, configuration, migration-ledger, Auth, storage, Edge Function, Stripe, or provider mutation occurred.

## Deterministic artifact

The query output was ordered by record type, schema, object identity, and metadata text under `C` collation. To keep connector transfer bounded, the exact ordered output was split into eight contiguous JSONL parts of 35 rows, with 29 rows in the final part.

| Part | Rows | Bytes | SHA-256 |
|---|---:|---:|---|
| 001 | 35 | 10,005 | `d10e4056eeace3b1ce2db2ff2512ac545b3563ef075bc6fc883488019516bf14` |
| 002 | 35 | 9,548 | `331aed6e59ab1fc7e9b239bd564f0ec5d1ba797b403dacaff8809e0694194a0f` |
| 003 | 35 | 9,046 | `5fea921ccceee9f09d93b97bc579f402fb94fdc6194e38929060bb7b72b7cff9` |
| 004 | 35 | 8,980 | `e41fd23f1a04bc773793fd309df6070f48b8d0155210454ae2b701b0033d2a5d` |
| 005 | 35 | 8,603 | `90bbafdd0f396541b89eb1487c7b16ab5c8af1da76e6d72df205798ed63e1409` |
| 006 | 35 | 7,918 | `f43b80286774c46c476a1232511b8aea88fa367fcc96b3fd821be1d8bdd7a736` |
| 007 | 35 | 9,367 | `ac3aa7339ec4d5126cd1c2be9df782c4964f4e18a3c244dae7f1bae7064a9bb5` |
| 008 | 29 | 7,611 | `833cda8b8af85aeac5b456b74c8d055e0a6f769139c2d1dc99fdd618889482fa` |

Concatenated in filename order:

- rows: **274**
- UTF-8 bytes: **71,078**
- SHA-256: `d33beb6850fc8398ad69611b7894ac026dd6766447996dbea560ccdced573a8b`

## Verified counts

- public tables: **45**
- public views: **5**
- public functions: **39**
- non-internal public-table triggers: **46**
- public-table RLS policies: **133**
- installed extensions: **6**
- RLS-enabled public tables: **45**
- FORCE-RLS public tables: **0**
- public materialized views: **0**

## Evidence boundary

This closes the top-level object-inventory artifact gap. It does not prove complete schema definitions, grants, policy expressions, function bodies, dependencies, rebuild parity, or Production-readiness. Those remain separate canonical-baseline gates.

Production impact: **NONE**.
