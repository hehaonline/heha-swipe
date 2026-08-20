-- HEHA Community Pass Package A: managed-Supabase runtime configuration.
--
-- A real disposable Supabase branch proved that persistent custom GUCs such as
-- `app.community_pass_environment` cannot be set through the hosted migration
-- role. This forward-only migration replaces that unsupported dependency with
-- one private, server-owned configuration row. Missing configuration fails
-- closed. The environment is immutable after insertion.
--
-- The same branch review also identified uncovered foreign-key indexes. They are
-- added here before Package B provider-event and Checkout traffic exists.

begin;

create schema if not exists community_pass_private;
revoke all on schema community_pass_private from public;
revoke all on schema community_pass_private from anon;
revoke all on schema community_pass_private from authenticated;

create table if not exists community_pass_private.runtime_config (
  singleton boolean primary key default true check (singleton),
  environment text not null check (environment in ('test', 'live')),
  config_version text not null,
  configured_by text not null,
  change_reference text not null,
  configured_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

alter table community_pass_private.runtime_config enable row level security;
alter table community_pass_private.runtime_config force row level security;
revoke all on table community_pass_private.runtime_config from public;
revoke all on table community_pass_private.runtime_config from anon;
revoke all on table community_pass_private.runtime_config from authenticated;
revoke all on table community_pass_private.runtime_config from service_role;

create or replace function community_pass_private.guard_runtime_config()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Community Pass runtime configuration cannot be deleted'
      using errcode = '42501';
  end if;

  if new.environment is distinct from old.environment then
    raise exception 'Community Pass runtime environment is immutable once configured'
      using errcode = '42501';
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function community_pass_private.guard_runtime_config() from public;
revoke all on function community_pass_private.guard_runtime_config() from anon;
revoke all on function community_pass_private.guard_runtime_config() from authenticated;
revoke all on function community_pass_private.guard_runtime_config() from service_role;

drop trigger if exists community_pass_runtime_config_guard
  on community_pass_private.runtime_config;
create trigger community_pass_runtime_config_guard
before update or delete on community_pass_private.runtime_config
for each row execute function community_pass_private.guard_runtime_config();

create or replace function public.community_pass_runtime_environment()
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

revoke all on function public.community_pass_runtime_environment() from public;
revoke all on function public.community_pass_runtime_environment() from anon;
revoke all on function public.community_pass_runtime_environment() from authenticated;
grant execute on function public.community_pass_runtime_environment() to service_role;

-- Customer status remains a deliberately narrow authenticated SECURITY DEFINER
-- RPC. The customer supplies no account or environment identifier. The private
-- server configuration and auth.uid() bind the result, and no canonical table is
-- directly readable by the browser.
create or replace function public.get_my_community_pass_status()
returns table (
  account_status text,
  entitlement_state text,
  source_type text,
  plan_code text,
  amount_cents integer,
  currency text,
  valid_from timestamptz,
  valid_until timestamptz,
  renews_monthly boolean,
  cancel_at_period_end boolean,
  payment_recovery_deadline timestamptz,
  benefit_version text,
  offer_version text
)
language sql
security definer
stable
set search_path = ''
as $function$
  with runtime_environment as (
    select public.community_pass_runtime_environment() as value
  )
  select
    a.status as account_status,
    ent.state as entitlement_state,
    ent.source_type,
    case
      when ent.source_type = 'free_trial' then 'community_pass_free_trial_v1'
      when ent.source_type = 'monthly_subscription' then 'community_pass_monthly_slider_v1'
      when ent.source_type = 'prepaid_purchase' then p.plan_code
      else null
    end as plan_code,
    case
      when ent.source_type = 'monthly_subscription' then s.selected_amount_cents
      when ent.source_type = 'prepaid_purchase' then p.amount_cents
      else null
    end as amount_cents,
    case
      when ent.source_type = 'monthly_subscription' then s.currency
      when ent.source_type = 'prepaid_purchase' then p.currency
      else null
    end as currency,
    coalesce(ent.active_start_at, ent.trial_start_at) as valid_from,
    coalesce(ent.retained_current_month_end_at, ent.active_end_at, ent.trial_end_at) as valid_until,
    (
      ent.source_type = 'monthly_subscription'
      and s.status in ('active', 'payment_recovery')
      and not coalesce(s.cancel_at_period_end, false)
    ) as renews_monthly,
    coalesce(s.cancel_at_period_end, false) as cancel_at_period_end,
    s.recovery_deadline_at as payment_recovery_deadline,
    ent.benefit_version,
    ent.offer_version
  from runtime_environment runtime
  join public.community_pass_accounts a
    on runtime.value in ('test', 'live')
  left join lateral (
    select e.*
    from public.community_pass_entitlements e
    where e.account_id = a.id
      and e.user_id = auth.uid()
      and e.environment = runtime.value
    order by
      case e.state
        when 'trial_active' then 1
        when 'monthly_subscription_active' then 1
        when 'prepaid_term_active' then 1
        when 'payment_recovery' then 2
        when 'cancel_scheduled' then 2
        when 'support_review' then 2
        when 'reconciliation_exception' then 2
        when 'activation_available' then 3
        when 'invited' then 4
        when 'reserved' then 5
        else 6
      end,
      e.updated_at desc,
      e.created_at desc
    limit 1
  ) ent on true
  left join public.community_pass_subscriptions s on s.id = ent.subscription_id
  left join public.community_pass_purchases p on p.id = ent.purchase_id
  where a.user_id = auth.uid()
    and a.status <> 'deleted'
    and ent.id is not null
  limit 1;
$function$;

revoke all on function public.get_my_community_pass_status() from public;
revoke all on function public.get_my_community_pass_status() from anon;
revoke all on function public.get_my_community_pass_status() from authenticated;
grant execute on function public.get_my_community_pass_status() to authenticated;

create or replace function public.is_community_pass_active(
  p_user_id uuid,
  p_at_time timestamptz default pg_catalog.now()
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $function$
  with runtime_environment as (
    select public.community_pass_runtime_environment() as value
  )
  select case
    when runtime.value not in ('test', 'live') then false
    else exists (
      select 1
      from public.community_pass_entitlements e
      join public.community_pass_accounts a on a.id = e.account_id
      where e.user_id = p_user_id
        and a.user_id = p_user_id
        and e.environment = runtime.value
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
        and coalesce(
          e.active_start_at,
          e.trial_start_at,
          '-infinity'::timestamptz
        ) <= p_at_time
        and coalesce(
          e.retained_current_month_end_at,
          e.active_end_at,
          e.trial_end_at,
          'infinity'::timestamptz
        ) > p_at_time
    )
  end
  from runtime_environment runtime;
$function$;

revoke all on function public.is_community_pass_active(uuid, timestamptz) from public;
revoke all on function public.is_community_pass_active(uuid, timestamptz) from anon;
revoke all on function public.is_community_pass_active(uuid, timestamptz) from authenticated;
grant execute on function public.is_community_pass_active(uuid, timestamptz) to service_role;

create or replace function public.start_my_community_pass_trial()
returns table (
  entitlement_id uuid,
  state text,
  trial_start_at timestamptz,
  trial_end_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_environment text := public.community_pass_runtime_environment();
  v_account public.community_pass_accounts%rowtype;
  v_entitlement public.community_pass_entitlements%rowtype;
  v_now timestamptz := pg_catalog.now();
begin
  if v_user_id is null then
    raise exception 'HEHA_COMMUNITY_PASS_AUTH_REQUIRED'
      using errcode = '42501';
  end if;

  if v_environment not in ('test', 'live') then
    raise exception 'HEHA_COMMUNITY_PASS_ENVIRONMENT_UNAVAILABLE'
      using errcode = 'P0001';
  end if;

  select a.*
  into v_account
  from public.community_pass_accounts a
  where a.user_id = v_user_id
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
    and e.user_id = v_user_id
    and e.source_type = 'free_trial'
    and e.environment = v_environment
    and e.state in ('invited', 'activation_available')
    and e.invitation_sent_at is not null
    and e.invitation_expires_at is not null
    and e.invitation_expires_at >= v_now
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
    raise exception 'HEHA_COMMUNITY_PASS_OPEN_ENTITLEMENT_EXISTS'
      using errcode = 'P0001';
  end if;

  update public.community_pass_entitlements e
  set state = 'trial_active',
      trial_start_at = v_now,
      trial_end_at = v_now + interval '30 days',
      active_start_at = v_now,
      active_end_at = v_now + interval '30 days'
  where e.id = v_entitlement.id
  returning e.* into v_entitlement;

  update public.community_pass_accounts a
  set status = 'trial_active',
      trial_used_at = v_now
  where a.id = v_account.id;

  insert into public.community_pass_events (
    account_id,
    user_id,
    entity_type,
    entity_id,
    event_type,
    actor_type,
    actor_reference,
    reason_code,
    idempotency_key,
    environment,
    before_state,
    after_state,
    event_data,
    occurred_at
  ) values (
    v_account.id,
    v_user_id,
    'entitlement',
    v_entitlement.id,
    'trial_activated',
    'customer',
    null,
    'member_started',
    'community-pass-trial-activation:' || v_entitlement.id::text,
    v_entitlement.environment,
    'activation_available',
    'trial_active',
    pg_catalog.jsonb_build_object(
      'trial_start_at', v_entitlement.trial_start_at,
      'trial_end_at', v_entitlement.trial_end_at
    ),
    v_now
  )
  on conflict (environment, idempotency_key)
    where idempotency_key is not null
  do nothing;

  return query
  select
    v_entitlement.id,
    v_entitlement.state,
    v_entitlement.trial_start_at,
    v_entitlement.trial_end_at;
end;
$function$;

revoke all on function public.start_my_community_pass_trial() from public;
revoke all on function public.start_my_community_pass_trial() from anon;
revoke all on function public.start_my_community_pass_trial() from authenticated;
grant execute on function public.start_my_community_pass_trial() to authenticated;

-- The final unlink trigger must use the same private runtime authority as the
-- customer and benefit RPCs above. Child rows remain useful evidence when they
-- exist, while the private runtime row guarantees one privacy-minimized event
-- for an account that is deleted before it has any entitlement or payment row.
-- SECURITY DEFINER is required because Supabase Auth initiates the FK action as
-- supabase_auth_admin while canonical tables and the private runtime row remain
-- closed to that role. The empty search_path and fixed object references bound
-- the elevated work to this trigger's deletion cleanup contract.
create or replace function public.cascade_community_pass_account_unlink()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.user_id is not null and new.user_id is null then
    update public.community_pass_subscriptions s
    set user_id = null,
        status = case
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
              'account_unlinked_at', pg_catalog.now(),
              'account_unlink_reason', 'provider_reconciliation_required'
            )
          else s.metadata
        end
    where s.account_id = new.id;

    update public.community_pass_purchases p
    set user_id = null
    where p.account_id = new.id;

    update public.community_pass_entitlements e
    set user_id = null,
        state = case
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
          ) then coalesce(e.ended_at, pg_catalog.now())
          else e.ended_at
        end
    where e.account_id = new.id;

    update public.community_pass_acceptances ca
    set user_id = null,
        account_reference_hash = new.account_reference_hash,
        redacted_at = coalesce(ca.redacted_at, pg_catalog.now())
    where ca.account_id = new.id
      and ca.user_id is not null;

    update public.community_pass_events ce
    set user_id = null,
        actor_reference = case
          when ce.actor_type = 'customer' then null
          else ce.actor_reference
        end
    where ce.account_id = new.id
      and (
        ce.user_id is not null
        or (ce.actor_type = 'customer' and ce.actor_reference is not null)
      );

    insert into public.community_pass_events (
      account_id,
      user_id,
      entity_type,
      entity_id,
      event_type,
      actor_type,
      actor_reference,
      reason_code,
      idempotency_key,
      environment,
      before_state,
      after_state,
      event_data,
      occurred_at
    )
    select
      new.id,
      null,
      'account',
      new.id,
      'account_unlinked',
      'system',
      'auth_account_unlink',
      'account_deleted',
      'community-pass-account-unlinked:' || new.id::text || ':' || env.environment,
      env.environment,
      old.status,
      new.status,
      pg_catalog.jsonb_build_object(
        'provider_reconciliation_required', exists (
          select 1
          from public.community_pass_subscriptions s
          where s.account_id = new.id
            and s.environment = env.environment
            and s.status = 'reconciliation_exception'
        ),
        'prepaid_liability_open', exists (
          select 1
          from public.community_pass_purchases p
          where p.account_id = new.id
            and p.environment = env.environment
            and p.refundable_unearned_cents > 0
            and p.payment_state not in ('refunded', 'payment_failed', 'checkout_expired')
        )
      ),
      pg_catalog.now()
    from (
      select e.environment
      from public.community_pass_entitlements e
      where e.account_id = new.id
      union
      select s.environment
      from public.community_pass_subscriptions s
      where s.account_id = new.id
      union
      select p.environment
      from public.community_pass_purchases p
      where p.account_id = new.id
      union
      select public.community_pass_runtime_environment()
    ) env
    where env.environment in ('test', 'live')
    on conflict (environment, idempotency_key)
      where idempotency_key is not null
    do nothing;
  end if;

  return null;
end;
$function$;

revoke all on function public.cascade_community_pass_account_unlink() from public;
revoke all on function public.cascade_community_pass_account_unlink() from anon;
revoke all on function public.cascade_community_pass_account_unlink() from authenticated;

-- Cover every foreign-key access path flagged by the managed Supabase advisor.
create index if not exists community_pass_subscriptions_account_idx
  on public.community_pass_subscriptions(account_id);
create index if not exists community_pass_subscriptions_user_idx
  on public.community_pass_subscriptions(user_id)
  where user_id is not null;

create index if not exists community_pass_purchases_account_idx
  on public.community_pass_purchases(account_id);
create index if not exists community_pass_purchases_user_idx
  on public.community_pass_purchases(user_id)
  where user_id is not null;

create index if not exists community_pass_entitlements_account_idx
  on public.community_pass_entitlements(account_id);
create index if not exists community_pass_entitlements_user_idx
  on public.community_pass_entitlements(user_id)
  where user_id is not null;

create index if not exists community_pass_acceptances_account_idx
  on public.community_pass_acceptances(account_id);
create index if not exists community_pass_acceptances_user_idx
  on public.community_pass_acceptances(user_id)
  where user_id is not null;

create index if not exists community_pass_events_user_time_idx
  on public.community_pass_events(user_id, occurred_at desc)
  where user_id is not null;

comment on schema community_pass_private is
  'Private server-owned Community Pass configuration; not exposed to browser roles.';
comment on table community_pass_private.runtime_config is
  'Exactly one immutable test/live runtime environment row; inserted by an environment-specific reviewed deployment step.';
comment on function public.community_pass_runtime_environment() is
  'Server-owned Community Pass environment lookup; returns NULL when unconfigured so all customer/benefit decisions fail closed.';

commit;
