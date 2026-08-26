-- ONE HEHA S1 — server-only identity and Community Pass transitions.
--
-- REVIEW ONLY. This file is intentionally outside supabase/migrations.
-- No browser role receives EXECUTE. Later S2 endpoints must bind every supplied
-- source identifier to the authenticated server-side session before calling.

begin;

create or replace function community_pass_private.current_environment()
returns text
language sql
security definer
stable
set search_path = ''
as $function$
  select rc.environment
  from community_pass_private.runtime_config rc
  where rc.singleton
  limit 1;
$function$;

revoke all on function community_pass_private.current_environment() from public;
revoke all on function community_pass_private.current_environment() from anon;
revoke all on function community_pass_private.current_environment() from authenticated;
revoke all on function community_pass_private.current_environment() from service_role;

create or replace function one_heha_private.begin_link_handshake(
  p_request_id uuid,
  p_swipe_user_id uuid,
  p_identity_classification text,
  p_swipe_reauthenticated_at timestamptz,
  p_nonce_hash text,
  p_now timestamptz default pg_catalog.now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := community_pass_private.current_environment();
  v_existing one_heha_private.link_handshakes%rowtype;
  v_handshake_id uuid;
begin
  if v_environment not in ('test', 'live') then
    raise exception 'HEHA_ONE_ENVIRONMENT_UNAVAILABLE'
      using errcode = 'P0001';
  end if;

  if p_request_id is null or p_swipe_user_id is null then
    raise exception 'HEHA_ONE_INVALID_LINK_REQUEST'
      using errcode = '22023';
  end if;

  if p_identity_classification is distinct from 'verified_non_sso' then
    raise exception 'HEHA_ONE_LINK_MANUAL_REVIEW_REQUIRED'
      using errcode = 'P0001';
  end if;

  if p_nonce_hash is null or p_nonce_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'HEHA_ONE_INVALID_NONCE_HASH'
      using errcode = '22023';
  end if;

  if p_swipe_reauthenticated_at is null
     or p_swipe_reauthenticated_at < p_now - interval '10 minutes'
     or p_swipe_reauthenticated_at > p_now + interval '1 minute' then
    raise exception 'HEHA_ONE_SWIPE_REAUTHENTICATION_REQUIRED'
      using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_swipe_user_id) then
    raise exception 'HEHA_ONE_SWIPE_ACCOUNT_UNAVAILABLE'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'one-heha:swipe:' || v_environment || ':' || p_swipe_user_id::text,
      0
    )
  );

  select h.*
  into v_existing
  from one_heha_private.link_handshakes h
  where h.environment = v_environment
    and h.request_id = p_request_id
  for update;

  if found then
    if v_existing.swipe_user_id = p_swipe_user_id
       and v_existing.nonce_hash = p_nonce_hash
       and v_existing.state = 'pending'
       and v_existing.expires_at > p_now then
      return v_existing.id;
    end if;

    raise exception 'HEHA_ONE_LINK_REQUEST_REUSE_DENIED'
      using errcode = '42501';
  end if;

  update one_heha_private.link_handshakes h
  set state = 'expired'
  where h.environment = v_environment
    and h.swipe_user_id = p_swipe_user_id
    and h.state = 'pending'
    and h.expires_at <= p_now;

  if exists (
    select 1
    from one_heha_private.link_handshakes h
    where h.environment = v_environment
      and h.swipe_user_id = p_swipe_user_id
      and h.state = 'pending'
  ) then
    raise exception 'HEHA_ONE_LINK_ALREADY_PENDING'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from one_heha_private.identity_links l
    where l.environment = v_environment
      and l.swipe_user_id = p_swipe_user_id
      and l.status = 'active'
  ) then
    raise exception 'HEHA_ONE_ACCOUNT_ALREADY_LINKED'
      using errcode = 'P0001';
  end if;

  insert into one_heha_private.link_handshakes (
    request_id,
    swipe_user_id,
    environment,
    identity_classification,
    nonce_hash,
    state,
    swipe_reauthenticated_at,
    expires_at,
    created_at
  ) values (
    p_request_id,
    p_swipe_user_id,
    v_environment,
    p_identity_classification,
    p_nonce_hash,
    'pending',
    p_swipe_reauthenticated_at,
    p_now + interval '5 minutes',
    p_now
  )
  returning id into v_handshake_id;

  insert into one_heha_private.identity_events (
    handshake_id,
    swipe_user_id,
    environment,
    event_type,
    reason_code,
    idempotency_key,
    event_data,
    occurred_at
  ) values (
    v_handshake_id,
    p_swipe_user_id,
    v_environment,
    'link_requested',
    'dual_reauthentication_required',
    'link-requested:' || p_request_id::text,
    pg_catalog.jsonb_build_object(
      'link_version', 'one-heha-link-v1',
      'expires_at', p_now + interval '5 minutes'
    ),
    p_now
  );

  return v_handshake_id;
end;
$function$;

create or replace function one_heha_private.activate_identity_link(
  p_request_id uuid,
  p_swipe_user_id uuid,
  p_canonical_user_id uuid,
  p_local_reauthenticated_at timestamptz,
  p_local_assertion_jti_hash text,
  p_now timestamptz default pg_catalog.now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := community_pass_private.current_environment();
  v_handshake one_heha_private.link_handshakes%rowtype;
  v_link one_heha_private.identity_links%rowtype;
  v_conflict one_heha_private.identity_links%rowtype;
begin
  if v_environment not in ('test', 'live') then
    raise exception 'HEHA_ONE_ENVIRONMENT_UNAVAILABLE'
      using errcode = 'P0001';
  end if;

  if p_request_id is null
     or p_swipe_user_id is null
     or p_canonical_user_id is null then
    raise exception 'HEHA_ONE_INVALID_LINK_ACTIVATION'
      using errcode = '22023';
  end if;

  if p_local_assertion_jti_hash is null
     or p_local_assertion_jti_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'HEHA_ONE_INVALID_ASSERTION_JTI_HASH'
      using errcode = '22023';
  end if;

  if p_local_reauthenticated_at is null
     or p_local_reauthenticated_at < p_now - interval '10 minutes'
     or p_local_reauthenticated_at > p_now + interval '1 minute' then
    raise exception 'HEHA_ONE_LOCAL_REAUTHENTICATION_REQUIRED'
      using errcode = '42501';
  end if;

  -- All callers take the canonical lock first and the Swipe lock second.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'one-heha:canonical:' || v_environment || ':' || p_canonical_user_id::text,
      0
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'one-heha:swipe:' || v_environment || ':' || p_swipe_user_id::text,
      0
    )
  );

  select h.*
  into v_handshake
  from one_heha_private.link_handshakes h
  where h.environment = v_environment
    and h.request_id = p_request_id
    and h.swipe_user_id = p_swipe_user_id
  for update;

  if not found then
    raise exception 'HEHA_ONE_LINK_REQUEST_UNAVAILABLE'
      using errcode = '42501';
  end if;

  if v_handshake.state = 'consumed' then
    select l.*
    into v_link
    from one_heha_private.identity_links l
    where l.environment = v_environment
      and l.status = 'active'
      and l.swipe_user_id = p_swipe_user_id
      and l.canonical_user_id = p_canonical_user_id;

    if found
       and v_handshake.local_assertion_jti_hash = p_local_assertion_jti_hash then
      return v_link.id;
    end if;

    raise exception 'HEHA_ONE_ASSERTION_REPLAY_DENIED'
      using errcode = '42501';
  end if;

  if v_handshake.state <> 'pending'
     or v_handshake.identity_classification <> 'verified_non_sso'
     or v_handshake.expires_at <= p_now then
    if v_handshake.state = 'pending' and v_handshake.expires_at <= p_now then
      update one_heha_private.link_handshakes h
      set state = 'expired'
      where h.id = v_handshake.id;
    end if;

    raise exception 'HEHA_ONE_LINK_REQUEST_EXPIRED_OR_BLOCKED'
      using errcode = '42501';
  end if;

  if v_handshake.swipe_reauthenticated_at < p_now - interval '10 minutes'
     or v_handshake.swipe_reauthenticated_at > p_now + interval '1 minute' then
    raise exception 'HEHA_ONE_SWIPE_REAUTHENTICATION_EXPIRED'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from one_heha_private.link_handshakes h
    where h.environment = v_environment
      and h.local_assertion_jti_hash = p_local_assertion_jti_hash
      and h.id <> v_handshake.id
  ) then
    raise exception 'HEHA_ONE_ASSERTION_REPLAY_DENIED'
      using errcode = '42501';
  end if;

  select l.*
  into v_conflict
  from one_heha_private.identity_links l
  where l.environment = v_environment
    and l.status = 'active'
    and (
      l.canonical_user_id = p_canonical_user_id
      or l.swipe_user_id = p_swipe_user_id
    )
  order by l.created_at
  limit 1
  for update;

  if found then
    if v_conflict.canonical_user_id = p_canonical_user_id
       and v_conflict.swipe_user_id = p_swipe_user_id then
      update one_heha_private.identity_links l
      set last_verified_at = p_now
      where l.id = v_conflict.id
      returning l.* into v_link;
    else
      raise exception 'HEHA_ONE_IDENTITY_LINK_CONFLICT'
        using errcode = '23505';
    end if;
  else
    insert into one_heha_private.identity_links (
      canonical_user_id,
      swipe_user_id,
      environment,
      status,
      link_method,
      link_version,
      linked_at,
      last_verified_at,
      created_at,
      updated_at
    ) values (
      p_canonical_user_id,
      p_swipe_user_id,
      v_environment,
      'active',
      'dual_reauthentication_jws_v1',
      'one-heha-link-v1',
      p_now,
      p_now,
      p_now,
      p_now
    )
    returning * into v_link;
  end if;

  update one_heha_private.link_handshakes h
  set state = 'consumed',
      local_reauthenticated_at = p_local_reauthenticated_at,
      local_assertion_jti_hash = p_local_assertion_jti_hash,
      consumed_at = p_now
  where h.id = v_handshake.id;

  insert into one_heha_private.identity_events (
    link_id,
    handshake_id,
    canonical_user_id,
    swipe_user_id,
    environment,
    event_type,
    reason_code,
    idempotency_key,
    event_data,
    occurred_at
  ) values (
    v_link.id,
    v_handshake.id,
    p_canonical_user_id,
    p_swipe_user_id,
    v_environment,
    'local_identity_verified',
    'recent_local_reauthentication',
    'local-identity-verified:' || p_request_id::text,
    pg_catalog.jsonb_build_object('link_version', 'one-heha-link-v1'),
    p_now
  )
  on conflict (environment, idempotency_key) do nothing;

  insert into one_heha_private.identity_events (
    link_id,
    handshake_id,
    canonical_user_id,
    swipe_user_id,
    environment,
    event_type,
    reason_code,
    idempotency_key,
    event_data,
    occurred_at
  ) values (
    v_link.id,
    v_handshake.id,
    p_canonical_user_id,
    p_swipe_user_id,
    v_environment,
    'link_activated',
    'dual_reauthentication_complete',
    'link-activated:' || p_request_id::text,
    pg_catalog.jsonb_build_object('link_version', 'one-heha-link-v1'),
    p_now
  )
  on conflict (environment, idempotency_key) do nothing;

  return v_link.id;
end;
$function$;

create or replace function one_heha_private.resolve_canonical_user_for_swipe(
  p_swipe_user_id uuid,
  p_environment text
)
returns uuid
language sql
security definer
stable
set search_path = ''
as $function$
  select l.canonical_user_id
  from one_heha_private.identity_links l
  where l.swipe_user_id = p_swipe_user_id
    and l.environment = p_environment
    and l.status = 'active'
    and l.canonical_user_id is not null
  limit 1;
$function$;

create or replace function community_pass_private.resolve_account_for_swipe_user(
  p_swipe_user_id uuid
)
returns uuid
language sql
security definer
stable
set search_path = ''
as $function$
  with runtime as (
    select community_pass_private.current_environment() as environment
  ), canonical as (
    select one_heha_private.resolve_canonical_user_for_swipe(
      p_swipe_user_id,
      runtime.environment
    ) as canonical_user_id,
    runtime.environment
    from runtime
  )
  select a.id
  from canonical c
  join public.community_pass_accounts a
    on a.environment = c.environment
   and a.canonical_user_id = c.canonical_user_id
   and a.status <> 'deleted'
  where c.environment in ('test', 'live')
    and c.canonical_user_id is not null
  limit 1;
$function$;

create or replace function community_pass_private.create_or_get_account_for_swipe_user(
  p_swipe_user_id uuid,
  p_offer_version text,
  p_benefit_version text,
  p_policy_bundle_version text,
  p_now timestamptz default pg_catalog.now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := community_pass_private.current_environment();
  v_canonical_user_id uuid;
  v_account_id uuid;
begin
  if v_environment not in ('test', 'live') then
    raise exception 'HEHA_ONE_ENVIRONMENT_UNAVAILABLE'
      using errcode = 'P0001';
  end if;

  v_canonical_user_id := one_heha_private.resolve_canonical_user_for_swipe(
    p_swipe_user_id,
    v_environment
  );

  if v_canonical_user_id is null then
    raise exception 'HEHA_ONE_ACTIVE_LINK_REQUIRED'
      using errcode = '42501';
  end if;

  if nullif(p_offer_version, '') is null
     or nullif(p_benefit_version, '') is null
     or nullif(p_policy_bundle_version, '') is null then
    raise exception 'HEHA_COMMUNITY_PASS_VERSION_REQUIRED'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'community-pass:canonical:' || v_environment || ':' || v_canonical_user_id::text,
      0
    )
  );

  select a.id
  into v_account_id
  from public.community_pass_accounts a
  where a.environment = v_environment
    and a.canonical_user_id = v_canonical_user_id
    and a.status <> 'deleted'
  for update;

  if found then
    return v_account_id;
  end if;

  insert into public.community_pass_accounts (
    canonical_user_id,
    environment,
    status,
    offer_version,
    benefit_version,
    policy_bundle_version,
    created_at,
    updated_at
  ) values (
    v_canonical_user_id,
    v_environment,
    'inactive',
    p_offer_version,
    p_benefit_version,
    p_policy_bundle_version,
    p_now,
    p_now
  )
  returning id into v_account_id;

  insert into public.community_pass_events (
    account_id,
    entity_type,
    entity_id,
    event_type,
    actor_type,
    reason_code,
    idempotency_key,
    environment,
    before_state,
    after_state,
    event_data,
    occurred_at
  ) values (
    v_account_id,
    'account',
    v_account_id,
    'account_created',
    'system',
    'canonical_identity_linked',
    'community-pass-account-created:' || v_account_id::text,
    v_environment,
    null,
    'inactive',
    pg_catalog.jsonb_build_object('account_version', 'community-pass-account-v1'),
    p_now
  );

  return v_account_id;
end;
$function$;

create or replace function community_pass_private.start_trial_for_swipe_user(
  p_swipe_user_id uuid,
  p_now timestamptz default pg_catalog.now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := community_pass_private.current_environment();
  v_account public.community_pass_accounts%rowtype;
  v_entitlement public.community_pass_entitlements%rowtype;
begin
  if v_environment not in ('test', 'live') then
    raise exception 'HEHA_ONE_ENVIRONMENT_UNAVAILABLE'
      using errcode = 'P0001';
  end if;

  select a.*
  into v_account
  from public.community_pass_accounts a
  where a.id = community_pass_private.resolve_account_for_swipe_user(p_swipe_user_id)
    and a.environment = v_environment
    and a.status <> 'deleted'
  for update;

  if not found or v_account.trial_used_at is not null then
    raise exception 'HEHA_COMMUNITY_PASS_TRIAL_NOT_AVAILABLE'
      using errcode = 'P0001';
  end if;

  select e.*
  into v_entitlement
  from public.community_pass_entitlements e
  where e.account_id = v_account.id
    and e.environment = v_environment
    and e.source_type = 'free_trial'
    and e.state in ('invited', 'activation_available')
    and e.invitation_sent_at is not null
    and e.invitation_expires_at is not null
    and e.invitation_expires_at >= p_now
  order by e.invitation_sent_at desc
  limit 1
  for update;

  if not found then
    raise exception 'HEHA_COMMUNITY_PASS_TRIAL_NOT_AVAILABLE'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.community_pass_entitlements e
    where e.account_id = v_account.id
      and e.environment = v_environment
      and e.state in (
        'trial_active',
        'monthly_subscription_active',
        'prepaid_term_active',
        'payment_recovery',
        'cancel_scheduled',
        'support_review',
        'reconciliation_exception'
      )
  ) then
    raise exception 'HEHA_COMMUNITY_PASS_OPEN_CONTRACT_EXISTS'
      using errcode = 'P0001';
  end if;

  update public.community_pass_entitlements e
  set state = 'trial_active',
      trial_start_at = p_now,
      trial_end_at = p_now + interval '30 days',
      active_start_at = p_now,
      active_end_at = p_now + interval '30 days'
  where e.id = v_entitlement.id
  returning e.* into v_entitlement;

  update public.community_pass_accounts a
  set status = 'trial_active',
      trial_used_at = p_now
  where a.id = v_account.id;

  insert into public.community_pass_events (
    account_id,
    entity_type,
    entity_id,
    event_type,
    actor_type,
    reason_code,
    idempotency_key,
    environment,
    before_state,
    after_state,
    event_data,
    occurred_at
  ) values (
    v_account.id,
    'entitlement',
    v_entitlement.id,
    'trial_activated',
    'customer',
    'member_started',
    'community-pass-trial-activation:' || v_entitlement.id::text,
    v_environment,
    'activation_available',
    'trial_active',
    pg_catalog.jsonb_build_object(
      'trial_start_at', v_entitlement.trial_start_at,
      'trial_end_at', v_entitlement.trial_end_at
    ),
    p_now
  )
  on conflict (environment, idempotency_key)
    where idempotency_key is not null
  do nothing;

  return v_entitlement.id;
end;
$function$;

create or replace function community_pass_private.is_active_for_canonical_user(
  p_canonical_user_id uuid,
  p_at_time timestamptz default pg_catalog.now()
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $function$
  with runtime as (
    select community_pass_private.current_environment() as environment
  )
  select case
    when runtime.environment not in ('test', 'live') then false
    else exists (
      select 1
      from public.community_pass_accounts a
      join public.community_pass_entitlements e on e.account_id = a.id
      where a.canonical_user_id = p_canonical_user_id
        and a.environment = runtime.environment
        and e.environment = runtime.environment
        and a.status in (
          'trial_active',
          'monthly_subscription_active',
          'prepaid_term_active'
        )
        and e.state in (
          'trial_active',
          'monthly_subscription_active',
          'prepaid_term_active'
        )
        and coalesce(e.active_start_at, e.trial_start_at, '-infinity'::timestamptz) <= p_at_time
        and coalesce(
          e.retained_current_month_end_at,
          e.active_end_at,
          e.trial_end_at,
          'infinity'::timestamptz
        ) > p_at_time
    )
  end
  from runtime;
$function$;

create or replace function one_heha_private.revoke_identity_for_canonical_user(
  p_canonical_user_id uuid,
  p_request_id uuid,
  p_reason_code text,
  p_tombstone_hash text,
  p_now timestamptz default pg_catalog.now()
)
returns table (
  links_revoked integer,
  accounts_closed integer
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := community_pass_private.current_environment();
  v_idempotency_key text := 'canonical-delete:' || p_request_id::text;
  v_event one_heha_private.identity_events%rowtype;
  v_swipe_user_ids uuid[] := array[]::uuid[];
  v_account_ids uuid[] := array[]::uuid[];
  v_links integer := 0;
  v_accounts integer := 0;
begin
  if v_environment not in ('test', 'live') then
    raise exception 'HEHA_ONE_ENVIRONMENT_UNAVAILABLE'
      using errcode = 'P0001';
  end if;

  if p_canonical_user_id is null or p_request_id is null then
    raise exception 'HEHA_ONE_INVALID_DELETION_REQUEST'
      using errcode = '22023';
  end if;

  if nullif(p_reason_code, '') is null then
    raise exception 'HEHA_ONE_DELETION_REASON_REQUIRED'
      using errcode = '22023';
  end if;

  if p_tombstone_hash is null or p_tombstone_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'HEHA_ONE_INVALID_TOMBSTONE_HASH'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'one-heha:canonical:' || v_environment || ':' || p_canonical_user_id::text,
      0
    )
  );

  select e.*
  into v_event
  from one_heha_private.identity_events e
  where e.environment = v_environment
    and e.idempotency_key = v_idempotency_key;

  if found then
    return query
    select
      coalesce((v_event.event_data ->> 'links_revoked')::integer, 0),
      coalesce((v_event.event_data ->> 'accounts_closed')::integer, 0);
    return;
  end if;

  select coalesce(pg_catalog.array_agg(l.swipe_user_id) filter (where l.swipe_user_id is not null), array[]::uuid[])
  into v_swipe_user_ids
  from one_heha_private.identity_links l
  where l.environment = v_environment
    and l.canonical_user_id = p_canonical_user_id
    and l.status <> 'deleted';

  update one_heha_private.link_handshakes h
  set state = 'cancelled'
  where h.environment = v_environment
    and h.state = 'pending'
    and h.swipe_user_id = any(v_swipe_user_ids);

  update one_heha_private.identity_links l
  set canonical_user_id = null,
      swipe_user_id = null,
      status = 'deleted',
      revoked_at = coalesce(l.revoked_at, p_now),
      revocation_reason_code = p_reason_code,
      tombstone_hash = p_tombstone_hash
  where l.environment = v_environment
    and l.canonical_user_id = p_canonical_user_id
    and l.status <> 'deleted';

  get diagnostics v_links = row_count;

  select coalesce(pg_catalog.array_agg(a.id), array[]::uuid[])
  into v_account_ids
  from public.community_pass_accounts a
  where a.environment = v_environment
    and a.canonical_user_id = p_canonical_user_id
    and a.status <> 'deleted';

  update public.community_pass_subscriptions s
  set status = case
        when s.status in ('active', 'payment_recovery', 'cancel_scheduled')
          then 'reconciliation_exception'
        else s.status
      end,
      reconciliation_state = case
        when s.status in ('active', 'payment_recovery', 'cancel_scheduled')
          then 'exception'
        else s.reconciliation_state
      end,
      metadata = case
        when s.status in ('active', 'payment_recovery', 'cancel_scheduled')
          then coalesce(s.metadata, '{}'::jsonb) || pg_catalog.jsonb_build_object(
            'canonical_account_deleted_at', p_now,
            'provider_reconciliation_required', true
          )
        else s.metadata
      end
  where s.account_id = any(v_account_ids);

  update public.community_pass_entitlements e
  set state = case
        when e.state in (
          'trial_active',
          'monthly_subscription_active',
          'prepaid_term_active',
          'payment_recovery',
          'cancel_scheduled',
          'support_review',
          'reconciliation_exception'
        ) then 'revoked_account_deleted'
        else e.state
      end,
      ended_at = case
        when e.state in (
          'trial_active',
          'monthly_subscription_active',
          'prepaid_term_active',
          'payment_recovery',
          'cancel_scheduled',
          'support_review',
          'reconciliation_exception'
        ) then coalesce(e.ended_at, p_now)
        else e.ended_at
      end
  where e.account_id = any(v_account_ids);

  update public.community_pass_accounts a
  set canonical_user_id = null,
      account_reference_hash = p_tombstone_hash,
      account_reference_hash_version = 'opaque_tombstone_v1',
      status = 'deleted',
      deleted_at = coalesce(a.deleted_at, p_now),
      review_hold_reason_code = p_reason_code
  where a.id = any(v_account_ids);

  get diagnostics v_accounts = row_count;

  insert into one_heha_private.identity_events (
    canonical_user_id,
    environment,
    event_type,
    reason_code,
    idempotency_key,
    event_data,
    occurred_at
  ) values (
    null,
    v_environment,
    'canonical_account_deleted',
    p_reason_code,
    v_idempotency_key,
    pg_catalog.jsonb_build_object(
      'links_revoked', v_links,
      'accounts_closed', v_accounts,
      'tombstone_version', 'opaque_tombstone_v1'
    ),
    p_now
  );

  return query select v_links, v_accounts;
end;
$function$;

do $function_acl$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'one_heha_private.begin_link_handshake(uuid,uuid,text,timestamptz,text,timestamptz)',
    'one_heha_private.activate_identity_link(uuid,uuid,uuid,timestamptz,text,timestamptz)',
    'one_heha_private.resolve_canonical_user_for_swipe(uuid,text)',
    'community_pass_private.resolve_account_for_swipe_user(uuid)',
    'community_pass_private.create_or_get_account_for_swipe_user(uuid,text,text,text,timestamptz)',
    'community_pass_private.start_trial_for_swipe_user(uuid,timestamptz)',
    'community_pass_private.is_active_for_canonical_user(uuid,timestamptz)',
    'one_heha_private.revoke_identity_for_canonical_user(uuid,uuid,text,text,timestamptz)'
  ] loop
    execute pg_catalog.format('revoke all on function %s from public', v_signature);
    execute pg_catalog.format('revoke all on function %s from anon', v_signature);
    execute pg_catalog.format('revoke all on function %s from authenticated', v_signature);
    execute pg_catalog.format('grant execute on function %s to service_role', v_signature);
  end loop;
end;
$function_acl$;

commit;
