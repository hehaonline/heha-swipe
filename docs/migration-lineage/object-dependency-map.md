# Object Dependency and Missing Baseline Map

| Object family | Evidence classification | Created by current chain? | First current dependency | Baseline treatment |
|---|---|---:|---|---|
| `auth.users`, `auth.uid()` | Platform dependency **[RP]**; live state **[U]** | No | 20260618000100 | Managed Supabase prerequisite; reference, do not recreate |
| `app_private`, `app_private.has_internal_role(text[])` | Required signature **[RP]**; live body, overloads, owner and grants **[U]** | No | 20260618000100 | Capture reviewed schema, exact function definition and grants |
| `public.partners` | Required by current SQL **[RP]**; live existence and definition **[U]** | No | 20260626120000 | Canonical table, constraints, indexes, RLS and grants |
| `public.user_roles` | Required by current SQL **[RP]**; live existence and definition **[U]** | No | 20260618000100 | Canonical role table and RLS/function contract |
| `public.admin_audit_logs` | Required by draft PR #82 **[RP]**; live existence and definition **[U]** | No | PR #82 only | Recover table, constraints, indexes, RLS, grants and audit contract before compatibility approval |
| Other admin foundation tables | Partial dependencies **[RP]**; exact live objects **[U]** | No | 20260618000100 onward | Inventory each table, constraint, RLS policy, grant and trigger |
| `public.profiles` and customer/account tables | Required by current SQL **[RP]**; live existence and definition **[U]** | No | 20260707062836 | Baseline full application schema without copying rows |
| Supporter/payment/contribution tables | Required by current SQL **[RP]**; live existence and definition **[U]** | No | 20260707062836 | Recover definitions without copying customer or payment rows |
| Orders, saves, reviews, swipe events, photos/services | No creator in current tree **[RP]**; live existence and definitions **[U]** | No | No creator in current tree | Authorized schema metadata export required |
| Community-offer redemption/public objects | Names appear in the committed ledger snapshot **[RP]**; live definitions **[U]** | No | Applied-snapshot entries only | Recover definitions before baseline approval |
| `storage.objects`, `storage.buckets` | Managed dependency **[RP]**; live bucket/policy state **[U]** | Managed only | 20260706143000 | Preserve managed schema; separately seed only approved synthetic bucket configuration |
| `extensions.pgcrypto` | Required by draft PR #82 **[RP]**; installed version/schema **[U]** | No | PR #82 only | Verify and declare the canonical prerequisite after authorized access |
| Public views, functions, triggers, RLS policies and grants | Partial names/dependencies **[RP]**; exact live definitions **[U]** | Incomplete | Multiple | Capture sanitized definitions before baseline approval |
| Constraints, indexes, enums, materialized views and cron | Incomplete repository evidence **[RP]**; live definitions **[U]** | Unknown | Unknown | Authorized schema metadata export required |

The PostgreSQL major version and the installed state of `pgcrypto` remain **[U]** in this package. Unknown function, policy, grant, view, constraint, trigger and storage definitions must remain **[U]** until recovered through authorized, reproducible access.
