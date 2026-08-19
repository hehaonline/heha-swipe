-- Focused proof for Package A account-unlink/deletion fallback.
--
-- Run after the full Package A migration chain on a disposable database with
-- the fixed synthetic Auth user seeded by community_pass_minimal_baseline.sql.
-- The test proves local entitlement revocation without fabricating Stripe
-- cancellation, plus financial-liability and immutable-evidence survival.

begin;

create or replace function pg_temp.set_auth_context(p_role text, p_sub uuid default null)
returns void
language plpgsql
as $function$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', v_sub, 'role', p_role)::text,
    true
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', v_sub, true);
  perform pg_catalog.set_config('request.jwt.claim.role', p_role, true);
end;
$function$;

do $proof$
declare
  v_user constant uuid := '00000000-0000-0000-0000-0000000000a1';
  v_account uuid;
  v_entitlement uuid;
  v_acceptance uuid;
  v_event uuid;
  v_purchase uuid;
  v_reference text;
  v_status_count integer;
  v_subscription record;
  v_purchase_row record;
  v_entitlement_row record;
  v_acceptance_row record;
  v_event_row record;
begin
  if not exists (select 1 from auth.users where id = v_user) then
    raise exception 'Synthetic Auth user is missing';
  end if;

  perform pg_temp.set_auth_context('service_role', v_user);

  insert into public.community_pass_accounts (
    user_id,
    status,
    trial_used_at,
    offer_version,
    benefit_version,
    policy_bundle_version
  ) values (
    v_user,
    'trial_active',
    pg_catalog.now(),
    'founding-v1',
    'beta-v1',
    'policy-v1'
  ) returning id into v_account;

  insert into public.community_pass_entitlements (
    account_id,
    user_id,
    source_type,
    state,
    environment,
    trial_start_at,
    trial_end_at,
    active_start_at,
    active_end_at,
    offer_version,
    benefit_version,
    policy_bundle_version
  ) values (
    v_account,
    v_user,
    'free_trial',
    'trial_active',
    'test',
    pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '29 days',
    pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '29 days',
    'founding-v1',
    'beta-v1',
    'policy-v1'
  ) returning id into v_entitlement;

  insert into public.community_pass_subscriptions (
    account_id,
    user_id,
    stripe_customer_id,
    stripe_subscription_id,
    stripe_price_id,
    latest_invoice_id,
    selected_amount_cents,
    quantity,
    currency,
    environment,
    status,
    current_period_start,
    current_period_end,
    cancel_at_period_end,
    offer_version,
    benefit_version,
    policy_bundle_version,
    reconciliation_state,
    metadata
  ) values (
    v_account,
    v_user,
    'cus-proof-delete',
    'sub-proof-delete',
    'price-proof-monthly',
    'in-proof-delete',
    500,
    5,
    'usd',
    'test',
    'active',
    pg_catalog.now(),
    pg_catalog.now() + interval '1 month',
    false,
    'founding-v1',
    'beta-v1',
    'policy-v1',
    'matched',
    pg_catalog.jsonb_build_object('existing_fact', 'preserve')
  );

  insert into public.community_pass_purchases (
    account_id,
    user_id,
    plan_code,
    term_months,
    amount_cents,
    currency,
    environment,
    stripe_checkout_session_id,
    stripe_payment_intent_id,
    stripe_charge_id,
    stripe_customer_id,
    payment_state,
    gross_cents,
    refunded_cents,
    refundable_unearned_cents,
    earned_cents,
    offer_version,
    benefit_version,
    policy_bundle_version,
    reconciliation_state
  ) values (
    v_account,
    v_user,
    'community_pass_6_month_prepaid_v1',
    6,
    1500,
    'usd',
    'test',
    'cs-proof-delete',
    'pi-proof-delete',
    'ch-proof-delete',
    'cus-proof-delete',
    'reserved_paid',
    1500,
    0,
    1500,
    0,
    'founding-v1',
    'beta-v1',
    'policy-v1',
    'matched'
  ) returning id into v_purchase;

  insert into public.community_pass_acceptances (
    account_id,
    user_id,
    plan_code,
    selected_amount_cents,
    offer_version,
    benefit_version,
    terms_version,
    privacy_version,
    recurring_billing_version,
    cancellation_policy_version,
    refund_policy_version,
    disclosure_text_hash,
    app_surface,
    environment,
    server_request_id
  ) values (
    v_account,
    v_user,
    'community_pass_monthly_slider_v1',
    500,
    'founding-v1',
    'beta-v1',
    'terms-v1',
    'privacy-v1',
    'recurring-v1',
    'cancel-v1',
    'refund-v1',
    'disclosure-hash-delete-proof',
    'heha-swipe',
    'test',
    'accept-delete-proof'
  ) returning id into v_acceptance;

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
    event_data
  ) values (
    v_account,
    v_user,
    'entitlement',
    v_entitlement,
    'trial_activated',
    'customer',
    v_user::text,
    'member_started',
    'delete-proof-event',
    'test',
    'activation_available',
    'trial_active',
    pg_catalog.jsonb_build_object('immutable_fact', 'preserve')
  ) returning id into v_event;

  update public.community_pass_accounts a
  set user_id = null
  where a.id = v_account;

  select a.account_reference_hash
  into v_reference
  from public.community_pass_accounts a
  where a.id = v_account
    and a.status = 'deleted'
    and a.deleted_at is not null
    and a.account_reference_hash is not null
    and a.account_reference_hash_version = 'random_tombstone_v1';

  if v_reference is null or char_length(v_reference) < 24 then
    raise exception 'Account unlink did not create an opaque random tombstone';
  end if;

  select
    s.user_id,
    s.status,
    s.reconciliation_state,
    s.cancel_at_period_end,
    s.canceled_at,
    s.stripe_customer_id,
    s.stripe_subscription_id,
    s.latest_invoice_id,
    s.metadata
  into v_subscription
  from public.community_pass_subscriptions s
  where s.account_id = v_account;

  if v_subscription.user_id is not null
     or v_subscription.status <> 'reconciliation_exception'
     or v_subscription.reconciliation_state <> 'exception'
     or v_subscription.cancel_at_period_end
     or v_subscription.canceled_at is not null
     or v_subscription.stripe_customer_id <> 'cus-proof-delete'
     or v_subscription.stripe_subscription_id <> 'sub-proof-delete'
     or v_subscription.latest_invoice_id <> 'in-proof-delete'
     or v_subscription.metadata ->> 'existing_fact' <> 'preserve'
     or v_subscription.metadata ->> 'account_unlink_reason' <> 'provider_reconciliation_required' then
    raise exception 'Account unlink fabricated cancellation, lost provider identity, or failed to create reconciliation evidence';
  end if;

  select p.*
  into v_purchase_row
  from public.community_pass_purchases p
  where p.id = v_purchase;

  if v_purchase_row.user_id is not null
     or v_purchase_row.payment_state <> 'reserved_paid'
     or v_purchase_row.gross_cents <> 1500
     or v_purchase_row.refundable_unearned_cents <> 1500
     or v_purchase_row.stripe_payment_intent_id <> 'pi-proof-delete'
     or v_purchase_row.stripe_charge_id <> 'ch-proof-delete' then
    raise exception 'Account unlink erased or reclassified prepaid financial liability';
  end if;

  select e.*
  into v_entitlement_row
  from public.community_pass_entitlements e
  where e.id = v_entitlement;

  if v_entitlement_row.user_id is not null
     or v_entitlement_row.state <> 'revoked_account_deleted'
     or v_entitlement_row.ended_at is null then
    raise exception 'Account unlink did not revoke active entitlement';
  end if;

  select ca.*
  into v_acceptance_row
  from public.community_pass_acceptances ca
  where ca.id = v_acceptance;

  if v_acceptance_row.user_id is not null
     or v_acceptance_row.account_reference_hash <> v_reference
     or v_acceptance_row.redacted_at is null
     or v_acceptance_row.disclosure_text_hash <> 'disclosure-hash-delete-proof'
     or v_acceptance_row.terms_version <> 'terms-v1' then
    raise exception 'Account unlink erased or rewrote policy acceptance evidence';
  end if;

  select ce.*
  into v_event_row
  from public.community_pass_events ce
  where ce.id = v_event;

  if v_event_row.user_id is not null
     or v_event_row.event_type <> 'trial_activated'
     or v_event_row.before_state <> 'activation_available'
     or v_event_row.after_state <> 'trial_active'
     or v_event_row.event_data ->> 'immutable_fact' <> 'preserve' then
    raise exception 'Account unlink erased or rewrote lifecycle audit facts';
  end if;

  perform pg_temp.set_auth_context('authenticated', v_user);
  select count(*)
  into v_status_count
  from public.get_my_community_pass_status();

  if v_status_count <> 0 then
    raise exception 'Deleted account still receives customer-facing Community Pass status';
  end if;

  perform pg_temp.set_auth_context('service_role', v_user);
  if public.is_community_pass_active(v_user, pg_catalog.now()) then
    raise exception 'Deleted account remains locally benefit-authorized';
  end if;
end;
$proof$;

select
  'account unlink fail-safe' as label,
  true as ok,
  'opaque tombstone, local revocation, open provider reconciliation, prepaid liability survival and immutable-evidence redaction passed' as detail;

rollback;
