# Security Advisory — `public.approve_partner(uuid)` callable by anonymous role

- **Project:** HEHA SWIPE (Supabase ref `rqpdvgmewoyaigzquqmj`)
- **Date:** 2026-06-26
- **Severity:** High — unauthenticated privilege escalation / broken access control
- **Status:** Confirmed and **partially remediated in production**.
  - ✅ **Applied (2026-06-26):** `REVOKE EXECUTE` from `anon` and `PUBLIC`
    (Supabase migration `restrict_approve_partner_revoke_anon_public`). The
    unauthenticated exploit is closed — `anon` can no longer execute the RPC.
  - ⏳ **Deferred for review:** the function-body authorization check, pinned
    `search_path`, and tightened `authenticated` grant
    (`supabase/security/2026-06-26_restrict_approve_partner.sql`). Until applied,
    **any authenticated (logged-in) user can still call this RPC.**

> Scope note: this advisory is independent of PR #26 (Stripe supporter slider).
> No changes were made to checkout/Stripe code.

## Summary

`public.approve_partner(p_partner_id uuid)` approves a partner listing by
setting `partners.status = 'live'`. As originally deployed it could be executed
by the **anonymous (unauthenticated) role** through the PostgREST
`/rpc/approve_partner` endpoint, with no admin authorization. An unauthenticated
caller could approve (publish) arbitrary partner listings.

## Investigation findings

| # | Question | Finding |
|---|----------|---------|
| 1 | Can `anon` execute it? | **Was yes** (`has_function_privilege('anon', ...) = true`). **Now no** after the applied revoke. |
| 2 | Can authenticated non-admins execute it? | **Yes** — granted to `authenticated` with no role check in the body. Still true until the deferred body fix is applied. |
| 3 | Owner / SECURITY DEFINER / grants | Owner `postgres`; `SECURITY DEFINER = true`; `search_path` unset (NULL); original ACL granted EXECUTE to `PUBLIC`, `anon`, `authenticated`, `service_role`. Because the owner is `postgres`, the function's `UPDATE` bypasses RLS on `public.partners`. |
| 4 | Does it validate admin role internally? | **No.** The body is just an `UPDATE ... SET status='live'`. No `app_private.has_internal_role(...)` check. |
| 5 | Fix | Revoke EXECUTE from `anon`/`PUBLIC` (done); add internal admin/service_role check + pin `search_path` (proposed). See `supabase/security/2026-06-26_restrict_approve_partner.sql`. |
| 6 | Proof | See `supabase/security/approve_partner_security_proof.sql`. |

### Original definition (vulnerable)

```sql
CREATE OR REPLACE FUNCTION public.approve_partner(p_partner_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER          -- owner = postgres -> bypasses RLS
AS $function$
BEGIN
  UPDATE public.partners
  SET status = 'live', updated_at = NOW()
  WHERE id = p_partner_id;   -- no authorization check
END;
$function$
```

Original ACL: `{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
(`=X` = EXECUTE granted to PUBLIC).
Current ACL (after applied revoke): `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`.

## Impact

`partners` exposes a public read policy *"Anyone can view approved partners"*
for `status IN ('approved','live')`. Flipping a listing to `live` therefore
publishes it. An anonymous attacker who knew or enumerated a partner `id`
could publish unreviewed/unapproved listings, bypassing the admin approval
workflow.

## Proof (non-destructive, rolled back)

Before the revoke, executed against production inside a transaction that was
**rolled back** — no data persisted:

```
-- as role anon:
SELECT public.approve_partner('<partner_id>'::uuid);
-- result: partner.status changed 'approved' -> 'live'
ROLLBACK;
```

After the revoke, the same `anon` call fails with `42501 insufficient_privilege`
(permission denied for function), confirmed in production.

## Remaining recommended fix (defense in depth) — deferred

1. **Pin `search_path`** on the SECURITY DEFINER function (`= public, pg_temp`).
2. **Authorize in the body**: allow only `service_role` or an internal admin
   (`app_private.has_internal_role(array['super_admin','pm_admin','developer_admin'])`)
   — the same convention used by the admin dashboard RLS policies.
3. **Tighten grants**: grant only to `authenticated` (still gated by the body
   check) and `service_role`.

Full script: [`supabase/security/2026-06-26_restrict_approve_partner.sql`](../../supabase/security/2026-06-26_restrict_approve_partner.sql).

### Post-(full-)fix expectation

| role | EXECUTE granted | runtime result |
|------|-----------------|----------------|
| `anon` | no | permission denied |
| `authenticated` (non-admin) | yes | `42501 insufficient_privilege` raised |
| `authenticated` (admin) | yes | approves |
| `service_role` | yes | approves |

## Apply instructions (after approval)

Run `supabase/security/2026-06-26_restrict_approve_partner.sql` in the Supabase
SQL editor (or via migration), then re-run
`supabase/security/approve_partner_security_proof.sql` to confirm behavior.
