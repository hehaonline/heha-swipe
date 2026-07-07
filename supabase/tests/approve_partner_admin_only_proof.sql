-- Proof / regression harness for the partner security foundation.
--
-- Run AFTER applying 20260707045848_partner_security_foundation.sql to a
-- non-production environment or a controlled production SQL session.
--
-- Required psql variables:
--   partner_id          - a real partner row id safe to approve inside a rolled-back transaction
--   ordinary_user_id    - an authenticated user id with no internal role
--   pm_admin_user_id    - an authenticated user id with an active pm_admin role
--   super_admin_user_id - an authenticated user id with an active super_admin role
--
-- Example:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v partner_id=00000000-0000-0000-0000-000000000000 \
--     -v ordinary_user_id=00000000-0000-0000-0000-000000000001 \
--     -v pm_admin_user_id=00000000-0000-0000-0000-000000000002 \
--     -v super_admin_user_id=00000000-0000-0000-0000-000000000003 \
--     -f supabase/tests/approve_partner_admin_only_proof.sql
--
-- All approve_partner calls run inside BEGIN / ROLLBACK.

begin;

create temporary table partner_security_foundation_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;

create or replace function pg_temp.set_auth_context(p_role text, p_sub uuid default null)
returns void
language plpgsql
as $$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', v_sub, 'role', p_role)::text,
    true
  );
  perform set_config('request.jwt.claim.sub', v_sub, true);
  perform set_config('request.jwt.claim.role', p_role, true);
end;
$$;

create or replace function pg_temp.expect_approve_denied(p_label text, p_partner_id uuid)
returns void
language plpgsql
as $$
begin
  perform public.approve_partner(p_partner_id);
  raise exception '% expected SQLSTATE 42501, but approve_partner succeeded', p_label;
exception
  when insufficient_privilege then
    insert into pg_temp.partner_security_foundation_results(label, ok, detail)
    values (p_label, true, 'denied with SQLSTATE 42501');
end;
$$;

create or replace function pg_temp.expect_approve_allowed(p_label text, p_partner_id uuid)
returns void
language plpgsql
as $$
begin
  perform public.approve_partner(p_partner_id);
  insert into pg_temp.partner_security_foundation_results(label, ok, detail)
  values (p_label, true, 'approve_partner call succeeded');
exception
  when others then
    raise exception '% expected success, got SQLSTATE %: %', p_label, SQLSTATE, SQLERRM;
end;
$$;

do $$
begin
  if pg_catalog.has_function_privilege('anon', 'public.approve_partner(uuid)', 'EXECUTE') then
    raise exception 'anon must not have EXECUTE on public.approve_partner(uuid)';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', 'public.approve_partner(uuid)', 'EXECUTE') then
    raise exception 'authenticated must retain EXECUTE on public.approve_partner(uuid) for super_admin callers';
  end if;

  if not pg_catalog.has_function_privilege('service_role', 'public.approve_partner(uuid)', 'EXECUTE') then
    raise exception 'service_role must retain EXECUTE on public.approve_partner(uuid)';
  end if;

  insert into pg_temp.partner_security_foundation_results(label, ok, detail)
  values ('approve_partner grants', true, 'anon revoked; authenticated and service_role retained');
end;
$$;

select pg_temp.set_auth_context('anon');
select pg_temp.expect_approve_denied('approve_partner anon denied', :'partner_id'::uuid);

select pg_temp.set_auth_context('authenticated', :'ordinary_user_id'::uuid);
select pg_temp.expect_approve_denied('approve_partner ordinary authenticated denied', :'partner_id'::uuid);

select pg_temp.set_auth_context('authenticated', :'pm_admin_user_id'::uuid);
select pg_temp.expect_approve_denied('approve_partner pm_admin denied', :'partner_id'::uuid);

select pg_temp.set_auth_context('authenticated', :'super_admin_user_id'::uuid);
select pg_temp.expect_approve_allowed('approve_partner super_admin allowed', :'partner_id'::uuid);

select pg_temp.set_auth_context('service_role');
select pg_temp.expect_approve_allowed('approve_partner service_role allowed', :'partner_id'::uuid);

do $$
declare
  v_record_swipe regprocedure := pg_catalog.to_regprocedure('public.record_swipe(uuid,text,text)');
begin
  if v_record_swipe is null then
    raise exception 'public.record_swipe(uuid,text,text) is missing; expected legacy RPC to exist for grant hardening proof';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) acl
    where p.oid = v_record_swipe
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC must not have EXECUTE on public.record_swipe(uuid,text,text)';
  end if;

  if pg_catalog.has_function_privilege('anon', v_record_swipe, 'EXECUTE') then
    raise exception 'anon must not have EXECUTE on public.record_swipe(uuid,text,text)';
  end if;

  if pg_catalog.has_function_privilege('authenticated', v_record_swipe, 'EXECUTE') then
    raise exception 'authenticated must not have EXECUTE on public.record_swipe(uuid,text,text)';
  end if;

  if not pg_catalog.has_function_privilege('service_role', v_record_swipe, 'EXECUTE') then
    raise exception 'service_role should retain EXECUTE on public.record_swipe(uuid,text,text)';
  end if;

  insert into pg_temp.partner_security_foundation_results(label, ok, detail)
  values ('record_swipe grants', true, 'PUBLIC, anon, and authenticated revoked; service_role retained');
end;
$$;

do $$
begin
  if pg_catalog.to_regclass('public.swipe_events') is null then
    raise exception 'public.swipe_events table is missing';
  end if;

  if pg_catalog.to_regclass('public.saves') is null then
    raise exception 'public.saves table is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.swipe_events'::regclass
      and not tgisinternal
      and tgenabled <> 'D'
      and (tgtype::int & 4) = 4
      and (tgtype::int & 2) = 0
  ) then
    raise exception 'Expected enabled AFTER INSERT trigger on public.swipe_events';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.saves'::regclass
      and not tgisinternal
      and tgenabled <> 'D'
      and (tgtype::int & 4) = 4
      and (tgtype::int & 2) = 0
  ) then
    raise exception 'Expected enabled AFTER INSERT trigger on public.saves';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.saves'::regclass
      and not tgisinternal
      and tgenabled <> 'D'
      and (tgtype::int & 8) = 8
      and (tgtype::int & 2) = 0
  ) then
    raise exception 'Expected enabled AFTER DELETE trigger on public.saves';
  end if;

  insert into pg_temp.partner_security_foundation_results(label, ok, detail)
  values ('swipe/save stats triggers', true, 'swipe_events AFTER INSERT and saves AFTER INSERT/DELETE triggers are present');
end;
$$;

select label, ok, detail
from pg_temp.partner_security_foundation_results
order by label;

rollback;
