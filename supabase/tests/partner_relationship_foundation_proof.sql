-- Proof / regression harness for the partner relationship foundation.
--
-- Run AFTER applying 20260709173000_partner_relationship_foundation.sql to a
-- controlled non-production database, or a controlled production SQL session.
--
-- Required psql variables:
--   owner_user_id       - ordinary authenticated user id with no internal role
--   other_owner_user_id - second ordinary authenticated user id with no internal role
--   pm_admin_user_id    - authenticated user id with active pm_admin role only
--   super_admin_user_id - authenticated user id with active super_admin role
--
-- Example:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v owner_user_id=00000000-0000-0000-0000-000000000001 \
--     -v other_owner_user_id=00000000-0000-0000-0000-000000000002 \
--     -v pm_admin_user_id=00000000-0000-0000-0000-000000000003 \
--     -v super_admin_user_id=00000000-0000-0000-0000-000000000004 \
--     -f supabase/tests/partner_relationship_foundation_proof.sql
--
-- All mutation proof steps run inside BEGIN / ROLLBACK.

begin;

create temporary table partner_relationship_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;

create or replace function pg_temp.set_auth_context(p_role text, p_sub uuid default null)
returns void
language plpgsql
as $$
declare
  v_claims jsonb := case
    when p_sub is null then pg_catalog.jsonb_build_object('role', p_role)
    else pg_catalog.jsonb_build_object('sub', p_sub::text, 'role', p_role)
  end;
begin
  perform pg_catalog.set_config('request.jwt.claims', v_claims::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', p_role, true);
  perform pg_catalog.set_config('app.partner_interest_request_context', '', true);
end;
$$;

create or replace function pg_temp.clear_auth_context()
returns void
language plpgsql
as $$
begin
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  perform pg_catalog.set_config('request.jwt.claim.role', '', true);
  perform pg_catalog.set_config('app.partner_interest_request_context', '', true);
end;
$$;

create or replace function pg_temp.expect_sqlstate(p_label text, p_expected text, p_sql text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise exception '% expected SQLSTATE %, but statement succeeded', p_label, p_expected;
exception
  when others then
    if SQLSTATE = p_expected then
      insert into pg_temp.partner_relationship_results(label, ok, detail)
      values (p_label, true, 'denied with SQLSTATE ' || p_expected);
    else
      raise exception '% expected SQLSTATE %, got SQLSTATE %: %', p_label, p_expected, SQLSTATE, SQLERRM;
    end if;
end;
$$;

do $$
declare
  v_columns text[];
  v_guard_config text[];
  v_apply_config text[];
begin
  select array_agg(column_name order by column_name)
  into v_columns
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'partners'
    and column_name = any (array[
      'relationship_status',
      'contract_status',
      'partnership_requested_at',
      'official_partner_since',
      'contract_signed_at'
    ]);

  if v_columns is distinct from array[
    'contract_signed_at',
    'contract_status',
    'official_partner_since',
    'partnership_requested_at',
    'relationship_status'
  ]::text[] then
    raise exception 'Expected partner relationship columns are missing: %', v_columns;
  end if;

  if pg_catalog.has_function_privilege('anon', 'public.approve_heha_partnership(uuid)', 'EXECUTE') then
    raise exception 'anon must not have EXECUTE on public.approve_heha_partnership(uuid)';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', 'public.approve_heha_partnership(uuid)', 'EXECUTE') then
    raise exception 'authenticated must have EXECUTE so super_admin callers can pass the in-function gate';
  end if;

  if not pg_catalog.has_function_privilege('service_role', 'public.approve_heha_partnership(uuid)', 'EXECUTE') then
    raise exception 'service_role must have EXECUTE on public.approve_heha_partnership(uuid)';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.partner_interest_requests', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.partner_interest_requests', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.partner_interest_requests', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.partner_interest_requests', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_interest_requests', 'DELETE') then
    raise exception 'partner_interest_requests table privileges do not match intended matrix';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'partner_interest_requests'
      and indexname = 'partner_interest_requests_one_active_partner_idx'
      and indexdef like '%UNIQUE%'
      and indexdef like '%partner_id%'
      and indexdef like '%submitted%'
      and indexdef like '%reviewing%'
      and indexdef like '%needs_info%'
  ) then
    raise exception 'active partner_interest_requests unique index is missing or has unexpected predicate';
  end if;

  select p.proconfig
  into v_guard_config
  from pg_catalog.pg_proc p
  where p.oid = 'app_private.guard_partner_interest_request()'::regprocedure;

  select p.proconfig
  into v_apply_config
  from pg_catalog.pg_proc p
  where p.oid = 'app_private.apply_partner_interest_request_state()'::regprocedure;

  if not exists (
    select 1
    from unnest(coalesce(v_guard_config, array[]::text[])) as cfg(value)
    where cfg.value in ('search_path=', 'search_path=""')
  ) then
    raise exception 'guard_partner_interest_request must pin search_path to empty string';
  end if;

  if not exists (
    select 1
    from unnest(coalesce(v_apply_config, array[]::text[])) as cfg(value)
    where cfg.value in ('search_path=', 'search_path=""')
  ) then
    raise exception 'apply_partner_interest_request_state must pin search_path to empty string';
  end if;

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('metadata and grants', true, 'columns, function grants, table privileges, active uniqueness, and trigger search_path verified');
end;
$$;

do $$
declare
  v_owner uuid := :'owner_user_id'::uuid;
  v_other_owner uuid := :'other_owner_user_id'::uuid;
  v_partner uuid := pg_catalog.gen_random_uuid();
  v_other_partner uuid := pg_catalog.gen_random_uuid();
  v_local_partner_empty uuid := pg_catalog.gen_random_uuid();
  v_local_partner_items uuid := pg_catalog.gen_random_uuid();
  v_duplicate_partner uuid := pg_catalog.gen_random_uuid();
  v_request uuid;
  v_duplicate_request uuid;
  v_relationship text;
  v_contract text;
  v_requested_at timestamptz;
  v_consent_at timestamptz;
  v_window_start timestamptz;
  v_window_end timestamptz;
begin
  perform pg_temp.clear_auth_context();

  insert into public.partners (id, owner_id, name, category, status, heha_partner)
  values
    (v_partner, v_owner, 'Proof Listed Business', 'Proof', 'approved', false),
    (v_other_partner, v_other_owner, 'Other Proof Business', 'Proof', 'approved', false),
    (v_local_partner_empty, v_owner, 'Proof Local Empty Intake Business', 'Proof', 'approved', false),
    (v_local_partner_items, v_owner, 'Proof Local Items Intake Business', 'Proof', 'approved', false),
    (v_duplicate_partner, v_owner, 'Proof Duplicate Protection Business', 'Proof', 'approved', false);

  select relationship_status, contract_status
  into v_relationship, v_contract
  from public.partners
  where id = v_partner;

  if v_relationship <> 'listed_only' or v_contract <> 'not_required' then
    raise exception 'Default relationship state mismatch: %, %', v_relationship, v_contract;
  end if;

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('relationship defaults', true, 'new partner rows default to listed_only/not_required');

  perform pg_temp.set_auth_context('authenticated', v_owner);

  v_window_start := pg_catalog.now() - interval '1 second';
  insert into public.partner_interest_requests (
    partner_id,
    owner_id,
    contact_consent,
    contact_consent_at,
    swipe_card_interest,
    heha_local_interest,
    starter_items
  ) values (
    v_partner,
    v_owner,
    true,
    '2001-01-01 00:00:00+00'::timestamptz,
    true,
    false,
    '[]'::jsonb
  ) returning id, contact_consent_at into v_request, v_consent_at;
  v_window_end := pg_catalog.now() + interval '1 second';

  if v_consent_at = '2001-01-01 00:00:00+00'::timestamptz
     or v_consent_at < v_window_start
     or v_consent_at > v_window_end then
    raise exception 'owner-supplied contact_consent_at was not replaced with server timestamp: % outside % - %',
      v_consent_at, v_window_start, v_window_end;
  end if;

  select relationship_status, contract_status, partnership_requested_at
  into v_relationship, v_contract, v_requested_at
  from public.partners
  where id = v_partner;

  if v_relationship <> 'partnership_requested'
     or v_contract <> 'not_signed'
     or v_requested_at is null then
    raise exception 'Successful request did not advance partner state: %, %, %', v_relationship, v_contract, v_requested_at;
  end if;

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('owner valid request', true, 'owner request created, client consent timestamp replaced, and partner moved to partnership_requested/not_signed');

  perform pg_temp.expect_sqlstate(
    'owner request requires contact consent',
    '42501',
    format(
      'insert into public.partner_interest_requests (partner_id, owner_id, contact_consent) values (%L, %L, false)',
      v_partner,
      v_owner
    )
  );

  perform pg_temp.expect_sqlstate(
    'owner cannot request another owner listing',
    '42501',
    format(
      'insert into public.partner_interest_requests (partner_id, owner_id, contact_consent) values (%L, %L, true)',
      v_other_partner,
      v_owner
    )
  );

  perform pg_temp.expect_sqlstate(
    'owner cannot directly set official_partner',
    '42501',
    format(
      'update public.partners set relationship_status = %L where id = %L',
      'official_partner',
      v_partner
    )
  );

  perform pg_temp.expect_sqlstate(
    'owner cannot directly sign contract',
    '42501',
    format(
      'update public.partners set contract_status = %L where id = %L',
      'signed',
      v_partner
    )
  );

  perform pg_temp.expect_sqlstate(
    'owner cannot change request status',
    '42501',
    format(
      'update public.partner_interest_requests set status = %L where id = %L',
      'reviewing',
      v_request
    )
  );

  perform pg_temp.expect_sqlstate(
    'owner cannot change request owner_id',
    '42501',
    format(
      'update public.partner_interest_requests set owner_id = %L where id = %L',
      v_other_owner,
      v_request
    )
  );

  perform pg_temp.expect_sqlstate(
    'owner cannot change request partner_id',
    '42501',
    format(
      'update public.partner_interest_requests set partner_id = %L where id = %L',
      v_other_partner,
      v_request
    )
  );

  insert into public.partner_interest_requests (
    partner_id,
    owner_id,
    contact_consent,
    heha_local_interest,
    starter_items
  ) values (
    v_duplicate_partner,
    v_owner,
    true,
    false,
    '[]'::jsonb
  ) returning id into v_duplicate_request;

  perform pg_temp.expect_sqlstate(
    'duplicate active request rejected',
    '23505',
    format(
      'insert into public.partner_interest_requests (partner_id, owner_id, contact_consent) values (%L, %L, true)',
      v_duplicate_partner,
      v_owner
    )
  );

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('duplicate active request protection', true, 'second submitted/reviewing/needs_info request for the same partner is rejected by unique index');

  perform pg_temp.set_auth_context('service_role');
  update public.partner_interest_requests
  set status = 'converted'
  where id = v_duplicate_request;

  perform pg_temp.set_auth_context('authenticated', v_owner);
  insert into public.partner_interest_requests (
    partner_id,
    owner_id,
    contact_consent,
    heha_local_interest,
    starter_items
  ) values (
    v_duplicate_partner,
    v_owner,
    true,
    false,
    '[]'::jsonb
  ) returning id into v_duplicate_request;

  perform pg_temp.set_auth_context('service_role');
  update public.partner_interest_requests
  set status = 'closed'
  where id = v_duplicate_request;

  perform pg_temp.set_auth_context('authenticated', v_owner);
  insert into public.partner_interest_requests (
    partner_id,
    owner_id,
    contact_consent,
    heha_local_interest,
    starter_items
  ) values (
    v_duplicate_partner,
    v_owner,
    true,
    false,
    '[]'::jsonb
  );

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('historical request reuse', true, 'converted and closed historical requests do not block a future active request');

  insert into public.partner_interest_requests (
    partner_id,
    owner_id,
    contact_consent,
    heha_local_interest,
    starter_items
  ) values (
    v_local_partner_empty,
    v_owner,
    true,
    false,
    '[]'::jsonb
  );

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('local starter false permits empty', true, 'heha_local_interest=false permits [] starter_items');

  perform pg_temp.expect_sqlstate(
    'local starter rejects fewer than 3',
    '23514',
    format(
      'insert into public.partner_interest_requests (partner_id, owner_id, contact_consent, heha_local_interest, starter_items) values (%L, %L, true, true, %L::jsonb)',
      v_local_partner_items,
      v_owner,
      '[{"name":"one"},{"name":"two"}]'
    )
  );

  insert into public.partner_interest_requests (
    partner_id,
    owner_id,
    contact_consent,
    heha_local_interest,
    starter_items
  ) values (
    v_local_partner_items,
    v_owner,
    true,
    true,
    '[{"name":"one"},{"name":"two"},{"name":"three"}]'::jsonb
  );

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('local starter accepts 3 to 6', true, 'heha_local_interest=true accepts three starter items');

  perform pg_temp.expect_sqlstate(
    'local starter rejects more than 6',
    '23514',
    format(
      'insert into public.partner_interest_requests (partner_id, owner_id, contact_consent, heha_local_interest, starter_items) values (%L, %L, true, true, %L::jsonb)',
      v_local_partner_items,
      v_owner,
      '[{"name":"one"},{"name":"two"},{"name":"three"},{"name":"four"},{"name":"five"},{"name":"six"},{"name":"seven"}]'
    )
  );
end;
$$;

do $$
declare
  v_owner uuid := :'owner_user_id'::uuid;
  v_approval_partner uuid := pg_catalog.gen_random_uuid();
  v_service_partner uuid := pg_catalog.gen_random_uuid();
  v_status_before text := 'approved';
  v_heha_before boolean := false;
  v_relationship text;
  v_contract text;
  v_status_after text;
  v_heha_after boolean;
  v_signed_at timestamptz;
  v_since timestamptz;
begin
  perform pg_temp.clear_auth_context();

  insert into public.partners (
    id,
    owner_id,
    name,
    category,
    status,
    heha_partner,
    relationship_status,
    contract_status,
    partnership_requested_at
  ) values (
    v_approval_partner,
    v_owner,
    'Proof Approval Business',
    'Proof',
    v_status_before,
    v_heha_before,
    'partnership_requested',
    'not_signed',
    now()
  ), (
    v_service_partner,
    v_owner,
    'Proof Service Approval Business',
    'Proof',
    v_status_before,
    v_heha_before,
    'partnership_requested',
    'not_signed',
    now()
  );

  perform pg_temp.set_auth_context('authenticated', v_owner);
  perform pg_temp.expect_sqlstate(
    'ordinary authenticated cannot approve official partnership',
    '42501',
    format('select public.approve_heha_partnership(%L)', v_approval_partner)
  );

  perform pg_temp.set_auth_context('authenticated', :'pm_admin_user_id'::uuid);
  perform pg_temp.expect_sqlstate(
    'pm_admin cannot approve official partnership',
    '42501',
    format('select public.approve_heha_partnership(%L)', v_approval_partner)
  );

  perform pg_temp.set_auth_context('authenticated', :'super_admin_user_id'::uuid);
  perform public.approve_heha_partnership(v_approval_partner);

  select relationship_status, contract_status, status, heha_partner, contract_signed_at, official_partner_since
  into v_relationship, v_contract, v_status_after, v_heha_after, v_signed_at, v_since
  from public.partners
  where id = v_approval_partner;

  if v_relationship <> 'official_partner'
     or v_contract <> 'signed'
     or v_signed_at is null
     or v_since is null
     or v_status_after is distinct from v_status_before
     or v_heha_after is distinct from v_heha_before then
    raise exception 'super_admin approval mutated unexpected fields: rel %, contract %, status %, heha %, signed %, since %',
      v_relationship, v_contract, v_status_after, v_heha_after, v_signed_at, v_since;
  end if;

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('super_admin official approval', true, 'super_admin approves official_partner without changing status or heha_partner');

  perform pg_temp.set_auth_context('service_role');
  perform public.approve_heha_partnership(v_service_partner);

  select relationship_status, contract_status, status, heha_partner, contract_signed_at, official_partner_since
  into v_relationship, v_contract, v_status_after, v_heha_after, v_signed_at, v_since
  from public.partners
  where id = v_service_partner;

  if v_relationship <> 'official_partner'
     or v_contract <> 'signed'
     or v_signed_at is null
     or v_since is null
     or v_status_after is distinct from v_status_before
     or v_heha_after is distinct from v_heha_before then
    raise exception 'service_role approval mutated unexpected fields: rel %, contract %, status %, heha %, signed %, since %',
      v_relationship, v_contract, v_status_after, v_heha_after, v_signed_at, v_since;
  end if;

  insert into pg_temp.partner_relationship_results(label, ok, detail)
  values ('service_role official approval', true, 'service_role approves official_partner without changing status or heha_partner');
end;
$$;

select label, ok, detail
from pg_temp.partner_relationship_results
order by label;

rollback;
