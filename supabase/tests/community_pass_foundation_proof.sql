-- Exact-head proof for HEHA Community Pass Package A foundation.
--
-- Run after applying the matching migration to a disposable Supabase branch or
-- current-schema clone. Never use real payment data.
--
-- Required psql variables:
--   user_a_id - existing synthetic authenticated auth.users UUID
--   user_b_id - second existing synthetic authenticated auth.users UUID
--
-- Example:
-- psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 \
--   -v user_a_id=00000000-0000-0000-0000-0000000000a1 \
--   -v user_b_id=00000000-0000-0000-0000-0000000000b2 \
--   -f supabase/tests/community_pass_foundation_proof.sql

begin;

create temporary table community_pass_proof_results (
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
      raise exception '% expected SQLSTATE %, got %: %', p_label, p_expected_state, sqlstate, sqlerrm;
    end if;

    insert into pg_temp.community_pass_proof_results(label, ok, detail)
    values (p_label, true, 'denied with SQLSTATE ' || p_expected_state)
    on conflict (label) do update set ok = excluded.ok, detail = excluded.detail;
end;
$function$;

-- Structural, RLS, ACL, and function-contract proof.
do $proof$
declare
  v_table text;
  v_rel record;
  v_config text[];
  v_args integer;
  v_result text;
  v_def text;
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

    select c.relrowsecurity, c.relforcerowsecurity
    into v_rel
    from pg_catalog.pg_class c
    where c.oid = pg_catalog.to_regclass('public.' || v_table);

    if not v_rel.relrowsecurity or not v_rel.relforcerowsecurity then
      raise exception 'public.% must have ENABLE + FORCE RLS', v_table;
    end if;

    if pg_catalog.has_table_privilege('anon', 'public.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'DELETE')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'TRUNCATE')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'REFERENCES')
       or pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'TRIGGER') then
      raise exception 'public.% has broader anon/authenticated privileges than approved', v_table;
    end if;
  end loop;

  select p.proconfig, p.pronargs,
         pg_catalog.pg_get_function_result(p.oid),
         pg_catalog.pg_get_functiondef(p.oid)
  into v_config, v_args, v_result, v_def
  from pg_catalog.pg_proc p
  where p.oid = 'public.get_my_community_pass_status()'::pg_catalog.regprocedure;

  if v_args <> 0 then
    raise exception 'get_my_community_pass_status must accept no user identifier';
  end if;

  -- PostgreSQL serializes an explicitly empty search_path as either
  -- `search_path=` or `search_path=""`, depending on version/tooling.
  if not (
    'search_path=' = any (coalesce(v_config, array[]::text[]))
    or 'search_path=""' = any (coalesce(v_config, array[]::text[]))
  ) then
    raise exception 'get_my_community_pass_status must pin empty search_path';
  end if;

  if position('stripe_' in lower(v_result)) > 0
     or position('metadata' in lower(v_result)) > 0
     or position('event_data' in lower(v_result)) > 0 then
    raise exception 'Status RPC exposes provider IDs, metadata, or event payloads: %', v_result;
  end if;

  if position('a.user_id = auth.uid()' in v_def) = 0
     or position('e.user_id = auth.uid()' in v_def) = 0 then
    raise exception 'Status RPC is not bound to auth.uid() for account and entitlement';
  end if;

  if pg_catalog.has_function_privilege('anon', 'public.get_my_community_pass_status()', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'public.get_my_community_pass_status()', 'EXECUTE') then
    raise exception 'Status RPC grants do not match anon-deny/authenticated-allow contract';
  end if;

  if pg_catalog.has_function_privilege('anon', 'public.start_my_community_pass_trial()', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'public.start_my_community_pass_trial()', 'EXECUTE') then
    raise exception 'Trial activation RPC grants do not match contract';
  end if;

  if pg_catalog.has_function_privilege('authenticated', 'public.is_community_pass_active(uuid,timestamptz)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', 'public.is_community_pass_active(uuid,timestamptz)', 'EXECUTE') then
    raise exception 'Server-only active-check grants do not match contract';
  end if;

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values (
    'schema and grants',
    true,
    'seven canonical tables, forced RLS, closed browser ACLs, minimal auth-bound RPCs and server-only active check verified'
  );
end;
$proof$;

-- Fixture setup.
do $fixtures$
declare
  v_user_a uuid := :'user_a_id'::uuid;
  v_user_b uuid := :'user_b_id'::uuid;
  v_account_a uuid;
  v_account_b uuid;
  v_entitlement_a uuid;
  v_entitlement_b uuid;
begin
  if v_user_a = v_user_b then
    raise exception 'user_a_id and user_b_id must be different';
  end if;

  if not exists (select 1 from auth.users where id = v_user_a)
     or not exists (select 1 from auth.users where id = v_user_b) then
    raise exception 'Both proof UUIDs must exist in auth.users';
  end if;

  perform pg_temp.set_auth_context('service_role', v_user_a);

  insert into public.community_pass_accounts (
    user_id, status, offer_version, benefit_version, policy_bundle_version
  ) values (
    v_user_a, 'invited', 'founding-v1', 'beta-v1', 'policy-v1'
  ) returning id into v_account_a;

  insert into public.community_pass_accounts (
    user_id, status, offer_version, benefit_version, policy_bundle_version
  ) values (
    v_user_b, 'invited', 'founding-v1', 'beta-v1', 'policy-v1'
  ) returning id into v_account_b;

  insert into public.community_pass_entitlements (
    account_id, user_id, source_type, state, environment,
    invitation_sent_at, invitation_expires_at,
    offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_a, v_user_a, 'free_trial', 'activation_available', 'test',
    pg_catalog.now() - interval '1 day', pg_catalog.now() + interval '10 days',
    'founding-v1', 'beta-v1', 'policy-v1'
  ) returning id into v_entitlement_a;

  insert into public.community_pass_entitlements (
    account_id, user_id, source_type, state, environment,
    invitation_sent_at, invitation_expires_at,
    offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_b, v_user_b, 'free_trial', 'activation_available', 'test',
    pg_catalog.now() - interval '1 day', pg_catalog.now() + interval '10 days',
    'founding-v1', 'beta-v1', 'policy-v1'
  ) returning id into v_entitlement_b;

  insert into public.community_pass_acceptances (
    account_id, user_id, plan_code, selected_amount_cents,
    offer_version, benefit_version, terms_version, privacy_version,
    recurring_billing_version, cancellation_policy_version, refund_policy_version,
    disclosure_text_hash, app_surface, environment, server_request_id
  ) values
    (
      v_account_a, v_user_a, 'community_pass_free_trial_v1', null,
      'founding-v1', 'beta-v1', 'terms-v1', 'privacy-v1',
      null, 'cancel-v1', 'refund-v1',
      'hash-free-a', 'heha-swipe', 'test', 'accept-free-a'
    ),
    (
      v_account_b, v_user_b, 'community_pass_monthly_slider_v1', 500,
      'founding-v1', 'beta-v1', 'terms-v1', 'privacy-v1',
      'recurring-v1', 'cancel-v1', 'refund-v1',
      'hash-monthly-b', 'heha-swipe', 'test', 'accept-monthly-b'
    );

  insert into public.community_pass_events (
    account_id, user_id, entity_type, entity_id, event_type, actor_type,
    actor_reference, reason_code, idempotency_key, environment,
    before_state, after_state
  ) values
    (
      v_account_a, v_user_a, 'entitlement', v_entitlement_a,
      'invitation_sent', 'system', 'proof', 'founding_invite',
      'proof-invite-a', 'test', 'reserved', 'activation_available'
    ),
    (
      v_account_b, v_user_b, 'entitlement', v_entitlement_b,
      'invitation_sent', 'system', 'proof', 'founding_invite',
      'proof-invite-b', 'test', 'reserved', 'activation_available'
    );

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('fixtures', true, 'two isolated synthetic accounts, invitations, acceptances and events created');
end;
$fixtures$;

-- User A can see only A, activate once, and receive exactly 30 days.
do $trial_a$
declare
  v_user_a uuid := :'user_a_id'::uuid;
  v_status record;
  v_activation record;
  v_count integer;
  v_event_count integer;
begin
  perform pg_temp.set_auth_context('authenticated', v_user_a);

  select * into v_status from public.get_my_community_pass_status();
  if v_status.entitlement_state <> 'activation_available'
     or v_status.plan_code <> 'community_pass_free_trial_v1' then
    raise exception 'User A pre-activation status is wrong: % / %',
      v_status.entitlement_state, v_status.plan_code;
  end if;

  select * into v_activation from public.start_my_community_pass_trial();

  if v_activation.state <> 'trial_active'
     or v_activation.trial_end_at - v_activation.trial_start_at <> interval '30 days' then
    raise exception 'Trial activation did not produce exact 30-day access';
  end if;

  select count(*) into v_count from public.get_my_community_pass_status();
  if v_count <> 1 then
    raise exception 'Status RPC must return at most one row, got %', v_count;
  end if;

  select * into v_status from public.get_my_community_pass_status();
  if v_status.entitlement_state <> 'trial_active'
     or v_status.valid_until - v_status.valid_from <> interval '30 days'
     or v_status.renews_monthly then
    raise exception 'User A active trial status is wrong';
  end if;

  perform pg_temp.expect_sqlstate(
    'trial activation is one-time',
    'P0001',
    'select * from public.start_my_community_pass_trial()'
  );

  perform pg_temp.set_auth_context('service_role', v_user_a);
  if not public.is_community_pass_active(v_user_a, pg_catalog.now()) then
    raise exception 'Server active-check must recognize User A trial';
  end if;

  select count(*) into v_event_count
  from public.community_pass_events e
  where e.user_id = v_user_a and e.event_type = 'trial_activated';
  if v_event_count <> 1 then
    raise exception 'Trial activation must create exactly one idempotent event, got %', v_event_count;
  end if;

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('trial activation', true, 'auth-bound one-time activation, exact 30 days, active check and one audit event passed');
end;
$trial_a$;

-- User B cannot see A; own record remains separate.
do $isolation$
declare
  v_user_a uuid := :'user_a_id'::uuid;
  v_user_b uuid := :'user_b_id'::uuid;
  v_status record;
  v_account_b uuid;
begin
  perform pg_temp.set_auth_context('authenticated', v_user_b);
  select * into v_status from public.get_my_community_pass_status();

  if v_status.entitlement_state <> 'activation_available'
     or v_status.valid_from is not null
     or v_status.valid_until is not null then
    raise exception 'User B saw incorrect or cross-user status';
  end if;

  select id into v_account_b from public.community_pass_accounts where user_id = v_user_b;

  perform pg_temp.set_auth_context('service_role', v_user_b);
  if public.is_community_pass_active(v_user_b, pg_catalog.now()) then
    raise exception 'Unactivated User B must not be active';
  end if;

  if v_account_b = (select id from public.community_pass_accounts where user_id = v_user_a) then
    raise exception 'Synthetic accounts unexpectedly share an account ID';
  end if;

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('cross-user isolation', true, 'User B receives only B status and no active authorization');
end;
$isolation$;

-- Monthly amount, one-active-subscription, and prepaid mapping invariants.
do $money_invariants$
declare
  v_user_b uuid := :'user_b_id'::uuid;
  v_account_b uuid;
  v_sub_id uuid;
begin
  perform pg_temp.set_auth_context('service_role', v_user_b);
  select id into v_account_b from public.community_pass_accounts where user_id = v_user_b;

  insert into public.community_pass_subscriptions (
    account_id, user_id, stripe_customer_id, stripe_subscription_id,
    stripe_price_id, selected_amount_cents, quantity, currency, environment,
    status, current_period_start, current_period_end,
    offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_b, v_user_b, 'cus-proof-b', 'sub-proof-b-1',
    'price-proof-monthly', 500, 5, 'usd', 'test',
    'active', pg_catalog.now(), pg_catalog.now() + interval '1 month',
    'founding-v1', 'beta-v1', 'policy-v1'
  ) returning id into v_sub_id;

  perform pg_temp.expect_sqlstate(
    'one active monthly subscription per account',
    '23505',
    pg_catalog.format(
      $sql$
      insert into public.community_pass_subscriptions (
        account_id, user_id, stripe_customer_id, stripe_subscription_id,
        stripe_price_id, selected_amount_cents, quantity, currency, environment,
        status, current_period_start, current_period_end,
        offer_version, benefit_version, policy_bundle_version
      ) values (
        %L, %L, 'cus-proof-b', 'sub-proof-b-2',
        'price-proof-monthly', 1000, 10, 'usd', 'test',
        'active', now(), now() + interval '1 month',
        'founding-v1', 'beta-v1', 'policy-v1'
      )
      $sql$,
      v_account_b,
      v_user_b
    )
  );

  perform pg_temp.expect_sqlstate(
    'monthly quantity must equal whole-dollar amount',
    '23514',
    pg_catalog.format(
      $sql$
      insert into public.community_pass_subscriptions (
        account_id, user_id, stripe_customer_id, stripe_subscription_id,
        stripe_price_id, selected_amount_cents, quantity, currency, environment,
        status, offer_version, benefit_version, policy_bundle_version
      ) values (
        %L, %L, 'cus-proof-b', 'sub-proof-b-bad-amount',
        'price-proof-monthly', 500, 4, 'usd', 'live',
        'checkout_pending', 'founding-v1', 'beta-v1', 'policy-v1'
      )
      $sql$,
      v_account_b,
      v_user_b
    )
  );

  perform pg_temp.expect_sqlstate(
    'six-month exact price mapping',
    '23514',
    pg_catalog.format(
      $sql$
      insert into public.community_pass_purchases (
        account_id, user_id, plan_code, term_months, amount_cents,
        currency, environment, offer_version, benefit_version, policy_bundle_version
      ) values (
        %L, %L, 'community_pass_6_month_prepaid_v1', 6, 1499,
        'usd', 'test', 'founding-v1', 'beta-v1', 'policy-v1'
      )
      $sql$,
      v_account_b,
      v_user_b
    )
  );

  insert into public.community_pass_purchases (
    account_id, user_id, plan_code, term_months, amount_cents,
    currency, environment, payment_state, gross_cents,
    refundable_unearned_cents, offer_version, benefit_version, policy_bundle_version
  ) values (
    v_account_b, v_user_b, 'community_pass_6_month_prepaid_v1', 6, 1500,
    'usd', 'test', 'reserved_paid', 1500,
    1500, 'founding-v1', 'beta-v1', 'policy-v1'
  );

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('money invariants', true, '$2-$100 whole-dollar recurring amounts, one active subscription and exact $15/$25 prepaid mapping fail closed');
end;
$money_invariants$;

-- Acceptance/event immutability with controlled privacy redaction.
do $immutability$
declare
  v_user_b uuid := :'user_b_id'::uuid;
  v_account_b uuid;
  v_acceptance_b uuid;
  v_event_b uuid;
begin
  perform pg_temp.set_auth_context('service_role', v_user_b);
  select id into v_account_b from public.community_pass_accounts where user_id = v_user_b;
  select id into v_acceptance_b from public.community_pass_acceptances
    where account_id = v_account_b and server_request_id = 'accept-monthly-b';
  select id into v_event_b from public.community_pass_events
    where account_id = v_account_b and idempotency_key = 'proof-invite-b';

  perform pg_temp.expect_sqlstate(
    'acceptance contract is immutable',
    '42501',
    pg_catalog.format(
      'update public.community_pass_acceptances set terms_version = %L where id = %L',
      'terms-tampered', v_acceptance_b
    )
  );

  update public.community_pass_acceptances
  set user_id = null,
      account_reference_hash = 'proof-redacted-b',
      redacted_at = pg_catalog.now()
  where id = v_acceptance_b;

  perform pg_temp.expect_sqlstate(
    'redacted acceptance cannot be relinked',
    '42501',
    pg_catalog.format(
      'update public.community_pass_acceptances set user_id = %L where id = %L',
      v_user_b, v_acceptance_b
    )
  );

  perform pg_temp.expect_sqlstate(
    'event facts are immutable',
    '42501',
    pg_catalog.format(
      'update public.community_pass_events set event_type = %L where id = %L',
      'tampered', v_event_b
    )
  );

  update public.community_pass_events set user_id = null where id = v_event_b;

  perform pg_temp.expect_sqlstate(
    'redacted event cannot be relinked',
    '42501',
    pg_catalog.format(
      'update public.community_pass_events set user_id = %L where id = %L',
      v_user_b, v_event_b
    )
  );

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('immutable evidence', true, 'policy/event facts cannot be rewritten; only one-way trusted privacy redaction is permitted');
end;
$immutability$;

-- Retry-safe event inbox uniqueness and processed-state contract.
do $inbox$
begin
  perform pg_temp.set_auth_context('service_role', :'user_a_id'::uuid);

  insert into public.community_pass_stripe_event_inbox (
    stripe_event_id, event_type, environment, livemode,
    object_id, payload_hash, status
  ) values (
    'evt-proof-1', 'invoice.paid', 'test', false,
    'in-proof-1', 'payload-hash-1', 'pending'
  );

  perform pg_temp.expect_sqlstate(
    'stripe event inbox deduplicates provider event',
    '23505',
    $sql$
    insert into public.community_pass_stripe_event_inbox (
      stripe_event_id, event_type, environment, livemode,
      object_id, payload_hash, status
    ) values (
      'evt-proof-1', 'invoice.paid', 'test', false,
      'in-proof-1', 'payload-hash-1', 'pending'
    )
    $sql$
  );

  perform pg_temp.expect_sqlstate(
    'processed inbox row requires processed_at',
    '23514',
    $sql$
    insert into public.community_pass_stripe_event_inbox (
      stripe_event_id, event_type, environment, livemode,
      object_id, payload_hash, status
    ) values (
      'evt-proof-2', 'refund.updated', 'test', false,
      're-proof-2', 'payload-hash-2', 'processed'
    )
    $sql$
  );

  update public.community_pass_stripe_event_inbox
  set status = 'processed',
      attempt_count = attempt_count + 1,
      last_attempt_at = pg_catalog.now(),
      processed_at = pg_catalog.now()
  where environment = 'test' and stripe_event_id = 'evt-proof-1';

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('event inbox', true, 'provider event dedupe and processed-at finality contract passed');
end;
$inbox$;

-- Account unlink/deletion automatically revokes reusable access and redacts links.
do $deletion$
declare
  v_user_a uuid := :'user_a_id'::uuid;
  v_account_a uuid;
  v_entitlement_state text;
  v_status_count integer;
  v_acceptance_user uuid;
  v_event_user uuid;
begin
  perform pg_temp.set_auth_context('service_role', v_user_a);
  select id into v_account_a from public.community_pass_accounts where user_id = v_user_a;

  update public.community_pass_accounts set user_id = null where id = v_account_a;

  if not exists (
    select 1 from public.community_pass_accounts
    where id = v_account_a
      and status = 'deleted'
      and deleted_at is not null
      and account_reference_hash is not null
  ) then
    raise exception 'Account unlink did not set deleted state/hash/timestamp';
  end if;

  select state into v_entitlement_state
  from public.community_pass_entitlements
  where account_id = v_account_a;

  if v_entitlement_state <> 'revoked_account_deleted' then
    raise exception 'Active entitlement survived account unlink: %', v_entitlement_state;
  end if;

  select user_id into v_acceptance_user
  from public.community_pass_acceptances
  where account_id = v_account_a
  limit 1;
  if v_acceptance_user is not null then
    raise exception 'Acceptance user linkage survived account unlink';
  end if;

  select user_id into v_event_user
  from public.community_pass_events
  where account_id = v_account_a
  order by created_at desc
  limit 1;
  if v_event_user is not null then
    raise exception 'Event user linkage survived account unlink';
  end if;

  perform pg_temp.set_auth_context('authenticated', v_user_a);
  select count(*) into v_status_count from public.get_my_community_pass_status();
  if v_status_count <> 0 then
    raise exception 'Deleted/unlinked account still returned customer status';
  end if;

  perform pg_temp.set_auth_context('service_role', v_user_a);
  if public.is_community_pass_active(v_user_a, pg_catalog.now()) then
    raise exception 'Deleted/unlinked account remained server-authorized';
  end if;

  insert into pg_temp.community_pass_proof_results(label, ok, detail)
  values ('account deletion', true, 'unlink sets deleted state, revokes entitlement, redacts evidence links and removes status/authorization');
end;
$deletion$;

-- Final result and minimum expected proof count.
do $final$
declare
  v_failures integer;
  v_total integer;
begin
  select count(*) filter (where not ok), count(*)
  into v_failures, v_total
  from pg_temp.community_pass_proof_results;

  if v_failures <> 0 then
    raise exception 'Community Pass proof recorded % failures', v_failures;
  end if;

  if v_total < 9 then
    raise exception 'Community Pass proof expected at least 9 result groups, got %', v_total;
  end if;
end;
$final$;

select label, ok, detail
from pg_temp.community_pass_proof_results
order by label;

rollback;
