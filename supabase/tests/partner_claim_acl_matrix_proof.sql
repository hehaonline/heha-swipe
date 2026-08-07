-- Deterministic ACL matrix proof for 20260807160000_partner_claim_foundation_v2.sql.
-- Rollback-only. Requires the synthetic baseline fixture and the v2 migration.
--
-- Proves, for public.partner_claim_invites, the final state of all seven
-- PostgreSQL table privileges (SELECT, INSERT, UPDATE, DELETE, TRUNCATE,
-- REFERENCES, TRIGGER) for PUBLIC, anon, authenticated, service_role and the
-- object owner — first declaratively against the catalog ACL, then
-- behaviorally with adversarial attempts that must fail with SQLSTATE 42501.
-- RLS does not govern TRUNCATE, REFERENCES or TRIGGER, so these checks cannot
-- be replaced by policy tests.

begin;

create temporary table acl_matrix_results (
  label text primary key,
  detail text not null
) on commit drop;

-- expect_denied records outcomes while running as anon/authenticated.
grant select, insert on pg_temp.acl_matrix_results to public;

create or replace function pg_temp.expect_denied(p_label text, p_sql text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> '42501' then
      raise exception '% expected SQLSTATE 42501, got %: %', p_label, sqlstate, sqlerrm;
    end if;
    insert into pg_temp.acl_matrix_results
    values (p_label, 'denied with SQLSTATE 42501');
    return;
  end;
  raise exception '% expected SQLSTATE 42501, but succeeded', p_label;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Declarative matrix: catalog ACL must match the approved design exactly.
-- ---------------------------------------------------------------------------

do $$
declare
  privs constant text[] := array[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ];
  priv text;
  role_name text;
  expected boolean;
  actual boolean;
  public_grant_count integer;
  owner_name text;
begin
  -- PUBLIC (grantee oid 0 in the ACL) must hold no privilege at all.
  select count(*) into public_grant_count
  from pg_class c
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
  where c.oid = 'public.partner_claim_invites'::regclass
    and a.grantee = 0;

  if public_grant_count <> 0 then
    raise exception 'PUBLIC holds % unexpected grant(s) on partner_claim_invites', public_grant_count;
  end if;
  insert into pg_temp.acl_matrix_results
  values ('matrix PUBLIC', 'no privileges of any kind');

  -- anon: every one of the seven privileges must be false.
  foreach priv in array privs loop
    if has_table_privilege('anon', 'public.partner_claim_invites', priv) then
      raise exception 'anon unexpectedly holds % on partner_claim_invites', priv;
    end if;
  end loop;
  insert into pg_temp.acl_matrix_results
  values ('matrix anon', 'all seven privileges denied');

  -- authenticated: SELECT only (further filtered by RLS); the other six false.
  foreach priv in array privs loop
    expected := (priv = 'SELECT');
    actual := has_table_privilege('authenticated', 'public.partner_claim_invites', priv);
    if actual <> expected then
      raise exception 'authenticated % on partner_claim_invites: expected %, got %', priv, expected, actual;
    end if;
  end loop;
  insert into pg_temp.acl_matrix_results
  values ('matrix authenticated', 'SELECT only; INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER denied');

  -- service_role: backend DML only; never TRUNCATE, REFERENCES or TRIGGER.
  foreach priv in array privs loop
    expected := priv in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
    actual := has_table_privilege('service_role', 'public.partner_claim_invites', priv);
    if actual <> expected then
      raise exception 'service_role % on partner_claim_invites: expected %, got %', priv, expected, actual;
    end if;
  end loop;
  insert into pg_temp.acl_matrix_results
  values ('matrix service_role', 'SELECT/INSERT/UPDATE/DELETE only; TRUNCATE/REFERENCES/TRIGGER denied');

  -- Owner: implicit full privileges, recorded for the evidence trail.
  select pg_get_userbyid(c.relowner) into owner_name
  from pg_class c
  where c.oid = 'public.partner_claim_invites'::regclass;

  foreach priv in array privs loop
    if not has_table_privilege(owner_name, 'public.partner_claim_invites', priv) then
      raise exception 'owner % lost % on partner_claim_invites', owner_name, priv;
    end if;
  end loop;
  insert into pg_temp.acl_matrix_results
  values ('matrix owner', owner_name || ' holds all seven privileges (object owner)');
end;
$$;

-- RLS must be enabled on the invite table.
do $$
declare
  rls_enabled boolean;
begin
  select c.relrowsecurity into rls_enabled
  from pg_class c
  where c.oid = 'public.partner_claim_invites'::regclass;

  if not rls_enabled then
    raise exception 'row level security must be enabled on partner_claim_invites';
  end if;
  insert into pg_temp.acl_matrix_results
  values ('rls enabled', 'row level security is enabled on partner_claim_invites');
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Function EXECUTE matrix for every claim RPC.
-- ---------------------------------------------------------------------------

do $$
declare
  fn text;
  fns constant text[] := array[
    'public.create_partner_claim_invite(uuid, interval, text, uuid, text)',
    'public.preview_partner_claim(text)',
    'public.claim_partner_profile(text)',
    'public.revoke_partner_claim_invite(uuid)'
  ];
  public_grant_count integer;
begin
  foreach fn in array fns loop
    select count(*) into public_grant_count
    from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as a
    where p.oid = fn::regprocedure
      and a.grantee = 0;

    if public_grant_count <> 0 then
      raise exception 'PUBLIC unexpectedly holds EXECUTE on %', fn;
    end if;
    if has_function_privilege('anon', fn, 'EXECUTE') then
      raise exception 'anon unexpectedly holds EXECUTE on %', fn;
    end if;
    if not has_function_privilege('authenticated', fn, 'EXECUTE') then
      raise exception 'authenticated must hold EXECUTE on %', fn;
    end if;
    if not has_function_privilege('service_role', fn, 'EXECUTE') then
      raise exception 'service_role must hold EXECUTE on %', fn;
    end if;
  end loop;

  insert into pg_temp.acl_matrix_results
  values ('matrix function execute', 'PUBLIC/anon denied; authenticated and service_role granted on all four claim RPCs');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Behavioral denial proofs. Each client role creates its own probe table
--    in a transaction-scoped scratch schema, so the REFERENCES attempt fails
--    on the missing privilege for partner_claim_invites, not on probe
--    ownership. No ALTER OWNER is used because the proof must also run where
--    the executor is not a superuser (e.g. the Supabase-local postgres role)
--    and client roles hold no CREATE on schema public. Every adversarial
--    attempt must raise SQLSTATE 42501.
-- ---------------------------------------------------------------------------

create schema acl_probe_scratch;
grant usage, create on schema acl_probe_scratch to authenticated, anon;

create or replace function pg_temp.acl_probe_trigger_fn()
returns trigger
language plpgsql
as $$
begin
  return new;
end;
$$;

-- authenticated adversarial attempts.
set local role authenticated;

create table acl_probe_scratch.probe_authenticated (
  id uuid primary key,
  invite_id uuid
);

select pg_temp.expect_denied(
  'authenticated TRUNCATE',
  'truncate table public.partner_claim_invites'
);
select pg_temp.expect_denied(
  'authenticated REFERENCES',
  'alter table acl_probe_scratch.probe_authenticated
     add constraint acl_probe_auth_fk
     foreign key (invite_id) references public.partner_claim_invites(id)'
);
select pg_temp.expect_denied(
  'authenticated TRIGGER',
  'create trigger acl_probe_auth_trg
     before insert on public.partner_claim_invites
     for each row execute function pg_temp.acl_probe_trigger_fn()'
);
select pg_temp.expect_denied(
  'authenticated direct INSERT',
  $sql$insert into public.partner_claim_invites
      (partner_id, token_hash, created_by, expires_at, recipient_hint, intended_email_normalized)
    values
      ('11111111-1111-4111-8111-111111111111', '\xdeadbeef'::bytea,
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now() + interval '1 day',
       'x***@example.invalid', 'x@example.invalid')$sql$
);
select pg_temp.expect_denied(
  'authenticated direct UPDATE',
  'update public.partner_claim_invites set revoked_at = now()'
);
select pg_temp.expect_denied(
  'authenticated direct DELETE',
  'delete from public.partner_claim_invites'
);

reset role;

-- anon adversarial attempts, including bare SELECT.
set local role anon;

create table acl_probe_scratch.probe_anon (
  id uuid primary key,
  invite_id uuid
);

select pg_temp.expect_denied(
  'anon SELECT',
  'select count(*) from public.partner_claim_invites'
);
select pg_temp.expect_denied(
  'anon TRUNCATE',
  'truncate table public.partner_claim_invites'
);
select pg_temp.expect_denied(
  'anon REFERENCES',
  'alter table acl_probe_scratch.probe_anon
     add constraint acl_probe_anon_fk
     foreign key (invite_id) references public.partner_claim_invites(id)'
);
select pg_temp.expect_denied(
  'anon TRIGGER',
  'create trigger acl_probe_anon_trg
     before insert on public.partner_claim_invites
     for each row execute function pg_temp.acl_probe_trigger_fn()'
);
select pg_temp.expect_denied(
  'anon direct INSERT',
  $sql$insert into public.partner_claim_invites
      (partner_id, token_hash, created_by, expires_at, recipient_hint, intended_email_normalized)
    values
      ('11111111-1111-4111-8111-111111111111', '\xfeedface'::bytea,
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now() + interval '1 day',
       'x***@example.invalid', 'x@example.invalid')$sql$
);
select pg_temp.expect_denied(
  'anon direct UPDATE',
  'update public.partner_claim_invites set revoked_at = now()'
);
select pg_temp.expect_denied(
  'anon direct DELETE',
  'delete from public.partner_claim_invites'
);
select pg_temp.expect_denied(
  'anon claim RPC EXECUTE',
  $$select * from public.claim_partner_profile('0000000000000000000000000000000000000000000000000000000000000000')$$
);

reset role;

-- ---------------------------------------------------------------------------
-- 4. RLS visibility split: an authenticated user without an approved internal
--    role sees zero invite rows; an approved internal role sees them.
-- ---------------------------------------------------------------------------

grant execute on function app_private.has_internal_role(text[]) to anon, authenticated;

do $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- perform (not select) so the raw one-time token never reaches stdout or
  -- any uploaded proof artifact.
  perform public.create_partner_claim_invite(
    '11111111-1111-4111-8111-111111111111',
    interval '1 day',
    'acl-matrix-proof',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    null
  );
end;
$$;

do $$
declare
  visible_count integer;
begin
  -- Ordinary authenticated user (no internal role): zero rows through RLS.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
  set local role authenticated;

  select count(*) into visible_count from public.partner_claim_invites;
  if visible_count <> 0 then
    raise exception 'ordinary authenticated user can see % invite row(s); expected 0', visible_count;
  end if;

  reset role;

  -- Approved internal role: the invitation is visible.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', true);
  set local role authenticated;

  select count(*) into visible_count
  from public.partner_claim_invites
  where partner_id = '11111111-1111-4111-8111-111111111111';
  if visible_count < 1 then
    raise exception 'internal admin cannot see the invitation through RLS';
  end if;

  reset role;

  insert into pg_temp.acl_matrix_results
  values ('rls visibility split', 'ordinary authenticated sees 0 rows; internal admin sees the invitation');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Cross-business boundary at the ACL/RPC layer: Business A's owner cannot
--    administer Business B's invitations, and the failed attempts change
--    nothing.
-- ---------------------------------------------------------------------------

do $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', true);

  -- perform (not select): the raw token must not appear in proof output.
  perform public.create_partner_claim_invite(
    '22222222-2222-4222-8222-222222222222',
    interval '1 day',
    'acl-matrix-proof',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    null
  );
end;
$$;

do $$
declare
  b_invite_id uuid;
  b_state record;
begin
  select id into b_invite_id
  from public.partner_claim_invites
  where partner_id = '22222222-2222-4222-8222-222222222222'
    and consumed_at is null and revoked_at is null;

  -- Act as user A (owner-side account for Business A, no internal role).
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

  begin
    perform public.revoke_partner_claim_invite(b_invite_id);
    raise exception 'user A revoked Business B invite; expected SQLSTATE 42501';
  exception when others then
    if sqlstate <> '42501' then
      raise exception 'cross-business revoke expected SQLSTATE 42501, got %: %', sqlstate, sqlerrm;
    end if;
  end;

  begin
    perform public.create_partner_claim_invite(
      '22222222-2222-4222-8222-222222222222', interval '1 day', 'acl-matrix-proof',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null);
    raise exception 'user A created an invite for Business B; expected SQLSTATE 42501';
  exception when others then
    if sqlstate <> '42501' then
      raise exception 'cross-business invite creation expected SQLSTATE 42501, got %: %', sqlstate, sqlerrm;
    end if;
  end;

  -- The failed attempts changed nothing.
  select i.consumed_at, i.revoked_at, p.owner_id
  into b_state
  from public.partner_claim_invites i
  join public.partners p on p.id = i.partner_id
  where i.id = b_invite_id;

  if b_state.consumed_at is not null or b_state.revoked_at is not null then
    raise exception 'Business B invitation state changed after denied cross-business attempts';
  end if;
  if b_state.owner_id is not null then
    raise exception 'Business B ownership changed after denied cross-business attempts';
  end if;

  insert into pg_temp.acl_matrix_results
  values ('cross-business admin boundary', 'user A denied (42501) revoking/creating Business B invites; B invite and ownership unchanged');
end;
$$;

select label, detail
from pg_temp.acl_matrix_results
order by label;

rollback;
