-- Account-deletion lifecycle proof for 20260807160000_partner_claim_foundation_v2.sql.
-- Rollback-only. Requires the synthetic baseline fixture and the v2 migration.
--
-- Proves the deletion-safe provenance model: deleting the invitation
-- creator, the intended recipient, or the claimant always succeeds (ON
-- DELETE SET NULL tombstones), a recipient-less active invitation fails
-- closed and stays replaceable, and deleting the canonical partner row is
-- deliberately blocked while invitation history exists.

begin;

grant execute on function app_private.has_internal_role(text[]) to anon, authenticated;

create temporary table lifecycle_results (
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
    insert into pg_temp.lifecycle_results
    values (p_label, 'denied with SQLSTATE ' || sqlstate);
    return;
  end;
  raise exception '% expected SQLSTATE %, but succeeded', p_label, p_expected_state;
end;
$$;

-- Disposable accounts created inside this rolled-back transaction.
insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
) values
  ('21212121-2121-4121-8121-212121212121', 'authenticated', 'authenticated',
   'lifecycle-creator@example.invalid', now(),
   '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
   false, false, now(), now()),
  ('23232323-2323-4323-8323-232323232323', 'authenticated', 'authenticated',
   'lifecycle-recipient@example.invalid', now(),
   '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
   false, false, now(), now());

insert into public.user_roles (user_id, role, active)
values ('21212121-2121-4121-8121-212121212121', 'developer_admin', true);

-- ---------------------------------------------------------------------------
-- 1. Creator deletion: the invitation survives as provenance tombstone and
--    remains claimable by its intended recipient.
-- ---------------------------------------------------------------------------

select pg_temp.set_auth_context('authenticated', '21212121-2121-4121-8121-212121212121');
create temporary table lifecycle_token_creator as
select *
from public.create_partner_claim_invite(
  '11111111-1111-4111-8111-111111111111',
  interval '1 day',
  'lifecycle-proof',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  null
);

delete from auth.users where id = '21212121-2121-4121-8121-212121212121';

do $$
begin
  if not exists (
    select 1 from public.partner_claim_invites
    where id = (select invite_id from lifecycle_token_creator)
      and created_by is null
      and consumed_at is null
      and revoked_at is null
  ) then
    raise exception 'creator deletion did not leave a usable tombstoned invitation';
  end if;
end;
$$;

select pg_temp.set_auth_context('authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
do $$
begin
  perform public.claim_partner_profile((select raw_token from lifecycle_token_creator));
end;
$$;

do $$
begin
  if not exists (
    select 1 from public.partners
    where id = '11111111-1111-4111-8111-111111111111'
      and owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) then
    raise exception 'claim after creator deletion did not attach the intended owner';
  end if;
  insert into pg_temp.lifecycle_results
  values ('creator deletion', 'creator account deleted; invitation tombstoned (created_by null) and still claimed exactly once by its intended recipient');
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Intended-recipient deletion on an ACTIVE invitation: deletion succeeds,
--    the recipient-less invitation fails closed, and an internal admin can
--    replace it.
-- ---------------------------------------------------------------------------

select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
create temporary table lifecycle_token_recipient as
select *
from public.create_partner_claim_invite(
  '22222222-2222-4222-8222-222222222222',
  interval '1 day',
  'lifecycle-proof',
  '23232323-2323-4323-8323-232323232323',
  null
);

delete from auth.users where id = '23232323-2323-4323-8323-232323232323';

do $$
begin
  if not exists (
    select 1 from public.partner_claim_invites
    where id = (select invite_id from lifecycle_token_recipient)
      and intended_user_id is null
      and intended_email_normalized is null
      and consumed_at is null
      and revoked_at is null
  ) then
    raise exception 'recipient deletion did not produce a recipient-less active tombstone';
  end if;
end;
$$;

select pg_temp.set_auth_context('authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_error(
  'recipient-less preview denied',
  format('select * from public.preview_partner_claim(%L)', (select raw_token from lifecycle_token_recipient)),
  '42501'
);
select pg_temp.expect_error(
  'recipient-less claim denied',
  format('select * from public.claim_partner_profile(%L)', (select raw_token from lifecycle_token_recipient)),
  '42501'
);

do $$
begin
  if not exists (
    select 1 from public.partner_claim_invites
    where id = (select invite_id from lifecycle_token_recipient)
      and consumed_at is null and revoked_at is null
  ) then
    raise exception 'recipient-less denial changed terminal invitation state';
  end if;
  if exists (
    select 1 from public.partners
    where id = '22222222-2222-4222-8222-222222222222' and owner_id is not null
  ) then
    raise exception 'recipient-less denial changed business ownership';
  end if;
  if exists (
    select 1 from public.admin_audit_logs
    where action_type = 'partner_profile_claimed'
      and related_id = '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'recipient-less denial wrote a successful-claim audit event';
  end if;
end;
$$;

-- Replacement restores claimability and revokes the tombstoned invitation.
select pg_temp.set_auth_context('authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
create temporary table lifecycle_token_replacement as
select *
from public.create_partner_claim_invite(
  '22222222-2222-4222-8222-222222222222',
  interval '1 day',
  'lifecycle-proof',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  null
);

do $$
declare
  active_count integer;
begin
  select count(*) into active_count
  from public.partner_claim_invites
  where partner_id = '22222222-2222-4222-8222-222222222222'
    and consumed_at is null and revoked_at is null;
  if active_count <> 1 then
    raise exception 'replacement left % active invitations; expected exactly 1', active_count;
  end if;
  if not exists (
    select 1 from public.partner_claim_invites
    where id = (select invite_id from lifecycle_token_recipient)
      and revoked_at is not null
  ) then
    raise exception 'replacement did not revoke the recipient-less tombstone';
  end if;
  insert into pg_temp.lifecycle_results
  values ('recipient deletion', 'intended account deleted; active invitation fails closed (42501), unchanged, and is replaceable with exactly one active invite');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Claimant deletion after consumption: deletion succeeds; the consumed
--    invitation and canonical Partner ID survive as tombstoned history.
-- ---------------------------------------------------------------------------

do $$
begin
  perform pg_temp.set_auth_context('authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  perform public.claim_partner_profile((select raw_token from lifecycle_token_replacement));
end;
$$;

delete from auth.users where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

do $$
begin
  if not exists (
    select 1 from public.partner_claim_invites
    where id = (select invite_id from lifecycle_token_replacement)
      and consumed_at is not null
      and consumed_by is null
      and intended_user_id is null
  ) then
    raise exception 'claimant deletion did not tombstone the consumed invitation';
  end if;
  if not exists (
    select 1 from public.partners
    where id = '22222222-2222-4222-8222-222222222222'
      and owner_id is null
  ) then
    raise exception 'claimant deletion did not clear ownership via SET NULL';
  end if;
  insert into pg_temp.lifecycle_results
  values ('claimant deletion', 'claimant account deleted; consumed invitation and canonical Partner ID retained as tombstoned history, ownership cleared');
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Partner deletion stays deliberately blocked while invitation history
--    exists (approved opt-out policy hides listings, never deletes the
--    canonical Partner ID; hard delete needs a reviewed forward migration).
-- ---------------------------------------------------------------------------

select pg_temp.expect_error(
  'partner delete blocked by invite history',
  $$delete from public.partners where id = '22222222-2222-4222-8222-222222222222'$$,
  '23503'
);

select label, detail
from pg_temp.lifecycle_results
order by label;

rollback;
