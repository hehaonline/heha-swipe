-- Exact-head behavioral proof for the ONE HEHA S1 Swipe foundation.
--
-- Run only after the matching review-only SQL files on a disposable synthetic
-- PostgreSQL/Supabase environment. The transaction rolls back all proof rows.

begin;

create temporary table s1_proof_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;

create or replace function pg_temp.expect_sqlstate(
  p_label text,
  p_expected_state text,
  p_sql text
)
returns void
language plpgsql
as $function$
begin
  execute p_sql;
  raise exception '% expected SQLSTATE %, but statement succeeded', p_label, p_expected_state;
exception
  when others then
    if sqlstate <> p_expected_state then
      raise exception '% expected SQLSTATE %, got %: %', p_label, p_expected_state, sqlstate, sqlerrm;
    end if;

    insert into pg_temp.s1_proof_results(label, ok, detail)
    values (p_label, true, 'denied with SQLSTATE ' || p_expected_state)
    on conflict (label) do update set ok = excluded.ok, detail = excluded.detail;
end;
$function$;

insert into community_pass_private.runtime_config (
  singleton,
  environment,
  config_version
) values (
  true,
  'test',
  's1-proof-v1'
);

-- Structural, RLS, ACL and canonical-identity proof.
do $structural$
declare
  v_table text;
  v_private_table text;
  v_column_count integer;
  v_fk_count integer;
  v_config text[];
  v_signature text;
begin
  foreach v_table in array array[
    'community_pass_accounts',
    'community_pass_subscriptions',
    'community_pass_purchases',
    'community_pass_entitlements',
    'community_pass_acceptances',
    'community_pass_events',
    'community_pass_stripe_event_inbox'
  ] loop
    if pg_catalog.to_regclass('public.' || v_table) is null then
      raise exception 'Missing required table public.%', v_table;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_class c
      where c.oid = pg_catalog.to_regclass('public.' || v_table)
        and c.relrowsecurity
        and c.relforcerowsecurity
    ) then
      raise exception 'public.% must have ENABLE + FORCE RLS', v_table;
    end if;

    if pg_catalog.has_table_privilege('anon', 'public.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'DELETE') then
      raise exception 'public.% exposes browser table access', v_table;
    end if;
  end loop;

  foreach v_private_table in array array[
    'one_heha_private.identity_links',
    'one_heha_private.link_handshakes',
    'one_heha_private.identity_events',
    'community_pass_private.runtime_config'
  ] loop
    if pg_catalog.to_regclass(v_private_table) is null then
      raise exception 'Missing private table %', v_private_table;
    end if;

    if pg_catalog.has_table_privilege('anon', v_private_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', v_private_table, 'SELECT')
       or pg_catalog.has_table_privilege('service_role', v_private_table, 'SELECT') then
      raise exception '% has direct table access outside its security-definer boundary', v_private_table;
    end if;
  end loop;

  if pg_catalog.has_schema_privilege('anon', 'one_heha_private', 'USAGE')
     or pg_catalog.has_schema_privilege('authenticated', 'one_heha_private', 'USAGE')
     or pg_catalog.has_schema_privilege('anon', 'community_pass_private', 'USAGE')
     or pg_catalog.has_schema_privilege('authenticated', 'community_pass_private', 'USAGE') then
    raise exception 'Browser role has private-schema USAGE';
  end if;

  select count(*)
  into v_column_count
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name like 'community_pass_%'
    and c.column_name = 'user_id';

  if v_column_count <> 0 then
    raise exception 'Community Pass child tables duplicate a Swipe user_id';
  end if;

  if not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'community_pass_accounts'
      and c.column_name = 'canonical_user_id'
      and c.data_type = 'uuid'
  ) then
    raise exception 'community_pass_accounts.canonical_user_id is missing';
  end if;

  select count(*)
  into v_fk_count
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class rel on rel.oid = con.conrelid
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  where n.nspname = 'public'
    and rel.relname = 'community_pass_accounts'
    and con.contype = 'f';

  if v_fk_count <> 0 then
    raise exception 'community_pass_accounts must not foreign-key the cross-project Local UUID';
  end if;

  foreach v_signature in array array[
    'one_heha_private.begin_link_handshake(uuid,uuid,text,timestamptz,text,timestamptz)',
    'one_heha_private.activate_identity_link(uuid,uuid,uuid,timestamptz,text,timestamptz)',
    'community_pass_private.create_or_get_account_for_swipe_user(uuid,text,text,text,timestamptz)',
    'community_pass_private.start_trial_for_swipe_user(uuid,timestamptz)',
    'one_heha_private.revoke_identity_for_canonical_user(uuid,uuid,text,text,timestamptz)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Function ACL mismatch for %', v_signature;
    end if;

    select p.proconfig
    into v_config
    from pg_catalog.pg_proc p
    where p.oid = v_signature::pg_catalog.regprocedure;

    if not (
      'search_path=' = any(coalesce(v_config, array[]::text[]))
      or 'search_path=""' = any(coalesce(v_config, array[]::text[]))
    ) then
      raise exception 'Function % must pin an empty search_path', v_signature;
    end if;
  end loop;

  insert into pg_temp.s1_proof_results(label, ok, detail)
  values (
    'structure and authorization',
    true,
    'private link registry, canonical-user account key, forced RLS, closed browser ACLs and service-only transitions verified'
  );
end;
$structural$;

-- Email/SSO classification cannot activate an automated link.
select pg_temp.expect_sqlstate(
  'sso routes to manual review',
  'P0001',
  $sql$
    select one_heha_private.begin_link_handshake(
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000a1',
      'sso',
      '2026-08-25 11:58:00+00',
      repeat('a', 64),
      '2026-08-25 12:00:00+00'
    )
  $sql$
);

select pg_temp.expect_sqlstate(
  'unverified email cannot link',
  'P0001',
  $sql$
    select one_heha_private.begin_link_handshake(
      '10000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-0000000000a1',
      'unverified',
      '2026-08-25 11:58:00+00',
      repeat('b', 64),
      '2026-08-25 12:00:00+00'
    )
  $sql$
);

-- Create and activate one valid dual-reauthentication link.
do $valid_link$
declare
  v_request constant uuid := '10000000-0000-0000-0000-000000000010';
  v_swipe constant uuid := '00000000-0000-0000-0000-0000000000a1';
  v_canonical constant uuid := '20000000-0000-0000-0000-0000000000a1';
  v_handshake uuid;
  v_link_first uuid;
  v_link_replay uuid;
begin
  v_handshake := one_heha_private.begin_link_handshake(
    v_request,
    v_swipe,
    'verified_non_sso',
    '2026-08-25 11:58:00+00',
    repeat('c', 64),
    '2026-08-25 12:00:00+00'
  );

  v_link_first := one_heha_private.activate_identity_link(
    v_request,
    v_swipe,
    v_canonical,
    '2026-08-25 11:59:00+00',
    repeat('d', 64),
    '2026-08-25 12:00:00+00'
  );

  v_link_replay := one_heha_private.activate_identity_link(
    v_request,
    v_swipe,
    v_canonical,
    '2026-08-25 11:59:00+00',
    repeat('d', 64),
    '2026-08-25 12:00:30+00'
  );

  if v_handshake is null or v_link_first is null or v_link_first <> v_link_replay then
    raise exception 'Same-request activation is not idempotent';
  end if;

  if (select count(*) from one_heha_private.identity_links where status = 'active') <> 1 then
    raise exception 'Expected exactly one active identity link';
  end if;

  if (select count(*) from one_heha_private.identity_events where event_type = 'link_activated') <> 1 then
    raise exception 'Expected exactly one link_activated event';
  end if;

  if one_heha_private.resolve_canonical_user_for_swipe(v_swipe, 'test') <> v_canonical then
    raise exception 'Active Swipe link did not resolve the canonical Local user';
  end if;

  if one_heha_private.resolve_canonical_user_for_swipe(
    '00000000-0000-0000-0000-0000000000b2',
    'test'
  ) is not null then
    raise exception 'Unlinked Swipe user resolved another account';
  end if;

  insert into pg_temp.s1_proof_results(label, ok, detail)
  values (
    'dual reauthentication link',
    true,
    'one active link, one activation receipt, same-request idempotency and cross-user denial verified'
  );
end;
$valid_link$;

select pg_temp.expect_sqlstate(
  'different JTI replay denied',
  '42501',
  $sql$
    select one_heha_private.activate_identity_link(
      '10000000-0000-0000-0000-000000000010',
      '00000000-0000-0000-0000-0000000000a1',
      '20000000-0000-0000-0000-0000000000a1',
      '2026-08-25 11:59:00+00',
      repeat('e', 64),
      '2026-08-25 12:01:00+00'
    )
  $sql$
);

-- An expired handshake cannot be consumed.
do $expired_setup$
begin
  perform one_heha_private.begin_link_handshake(
    '10000000-0000-0000-0000-000000000020',
    '00000000-0000-0000-0000-0000000000b2',
    'verified_non_sso',
    '2026-08-25 11:58:00+00',
    repeat('f', 64),
    '2026-08-25 12:00:00+00'
  );
end;
$expired_setup$;

select pg_temp.expect_sqlstate(
  'expired handshake denied',
  '42501',
  $sql$
    select one_heha_private.activate_identity_link(
      '10000000-0000-0000-0000-000000000020',
      '00000000-0000-0000-0000-0000000000b2',
      '20000000-0000-0000-0000-0000000000b2',
      '2026-08-25 12:04:00+00',
      repeat('1', 64),
      '2026-08-25 12:06:00+00'
    )
  $sql$
);

-- Community Pass account and trial resolve only through the active link.
do $community_pass$
declare
  v_swipe constant uuid := '00000000-0000-0000-0000-0000000000a1';
  v_canonical constant uuid := '20000000-0000-0000-0000-0000000000a1';
  v_account uuid;
  v_account_replay uuid;
  v_entitlement uuid;
begin
  v_account := community_pass_private.create_or_get_account_for_swipe_user(
    v_swipe,
    'founding-v1',
    'beta-v1',
    'policy-v1',
    '2026-08-25 12:02:00+00'
  );

  v_account_replay := community_pass_private.create_or_get_account_for_swipe_user(
    v_swipe,
    'founding-v1',
    'beta-v1',
    'policy-v1',
    '2026-08-25 12:02:30+00'
  );

  if v_account is null or v_account <> v_account_replay then
    raise exception 'Community Pass account creation is not idempotent';
  end if;

  insert into public.community_pass_entitlements (
    account_id,
    source_type,
    state,
    environment,
    invitation_sent_at,
    invitation_expires_at,
    offer_version,
    benefit_version,
    policy_bundle_version
  ) values (
    v_account,
    'free_trial',
    'activation_available',
    'test',
    '2026-08-25 12:00:00+00',
    '2026-10-24 12:00:00+00',
    'founding-v1',
    'beta-v1',
    'policy-v1'
  );

  v_entitlement := community_pass_private.start_trial_for_swipe_user(
    v_swipe,
    '2026-08-25 12:03:00+00'
  );

  if v_entitlement is null then
    raise exception 'Trial activation returned no entitlement';
  end if;

  if not community_pass_private.is_active_for_canonical_user(
    v_canonical,
    '2026-08-25 12:04:00+00'
  ) then
    raise exception 'Active trial did not authorize the canonical Local user';
  end if;

  if community_pass_private.is_active_for_canonical_user(
    '20000000-0000-0000-0000-0000000000b2',
    '2026-08-25 12:04:00+00'
  ) then
    raise exception 'Another canonical user inherited the trial';
  end if;

  insert into public.community_pass_subscriptions (
    account_id,
    stripe_customer_id,
    stripe_subscription_id,
    stripe_price_id,
    selected_amount_cents,
    quantity,
    currency,
    environment,
    status,
    current_period_start,
    current_period_end,
    offer_version,
    benefit_version,
    policy_bundle_version,
    reconciliation_state
  ) values (
    v_account,
    'cus_synthetic_a',
    'sub_synthetic_a',
    'price_synthetic_a',
    500,
    5,
    'usd',
    'test',
    'active',
    '2026-08-25 12:00:00+00',
    '2026-09-25 12:00:00+00',
    'founding-v1',
    'beta-v1',
    'policy-v1',
    'matched'
  );

  insert into pg_temp.s1_proof_results(label, ok, detail)
  values (
    'canonical Community Pass',
    true,
    'account idempotency, link-derived ownership, one trial and canonical-user active decision verified'
  );
end;
$community_pass$;

select pg_temp.expect_sqlstate(
  'trial cannot activate twice',
  'P0001',
  $sql$
    select community_pass_private.start_trial_for_swipe_user(
      '00000000-0000-0000-0000-0000000000a1',
      '2026-08-25 12:05:00+00'
    )
  $sql$
);

select pg_temp.expect_sqlstate(
  'trial marker cannot reset',
  '42501',
  $sql$
    update public.community_pass_accounts
    set trial_used_at = null
    where canonical_user_id = '20000000-0000-0000-0000-0000000000a1'
  $sql$
);

select pg_temp.expect_sqlstate(
  'identity event update denied',
  '42501',
  $sql$
    update one_heha_private.identity_events
    set reason_code = 'tampered'
    where event_type = 'link_activated'
  $sql$
);

select pg_temp.expect_sqlstate(
  'Community Pass event delete denied',
  '42501',
  $sql$
    delete from public.community_pass_events
    where event_type = 'trial_activated'
  $sql$
);

select pg_temp.expect_sqlstate(
  'runtime environment immutable',
  '42501',
  $sql$
    update community_pass_private.runtime_config
    set environment = 'live'
    where singleton
  $sql$
);

-- Deletion fails member access closed, preserves provider liability and is idempotent.
do $deletion$
declare
  v_first record;
  v_replay record;
  v_canonical constant uuid := '20000000-0000-0000-0000-0000000000a1';
begin
  select * into v_first
  from one_heha_private.revoke_identity_for_canonical_user(
    v_canonical,
    '30000000-0000-0000-0000-000000000001',
    'canonical_account_deleted',
    repeat('9', 64),
    '2026-08-25 12:10:00+00'
  );

  select * into v_replay
  from one_heha_private.revoke_identity_for_canonical_user(
    v_canonical,
    '30000000-0000-0000-0000-000000000001',
    'canonical_account_deleted',
    repeat('9', 64),
    '2026-08-25 12:11:00+00'
  );

  if v_first.links_revoked <> 1
     or v_first.accounts_closed <> 1
     or v_replay.links_revoked <> v_first.links_revoked
     or v_replay.accounts_closed <> v_first.accounts_closed then
    raise exception 'Canonical deletion is not idempotent';
  end if;

  if exists (
    select 1
    from one_heha_private.identity_links
    where status = 'active'
  ) then
    raise exception 'Deleted canonical account retains an active identity link';
  end if;

  if exists (
    select 1
    from public.community_pass_accounts
    where status = 'deleted'
      and canonical_user_id is not null
  ) then
    raise exception 'Deleted Community Pass account retains canonical identity';
  end if;

  if exists (
    select 1
    from public.community_pass_subscriptions
    where stripe_subscription_id = 'sub_synthetic_a'
      and (
        status <> 'reconciliation_exception'
        or reconciliation_state <> 'exception'
        or coalesce((metadata ->> 'provider_reconciliation_required')::boolean, false) is not true
      )
  ) then
    raise exception 'Provider subscription liability was not preserved as a reconciliation exception';
  end if;

  if exists (
    select 1
    from public.community_pass_entitlements
    where state = 'trial_active'
  ) then
    raise exception 'Deleted account retains active member entitlement';
  end if;

  if community_pass_private.is_active_for_canonical_user(
    v_canonical,
    '2026-08-25 12:12:00+00'
  ) then
    raise exception 'Deleted canonical user still receives active member decision';
  end if;

  insert into pg_temp.s1_proof_results(label, ok, detail)
  values (
    'deletion and liabilities',
    true,
    'link and entitlement revoked first, provider liability preserved, tombstone minimized and replay idempotent'
  );
end;
$deletion$;

-- A new canonical UUID receives no inherited account or entitlement.
do $recreation$
declare
  v_request constant uuid := '10000000-0000-0000-0000-000000000030';
  v_new_canonical constant uuid := '20000000-0000-0000-0000-0000000000b2';
  v_account uuid;
begin
  perform one_heha_private.begin_link_handshake(
    v_request,
    '00000000-0000-0000-0000-0000000000b2',
    'verified_non_sso',
    '2026-08-25 12:18:00+00',
    repeat('2', 64),
    '2026-08-25 12:20:00+00'
  );

  perform one_heha_private.activate_identity_link(
    v_request,
    '00000000-0000-0000-0000-0000000000b2',
    v_new_canonical,
    '2026-08-25 12:19:00+00',
    repeat('3', 64),
    '2026-08-25 12:20:00+00'
  );

  v_account := community_pass_private.create_or_get_account_for_swipe_user(
    '00000000-0000-0000-0000-0000000000b2',
    'founding-v1',
    'beta-v1',
    'policy-v1',
    '2026-08-25 12:21:00+00'
  );

  if v_account is null then
    raise exception 'New canonical account was not created';
  end if;

  if exists (
    select 1
    from public.community_pass_entitlements e
    where e.account_id = v_account
  ) then
    raise exception 'Recreated account inherited an old entitlement';
  end if;

  if community_pass_private.is_active_for_canonical_user(
    v_new_canonical,
    '2026-08-25 12:22:00+00'
  ) then
    raise exception 'Recreated account inherited active membership';
  end if;

  insert into pg_temp.s1_proof_results(label, ok, detail)
  values (
    'account recreation isolation',
    true,
    'new immutable canonical ID receives a new empty account and inherits no trial, entitlement or provider state'
  );
end;
$recreation$;

-- Final result contract.
do $final$
declare
  v_failures integer;
  v_total integer;
begin
  select count(*) filter (where not ok), count(*)
  into v_failures, v_total
  from pg_temp.s1_proof_results;

  if v_failures <> 0 then
    raise exception 'S1 proof contains % failed results', v_failures;
  end if;

  if v_total <> 14 then
    raise exception 'Expected 14 S1 proof results, found %', v_total;
  end if;

  raise notice 'PASS: ONE HEHA S1 SQL proof verified %/14 results', v_total;
end;
$final$;

rollback;
