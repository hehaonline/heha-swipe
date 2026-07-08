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

do $$
declare
  v_view_options text[];
  v_columns text[];
  v_viewdef text;
begin
  select reloptions into v_view_options
  from pg_catalog.pg_class
  where oid = 'public.my_active_supporter_entitlements'::regclass;

  if not ('security_invoker=true' = any (coalesce(v_view_options, array[]::text[]))) then
    raise exception 'my_active_supporter_entitlements must use security_invoker=true';
  end if;

  select array_agg(column_name order by ordinal_position) into v_columns
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'my_active_supporter_entitlements';

  if v_columns is distinct from array['user_id', 'status', 'quantity', 'amount_cents']::text[] then
    raise exception 'my_active_supporter_entitlements exposes unexpected columns: %', v_columns;
  end if;

  v_viewdef := pg_catalog.pg_get_viewdef('public.my_active_supporter_entitlements'::regclass, true);
  if position('stripe_subscription_id' in v_viewdef) > 0
     or position('stripe_customer_id' in v_viewdef) > 0
     or position('stripe_price_id' in v_viewdef) > 0 then
    raise exception 'my_active_supporter_entitlements view definition exposes Stripe identifiers';
  end if;

  if position('active' in v_viewdef) = 0
     or position('trialing' in v_viewdef) = 0
     or position('environment' in v_viewdef) = 0
     or position('live' in v_viewdef) = 0 then
    raise exception 'my_active_supporter_entitlements must filter active/trialing live subscriptions';
  end if;

  if not (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.supporter_subscriptions'::regclass
  ) then
    raise exception 'supporter_subscriptions RLS must remain enabled';
  end if;

  if pg_temp.public_has_table_privilege('public.my_active_supporter_entitlements'::regclass, 'SELECT') then
    raise exception 'PUBLIC must not have SELECT on my_active_supporter_entitlements';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.my_active_supporter_entitlements', 'SELECT') then
    raise exception 'anon must not have SELECT on my_active_supporter_entitlements';
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.my_active_supporter_entitlements', 'SELECT') then
    raise exception 'authenticated must have SELECT on my_active_supporter_entitlements';
  end if;

  insert into pg_temp.supporter_security_results(label, ok, detail)
  values ('entitlement view', true, 'security_invoker, minimal columns, live active/trialing filter, and grants verified');
end;
$$;

do $$
begin
  if not pg_catalog.has_table_privilege('authenticated', 'public.supporter_subscriptions', 'SELECT') then
    raise exception 'authenticated SELECT on supporter_subscriptions is required for the security_invoker entitlement view';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.supporter_subscriptions', 'SELECT')
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
