-- Exact-head proof for Community Pass Package A security hardening.
-- Run only after the complete Package A migration chain on a disposable database.

begin;

create temporary table community_pass_security_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;

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
      raise exception '% expected SQLSTATE %, got %: %',
        p_label, p_expected_state, sqlstate, sqlerrm;
    end if;

    insert into pg_temp.community_pass_security_results(label, ok, detail)
    values (p_label, true, 'denied with SQLSTATE ' || p_expected_state)
    on conflict (label) do update
      set ok = excluded.ok,
          detail = excluded.detail;
end;
$function$;

-- Environment binding, one-time trial, customer actor minimization, and unlink audit.
do $trial_environment_and_deletion$
declare
  v_user_a constant uuid := '00000000-0000-0000-0000-0000000000a1';
  v_account_a uuid;
  v_entitlement_a uuid;
  v_activation record;
  v_status_count integer;
  v_trial_event record;
  v_legacy_actor_event uuid;
  v_unlink_event record;
begin
  if pg_catalog.current_setting('app.community_pass_environment', true) <> 'test' then
    raise exception 'Disposable proof database must be configured for test environment';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'public.community_pass_request_role()',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not execute the trusted-role helper';
  end if;

  perform pg_temp.set_auth_context('service_role', v_user_a);

  insert into public.community_pass_accounts (
    user_id,
    status,
    offer_version,
    benefit_version,
    policy_bundle_version
  ) values (
    v_user_a,
    'invited',
    'founding-v1',
    'beta-v1',
    'policy-v1'
  ) returning id into v_account_a;

  insert into public.community_pass_entitlements (
    account_id,
    user_id,
    source_type,
    state,
    environment,
    invitation_sent_at,
    invitation_expires_at,
    offer_version,
    benefit_version,
    policy_bundle_version
  ) values (
    v_account_a,
    v_user_a,
    'free_trial',
    'activation_available',
    'test',
    pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '10 days',
    'founding-v1',
    'beta-v1',
    'policy-v1'
  ) returning id into v_entitlement_a;

  perform pg_temp.set_auth_context('authenticated', v_user_a);
  select * into v_activation from public.start_my_community_pass_trial();

  if v_activation.state <> 'trial_active'
     or v_activation.trial_end_at - v_activation.trial_start_at <> interval '30 days' then
    raise exception 'Environment-bound trial activation is incorrect';
  end if;

  perform pg_temp.set_auth_context('service_role', v_user_a);
  if not public.is_community_pass_active(v_user_a, pg_catalog.now()) then
    raise exception 'Test entitlement was not authorized in the configured test environment';
  end if;

  select ce.user_id, ce.actor_reference
  into v_trial_event
  from public.community_pass_events ce
  where ce.account_id = v_account_a
    and ce.event_type = 'trial_activated';

  if v_trial_event.user_id <> v_user_a or v_trial_event.actor_reference is not null then
    raise exception 'Trial event retained a duplicate customer actor identifier';
  end if;

  perform pg_catalog.set_config('app.community_pass_environment', 'live', true);

  if public.is_community_pass_active(v_user_a, pg_catalog.now()) then
    raise exception 'Test entitlement crossed into the live environment';
  end if;

  perform pg_temp.set_auth_context('authenticated', v_user_a);
  select count(*) into v_status_count
  from public.get_my_community_pass_status();

  if v_status_count <> 0 then
    raise exception 'Test customer status crossed into the live environment';
  end if;

  perform pg_catalog.set_config('app.community_pass_environment', 'test', true);
  perform pg_temp.set_auth_context('service_role', v_user_a);

  perform pg_temp.expect_sqlstate(
    'trial-used marker cannot be cleared',
    '42501',
    pg_catalog.format(
      'update public.community_pass_accounts set trial_used_at = null where id = %L',
      v_account_a
    )
  );

  perform pg_temp.expect_sqlstate(
    'trial-used marker cannot be rewritten',
    '42501',
    pg_catalog.format(
      'update public.community_pass_accounts set trial_used_at = trial_used_at + interval ''1 second'' where id = %L',
      v_account_a
    )
  );

  -- Simulate a pre-hardening customer event that duplicated the Auth UUID in
  -- actor_reference. Unlink must clear both direct customer links.
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
    after_state
  ) values (
    v_account_a,
    v_user_a,
    'entitlement',
    v_entitlement_a,
    'legacy_customer_reference_fixture',
    'customer',
    v_user_a::text,
    'proof_fixture',
    'legacy-customer-actor-proof',
    'test',
    'trial_active',
    'trial_active'
  ) returning id into v_legacy_actor_event;

  update public.community_pass_accounts
  set user_id = null
  where id = v_account_a;

  select ce.user_id, ce.actor_reference
  into v_trial_event
  from public.community_pass_events ce
  where ce.id = v_legacy_actor_event;

  if v_trial_event.user_id is not null or v_trial_event.actor_reference is not null then
    raise exception 'Account unlink retained a direct customer event identifier';
  end if;

  select ce.user_id, ce.actor_reference, ce.before_state, ce.after_state, ce.event_data
  into v_unlink_event
  from public.community_pass_events ce
  where ce.account_id = v_account_a
    and ce.event_type = 'account_unlinked'
    and ce.environment = 'test';

  if v_unlink_event.user_id is not null
     or v_unlink_event.actor_reference <> 'auth_account_unlink'
     or v_unlink_event.before_state <> 'trial_active'
     or v_unlink_event.after_state <> 'deleted' then
    raise exception 'Privacy-minimized account-unlink audit event is missing or incorrect';
  end if;

  if public.is_community_pass_active(v_user_a, pg_catalog.now()) then
    raise exception 'Deleted account remained benefit-authorized';
  end if;

  perform pg_temp.set_auth_context('authenticated', v_user_a);
  select count(*) into v_status_count
  from public.get_my_community_pass_status();

  if v_status_count <> 0 then
    raise exception 'Deleted account still returned customer status';
  end if;

  insert into pg_temp.community_pass_security_results(label, ok, detail)
  values (
    'environment, trial and deletion hardening',
    true,
    'server environment binding, monotonic trial use, minimized customer actor data, local revocation and unlink audit passed'
  );
end;
$trial_environment_and_deletion$;

-- Exact prepaid acceptance amounts.
do $acceptance_amounts$
declare
  v_user_b constant uuid := '00000000-0000-0000-0000-0000000000b2';
  v_account_b uuid;
begin
  perform pg_temp.set_auth_context('service_role', v_user_b);

  insert into public.community_pass_accounts (
    user_id,
    status,
    offer_version,
    benefit_version,
    policy_bundle_version
  ) values (
    v_user_b,
    'payment_recovery',
    'founding-v1',
    'beta-v1',
    'policy-v1'
  ) returning id into v_account_b;

  perform pg_temp.expect_sqlstate(
    'six-month acceptance requires exact amount',
    '23514',
    pg_catalog.format(
      $sql$
      insert into public.community_pass_acceptances (
        account_id, user_id, plan_code, selected_amount_cents,
        offer_version, benefit_version, terms_version, privacy_version,
        recurring_billing_version, cancellation_policy_version,
        refund_policy_version, disclosure_text_hash, app_surface,
        environment, server_request_id
      ) values (
        %L, %L, 'community_pass_6_month_prepaid_v1', 1499,
        'founding-v1', 'beta-v1', 'terms-v1', 'privacy-v1',
        null, 'cancel-v1', 'refund-v1', 'hash-6-bad',
        'heha-swipe', 'test', 'accept-6-bad'
      )
      $sql$,
      v_account_b,
      v_user_b
    )
  );

  insert into public.community_pass_acceptances (
    account_id, user_id, plan_code, selected_amount_cents,
    offer_version, benefit_version, terms_version, privacy_version,
    recurring_billing_version, cancellation_policy_version,
    refund_policy_version, disclosure_text_hash, app_surface,
    environment, server_request_id
  ) values (
    v_account_b, v_user_b, 'community_pass_6_month_prepaid_v1', 1500,
    'founding-v1', 'beta-v1', 'terms-v1', 'privacy-v1',
    null, 'cancel-v1', 'refund-v1', 'hash-6-good',
    'heha-swipe', 'test', 'accept-6-good'
  );

  perform pg_temp.expect_sqlstate(
    'twelve-month acceptance requires exact amount',
    '23514',
    pg_catalog.format(
      $sql$
      insert into public.community_pass_acceptances (
        account_id, user_id, plan_code, selected_amount_cents,
        offer_version, benefit_version, terms_version, privacy_version,
        recurring_billing_version, cancellation_policy_version,
        refund_policy_version, disclosure_text_hash, app_surface,
        environment, server_request_id
      ) values (
        %L, %L, 'community_pass_12_month_prepaid_v1', 2501,
        'founding-v1', 'beta-v1', 'terms-v1', 'privacy-v1',
        null, 'cancel-v1', 'refund-v1', 'hash-12-bad',
        'heha-swipe', 'test', 'accept-12-bad'
      )
      $sql$,
      v_account_b,
      v_user_b
    )
  );

  insert into public.community_pass_acceptances (
    account_id, user_id, plan_code, selected_amount_cents,
    offer_version, benefit_version, terms_version, privacy_version,
    recurring_billing_version, cancellation_policy_version,
    refund_policy_version, disclosure_text_hash, app_surface,
    environment, server_request_id
  ) values (
    v_account_b, v_user_b, 'community_pass_12_month_prepaid_v1', 2500,
    'founding-v1', 'beta-v1', 'terms-v1', 'privacy-v1',
    null, 'cancel-v1', 'refund-v1', 'hash-12-good',
    'heha-swipe', 'test', 'accept-12-good'
  );

  insert into pg_temp.community_pass_security_results(label, ok, detail)
  values (
    'exact prepaid acceptance amounts',
    true,
    '$15 six-month and $25 twelve-month clickwrap amounts are exact and fail closed'
  );
end;
$acceptance_amounts$;

-- Recovery/open-contract uniqueness and trial bypass prevention.
do $open_contract_uniqueness$
declare
  v_user_b constant uuid := '00000000-0000-0000-0000-0000000000b2';
  v_account_b uuid;
  v_subscription_b uuid;
begin
  perform pg_catalog.set_config('app.community_pass_environment', 'test', true);
  perform pg_temp.set_auth_context('service_role', v_user_b);

  select id into v_account_b
  from public.community_pass_accounts
  where user_id = v_user_b;

  insert into public.community_pass_entitlements (
    account_id, user_id, source_type, state, environment,
    invitation_sent_at, invitation_expires_at,
    offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_b, v_user_b, 'free_trial', 'activation_available', 'test',
    pg_catalog.now() - interval '1 day', pg_catalog.now() + interval '10 days',
    'founding-v1', 'beta-v1', 'policy-v1'
  );

  insert into public.community_pass_subscriptions (
    account_id, user_id, stripe_customer_id, stripe_subscription_id,
    stripe_price_id, selected_amount_cents, quantity, currency,
    environment, status, current_period_start, current_period_end,
    recovery_started_at, recovery_deadline_at,
    offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_b, v_user_b, 'cus-recovery-proof', 'sub-recovery-proof',
    'price-recovery-proof', 500, 5, 'usd',
    'test', 'payment_recovery', pg_catalog.now() - interval '1 month',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now() + interval '7 days',
    'founding-v1', 'beta-v1', 'policy-v1'
  ) returning id into v_subscription_b;

  insert into public.community_pass_entitlements (
    account_id, user_id, source_type, subscription_id, state,
    environment, active_start_at, active_end_at,
    offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_b, v_user_b, 'monthly_subscription', v_subscription_b,
    'payment_recovery', 'test', pg_catalog.now() - interval '1 month',
    pg_catalog.now(), 'founding-v1', 'beta-v1', 'policy-v1'
  );

  perform pg_temp.expect_sqlstate(
    'open entitlement uniqueness blocks a second active entitlement',
    '23505',
    pg_catalog.format(
      $sql$
      insert into public.community_pass_entitlements (
        account_id, user_id, source_type, state, environment,
        trial_start_at, trial_end_at, active_start_at, active_end_at,
        offer_version, benefit_version, policy_bundle_version
      ) values (
        %L, %L, 'free_trial', 'trial_active', 'test',
        now(), now() + interval '30 days', now(), now() + interval '30 days',
        'founding-v1', 'beta-v1', 'policy-v1'
      )
      $sql$,
      v_account_b,
      v_user_b
    )
  );

  perform pg_temp.set_auth_context('authenticated', v_user_b);
  perform pg_temp.expect_sqlstate(
    'payment recovery blocks free-trial bypass',
    'P0001',
    'select * from public.start_my_community_pass_trial()'
  );

  insert into pg_temp.community_pass_security_results(label, ok, detail)
  values (
    'open contract uniqueness',
    true,
    'payment recovery cannot coexist with or be bypassed by a second active trial'
  );
end;
$open_contract_uniqueness$;

-- Final sanity.
do $final$
declare
  v_total integer;
begin
  select count(*) into v_total
  from pg_temp.community_pass_security_results
  where ok;

  if v_total < 7 then
    raise exception 'Security hardening proof expected at least 7 passing result rows, got %', v_total;
  end if;
end;
$final$;

select label, ok, detail
from pg_temp.community_pass_security_results
order by label;

rollback;
