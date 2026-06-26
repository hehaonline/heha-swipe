-- =============================================================================
-- Security hardening: public.approve_partner(uuid)
-- =============================================================================
-- Project : HEHA SWIPE (Supabase ref: rqpdvgmewoyaigzquqmj)
-- Date    : 2026-06-26
-- Advisor : "approve_partner may be executable by the anonymous role"
--
-- STATUS  : PROPOSED — NOT YET APPLIED TO PRODUCTION.
--           Review and approve before running in the Supabase SQL editor.
--           This is a security/grants change; it does not alter the approval
--           outcome (status -> 'live') for legitimate admin callers.
--
-- WHY ----------------------------------------------------------------------
-- The deployed function is SECURITY DEFINER, owned by `postgres` (so its
-- UPDATE bypasses RLS on public.partners), has NO internal authorization
-- check, and EXECUTE is granted to PUBLIC + anon + authenticated.
-- Net effect (confirmed by SQL proof): an UNAUTHENTICATED caller hitting the
-- PostgREST RPC endpoint can flip any partner to status='live', which makes
-- it publicly visible via the "Anyone can view approved partners" policy.
--
-- FIX (defense in depth) ---------------------------------------------------
--   1. Pin search_path on the SECURITY DEFINER function.
--   2. Add an internal authorization check in the body: allow only the
--      trusted backend (service_role) or an internal admin role. This matches
--      the project convention app_private.has_internal_role(text[]).
--   3. Revoke EXECUTE from PUBLIC and anon; grant only to authenticated
--      (gated by the body check) and service_role.
-- =============================================================================

begin;

-- 1 + 2: redefine the function with a pinned search_path and an authz gate.
create or replace function public.approve_partner(p_partner_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = public, pg_temp
as $function$
begin
  -- Allow the trusted backend key (service_role) OR an internal admin.
  -- auth.role() reflects the JWT role even inside SECURITY DEFINER.
  if coalesce(auth.role(), '') <> 'service_role'
     and not app_private.has_internal_role(
       array['super_admin','pm_admin','developer_admin']
     )
  then
    raise exception
      'insufficient_privilege: approve_partner requires an internal admin role or service_role'
      using errcode = '42501';
  end if;

  update public.partners
     set status = 'live',
         updated_at = now()
   where id = p_partner_id;
end;
$function$;

-- 3: tighten EXECUTE grants. CREATE OR REPLACE preserves the old ACL, so the
--    revokes below are required to actually remove anon/public access.
revoke all     on function public.approve_partner(uuid) from public;
revoke execute on function public.approve_partner(uuid) from anon;
grant  execute on function public.approve_partner(uuid) to authenticated;  -- still gated by body check
grant  execute on function public.approve_partner(uuid) to service_role;

commit;

-- ---------------------------------------------------------------------------
-- Post-apply verification (expected results):
--   anon          -> false
--   authenticated -> true   (but body rejects non-admins at runtime)
--   service_role  -> true
-- ---------------------------------------------------------------------------
-- select
--   has_function_privilege('anon',          'public.approve_partner(uuid)', 'execute') as anon_exec,
--   has_function_privilege('authenticated', 'public.approve_partner(uuid)', 'execute') as auth_exec,
--   has_function_privilege('service_role',  'public.approve_partner(uuid)', 'execute') as service_exec;
