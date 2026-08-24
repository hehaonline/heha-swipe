# HEHA Swipe live-object manifest capture receipt — 2026-08-24

Status: **READ-ONLY SANITIZED METADATA CAPTURE / HASH-BOUND / NO PRODUCTION CHANGE**  
Task: `SWP-016`  
PR: `#132`

## Source and scope

The capture used the committed query:

`docs/migration-lineage/queries/live-object-manifest-capture.sql`

Target: canonical HEHA Swipe Supabase project `rqpdvgmewoyaigzquqmj`.

The query read only PostgreSQL catalog, policy, and extension metadata. It did not read application rows, Auth rows, storage objects, Vault values, function bodies, policy expressions, ACLs, configuration secrets, credentials, tokens, webhook payloads, or provider data.

No DDL, DML, configuration, migration-ledger, Auth, storage, Edge Function, Stripe, or provider mutation occurred.

## Integrity repair

The first GitHub transport attempt was rejected by CI because several committed part bytes did not match their recorded hashes. The database capture itself remained read-only. The affected parts and documentation were rebuilt from the same deterministic query contract, and this receipt records the corrected query-produced hashes. Exact-head CI remains the merge gate.

## Deterministic artifact

The query output is ordered by record type, schema, object identity, and metadata text under `C` collation. To keep connector transfer bounded, the exact ordered output is stored as fourteen contiguous JSONL parts.

| Part | Rows | Bytes | SHA-256 |
|---|---:|---:|---|
| 001a | 12 | 2,492 | `c319225f63ea27aec4d7d28f53cbe60d649461d67c37e2dbafb2921d3a2b7980` |
| 001b | 12 | 4,031 | `877267481a70a01717b13cafb4f49f17bd64aeb6d7d07ef02745d3d02d1b3b1a` |
| 001c | 11 | 3,482 | `82c51daa40b4f6c8c86b58f5d223bae651634a7f52a023c9693136a64fae7702` |
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
- SHA-256: `065bb72658cee40d194dbc4c6fe17c8f40d11343e1dcbc05f5b59cabca0c6779`

## Verified counts

The committed verifier must recompute these values at the exact review head:

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

This closes the top-level object-inventory artifact gap only after exact-head CI passes. It does not prove complete schema definitions, grants, policy expressions, function bodies, dependencies, rebuild parity, or Production readiness. Those remain separate canonical-baseline gates.

Production impact: **NONE**.
