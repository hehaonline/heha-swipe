-- Extended rollback-only proof for PR #82.
-- Requires the synthetic baseline fixture and partner-claim migration.

begin;

-- Match the live prerequisite helper grant so RLS policies can evaluate it.
grant execute on function app_private.has_internal_role(text[]) to anon, authenticated;

create temporary table partner_claim_extended_results (
  label text primary key,
  detail text not null
) on commit drop;

create or replace function pg_temp.set_auth_context(p_role text, p_sub uuid default null)
returns void
language plpgsql
as $$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_sub, 'role', p_role)::text, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);
  perform set_config('request.jwt.claim.role', p_role, true);
end;
$$;

create or replace function pg_temp.expect_error(p_label text, p_sql text, p_expected_state text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> p_expected_state then
      raise exception '% expected SQLSTATE %, got %: %', p_label, p_expected_state, sqlstate, sqlerrm;
    end if;
    insert into pg_temp.partner_claim_extended_results
    values (p_label, 'denied with SQLSTATE ' || sqlstate);
    return;
  end;
  raise exception '% expected SQLSTATE %, but succeeded', p_label, p_expected_state;
end;
$$;

-- SECURITY DEFINER and fixed search_path proof.
do $$
declare
  fn record;
begin
  for fn in
    select
      p.oid::regprocedure as signature,
      p.prosecdef,
      p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'create_partner_claim_invite',
        'preview_partner_claim',
        'claim_partner_profile',
        'revoke_partner_claim_invite'
      )
  loop
    if not fn.prosecdef then
      raise exception '% must remain SECURITY DEFINER', fn.signature;
    end if;
    if fn.proconfig is null
       or not exists (
         select 1
         from unnest(fn.proconfig) as setting
         where setting like 'search_path=%'
       ) then
      raise exception '% must have an explicit search_path', fn.signature;
    end if;
  end loop;

  insert into pg_temp.partner_claim_extended_results
  values ('function hardening', 'all claim RPCs are SECURITY DEFINER with explicit search_path');
end;
$$;

-- Ordinary authenticated users cannot create invitations.
select pg_temp.set_auth_context('authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_error(
  'unauthorized invite creation',
  $$select * from public.create_partner_claim_invite(
      '22222222-2222-4222-8222-222222222222', interval '1 day', 'proof',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null
    )$$,
  '42501'
);

select pg_temp.expect_error(
  'ordinary user invite revocation',
  $$select public.revoke_partner_claim_invite('99999999-9999-4999-8999-999999999999')$$,
  '42501'
);

-- An authenticated but unsupported internal role cannot read, create or revoke.
select pg_temp.set_auth_context('authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select pg_temp.expect_error(
  'unsupported role invite creation',
  $$select * from public.create_partner_claim_invite(
      '22222222-2222-4222-8222-222222222222', interval '1 day', 'proof',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null
    )$$,
  '42501'
);
select pg_temp.expect_error(
  'unsupported role invite revocation',
  $$select public.revoke_partner_claim_invite('99999999-9999-4999-8999-999999999999')$$,
  '42501'
);

set local role authenticated;
select pg_temp.set_auth_context('authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
do $$
begin
  if exists (select 1 from public.partner_claim_invites) then
    raise exception 'unsupported internal role enumerated claim invitations';
  end if;
end;
$$;
reset role;
insert into pg_temp.partner_claim_extended_results
values ('unsupported role boundary', 'unsupported internal role cannot read, create or revoke invitations');

do $$
begin
  if has_table_privilege('anon', 'public.partner_claim_invites', 'SELECT')
     or has_function_privilege('anon', 'public.create_partner_claim_invite(uuid,interval,text,uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.revoke_partner_claim_invite(uuid)', 'EXECUTE') then
    raise exception 'anonymous claim-invite access is broader than intended';
  end if;
  insert into pg_temp.partner_claim_extended_results
  values ('anonymous claim boundary', 'anonymous users cannot read, create or revoke invitations');
end;
$$;

-- Already-owned profiles cannot receive a new claim invitation.
select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select pg_temp.expect_error(
  'already-owned invitation rejected',
  $$select * from public.create_partner_claim_invite(
      '33333333-3333-4333-8333-333333333333', interval '1 day', 'proof',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null
    )$$,
  '23505'
);

select pg_temp.expect_error(
  'missing intended recipient rejected',
  $$select * from public.create_partner_claim_invite(
      '22222222-2222-4222-8222-222222222222', interval '1 day', 'proof',
      null, null
    )$$,
  '22023'
);

select pg_temp.expect_error(
  'ambiguous intended recipient rejected',
  $$select * from public.create_partner_claim_invite(
      '22222222-2222-4222-8222-222222222222', interval '1 day', 'proof',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'claim-owner-a@example.invalid'
    )$$,
  '22023'
);

-- Opted-out profiles remain unclaimable.
select pg_temp.set_auth_context('service_role');
update public.partners
set relationship_status = 'opted_out',
    opted_out_at = now()
where id = '44444444-4444-4444-8444-444444444444';

select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select pg_temp.expect_error(
  'opted-out invitation rejected',
  $$select * from public.create_partner_claim_invite(
      '44444444-4444-4444-8444-444444444444', interval '1 day', 'proof',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null
    )$$,
  '42501'
);

-- Create a claim for Business A and verify token storage, preview and preservation.
create temporary table extended_token_a as
select *
from public.create_partner_claim_invite(
  '11111111-1111-4111-8111-111111111111',
  interval '1 day',
  'proof',
  null,
  ' CLAIM-OWNER-A@EXAMPLE.INVALID '
);

create temporary table extended_partner_a_before as
select to_jsonb(p) as row_data
from public.partners p
where p.id = '11111111-1111-4111-8111-111111111111';

create temporary table extended_history_before as
select
  (select count(*) from public.saves where partner_id = '11111111-1111-4111-8111-111111111111') as save_count,
  (select count(*) from public.swipes where partner_id = '11111111-1111-4111-8111-111111111111') as swipe_count;

do $$
declare
  raw_value text := (select raw_token from extended_token_a);
  stored_hash bytea := (
    select token_hash
    from public.partner_claim_invites
    where id = (select invite_id from extended_token_a)
  );
  stored_invite public.partner_claim_invites%rowtype;
begin
  select * into stored_invite
  from public.partner_claim_invites
  where id = (select invite_id from extended_token_a);
  if stored_hash is null then
    raise exception 'claim token hash was not stored';
  end if;
  if stored_hash <> extensions.digest(raw_value, 'sha256') then
    raise exception 'stored token hash does not match SHA-256 of the raw token';
  end if;
  if encode(stored_hash, 'hex') = raw_value then
    raise exception 'raw token appears to be stored instead of its hash';
  end if;
  if stored_invite.intended_user_id <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid
     or stored_invite.intended_email_normalized is not null
     or stored_invite.recipient_hint like '%claim-owner-a@example.invalid%' then
    raise exception 'existing-account invitation was not safely user-bound';
  end if;
  insert into pg_temp.partner_claim_extended_results
  values ('token and recipient storage', 'token is hashed; existing recipient is bound by user ID with a masked hint');
end;
$$;

-- A forwarded valid link fails closed for the wrong authenticated account.
select pg_temp.set_auth_context('authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select pg_temp.expect_error(
  'wrong intended user preview',
  format('select * from public.preview_partner_claim(%L)', (select raw_token from extended_token_a)),
  '42501'
);
select pg_temp.expect_error(
  'forwarded link wrong account claim',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from extended_token_a)),
  '42501'
);

do $$
begin
  if exists (
    select 1
    from public.partner_claim_invites
    where id = (select invite_id from extended_token_a)
      and (consumed_at is not null or revoked_at is not null)
  ) or exists (
    select 1 from public.partners
    where id = '11111111-1111-4111-8111-111111111111'
      and owner_id is not null
  ) then
    raise exception 'recipient mismatch changed ownership or terminal invitation state';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('intended user mismatch', 'forwarded link failed without consuming, revoking or assigning ownership');
end;
$$;

select pg_temp.set_auth_context('authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

do $$
declare
  preview_row record;
begin
  select * into preview_row
  from public.preview_partner_claim((select raw_token from extended_token_a));

  if preview_row.partner_id <> '11111111-1111-4111-8111-111111111111'::uuid
     or preview_row.partner_name <> 'Synthetic Business A'
     or preview_row.claimable is not true then
    raise exception 'valid preview did not return the expected partner';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('valid preview', 'authenticated preview returned the token-bound synthetic business');
end;
$$;

select *
from public.claim_partner_profile((select raw_token from extended_token_a));

do $$
declare
  before_row jsonb := (select row_data from extended_partner_a_before);
  after_row jsonb := (
    select to_jsonb(p)
    from public.partners p
    where p.id = '11111111-1111-4111-8111-111111111111'
  );
  expected_saves integer := (select save_count from extended_history_before);
  expected_swipes integer := (select swipe_count from extended_history_before);
  actual_saves integer;
  actual_swipes integer;
  allowed_keys constant text[] := array['owner_id','relationship_status','claimed_at','claimed_by','updated_at'];
begin
  if after_row->>'id' <> '11111111-1111-4111-8111-111111111111'
     or after_row->>'owner_id' <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' then
    raise exception 'claim did not preserve Business A identity or expected owner';
  end if;

  if (before_row - allowed_keys) is distinct from (after_row - allowed_keys) then
    raise exception 'claim changed publication, routing, product or analytics fields';
  end if;

  select count(*) into actual_saves
  from public.saves
  where partner_id = '11111111-1111-4111-8111-111111111111';

  select count(*) into actual_swipes
  from public.swipes
  where partner_id = '11111111-1111-4111-8111-111111111111';

  if actual_saves <> expected_saves or actual_swipes <> expected_swipes then
    raise exception 'claim detached existing save or swipe history';
  end if;

  if not exists (
    select 1
    from public.admin_audit_logs
    where action_type = 'partner_profile_claimed'
      and related_id = '11111111-1111-4111-8111-111111111111'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) then
    raise exception 'successful claim audit row missing';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('identity and history preservation', 'Partner ID, public fields, saves and swipes remained attached');
end;
$$;

select pg_temp.set_auth_context('authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select pg_temp.expect_error(
  'extended reused token rejected',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from extended_token_a)),
  'P0002'
);

-- RLS prevents ordinary users from enumerating claim invitations.
reset role;
set local role authenticated;
select pg_temp.set_auth_context('authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
do $$
begin
  if exists (select 1 from public.partner_claim_invites) then
    raise exception 'ordinary authenticated user enumerated claim invitations';
  end if;
end;
$$;
reset role;
insert into pg_temp.partner_claim_extended_results
values ('claim invite RLS', 'ordinary authenticated users cannot enumerate invitations');

-- Internal admin can see the invitation rows through the intended policy.
set local role authenticated;
select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
do $$
begin
  if not exists (select 1 from public.partner_claim_invites) then
    raise exception 'internal admin could not inspect claim invitation state';
  end if;
end;
$$;
reset role;
insert into pg_temp.partner_claim_extended_results
values ('internal claim visibility', 'authorized internal role can inspect invitation state');

-- New invitations revoke the previous active invitation for the same partner.
select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
create temporary table extended_token_b_first as
select *
from public.create_partner_claim_invite(
  '22222222-2222-4222-8222-222222222222',
  interval '1 day',
  'proof',
  null,
  ' Future.Owner+tag@Example.Invalid '
);

create temporary table extended_token_b_second as
select *
from public.create_partner_claim_invite(
  '22222222-2222-4222-8222-222222222222',
  interval '1 day',
  'proof',
  null,
  ' Future.Owner+tag@Example.Invalid '
);

do $$
begin
  if not exists (
    select 1
    from public.partner_claim_invites
    where id = (select invite_id from extended_token_b_first)
      and revoked_at is not null
  ) then
    raise exception 'older active invitation was not revoked';
  end if;

  if (
    select count(*)
    from public.partner_claim_invites
    where partner_id = '22222222-2222-4222-8222-222222222222'
      and consumed_at is null
      and revoked_at is null
  ) <> 1 then
    raise exception 'partner does not have exactly one active invitation';
  end if;

  if not exists (
    select 1
    from public.partner_claim_invites
    where id = (select invite_id from extended_token_b_second)
      and intended_user_id is null
      and intended_email_normalized = 'future.owner+tag@example.invalid'
      and recipient_hint = 'f***@example.invalid'
  ) then
    raise exception 'new-account invitation did not preserve lower(trim(email)) binding and masked hint';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('one active invite and email normalization', 'replacement revoked the old invite; email binding used only lower(trim(email))');
end;
$$;

-- The wrong account cannot use the email-bound link, and the mismatch is non-terminal.
select pg_temp.set_auth_context('authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select pg_temp.expect_error(
  'mismatched verified email claim',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from extended_token_b_second)),
  '42501'
);

do $$
begin
  if exists (
    select 1 from public.partner_claim_invites
    where id = (select invite_id from extended_token_b_second)
      and (consumed_at is not null or revoked_at is not null)
  ) then
    raise exception 'verified-email mismatch consumed or revoked the invitation';
  end if;
end;
$$;

-- Simulate account creation after invitation issuance with the exact normalized,
-- verified email. Provider-specific dot/plus rewriting is intentionally absent.
insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
) values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'authenticated',
  'authenticated',
  'future.owner+tag@example.invalid',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  false,
  false,
  now(),
  now()
);

select pg_temp.set_auth_context('authenticated', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select *
from public.claim_partner_profile((select raw_token from extended_token_b_second));

do $$
begin
  if not exists (
    select 1 from public.partners
    where id = '22222222-2222-4222-8222-222222222222'
      and owner_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ) then
    raise exception 'matching newly verified account did not claim the intended partner';
  end if;

  if exists (
    select 1 from public.admin_audit_logs
    where action_type like 'partner_claim_%'
      and (coalesce(previous_value::text, '') like '%@%'
        or coalesce(new_value::text, '') like '%@%')
  ) then
    raise exception 'claim audit output contains a full recipient email';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('verified email recipient', 'matching newly verified email claimed; mismatch was non-terminal; audit contained no email');
end;
$$;

-- Claiming an official partner preserves that separate relationship and public fields.
select pg_temp.set_auth_context('service_role');
update public.partners
set relationship_status = 'official_partner'
where id = '55555555-5555-4555-8555-555555555555';

select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
create temporary table extended_token_official as
select *
from public.create_partner_claim_invite(
  '55555555-5555-4555-8555-555555555555',
  interval '1 day',
  'proof',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  null
);

select pg_temp.set_auth_context('authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select *
from public.claim_partner_profile((select raw_token from extended_token_official));

do $$
begin
  if not exists (
    select 1
    from public.partners
    where id = '55555555-5555-4555-8555-555555555555'
      and owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and relationship_status = 'official_partner'
      and heha_partner = true
      and status = 'approved'
      and local_eligible = true
      and items = '[{"name":"Official Synthetic Item"}]'::jsonb
  ) then
    raise exception 'claim did not preserve Official HEHA Partner/public product state';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('official partner preservation', 'claim retained official relationship, publication, Local eligibility and product state');
end;
$$;

-- A downstream audit failure must roll back ownership and token consumption atomically.
select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
create temporary table extended_token_atomicity as
select *
from public.create_partner_claim_invite(
  '66666666-6666-4666-8666-666666666666',
  interval '1 day',
  'proof',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  null
);

create or replace function pg_temp.reject_claim_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action_type = 'partner_profile_claimed'
     and new.related_id = '66666666-6666-4666-8666-666666666666'::uuid then
    raise exception 'synthetic audit failure';
  end if;
  return new;
end;
$$;

create trigger reject_synthetic_claim_audit
before insert on public.admin_audit_logs
for each row
execute function pg_temp.reject_claim_audit();

select pg_temp.set_auth_context('authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_error(
  'atomic claim rollback',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from extended_token_atomicity)),
  'P0001'
);

drop trigger reject_synthetic_claim_audit on public.admin_audit_logs;

do $$
begin
  if exists (
    select 1
    from public.partners
    where id = '66666666-6666-4666-8666-666666666666'
      and owner_id is not null
  ) then
    raise exception 'failed claim left a partial owner assignment';
  end if;

  if exists (
    select 1
    from public.partner_claim_invites
    where id = (select invite_id from extended_token_atomicity)
      and consumed_at is not null
  ) then
    raise exception 'failed claim consumed its invitation';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('atomicity', 'downstream audit failure rolled back owner and invitation consumption');
end;
$$;

-- Every invitation must carry exactly one recipient binding.
do $$
begin
  if exists (
    select 1 from public.partner_claim_invites
    where num_nonnulls(intended_user_id, intended_email_normalized) <> 1
  ) then
    raise exception 'claim invitation missing an exclusive intended recipient binding';
  end if;

  insert into pg_temp.partner_claim_extended_results
  values ('claim identity model', 'token possession plus intended user or verified normalized email is required');
end;
$$;

select label, detail
from pg_temp.partner_claim_extended_results
order by label;

rollback;
