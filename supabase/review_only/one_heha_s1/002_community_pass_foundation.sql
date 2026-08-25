-- ONE HEHA S1 — canonical-user Community Pass foundation.
--
-- REVIEW ONLY. This file is intentionally outside supabase/migrations.
-- It recomposes the useful Package A semantics without treating Swipe Auth as
-- the permanent cross-app consumer identity.

begin;

create table if not exists community_pass_private.runtime_config (
  singleton boolean primary key default true check (singleton),
  environment text not null check (environment in ('test', 'live')),
  config_version text not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

alter table community_pass_private.runtime_config enable row level security;
alter table community_pass_private.runtime_config force row level security;

revoke all on table community_pass_private.runtime_config from public;
revoke all on table community_pass_private.runtime_config from anon;
revoke all on table community_pass_private.runtime_config from authenticated;
revoke all on table community_pass_private.runtime_config from service_role;

create or replace function community_pass_private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function community_pass_private.set_updated_at() from public;
revoke all on function community_pass_private.set_updated_at() from anon;
revoke all on function community_pass_private.set_updated_at() from authenticated;
revoke all on function community_pass_private.set_updated_at() from service_role;

create or replace function community_pass_private.guard_runtime_config()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'HEHA_COMMUNITY_PASS_RUNTIME_CONFIG_DELETE_DENIED'
      using errcode = '42501';
  end if;

  if old.environment is distinct from new.environment
     or old.config_version is distinct from new.config_version
     or old.created_at is distinct from new.created_at then
    raise exception 'HEHA_COMMUNITY_PASS_RUNTIME_CONFIG_IMMUTABLE'
      using errcode = '42501';
  end if;

  new.updated_at := old.updated_at;
  return new;
end;
$function$;

revoke all on function community_pass_private.guard_runtime_config() from public;
revoke all on function community_pass_private.guard_runtime_config() from anon;
revoke all on function community_pass_private.guard_runtime_config() from authenticated;
revoke all on function community_pass_private.guard_runtime_config() from service_role;

drop trigger if exists community_pass_runtime_config_guard on community_pass_private.runtime_config;
create trigger community_pass_runtime_config_guard
before update or delete on community_pass_private.runtime_config
for each row execute function community_pass_private.guard_runtime_config();

create table if not exists public.community_pass_accounts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  canonical_user_id uuid,
  environment text not null check (environment in ('test', 'live')),
  account_reference_hash text,
  account_reference_hash_version text,
  status text not null default 'inactive' check (
    status in (
      'inactive',
      'reserved',
      'invited',
      'trial_active',
      'monthly_subscription_active',
      'prepaid_term_active',
      'payment_recovery',
      'support_review',
      'suspended',
      'deleted',
      'reconciliation_exception'
    )
  ),
  trial_used_at timestamptz,
  review_hold_reason_code text,
  offer_version text not null,
  benefit_version text not null,
  policy_bundle_version text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_accounts_identity_state_check check (
    (status = 'deleted' and canonical_user_id is null and deleted_at is not null)
    or (status <> 'deleted' and canonical_user_id is not null)
  ),
  constraint community_pass_accounts_reference_hash_shape_check check (
    account_reference_hash is null
    or account_reference_hash ~ '^[a-f0-9]{64}$'
  )
);

create unique index if not exists community_pass_accounts_canonical_unique
  on public.community_pass_accounts(environment, canonical_user_id)
  where canonical_user_id is not null;

create unique index if not exists community_pass_accounts_reference_hash_unique
  on public.community_pass_accounts(environment, account_reference_hash)
  where account_reference_hash is not null;

create table if not exists public.community_pass_subscriptions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  stripe_customer_id text not null,
  stripe_subscription_id text not null,
  stripe_price_id text not null,
  latest_invoice_id text,
  selected_amount_cents integer not null check (
    selected_amount_cents between 200 and 10000
    and selected_amount_cents % 100 = 0
  ),
  quantity integer not null check (quantity between 2 and 100),
  currency text not null default 'usd' check (
    currency = lower(currency) and char_length(currency) = 3
  ),
  environment text not null check (environment in ('test', 'live')),
  status text not null check (
    status in (
      'checkout_pending',
      'incomplete',
      'active',
      'payment_recovery',
      'inactive_unpaid',
      'cancel_scheduled',
      'canceled',
      'refunded',
      'disputed',
      'reconciliation_exception'
    )
  ),
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  recovery_started_at timestamptz,
  recovery_deadline_at timestamptz,
  canceled_at timestamptz,
  offer_version text not null,
  benefit_version text not null,
  policy_bundle_version text not null,
  reconciliation_state text not null default 'pending' check (
    reconciliation_state in ('pending', 'matched', 'exception')
  ),
  metadata jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(metadata) = 'object'
  ),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_subscriptions_amount_quantity_check check (
    selected_amount_cents = quantity * 100
  ),
  constraint community_pass_subscriptions_period_check check (
    current_period_end is null
    or current_period_start is null
    or current_period_end > current_period_start
  ),
  constraint community_pass_subscriptions_recovery_check check (
    (status = 'payment_recovery'
      and recovery_started_at is not null
      and recovery_deadline_at is not null
      and recovery_deadline_at > recovery_started_at)
    or status <> 'payment_recovery'
  )
);

create unique index if not exists community_pass_subscriptions_provider_unique
  on public.community_pass_subscriptions(environment, stripe_subscription_id);

create unique index if not exists community_pass_subscriptions_open_account_unique
  on public.community_pass_subscriptions(account_id, environment)
  where status in ('active', 'payment_recovery', 'cancel_scheduled');

create index if not exists community_pass_subscriptions_account_idx
  on public.community_pass_subscriptions(account_id);

create table if not exists public.community_pass_purchases (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  plan_code text not null check (
    plan_code in (
      'community_pass_6_month_prepaid_v1',
      'community_pass_12_month_prepaid_v1'
    )
  ),
  term_months integer not null check (term_months in (6, 12)),
  amount_cents integer not null,
  currency text not null default 'usd' check (
    currency = lower(currency) and char_length(currency) = 3
  ),
  environment text not null check (environment in ('test', 'live')),
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  stripe_charge_id text,
  stripe_customer_id text,
  payment_state text not null default 'checkout_pending' check (
    payment_state in (
      'checkout_pending',
      'payment_pending',
      'reserved_paid',
      'payment_failed',
      'checkout_expired',
      'refund_requested',
      'refund_pending',
      'partially_refunded',
      'refunded',
      'refund_failed',
      'disputed',
      'reconciliation_exception'
    )
  ),
  gross_cents integer not null default 0 check (gross_cents >= 0),
  refunded_cents integer not null default 0 check (refunded_cents >= 0),
  refundable_unearned_cents integer not null default 0 check (refundable_unearned_cents >= 0),
  earned_cents integer not null default 0 check (earned_cents >= 0),
  reserved_at timestamptz,
  refund_requested_at timestamptz,
  refund_settled_at timestamptz,
  offer_version text not null,
  benefit_version text not null,
  policy_bundle_version text not null,
  reconciliation_state text not null default 'pending' check (
    reconciliation_state in ('pending', 'matched', 'exception')
  ),
  metadata jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(metadata) = 'object'
  ),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_purchases_plan_amount_check check (
    (plan_code = 'community_pass_6_month_prepaid_v1' and term_months = 6 and amount_cents = 1500)
    or
    (plan_code = 'community_pass_12_month_prepaid_v1' and term_months = 12 and amount_cents = 2500)
  ),
  constraint community_pass_purchases_money_check check (
    refunded_cents <= gross_cents
    and earned_cents <= gross_cents
    and refundable_unearned_cents <= gross_cents
    and refunded_cents + earned_cents + refundable_unearned_cents <= gross_cents
  )
);

create unique index if not exists community_pass_purchases_checkout_unique
  on public.community_pass_purchases(environment, stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create unique index if not exists community_pass_purchases_payment_intent_unique
  on public.community_pass_purchases(environment, stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

create index if not exists community_pass_purchases_account_idx
  on public.community_pass_purchases(account_id);

create table if not exists public.community_pass_entitlements (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  source_type text not null check (
    source_type in ('free_trial', 'monthly_subscription', 'prepaid_purchase')
  ),
  subscription_id uuid references public.community_pass_subscriptions(id) on delete restrict,
  purchase_id uuid references public.community_pass_purchases(id) on delete restrict,
  state text not null check (
    state in (
      'reserved',
      'invited',
      'activation_available',
      'trial_active',
      'monthly_subscription_active',
      'prepaid_term_active',
      'payment_recovery',
      'activation_window_expired',
      'support_review',
      'cancel_scheduled',
      'expired',
      'revoked_account_deleted',
      'refunded',
      'disputed',
      'reconciliation_exception'
    )
  ),
  environment text not null check (environment in ('test', 'live')),
  invitation_sent_at timestamptz,
  invitation_expires_at timestamptz,
  trial_start_at timestamptz,
  trial_end_at timestamptz,
  active_start_at timestamptz,
  active_end_at timestamptz,
  retained_current_month_end_at timestamptz,
  ended_at timestamptz,
  offer_version text not null,
  benefit_version text not null,
  policy_bundle_version text not null,
  human_override_reference text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_entitlements_source_check check (
    (source_type = 'free_trial' and subscription_id is null and purchase_id is null)
    or
    (source_type = 'monthly_subscription' and subscription_id is not null and purchase_id is null)
    or
    (source_type = 'prepaid_purchase' and purchase_id is not null and subscription_id is null)
  ),
  constraint community_pass_entitlements_invitation_check check (
    invitation_expires_at is null
    or invitation_sent_at is null
    or invitation_expires_at > invitation_sent_at
  ),
  constraint community_pass_entitlements_trial_check check (
    trial_end_at is null
    or trial_start_at is null
    or trial_end_at > trial_start_at
  ),
  constraint community_pass_entitlements_active_period_check check (
    active_end_at is null
    or active_start_at is null
    or active_end_at > active_start_at
  )
);

create unique index if not exists community_pass_entitlements_open_account_unique
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

create unique index if not exists community_pass_entitlements_subscription_unique
  on public.community_pass_entitlements(subscription_id)
  where subscription_id is not null;

create unique index if not exists community_pass_entitlements_purchase_unique
  on public.community_pass_entitlements(purchase_id)
  where purchase_id is not null;

create index if not exists community_pass_entitlements_account_idx
  on public.community_pass_entitlements(account_id);

create table if not exists public.community_pass_acceptances (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  plan_code text not null,
  selected_amount_cents integer,
  offer_version text not null,
  benefit_version text not null,
  terms_version text not null,
  privacy_version text not null,
  recurring_billing_version text,
  cancellation_policy_version text not null,
  refund_policy_version text not null,
  disclosure_text_hash text not null check (disclosure_text_hash ~ '^[a-f0-9]{64}$'),
  accepted_at timestamptz not null default pg_catalog.now(),
  locale text not null default 'en-US',
  app_surface text not null,
  app_version text,
  environment text not null check (environment in ('test', 'live')),
  server_request_id text not null,
  account_reference_hash text,
  created_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_acceptances_plan_disclosure_check check (
    (plan_code = 'community_pass_monthly_slider_v1'
      and recurring_billing_version is not null
      and selected_amount_cents between 200 and 10000
      and selected_amount_cents % 100 = 0)
    or
    (plan_code = 'community_pass_6_month_prepaid_v1'
      and recurring_billing_version is null
      and selected_amount_cents = 1500)
    or
    (plan_code = 'community_pass_12_month_prepaid_v1'
      and recurring_billing_version is null
      and selected_amount_cents = 2500)
    or
    (plan_code = 'community_pass_free_trial_v1'
      and recurring_billing_version is null
      and selected_amount_cents is null)
  )
);

create unique index if not exists community_pass_acceptances_request_unique
  on public.community_pass_acceptances(environment, server_request_id);

create index if not exists community_pass_acceptances_account_idx
  on public.community_pass_acceptances(account_id);

create table if not exists public.community_pass_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  entity_type text not null check (
    entity_type in (
      'account',
      'subscription',
      'purchase',
      'entitlement',
      'acceptance',
      'refund',
      'dispute',
      'support_case'
    )
  ),
  entity_id uuid,
  event_type text not null,
  actor_type text not null check (
    actor_type in ('customer', 'system', 'stripe', 'staff', 'support', 'migration')
  ),
  actor_reference_hash text,
  reason_code text,
  idempotency_key text,
  provider_event_id text,
  environment text not null check (environment in ('test', 'live')),
  before_state text,
  after_state text,
  event_data jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(event_data) = 'object'
  ),
  occurred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_events_actor_hash_shape_check check (
    actor_reference_hash is null
    or actor_reference_hash ~ '^[a-f0-9]{64}$'
  )
);

create unique index if not exists community_pass_events_idempotency_unique
  on public.community_pass_events(environment, idempotency_key)
  where idempotency_key is not null;

create index if not exists community_pass_events_account_time_idx
  on public.community_pass_events(account_id, occurred_at desc);

create table if not exists public.community_pass_stripe_event_inbox (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  stripe_event_id text not null,
  event_type text not null,
  environment text not null check (environment in ('test', 'live')),
  livemode boolean not null,
  object_id text,
  event_created_at timestamptz,
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  status text not null default 'pending' check (
    status in ('pending', 'processing', 'retryable', 'processed', 'dead_letter')
  ),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz,
  processing_started_at timestamptz,
  processed_at timestamptz,
  last_error_code text,
  last_error_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_stripe_inbox_livemode_check check (
    (environment = 'live' and livemode)
    or (environment = 'test' and not livemode)
  ),
  constraint community_pass_stripe_inbox_processed_check check (
    (status = 'processed' and processed_at is not null)
    or status <> 'processed'
  )
);

create unique index if not exists community_pass_stripe_inbox_event_unique
  on public.community_pass_stripe_event_inbox(environment, stripe_event_id);

create index if not exists community_pass_stripe_inbox_retry_idx
  on public.community_pass_stripe_event_inbox(status, next_attempt_at);

create or replace function community_pass_private.guard_trial_used_once()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.trial_used_at is not null
     and new.trial_used_at is distinct from old.trial_used_at then
    raise exception 'HEHA_COMMUNITY_PASS_TRIAL_USE_IMMUTABLE'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function community_pass_private.guard_trial_used_once() from public;
revoke all on function community_pass_private.guard_trial_used_once() from anon;
revoke all on function community_pass_private.guard_trial_used_once() from authenticated;
revoke all on function community_pass_private.guard_trial_used_once() from service_role;

create or replace function community_pass_private.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'HEHA_COMMUNITY_PASS_APPEND_ONLY'
    using errcode = '42501';
end;
$function$;

revoke all on function community_pass_private.reject_append_only_mutation() from public;
revoke all on function community_pass_private.reject_append_only_mutation() from anon;
revoke all on function community_pass_private.reject_append_only_mutation() from authenticated;
revoke all on function community_pass_private.reject_append_only_mutation() from service_role;

drop trigger if exists community_pass_accounts_set_updated_at on public.community_pass_accounts;
create trigger community_pass_accounts_set_updated_at
before update on public.community_pass_accounts
for each row execute function community_pass_private.set_updated_at();

drop trigger if exists community_pass_subscriptions_set_updated_at on public.community_pass_subscriptions;
create trigger community_pass_subscriptions_set_updated_at
before update on public.community_pass_subscriptions
for each row execute function community_pass_private.set_updated_at();

drop trigger if exists community_pass_purchases_set_updated_at on public.community_pass_purchases;
create trigger community_pass_purchases_set_updated_at
before update on public.community_pass_purchases
for each row execute function community_pass_private.set_updated_at();

drop trigger if exists community_pass_entitlements_set_updated_at on public.community_pass_entitlements;
create trigger community_pass_entitlements_set_updated_at
before update on public.community_pass_entitlements
for each row execute function community_pass_private.set_updated_at();

drop trigger if exists community_pass_stripe_inbox_set_updated_at on public.community_pass_stripe_event_inbox;
create trigger community_pass_stripe_inbox_set_updated_at
before update on public.community_pass_stripe_event_inbox
for each row execute function community_pass_private.set_updated_at();

drop trigger if exists community_pass_accounts_trial_used_once on public.community_pass_accounts;
create trigger community_pass_accounts_trial_used_once
before update of trial_used_at on public.community_pass_accounts
for each row execute function community_pass_private.guard_trial_used_once();

drop trigger if exists community_pass_acceptances_append_only on public.community_pass_acceptances;
create trigger community_pass_acceptances_append_only
before update or delete on public.community_pass_acceptances
for each row execute function community_pass_private.reject_append_only_mutation();

drop trigger if exists community_pass_events_append_only on public.community_pass_events;
create trigger community_pass_events_append_only
before update or delete on public.community_pass_events
for each row execute function community_pass_private.reject_append_only_mutation();

do $rls_and_acl$
declare
  v_table text;
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
    execute pg_catalog.format('alter table public.%I enable row level security', v_table);
    execute pg_catalog.format('alter table public.%I force row level security', v_table);
    execute pg_catalog.format('revoke all on table public.%I from public', v_table);
    execute pg_catalog.format('revoke all on table public.%I from anon', v_table);
    execute pg_catalog.format('revoke all on table public.%I from authenticated', v_table);
  end loop;
end;
$rls_and_acl$;

commit;
