-- Proof / regression harness for public.approve_partner(uuid) hardening.
--
-- Run AFTER applying 20260626120000_harden_approve_partner_admin_only.sql to a
-- non-production environment (Supabase preview branch or staging).
-- It is read-only except for the wrapped approve calls, which run inside a
-- transaction that is ROLLED BACK, so no partner data persists.
--
-- Replace the sample UUIDs with a real active super_admin user_id and a real
-- non-admin user_id from the target environment before running.

-- ── Part 1: authorization predicate (no writes) ─────────────────────────────
-- Mirrors the in-body gate. Each statement runs in its own implicit transaction;
-- set_config(..., true) is local and discarded automatically.

-- (A) authenticated ADMIN  -> expect approve_allowed = true
select 'A_admin' as persona,
  coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role'
    or app_private.has_internal_role(array['super_admin','pm_admin']) as approve_allowed
from (select set_config('request.jwt.claims', '{"sub":"<ADMIN_USER_ID>","role":"authenticated"}', true)) cfg;

-- (B) authenticated NON-ADMIN -> expect approve_allowed = false
select 'B_non_admin' as persona,
  coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role'
    or app_private.has_internal_role(array['super_admin','pm_admin']) as approve_allowed
from (select set_config('request.jwt.claims', '{"sub":"<NON_ADMIN_USER_ID>","role":"authenticated"}', true)) cfg;

-- (C) service_role -> expect approve_allowed = true
select 'C_service_role' as persona,
  coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role'
    or app_private.has_internal_role(array['super_admin','pm_admin']) as approve_allowed
from (select set_config('request.jwt.claims', '{"role":"service_role"}', true)) cfg;

-- ── Part 2: EXECUTE privileges ──────────────────────────────────────────────
-- expect: anon=false, authenticated=true, service_role=true
select
  has_function_privilege('anon','public.approve_partner(uuid)','EXECUTE')          as anon_exec,
  has_function_privilege('authenticated','public.approve_partner(uuid)','EXECUTE') as authenticated_exec,
  has_function_privilege('service_role','public.approve_partner(uuid)','EXECUTE')  as service_exec;

-- ── Part 3: end-to-end deny/allow against a real call (rolled back) ──────────
-- Non-admin call must RAISE (42501) and change nothing; admin call must succeed.
-- Run interactively; ROLLBACK leaves partner data untouched.
--
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<NON_ADMIN_USER_ID>","role":"authenticated"}', true);
--   -- expect ERROR: Not authorized to approve partners (SQLSTATE 42501)
--   select public.approve_partner('<SOME_PENDING_PARTNER_ID>');
-- rollback;
--
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<ADMIN_USER_ID>","role":"authenticated"}', true);
--   -- expect success; verify status flips to 'live'
--   select public.approve_partner('<SOME_PENDING_PARTNER_ID>');
--   select id, status from public.partners where id = '<SOME_PENDING_PARTNER_ID>';
-- rollback;
