-- Community Pass Package A security and truthfulness hardening.
--
-- Review-only follow-up. This closes exact-head gaps found after the first
-- synthetic proof:
--   1. benefit/status decisions are bound to a server-owned environment;
--   2. prepaid acceptances record the exact $15/$25 amount;
--   3. trial use is monotonic and cannot be reset;
--   4. account deletion removes customer actor linkage and records a durable,
--      privacy-minimized unlink event;
--   5. recovery/support/reconciliation states cannot be bypassed by activating
--      another entitlement.
--
-- No provider, customer, billing, or Production action occurs when this file is
-- merely committed. Apply only to disposable/current-schema review environments
-- until the final Production gate is separately approved.

begin;

-- Trigger authorization must rely on the effective database role, not a mutable
-- request GUC. SECURITY DEFINER callers execute as their function owner; direct
-- trusted writes execute as service_role/postgres/auth-admin.
create or replace function public.community_pass_request_role()
returns text
language sql
stable
set search_path = ''
as $function$
  select current_user::text;
$function$;

revoke all on function public.community_pass_request_role() from public;
revoke all on function public.community_pass_request_role() from anon;
revoke all on function public.community_pass_request_role() from authenticated;
grant execute on function public.community_pass_request_role() to service_role;

do $grant_auth_admin$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant execute on function public.community_pass_request_role() to supabase_auth_admin';
  end if;
end;
$grant_auth_admin$;

-- A prepaid clickwrap must preserve the exact one-time amount, just as the
-- recurring clickwrap preserves the selected monthly amount. Both constraint
-- names are dropped so the forward migration is safe under repeatability proof.
alter table public.community_pass_acceptances
  drop constraint if exists community_pass_acceptances_monthly_disclosure_check;

alter table public.community_pass_acceptances
  drop constraint if exists community_pass_acceptances_plan_disclosure_check;

alter table public.community_pass_acceptances
  add constraint community_pass_acceptances_plan_disclosure_check check (
    (
      plan_code = 'community_pass_monthly_slider_v1'
      and recurring_billing_version is not null
      and selected_amount_cents between 200 and 10000
      and selected_amount_cents % 100 = 0
    )
    or
    (
      plan_code = 'community_pass_6_month_prepaid_v1'
      and recurring_billing_version is null
      and selected_amount_cents = 1500
    )
    or
    (
      plan_code = 'community_pass_12_month_prepaid_v1'
      and recurring_billing_version is null
      and selected_amount_cents = 2500
    )
    or
    (
      plan_code = 'community_pass_free_trial_v1'
      and recurring_billing_version is null
      and selected_amount_cents is null
    )
  );

-- Once consumed, the founding trial marker cannot be cleared or rewritten.
create or replace function public.guard_community_pass_trial_used_once()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.trial_used_at is not null
     and new.trial_used_at is distinct from old.trial_used_at then
    raise exception 'Community Pass trial use is immutable once recorded'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_community_pass_trial_used_once() from public;
revoke all on function public.guard_community_pass_trial_used_once() from anon;
revoke all on function public.guard_community_pass_trial_used_once() from authenticated;

drop trigger if exists community_pass_accounts_trial_used_once on public.community_pass_accounts;
create trigger community_pass_accounts_trial_used_once
before update of trial_used_at on public.community_pass_accounts
for each row execute function public.guard_community_pass_trial_used_once();

-- One account/environment may have only one open entitlement contract. Recovery,
-- cancellation, support review, and reconciliation exceptions remain open states
-- and cannot be bypassed by activating a second entitlement.
drop index if exists public.community_pass_entitlements_active_account_unique;
create unique index community_pass_entitlements_active_account_unique
  on public.community_pass_entitlements(account_id, environment)
  where state in (
    'trial_active',
    'monthly_subscription_active',
    'prepaid_term_active',
    'payment_recovery',
    'cancel_scheduled',
    'support_review',
    'reconciliation_exception'
  );

-- Customer status fails closed unless the database has an explicit test/live
-- environment setting. A disposable proof database sets this to `test`; the live
-- project must set it to `live` in a separately reviewed configuration step.
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
    select nullif(
      pg_catalog.current_setting('app.community_pass_environment', true),
      ''
    ) as value
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
  limit 1;
$function$;

revoke all on function public.get_my_community_pass_status() from public;
revoke all on function public.get_my_community_pass_status() from anon;
revoke all on function public.get_my_community_pass_status() from authenticated;
grant execute on function public.get_my_community_pass_status() to authenticated;

-- The server benefit decision is bound to the database's reviewed environment.
-- Missing, invalid, or mismatched configuration returns false.
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
    select nullif(
      pg_catalog.current_setting('app.community_pass_environment', true),
      ''
    ) as value
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

-- Event facts remain immutable. During trusted deletion, the direct customer
-- actor reference may be cleared in the same one-way mutation as user_id.
create or replace function public.guard_community_pass_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_role text := public.community_pass_request_role();
  v_customer_actor_redaction boolean := false;
begin
  if tg_op = 'DELETE' then
    raise exception 'Community Pass events cannot be deleted'
      using errcode = '42501';
  end if;

  if v_role not in ('service_role', 'postgres', 'supabase_admin', 'supabase_auth_admin') then
    raise exception 'Only the trusted backend may redact Community Pass event linkage'
      using errcode = '42501';
  end if;

  v_customer_actor_redaction := (
    old.user_id is not null
    and new.user_id is null
    and old.actor_type = 'customer'
    and new.actor_reference is null
  );

  if new.id is distinct from old.id
     or new.account_id is distinct from old.account_id
     or new.entity_type is distinct from old.entity_type
     or new.entity_id is distinct from old.entity_id
     or new.event_type is distinct from old.event_type
     or new.actor_type is distinct from old.actor_type
     or (
       new.actor_reference is distinct from old.actor_reference
       and not v_customer_actor_redaction
     )
     or new.reason_code is distinct from old.reason_code
     or new.idempotency_key is distinct from old.idempotency_key
     or new.provider_event_id is distinct from old.provider_event_id
     or new.environment is distinct from old.environment
     or new.before_state is distinct from old.before_state
     or new.after_state is distinct from old.after_state
     or new.event_data is distinct from old.event_data
     or new.occurred_at is distinct from old.occurred_at
     or new.created_at is distinct from old.created_at then
    raise exception 'Community Pass event facts are immutable'
      using errcode = '42501';
  end if;

  if old.user_id is null and new.user_id is not null then
    raise exception 'Redacted Community Pass event cannot be re-linked'
      using errcode = '42501';
  end if;

  if new.user_id is distinct from old.user_id and new.user_id is not null then
    raise exception 'Community Pass event user linkage may only be cleared'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_community_pass_events_append_only() from public;
revoke all on function public.guard_community_pass_events_append_only() from anon;
revoke all on function public.guard_community_pass_events_append_only() from authenticated;

-- Trial activation now uses the configured environment, blocks any other open
-- contract in that environment, and avoids retaining the user's UUID in the
-- immutable actor_reference field.
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
  v_environment text := nullif(
    pg_catalog.current_setting('app.community_pass_environment', true),
    ''
  );
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

-- Account unlink keeps provider and financial facts, removes direct customer
-- linkage, and appends one privacy-minimized event per known environment.
create or replace function public.cascade_community_pass_account_unlink()
returns trigger
language plpgsql
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
      select nullif(
        pg_catalog.current_setting('app.community_pass_environment', true),
        ''
      )
      where nullif(
        pg_catalog.current_setting('app.community_pass_environment', true),
        ''
      ) in ('test', 'live')
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

commit;
