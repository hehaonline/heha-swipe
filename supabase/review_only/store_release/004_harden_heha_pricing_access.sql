-- REVIEW ONLY. Do not apply through migration automation.
-- Purpose: harden the live heha_pricing view without recreating it or restating
-- stale pricing constants.
--
-- Blocked until Wix, Make, HEHA Local, and other external consumers are
-- inventoried. Capture pg_get_viewdef(), owner, relkind, reloptions, and the
-- exact ACL matrix before any separately approved staging apply.

begin;

alter view public.heha_pricing
  set (security_invoker = true);

-- Revoke first from every browser/backend role, then restore only the service
-- role's read access. The object owner is not changed.
revoke all on table public.heha_pricing
  from public, anon, authenticated, service_role;
grant select on table public.heha_pricing
  to service_role;

commit;

-- Required disposable/staging proof:
--   * md5(pg_get_viewdef), owner, and relkind are unchanged;
--   * reloptions contains security_invoker=true;
--   * public/anon/authenticated have zero relation privileges;
--   * service_role has SELECT only;
--   * the security_definer_view advisor error disappears;
--   * all certified external consumers still pass.
