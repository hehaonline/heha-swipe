-- Proof / regression harness for Launch Security Gate 1A.
--
-- Run AFTER applying 20260707062836_supporter_entitlement_security.sql to a
-- controlled non-production database, or a controlled production SQL session.
--
-- Required psql variable:
--   ordinary_user_id - a real ordinary authenticated user id with a public.profiles row
--
-- Example:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v ordinary_user_id=00000000-0000-0000-0000-000000000001 \
--     -f supabase/tests/supporter_entitlement_security_proof.sql
--
-- All mutation proof steps run inside BEGIN / ROLLBACK.

begin;

create temporary table supporter_security_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;

create or replace function pg_temp.set_auth_context(p_role text, p_sub uuid default null)
returns void
language plpgsql
as $$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', v_sub, 'role', p_role)::text,
    true
  );
  perform set_config('request.jwt.claim.sub', v_sub, true);
  perform set_config('request.jwt.claim.role', p_role, true);
end;
$$;

create or replace function pg_temp.expect_42501(p_label text, p_sql text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise exception '% expected SQLSTATE 42501, but statement succeeded', p_label;
exception
  when insufficient_privilege then
    insert into pg_temp.supporter_security_results(label, ok, detail)
    values (p_label, true, 'denied with SQLSTATE 42501');
end;
$$;

create or replace function pg_temp.public_has_table_privilege(p_relation regclass, p_privilege text)
returns boolean
language sql
as $$
  select exists (
    select 1
    from pg_catalog.pg_class c
    cross join lateral pg_catalog.aclexplode(
      coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))
    ) acl
    where c.oid = p_relation
      and acl.grantee = 0
      and acl.privilege_type = p_privilege
  );
$$;

create or replace function pg_temp.public_has_function_privilege(p_function regprocedure, p_privilege text)
returns boolean
language sql
as $$
  select exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where p.oid = p_function
      and acl.grantee = 0
      and acl.privilege_type = p_privilege
  );
$$;

do $$
declare
  v_config text[];
  v_arg_count integer;
  v_functiondef text;
  v_function_result text;
begin
  if to_regclass('public.my_active_supporter_entitlements') is not null then
    raise exception 'my_active_supporter_entitlements view must be removed; browser reads must use RPC';
  end if;

  select p.proconfig, p.pronargs
  into v_config, v_arg_count
  from pg_catalog.pg_proc p
  where p.oid = 'public.get_my_active_supporter_entitlement()'::regprocedure;

  if v_arg_count <> 0 then
    raise exception 'get_my_active_supporter_entitlement must take no user_id or other arguments';
  end if;

  if not ('search_path=' = any (coalesce(v_config, array[]::text[]))) then
    raise exception 'get_my_active_supporter_entitlement must pin search_path to empty string';
  end if;

  v_function_result := pg_catalog.pg_get_function_result('public.get_my_active_supporter_entitlement()'::regprocedure);
  if v_function_result <> 'TABLE(status text, quantity integer, amount_cents integer)' then
    raise exception 'get_my_active_supporter_entitlement exposes unexpected return shape: %', v_function_result;
  end if;

  v_functiondef := pg_catalog.pg_get_functiondef('public.get_my_active_supporter_entitlement()'::regprocedure);
  if position('auth.uid()' in v_functiondef) = 0
     or position('ss.user_id = auth.uid()' in v_functiondef) = 0 then
    raise exception 'get_my_active_supporter_entitlement must be bound to auth.uid()';
  end if;

  if position('active' in v_functiondef) = 0
     or position('trialing' in v_functiondef) = 0
     or position('environment' in v_functiondef) = 0
     or position('live' in v_functiondef) = 0 then
    raise exception 'get_my_active_supporter_entitlement must filter active/trialing live subscriptions';
  end if;

  if position('stripe_subscription_id' in v_functiondef) > 0
     or position('stripe_customer_id' in v_functiondef) > 0
     or position('stripe_price_id' in v_functiondef) > 0
     or position('metadata,' in v_functiondef) > 0
     or position('checkout_session_id' in v_functiondef) > 0 then
    raise exception 'get_my_active_supporter_entitlement exposes Stripe identifiers or metadata';
  end if;

  if not (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.supporter_subscriptions'::regclass
  ) then
    raise exception 'supporter_subscriptions RLS must remain enabled';
  end if;

  if pg_temp.public_has_function_privilege('public.get_my_active_supporter_entitlement()'::regprocedure, 'EXECUTE') then
    raise exception 'PUBLIC must not have EXECUTE on get_my_active_supporter_entitlement';
  end if;

  if pg_catalog.has_function_privilege('anon', 'public.get_my_active_supporter_entitlement()', 'EXECUTE') then
    raise exception 'anon must not have EXECUTE on get_my_active_supporter_entitlement';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', 'public.get_my_active_supporter_entitlement()', 'EXECUTE') then
    raise exception 'authenticated must have EXECUTE on get_my_active_supporter_entitlement';
  end if;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('entitlement rpc', true, 'no-arg SECURITY DEFINER RPC, empty search_path, minimal columns, auth.uid boundary, and grants verified');
end;
$$;

do $$
begin
  if pg_catalog.has_table_privilege('anon', 'public.supporter_subscriptions', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.supporter_subscriptions', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.supporter_subscriptions', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.supporter_subscriptions', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.supporter_subscriptions', 'DELETE') then
    raise exception 'supporter_subscriptions privileges are broader than intended';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.supporter_payments', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.supporter_payments', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.contributions', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.contributions', 'SELECT') then
    raise exception 'payment history/contribution tables must not be directly readable by anon/authenticated';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.profiles', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
     or not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'TRIGGER')
     or pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'TRUNCATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'REFERENCES') then
    raise exception 'profiles privileges do not match the intended self-service matrix';
  end if;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('table privileges', true, 'payment table and profile privilege matrix verified');
end;
$$;

do $$
declare
  v_user_id uuid := :'ordinary_user_id'::uuid;
  v_entitlement record;
  v_count integer;
begin
  perform pg_temp.set_auth_context('service_role', v_user_id);

  insert into public.supporter_subscriptions (
    user_id,
    stripe_subscription_id,
    stripe_customer_id,
    stripe_price_id,
    quantity,
    amount_cents,
    currency,
    status,
    metadata
  ) values
    (v_user_id, 'sub_codex_test_old_' || pg_catalog.txid_current()::text, 'cus_codex_test', 'price_codex', 1, 100, 'usd', 'canceled', '{"environment":"live"}'::jsonb),
    (v_user_id, 'sub_codex_test_env_' || pg_catalog.txid_current()::text, 'cus_codex_test', 'price_codex', 2, 200, 'usd', 'active', '{"environment":"test"}'::jsonb),
    (null, 'sub_codex_test_no_user_' || pg_catalog.txid_current()::text, 'cus_codex_other', 'price_codex', 99, 9900, 'usd', 'active', '{"environment":"live"}'::jsonb),
    (v_user_id, 'sub_codex_test_live_' || pg_catalog.txid_current()::text, 'cus_codex_test', 'price_codex', 7, 700, 'usd', 'trialing', '{"environment":"live"}'::jsonb);

  perform pg_temp.set_auth_context('authenticated', v_user_id);
  select * into v_entitlement
  from public.get_my_active_supporter_entitlement();

  if v_entitlement.status <> 'trialing'
     or v_entitlement.quantity <> 7
     or v_entitlement.amount_cents <> 700 then
    raise exception 'entitlement RPC returned wrong row or fields: %, %, %',
      v_entitlement.status, v_entitlement.quantity, v_entitlement.amount_cents;
  end if;

  select count(*) into v_count
  from public.get_my_active_supporter_entitlement();
  if v_count <> 1 then
    raise exception 'entitlement RPC must return at most one row, got %', v_count;
  end if;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('entitlement rpc behavior', true, 'only the caller live active/trialing row qualifies; test/inactive/non-caller rows do not leak');
end;
$$;

do $$
declare
  v_user_id uuid := :'ordinary_user_id'::uuid;
begin
  if not exists (select 1 from public.profiles where id = v_user_id) then
    raise exception 'ordinary_user_id % must have an existing public.profiles row', v_user_id;
  end if;

  perform pg_temp.set_auth_context('service_role', v_user_id);
  update public.profiles
  set subscription_type = 'customer_free',
      subscription_active = false,
      subscription_amount = 0,
      subscription_status = null,
      stripe_customer_id = null,
      stripe_subscription_id = null,
      freebird_contributions = 0
  where id = v_user_id;

  perform pg_temp.set_auth_context('authenticated', v_user_id);
  update public.profiles
  set full_name = coalesce(full_name, 'HEHA proof user') || ' proof'
  where id = v_user_id;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('profile ordinary update', true, 'ordinary authenticated user can update an ordinary profile field');

  perform pg_temp.expect_42501(
    'profile blocks subscription_active',
    format('update public.profiles set subscription_active = true where id = %L', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks subscription_amount',
    format('update public.profiles set subscription_amount = 42 where id = %L', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks subscription_status',
    format('update public.profiles set subscription_status = %L where id = %L', 'active', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks stripe_customer_id',
    format('update public.profiles set stripe_customer_id = %L where id = %L', 'cus_client_forbidden', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks stripe_subscription_id',
    format('update public.profiles set stripe_subscription_id = %L where id = %L', 'sub_client_forbidden', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks freebird_contributions',
    format('update public.profiles set freebird_contributions = 99 where id = %L', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks customer_free to supporter_membership',
    format('update public.profiles set subscription_type = %L where id = %L', 'supporter_membership', v_user_id)
  );
  perform pg_temp.expect_42501(
    'profile blocks customer_free to customer_supporter',
    format('update public.profiles set subscription_type = %L where id = %L', 'customer_supporter', v_user_id)
  );

  update public.profiles
  set subscription_type = 'partner_free'
  where id = v_user_id;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('profile free transition', true, 'ordinary authenticated user can make a safe free subscription_type transition');

  perform pg_temp.set_auth_context('service_role', v_user_id);
  update public.profiles
  set subscription_type = 'supporter_membership',
      subscription_active = true,
      subscription_amount = 1,
      subscription_status = 'active',
      stripe_customer_id = 'cus_service_proof',
      stripe_subscription_id = 'sub_service_proof',
      freebird_contributions = 1
  where id = v_user_id;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('profile service role maintenance', true, 'service_role can maintain backend entitlement cache fields');
end;
$$;

do $$
declare
  v_user_id uuid := :'ordinary_user_id'::uuid;
  v_payment_id text := 'codex-proof-' || pg_catalog.txid_current()::text;
begin
  if exists (
    select 1
    from public.contributions
    where stripe_payment_id is not null
    group by stripe_payment_id
    having count(*) > 1
  ) then
    raise exception 'pre-existing duplicate non-null stripe_payment_id values found';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a
      on a.attrelid = c.conrelid
     and a.attname = 'stripe_payment_id'
    where c.conrelid = 'public.contributions'::regclass
      and c.contype = 'u'
      and c.conkey = array[a.attnum]::int2[]
  ) then
    raise exception 'unique constraint on public.contributions(stripe_payment_id) is missing';
  end if;

  insert into public.contributions (
    user_id,
    type,
    amount,
    freebird_portion,
    heha_portion,
    stripe_payment_id,
    status
  ) values (
    v_user_id,
    'supporter_membership',
    1,
    0,
    1,
    v_payment_id,
    'paid'
  );

  begin
    insert into public.contributions (
      user_id,
      type,
      amount,
      freebird_portion,
      heha_portion,
      stripe_payment_id,
      status
    ) values (
      v_user_id,
      'supporter_membership',
      1,
      0,
      1,
      v_payment_id,
      'paid'
    );
    raise exception 'duplicate stripe_payment_id insert unexpectedly succeeded';
  exception
    when unique_violation then
      insert into pg_temp.supporter_security_results(label, ok, detail)
      values ('contribution dedupe', true, 'duplicate stripe_payment_id cannot create two contribution rows');
  end;
end;
$$;

select label, ok, detail
from pg_temp.supporter_security_results
order by label;

rollback;
