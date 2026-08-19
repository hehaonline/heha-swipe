-- HEHA Community Pass Package A: server-owned entitlement and audit foundation.
--
-- Review-only migration. Apply only to a disposable Supabase branch/current-schema
-- clone until exact-head proof, independent review, CPA/legal decisions, and a
-- separate Production approval pass.
--
-- This migration is additive. It does not reinterpret or rewrite legacy
-- supporter_* rows, profile subscription caches, Stripe IDs, or customer state.

begin;

create or replace function public.community_pass_request_role()
returns text
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_claims jsonb := '{}'::jsonb;
  v_role text;
begin
  begin
    v_claims := coalesce(
      nullif(pg_catalog.current_setting('request.jwt.claims', true), ''),
      '{}'
    )::jsonb;
  exception
    when others then
      v_claims := '{}'::jsonb;
  end;

  v_role := coalesce(
    nullif(v_claims ->> 'role', ''),
    nullif(pg_catalog.current_setting('request.jwt.claim.role', true), ''),
    current_user
  );

  return v_role;
end;
$function$;

revoke all on function public.community_pass_request_role() from public;
revoke all on function public.community_pass_request_role() from anon;
revoke all on function public.community_pass_request_role() from authenticated;
grant execute on function public.community_pass_request_role() to authenticated;
grant execute on function public.community_pass_request_role() to service_role;
do $grant_auth_admin$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant execute on function public.community_pass_request_role() to supabase_auth_admin';
  end if;
end;
$grant_auth_admin$;

create or replace function public.community_pass_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function public.community_pass_set_updated_at() from public;
revoke all on function public.community_pass_set_updated_at() from anon;
revoke all on function public.community_pass_set_updated_at() from authenticated;

create table if not exists public.community_pass_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
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
  constraint community_pass_accounts_deleted_state_check check (
    (status = 'deleted' and deleted_at is not null)
    or status <> 'deleted'
  )
);

create unique index if not exists community_pass_accounts_user_unique
  on public.community_pass_accounts(user_id)
  where user_id is not null;

create unique index if not exists community_pass_accounts_reference_hash_unique
  on public.community_pass_accounts(account_reference_hash)
  where account_reference_hash is not null;

create table if not exists public.community_pass_subscriptions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  stripe_customer_id text not null,
  stripe_subscription_id text not null,
  stripe_price_id text not null,
  latest_invoice_id text,
  selected_amount_cents integer not null check (
    selected_amount_cents between 200 and 10000
    and selected_amount_cents % 100 = 0
  ),
  quantity integer not null check (quantity between 2 and 100),
  currency text not null default 'usd' check (currency = lower(currency) and char_length(currency) = 3),
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
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_subscriptions_amount_quantity_check
    check (selected_amount_cents = quantity * 100),
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

create unique index if not exists community_pass_subscriptions_active_account_unique
  on public.community_pass_subscriptions(account_id, environment)
  where status in ('active', 'payment_recovery', 'cancel_scheduled');

create table if not exists public.community_pass_purchases (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  plan_code text not null check (
    plan_code in ('community_pass_6_month_prepaid_v1', 'community_pass_12_month_prepaid_v1')
  ),
  term_months integer not null check (term_months in (6, 12)),
  amount_cents integer not null,
  currency text not null default 'usd' check (currency = lower(currency) and char_length(currency) = 3),
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
  metadata jsonb not null default '{}'::jsonb,
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

create table if not exists public.community_pass_entitlements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
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

create unique index if not exists community_pass_entitlements_active_account_unique
  on public.community_pass_entitlements(account_id, environment)
  where state in ('trial_active', 'monthly_subscription_active', 'prepaid_term_active');

create unique index if not exists community_pass_entitlements_subscription_unique
  on public.community_pass_entitlements(subscription_id)
  where subscription_id is not null;

create unique index if not exists community_pass_entitlements_purchase_unique
  on public.community_pass_entitlements(purchase_id)
  where purchase_id is not null;

create table if not exists public.community_pass_acceptances (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  subscription_attempt_id uuid,
  purchase_attempt_id uuid,
  plan_code text not null,
  selected_amount_cents integer,
  offer_version text not null,
  benefit_version text not null,
  terms_version text not null,
  privacy_version text not null,
  recurring_billing_version text,
  cancellation_policy_version text not null,
  refund_policy_version text not null,
  disclosure_text_hash text not null,
  accepted_at timestamptz not null default pg_catalog.now(),
  locale text not null default 'en-US',
  app_surface text not null,
  app_version text,
  environment text not null check (environment in ('test', 'live')),
  server_request_id text not null,
  account_reference_hash text,
  redacted_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_acceptances_monthly_disclosure_check check (
    (plan_code = 'community_pass_monthly_slider_v1'
      and recurring_billing_version is not null
      and selected_amount_cents between 200 and 10000
      and selected_amount_cents % 100 = 0)
    or
    (plan_code in ('community_pass_6_month_prepaid_v1', 'community_pass_12_month_prepaid_v1')
      and recurring_billing_version is null)
    or
    (plan_code = 'community_pass_free_trial_v1'
      and recurring_billing_version is null
      and selected_amount_cents is null)
  )
);

create unique index if not exists community_pass_acceptances_request_unique
  on public.community_pass_acceptances(environment, server_request_id);

create table if not exists public.community_pass_events (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.community_pass_accounts(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  entity_type text not null check (
    entity_type in ('account', 'subscription', 'purchase', 'entitlement', 'acceptance', 'refund', 'dispute', 'support_case')
  ),
  entity_id uuid,
  event_type text not null,
  actor_type text not null check (actor_type in ('customer', 'system', 'stripe', 'staff', 'support', 'migration')),
  actor_reference text,
  reason_code text,
  idempotency_key text,
  provider_event_id text,
  environment text not null check (environment in ('test', 'live')),
  before_state text,
  after_state text,
  event_data jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create unique index if not exists community_pass_events_idempotency_unique
  on public.community_pass_events(environment, idempotency_key)
  where idempotency_key is not null;

create index if not exists community_pass_events_account_time_idx
  on public.community_pass_events(account_id, occurred_at desc);

create table if not exists public.community_pass_stripe_event_inbox (
  id uuid primary key default gen_random_uuid(),
  stripe_event_id text not null,
  event_type text not null,
  environment text not null check (environment in ('test', 'live')),
  livemode boolean not null,
  object_id text,
  event_created_at timestamptz,
  payload_hash text not null,
  status text not null default 'pending' check (
    status in ('pending', 'processing', 'retryable', 'processed', 'dead_letter')
  ),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  first_received_at timestamptz not null default pg_catalog.now(),
  last_attempt_at timestamptz,
  next_retry_at timestamptz,
  processed_at timestamptz,
  error_code text,
  error_summary text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint community_pass_stripe_event_inbox_finality_check check (
    (status = 'processed' and processed_at is not null)
    or status <> 'processed'
  )
);

create unique index if not exists community_pass_stripe_event_inbox_provider_unique
  on public.community_pass_stripe_event_inbox(environment, stripe_event_id);

create index if not exists community_pass_stripe_event_inbox_retry_idx
  on public.community_pass_stripe_event_inbox(status, next_retry_at)
  where status in ('pending', 'retryable');

-- Updated-at triggers for mutable operational tables.
drop trigger if exists community_pass_accounts_set_updated_at on public.community_pass_accounts;
create trigger community_pass_accounts_set_updated_at
before update on public.community_pass_accounts
for each row execute function public.community_pass_set_updated_at();

drop trigger if exists community_pass_subscriptions_set_updated_at on public.community_pass_subscriptions;
create trigger community_pass_subscriptions_set_updated_at
before update on public.community_pass_subscriptions
for each row execute function public.community_pass_set_updated_at();

drop trigger if exists community_pass_purchases_set_updated_at on public.community_pass_purchases;
create trigger community_pass_purchases_set_updated_at
before update on public.community_pass_purchases
for each row execute function public.community_pass_set_updated_at();

drop trigger if exists community_pass_entitlements_set_updated_at on public.community_pass_entitlements;
create trigger community_pass_entitlements_set_updated_at
before update on public.community_pass_entitlements
for each row execute function public.community_pass_set_updated_at();

drop trigger if exists community_pass_stripe_event_inbox_set_updated_at on public.community_pass_stripe_event_inbox;
create trigger community_pass_stripe_event_inbox_set_updated_at
before update on public.community_pass_stripe_event_inbox
for each row execute function public.community_pass_set_updated_at();

-- Events are append-only except for controlled privacy redaction of the user
-- linkage after account deletion. Event meaning, state, amounts, actor, reason,
-- timestamps, and payload remain immutable.
create or replace function public.guard_community_pass_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_role text := public.community_pass_request_role();
begin
  if tg_op = 'DELETE' then
    raise exception 'Community Pass events cannot be deleted'
      using errcode = '42501';
  end if;

  if v_role not in ('service_role', 'postgres', 'supabase_admin', 'supabase_auth_admin') then
    raise exception 'Only the trusted backend may redact Community Pass event linkage'
      using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.account_id is distinct from old.account_id
     or new.entity_type is distinct from old.entity_type
     or new.entity_id is distinct from old.entity_id
     or new.event_type is distinct from old.event_type
     or new.actor_type is distinct from old.actor_type
     or new.actor_reference is distinct from old.actor_reference
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

drop trigger if exists community_pass_events_append_only on public.community_pass_events;
create trigger community_pass_events_append_only
before update or delete on public.community_pass_events
for each row execute function public.guard_community_pass_events_append_only();

-- Acceptances are immutable except for a controlled privacy redaction of the
-- account linkage after deletion. The disclosure/versions/amount/timestamp may
-- never be rewritten.
create or replace function public.guard_community_pass_acceptance_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_role text := public.community_pass_request_role();
begin
  if tg_op = 'DELETE' then
    raise exception 'Community Pass acceptance evidence cannot be deleted'
      using errcode = '42501';
  end if;

  if v_role not in ('service_role', 'postgres', 'supabase_admin', 'supabase_auth_admin') then
    raise exception 'Only the trusted backend may redact Community Pass acceptance linkage'
      using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.account_id is distinct from old.account_id
     or new.subscription_attempt_id is distinct from old.subscription_attempt_id
     or new.purchase_attempt_id is distinct from old.purchase_attempt_id
     or new.plan_code is distinct from old.plan_code
     or new.selected_amount_cents is distinct from old.selected_amount_cents
     or new.offer_version is distinct from old.offer_version
     or new.benefit_version is distinct from old.benefit_version
     or new.terms_version is distinct from old.terms_version
     or new.privacy_version is distinct from old.privacy_version
     or new.recurring_billing_version is distinct from old.recurring_billing_version
     or new.cancellation_policy_version is distinct from old.cancellation_policy_version
     or new.refund_policy_version is distinct from old.refund_policy_version
     or new.disclosure_text_hash is distinct from old.disclosure_text_hash
     or new.accepted_at is distinct from old.accepted_at
     or new.locale is distinct from old.locale
     or new.app_surface is distinct from old.app_surface
     or new.app_version is distinct from old.app_version
     or new.environment is distinct from old.environment
     or new.server_request_id is distinct from old.server_request_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Community Pass acceptance contract fields are immutable'
      using errcode = '42501';
  end if;

  if old.user_id is null and new.user_id is not null then
    raise exception 'Redacted Community Pass acceptance cannot be re-linked'
      using errcode = '42501';
  end if;

  if new.user_id is distinct from old.user_id
     and new.user_id is not null then
    raise exception 'Community Pass acceptance user linkage may only be cleared'
      using errcode = '42501';
  end if;

  if new.user_id is null and old.user_id is not null then
    if new.redacted_at is null or new.account_reference_hash is null then
      raise exception 'Acceptance redaction requires redacted_at and account_reference_hash'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_community_pass_acceptance_mutation() from public;
revoke all on function public.guard_community_pass_acceptance_mutation() from anon;
revoke all on function public.guard_community_pass_acceptance_mutation() from authenticated;

drop trigger if exists community_pass_acceptances_mutation_guard on public.community_pass_acceptances;
create trigger community_pass_acceptances_mutation_guard
before update or delete on public.community_pass_acceptances
for each row execute function public.guard_community_pass_acceptance_mutation();

-- A removed auth user must never remain benefit-active. Production deletion
-- should pre-populate a peppered reference hash; this trigger provides a
-- deterministic UUID hash fallback so entitlement revocation still fails safe.
create or replace function public.revoke_community_pass_on_account_unlink()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_hash text;
  v_salt text;
begin
  if old.user_id is not null and new.user_id is null then
    v_salt := nullif(pg_catalog.current_setting('app.community_pass_hash_salt', true), '');
    v_hash := coalesce(
      new.account_reference_hash,
      pg_catalog.md5(coalesce(v_salt, 'UNSALTED_REVIEW_ONLY') || ':' || old.user_id::text)
    );

    new.account_reference_hash := v_hash;
    new.account_reference_hash_version := coalesce(
      new.account_reference_hash_version,
      case when v_salt is null then 'review_only_uuid_hash_v1' else 'peppered_uuid_hash_v1' end
    );
    new.status := 'deleted';
    new.deleted_at := coalesce(new.deleted_at, pg_catalog.now());
    new.review_hold_reason_code := coalesce(new.review_hold_reason_code, 'account_deleted');
  end if;

  return new;
end;
$function$;

revoke all on function public.revoke_community_pass_on_account_unlink() from public;
revoke all on function public.revoke_community_pass_on_account_unlink() from anon;
revoke all on function public.revoke_community_pass_on_account_unlink() from authenticated;

drop trigger if exists community_pass_accounts_unlink_guard on public.community_pass_accounts;
create trigger community_pass_accounts_unlink_guard
before update of user_id on public.community_pass_accounts
for each row execute function public.revoke_community_pass_on_account_unlink();

create or replace function public.cascade_community_pass_account_unlink()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.user_id is not null and new.user_id is null then
    update public.community_pass_subscriptions
    set user_id = null,
        status = case
          when status in ('active', 'payment_recovery', 'cancel_scheduled') then 'canceled'
          else status
        end,
        cancel_at_period_end = true,
        canceled_at = coalesce(canceled_at, pg_catalog.now())
    where account_id = new.id;

    update public.community_pass_purchases
    set user_id = null
    where account_id = new.id;

    update public.community_pass_entitlements
    set user_id = null,
        state = case
          when state in ('trial_active', 'monthly_subscription_active', 'prepaid_term_active', 'payment_recovery', 'cancel_scheduled')
            then 'revoked_account_deleted'
          else state
        end,
        ended_at = case
          when state in ('trial_active', 'monthly_subscription_active', 'prepaid_term_active', 'payment_recovery', 'cancel_scheduled')
            then coalesce(ended_at, pg_catalog.now())
          else ended_at
        end
    where account_id = new.id;

    update public.community_pass_acceptances
    set user_id = null,
        account_reference_hash = new.account_reference_hash,
        redacted_at = coalesce(redacted_at, pg_catalog.now())
    where account_id = new.id
      and user_id is not null;

    update public.community_pass_events
    set user_id = null
    where account_id = new.id
      and user_id is not null;
  end if;

  return null;
end;
$function$;

revoke all on function public.cascade_community_pass_account_unlink() from public;
revoke all on function public.cascade_community_pass_account_unlink() from anon;
revoke all on function public.cascade_community_pass_account_unlink() from authenticated;

drop trigger if exists community_pass_accounts_unlink_cascade on public.community_pass_accounts;
create trigger community_pass_accounts_unlink_cascade
after update of user_id on public.community_pass_accounts
for each row execute function public.cascade_community_pass_account_unlink();

-- Minimal customer-facing status. No Stripe IDs, provider metadata, internal
-- notes, other users, or raw event data are exposed.
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
  select
    a.status as account_status,
    e.state as entitlement_state,
    e.source_type,
    case
      when e.source_type = 'free_trial' then 'community_pass_free_trial_v1'
      when e.source_type = 'monthly_subscription' then 'community_pass_monthly_slider_v1'
      when e.source_type = 'prepaid_purchase' then p.plan_code
      else null
    end as plan_code,
    case
      when e.source_type = 'monthly_subscription' then s.selected_amount_cents
      when e.source_type = 'prepaid_purchase' then p.amount_cents
      else null
    end as amount_cents,
    case
      when e.source_type = 'monthly_subscription' then s.currency
      when e.source_type = 'prepaid_purchase' then p.currency
      else null
    end as currency,
    coalesce(e.active_start_at, e.trial_start_at) as valid_from,
    coalesce(e.retained_current_month_end_at, e.active_end_at, e.trial_end_at) as valid_until,
    (e.source_type = 'monthly_subscription') as renews_monthly,
    coalesce(s.cancel_at_period_end, false) as cancel_at_period_end,
    s.recovery_deadline_at as payment_recovery_deadline,
    e.benefit_version,
    e.offer_version
  from public.community_pass_accounts a
  left join lateral (
    select ce.*
    from public.community_pass_entitlements ce
    where ce.account_id = a.id
      and ce.user_id = auth.uid()
    order by
      case ce.state
        when 'trial_active' then 1
        when 'monthly_subscription_active' then 1
        when 'prepaid_term_active' then 1
        when 'payment_recovery' then 2
        when 'activation_available' then 3
        when 'invited' then 4
        when 'reserved' then 5
        else 6
      end,
      ce.updated_at desc,
      ce.created_at desc
    limit 1
  ) e on true
  left join public.community_pass_subscriptions s on s.id = e.subscription_id
  left join public.community_pass_purchases p on p.id = e.purchase_id
  where a.user_id = auth.uid()
    and a.status <> 'deleted'
  limit 1;
$function$;

revoke all on function public.get_my_community_pass_status() from public;
revoke all on function public.get_my_community_pass_status() from anon;
revoke all on function public.get_my_community_pass_status() from authenticated;
grant execute on function public.get_my_community_pass_status() to authenticated;

-- Server-only authorization helper. HEHA Local must consume a separately
-- authenticated server-to-server Edge interface, not call this from a browser.
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
  select exists (
    select 1
    from public.community_pass_entitlements e
    join public.community_pass_accounts a on a.id = e.account_id
    where e.user_id = p_user_id
      and a.user_id = p_user_id
      and a.status <> 'deleted'
      and e.state in ('trial_active', 'monthly_subscription_active', 'prepaid_term_active')
      and coalesce(e.active_start_at, e.trial_start_at, '-infinity'::timestamptz) <= p_at_time
      and coalesce(e.retained_current_month_end_at, e.active_end_at, e.trial_end_at, 'infinity'::timestamptz) > p_at_time
  );
$function$;

revoke all on function public.is_community_pass_active(uuid, timestamptz) from public;
revoke all on function public.is_community_pass_active(uuid, timestamptz) from anon;
revoke all on function public.is_community_pass_active(uuid, timestamptz) from authenticated;
grant execute on function public.is_community_pass_active(uuid, timestamptz) to service_role;

-- Member-triggered activation is still server-authoritative: no arguments,
-- auth.uid() binding, row locks, invitation-window checks, active-entitlement
-- uniqueness, and an append-only idempotency event.
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
  v_account public.community_pass_accounts%rowtype;
  v_entitlement public.community_pass_entitlements%rowtype;
  v_now timestamptz := pg_catalog.now();
begin
  if v_user_id is null then
    raise exception 'HEHA_COMMUNITY_PASS_AUTH_REQUIRED'
      using errcode = '42501';
  end if;

  select * into v_account
  from public.community_pass_accounts
  where user_id = v_user_id
    and status <> 'deleted'
  for update;

  if not found or v_account.trial_used_at is not null then
    raise exception 'HEHA_COMMUNITY_PASS_TRIAL_NOT_AVAILABLE'
      using errcode = 'P0001';
  end if;

  select * into v_entitlement
  from public.community_pass_entitlements
  where account_id = v_account.id
    and user_id = v_user_id
    and source_type = 'free_trial'
    and state in ('invited', 'activation_available')
    and invitation_sent_at is not null
    and invitation_expires_at is not null
    and invitation_expires_at >= v_now
  order by invitation_sent_at desc
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
      and e.state in ('trial_active', 'monthly_subscription_active', 'prepaid_term_active')
  ) then
    raise exception 'HEHA_COMMUNITY_PASS_ACTIVE_ENTITLEMENT_EXISTS'
      using errcode = 'P0001';
  end if;

  update public.community_pass_entitlements
  set state = 'trial_active',
      trial_start_at = v_now,
      trial_end_at = v_now + interval '30 days',
      active_start_at = v_now,
      active_end_at = v_now + interval '30 days'
  where id = v_entitlement.id
  returning * into v_entitlement;

  update public.community_pass_accounts
  set status = 'trial_active',
      trial_used_at = v_now
  where id = v_account.id;

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
    v_user_id::text,
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
  ) on conflict (environment, idempotency_key) where idempotency_key is not null do nothing;

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

-- No direct customer access to canonical financial/entitlement/audit tables.
-- Customer reads and actions use the minimal, auth-bound RPCs above.
do $privileges$
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
    execute pg_catalog.format('grant all on table public.%I to service_role', v_table);
  end loop;
end;
$privileges$;

comment on table public.community_pass_accounts is
  'Canonical HEHA Community Pass account-level state; no browser writes or direct reads.';
comment on table public.community_pass_subscriptions is
  'Recurring $2-$100/month Community Pass contracts; provider IDs remain server-only.';
comment on table public.community_pass_purchases is
  'One-time six- and twelve-month prepaid Community Pass purchases and refundable liability.';
comment on table public.community_pass_entitlements is
  'Canonical access periods for free trial, recurring monthly, and prepaid terms.';
comment on table public.community_pass_acceptances is
  'Versioned clickwrap evidence; immutable except controlled privacy redaction.';
comment on table public.community_pass_events is
  'Append-only Community Pass lifecycle and human/system/provider audit trail.';
comment on table public.community_pass_stripe_event_inbox is
  'Normalized, retry-safe Stripe event inbox; no raw webhook payload retention.';

commit;
