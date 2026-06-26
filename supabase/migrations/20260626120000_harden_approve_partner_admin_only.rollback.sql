-- EMERGENCY ROLLBACK for 20260626120000_harden_approve_partner_admin_only.sql
--
-- Use ONLY if the hardened gate unexpectedly blocks the legitimate admin approval
-- workflow (e.g., admins are not represented in public.user_roles as super_admin/
-- pm_admin, or the app approves via a role/path not covered by the gate).
--
-- This restores the previous approval behavior BUT intentionally keeps:
--   * search_path pinned (security hardening that is safe to keep), and
--   * EXECUTE revoked from anon/PUBLIC (do NOT reintroduce anonymous approval).
-- It removes only the admin/service authorization check.

create or replace function public.approve_partner(p_partner_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $function$
begin
  update public.partners
  set status = 'live',
      updated_at = pg_catalog.now()
  where id = p_partner_id;
end;
$function$;

revoke execute on function public.approve_partner(uuid) from public;
revoke execute on function public.approve_partner(uuid) from anon;
grant  execute on function public.approve_partner(uuid) to authenticated;
grant  execute on function public.approve_partner(uuid) to service_role;

-- Preferred fix instead of rolling back: ensure the approving admins have an active
-- row in public.user_roles with role super_admin or pm_admin, then keep the hardened
-- function in place.
