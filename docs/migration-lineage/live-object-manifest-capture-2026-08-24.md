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

The query output was ordered by record type, schema, object identity, and metadata text under `C` collation. To keep connector transfer bounded, the exact ordered output is stored as fourteen contiguous JSONL parts.

| Part | Rows | Bytes | SHA-256 |
|---|---:|---:|---|
| 001a | 12 | 3,321 | `36db6de8f50d5d1dc4acdb40fe79d02443b083e4d13a56fa27985175b7702651` |
| 001b | 12 | 3,571 | `80fc249e38e4778073f254f075f592ab3419d8f219f9d521876a52abdd8afedf` |
| 001c | 11 | 3,113 | `439a219280d482d3f9d579835b0929c98a9bfcef036806ea8e62f2a87707ec85` |
| 002 | 35 | 9,548 | `331aed6e59ab1fc7e9b239bd564f0ec5d1ba797b403dacaff8809e0694194a0f` |
| 003a | 12 | 3,124 | `af052ead1c0db00afa20d5d78b19b36e2b46afd36a5728d03627929ae6d0419b` |
| 003b | 12 | 2,997 | `ca35469ad48f75c81acc6ddd0ef9de0845d9a0177a0f16ead10785acb47becb7` |
| 003c | 11 | 2,925 | `b3db303afbc796d06456e529e184966e5c64f10e114a932266e5c93b0326d2f4` |
| 004 | 35 | 8,980 | `e41fd23f1a04bc773793fd309df6070f48b8d0155210454ae2b701b0033d2a5d` |
| 005 | 35 | 8,603 | `90bbafdd0f396541b89eb1487c7b16ab5c8af1da76e6d72df205798ed63e1409` |
| 006 | 35 | 7,918 | `f43b80286774c46c476a1232511b8aea88fa367fcc96b3fd821be1d8bdd7a736` |
| 007 | 35 | 9,367 | `ac3aa7339ec4d5126cd1c2be9df782c4964f4e18a3c244dae7f1bae7064a9bb5` |
| 008a | 10 | 2,826 | `7c20782a4ca9b763a1ad166fa10e070494b57f0423d32bd05bd284b0425368d2` |
| 008b | 10 | 2,757 | `23117f53fb2bf134de01541d26fae9ccff3a660acbd1d82eb6640b6392d56c82` |
| 008c | 9 | 2,028 | `a99ea26764fc5775c0bad7081562aeff9b04b32d34e092e708435de35529437a` |

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

This closes the top-level object-inventory artifact gap. It does not prove complete schema definitions, grants, policy expressions, function bodies, dependencies, rebuild parity, or Production readiness. Those remain separate canonical-baseline gates.

Production impact: **NONE**.
