# Object Dependency and Missing Baseline Map

| Object family | Live evidence | Created by current chain? | First current dependency | Baseline treatment |
|---|---|---:|---|---|
| `auth.users`, `auth.uid()` | **[LP]** platform/live dependency | No | 20260618000100 | Managed Supabase prerequisite; reference, do not recreate |
| `app_private` and `has_internal_role` | **[RP]** required; live definition **[U]** | No | 20260618000100 | Capture reviewed schema/function/grants |
| `partners` | **[LP]** exists | No | 20260626120000 | Canonical table, constraints, indexes, RLS and grants |
| `user_roles` | **[LP]** exists | No | 20260618000100 | Canonical role table and RLS/function contract |
| Admin foundation tables | **[LP]** exist | No | 20260618000100 onward | Baseline tables, constraints, RLS, grants and triggers |
| `profiles` and customer/account tables | **[LP]** exist | No | 20260707062836 | Baseline full application schema |
| Supporter/payment/contribution tables | **[LP]** exist | No | 20260707062836 | Baseline without copying customer rows |
| Orders, saves, reviews, swipe events, photos/services | **[LP]** exist | No | No creator in current tree | Baseline to reproduce complete application schema |
| Community-offer redemption/public objects | **[LP]** exist | No | Applied ledger only | Recover definitions and baseline |
| `storage.objects`, `storage.buckets` | **[LP]** exist | Managed only | 20260706143000 | Preserve managed schema; separately seed approved bucket configuration |
| `extensions.pgcrypto` | **[LP]** installed | No | 20260716090000 | Explicit canonical prerequisite |
| Public views/functions/triggers/policies/grants | Partial names **[RP+LP]**; live bodies **[U]** | Incomplete | Multiple | Capture sanitized definitions before baseline approval |
| Enums/check constraints/materialized views/cron | **[U]** | Unknown | Unknown | Schema metadata export required |

The live project is PostgreSQL 17 and has `pgcrypto` installed under `extensions`. **[LP]**
