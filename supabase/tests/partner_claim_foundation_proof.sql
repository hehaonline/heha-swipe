-- Rollback-only security proof for 20260716090000_partner_claim_foundation.sql.
-- Run in a non-production database after the migration with psql ON_ERROR_STOP=1.
-- Required variables: partner_a_id, partner_b_id, user_a_id, user_b_id,
-- internal_admin_user_id. The two partner rows must be safe to mutate in this
-- rolled-back transaction; the admin must have an allowed active internal role.

begin;

-- psql does not reliably interpolate variables inside dollar-quoted DO blocks.
-- Store the supplied fixture IDs in transaction-local settings for those blocks.
select set_config('heha.proof.partner_a_id', :'partner_a_id', true);
select set_config('heha.proof.partner_b_id', :'partner_b_id', true);
select set_config('heha.proof.user_a_id', :'user_a_id', true);
select set_config('heha.proof.user_b_id', :'user_b_id', true);
select set_config('heha.proof.internal_admin_user_id', :'internal_admin_user_id', true);

create temporary table partner_claim_results (
  label text primary key,
  detail text not null
) on commit drop;

create or replace function pg_temp.set_auth_context(p_role text, p_sub uuid default null)
returns void language plpgsql as $$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_sub, 'role', p_role)::text, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);
  perform set_config('request.jwt.claim.role', p_role, true);
end;
$$;

create or replace function pg_temp.expect_error(p_label text, p_sql text, p_expected_state text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> p_expected_state then
      raise exception '% expected SQLSTATE %, got %: %', p_label, p_expected_state, sqlstate, sqlerrm;
    end if;
    insert into pg_temp.partner_claim_results values (p_label, 'denied with SQLSTATE ' || sqlstate);
    return;
  end;
  raise exception '% expected SQLSTATE %, but succeeded', p_label, p_expected_state;
end;
$$;

create or replace function pg_temp.expect_cross_business_update_zero(p_partner_id uuid)
returns void language plpgsql as $$
declare
  affected integer;
begin
  update public.partners set tagline = tagline where id = p_partner_id;
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Business B unexpectedly updated Business A';
  end if;
end;
$$;

do $$
declare
  fn regprocedure;
begin
  foreach fn in array array[
    'public.create_partner_claim_invite(uuid,interval,text,text)'::regprocedure,
    'public.preview_partner_claim(text)'::regprocedure,
    'public.claim_partner_profile(text)'::regprocedure,
    'public.revoke_partner_claim_invite(uuid)'::regprocedure
  ] loop
    if has_function_privilege('anon', fn, 'EXECUTE') then
      raise exception 'anon must not execute %', fn;
    end if;
    if not has_function_privilege('authenticated', fn, 'EXECUTE') then
      raise exception 'authenticated must execute %', fn;
    end if;
  end loop;

  if has_table_privilege('anon', 'public.partner_claim_invites', 'SELECT')
     or has_table_privilege('authenticated', 'public.partner_claim_invites', 'INSERT')
     or has_table_privilege('authenticated', 'public.partner_claim_invites', 'UPDATE')
     or has_table_privilege('authenticated', 'public.partner_claim_invites', 'DELETE') then
    raise exception 'partner_claim_invites grants are broader than intended';
  end if;

  insert into pg_temp.partner_claim_results values ('grants', 'anon RPC/table access revoked; authenticated RPC access is narrow');
end;
$$;

-- Normalize two disposable fixtures. ROLLBACK restores every value.
select pg_temp.set_auth_context('service_role');
update public.partners
set owner_id = null,
    relationship_status = 'community_listed',
    opted_out_at = null,
    opted_out_by = null
where id in (:'partner_a_id'::uuid, :'partner_b_id'::uuid);

select pg_temp.set_auth_context('authenticated', :'user_a_id'::uuid);
select pg_temp.expect_error(
  'invalid token',
  $$select * from public.claim_partner_profile('not-a-real-token')$$,
  'P0002'
);

select pg_temp.set_auth_context('authenticated', :'internal_admin_user_id'::uuid);
select pg_temp.expect_error(
  'null expiry rejected',
  format('select * from public.create_partner_claim_invite(%L, null, null, null)', :'partner_a_id'::uuid),
  '22023'
);

create temporary table claim_tokens as
select 'a'::text as fixture, *
from public.create_partner_claim_invite(:'partner_a_id'::uuid, interval '1 day', 'proof', null)
union all
select 'b'::text as fixture, *
from public.create_partner_claim_invite(:'partner_b_id'::uuid, interval '1 day', 'proof', null);

do $$
begin
  if exists (
    select 1 from public.partners
    where id in (
      current_setting('heha.proof.partner_a_id')::uuid,
      current_setting('heha.proof.partner_b_id')::uuid
    )
      and relationship_status <> 'community_listed'
  ) then
    raise exception 'creating an invite must not change relationship/publication state';
  end if;
  insert into pg_temp.partner_claim_results values ('invite ownership-only boundary', 'invite creation preserved partner relationship state');
end;
$$;

-- Expiry and revocation are terminal. Backdate both fields so the fixture remains
-- valid under partner_claim_invites_expiry_check while still being expired.
select pg_temp.set_auth_context('service_role');
update public.partner_claim_invites
set created_at = now() - interval '2 days',
    expires_at = now() - interval '1 day'
where id = (select invite_id from claim_tokens where fixture = 'b');

select pg_temp.set_auth_context('authenticated', :'user_b_id'::uuid);
select pg_temp.expect_error(
  'expired token',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from claim_tokens where fixture = 'b')),
  'P0002'
);

select pg_temp.set_auth_context('service_role');
update public.partner_claim_invites
set expires_at = now() + interval '1 day'
where id = (select invite_id from claim_tokens where fixture = 'b');

select pg_temp.set_auth_context('authenticated', :'internal_admin_user_id'::uuid);
select public.revoke_partner_claim_invite((select invite_id from claim_tokens where fixture = 'b'));
select pg_temp.set_auth_context('authenticated', :'user_b_id'::uuid);
select pg_temp.expect_error(
  'revoked token',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from claim_tokens where fixture = 'b')),
  'P0002'
);

-- Claim A once and prove stable identity plus ownership-only changes.
create temporary table partner_a_before as
select to_jsonb(p) as row_data from public.partners p where id = :'partner_a_id'::uuid;

select pg_temp.set_auth_context('authenticated', :'user_a_id'::uuid);
select * from public.claim_partner_profile((select raw_token from claim_tokens where fixture = 'a'));

do $$
declare
  before_row jsonb := (
    select row_data
    from partner_a_before
  );
  after_row jsonb := (
    select to_jsonb(p)
    from public.partners p
    where id = current_setting('heha.proof.partner_a_id')::uuid
  );
  allowed_keys constant text[] := array['owner_id','relationship_status','claimed_at','claimed_by','updated_at'];
begin
  if after_row->>'id' <> current_setting('heha.proof.partner_a_id')
     or after_row->>'owner_id' <> current_setting('heha.proof.user_a_id') then
    raise exception 'claim did not preserve canonical partner ID and assign expected owner';
  end if;
  if (before_row - allowed_keys) is distinct from (after_row - allowed_keys) then
    raise exception 'claim changed fields outside the ownership/claim audit allowlist';
  end if;
  insert into pg_temp.partner_claim_results values ('claim ownership-only boundary', 'stable partner ID; only owner and claim-audit fields changed');
end;
$$;

select pg_temp.set_auth_context('authenticated', :'user_b_id'::uuid);
select pg_temp.expect_error(
  'reused token takeover',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from claim_tokens where fixture = 'a')),
  'P0002'
);

-- Business B cannot update Business A through the owner policy.
reset role;
set local role authenticated;
select pg_temp.set_auth_context('authenticated', :'user_b_id'::uuid);
select pg_temp.expect_cross_business_update_zero(:'partner_a_id'::uuid);
reset role;
insert into pg_temp.partner_claim_results values ('business A versus B', 'cross-business owner update matched zero rows under RLS');

select label, detail from pg_temp.partner_claim_results order by label;
rollback;
