-- =============================================================================
-- SQL proof: anon access to public.approve_partner(uuid)
-- =============================================================================
-- Project: HEHA SWIPE (Supabase ref: rqpdvgmewoyaigzquqmj)
-- Run these read-only / rolled-back checks in the Supabase SQL editor.
-- They never persist changes to production (each exploit demo ends in ROLLBACK).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- A) Static facts about the deployed function
--    BEFORE the fix you will see: security_definer = true, owner = postgres,
--    config = NULL (no pinned search_path), and acl granting EXECUTE to
--    anon/PUBLIC.
-- ---------------------------------------------------------------------------
select
  n.nspname                                   as schema,
  p.proname                                   as function_name,
  pg_get_function_identity_arguments(p.oid)   as args,
  pg_get_userbyid(p.proowner)                 as owner,
  p.prosecdef                                 as security_definer,
  p.proconfig                                 as config_settings,
  p.proacl                                    as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'approve_partner';

-- ---------------------------------------------------------------------------
-- B) EXECUTE privilege per role.
--    BEFORE fix:  anon=true,  authenticated=true, service_role=true
--    AFTER  fix:  anon=false, authenticated=true, service_role=true
-- ---------------------------------------------------------------------------
select
  has_function_privilege('anon',          'public.approve_partner(uuid)', 'execute') as anon_exec,
  has_function_privilege('authenticated', 'public.approve_partner(uuid)', 'execute') as auth_exec,
  has_function_privilege('service_role',  'public.approve_partner(uuid)', 'execute') as service_exec;

-- ---------------------------------------------------------------------------
-- C) Dynamic exploit demo (ROLLED BACK — nothing is persisted).
--    BEFORE fix: the partner flips approved/listed -> 'live' as the anon role.
--    AFTER  fix: the SELECT call raises
--                "insufficient_privilege ... requires an internal admin role
--                 or service_role" (or "permission denied for function" because
--                 the EXECUTE grant was revoked), and status is unchanged.
--
--    Replace the id literal with any real, non-live partner id, e.g.:
--      select id, status, name from public.partners
--      where status is distinct from 'live' order by created_at limit 1;
-- ---------------------------------------------------------------------------
begin;
  set local role anon;
  select public.approve_partner('00000000-0000-0000-0000-000000000000'::uuid) as anon_call_returned;
  reset role;
  select id as partner_id, status as status_after_anon_call
    from public.partners
   where id = '00000000-0000-0000-0000-000000000000';
rollback;
