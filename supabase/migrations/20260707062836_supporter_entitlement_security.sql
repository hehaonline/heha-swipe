-- Launch Security Gate 1A: supporter entitlement and payment integrity.
--
-- Safety:
-- * No existing profile, subscription, payment, or contribution rows are rewritten.
-- * The entitlement RPC exposes only minimal client fields and filters to live active/trialing rows.
-- * The profile guard blocks authenticated browser writes to server-owned payment cache fields.
-- * Contribution dedupe fails closed if duplicate non-null Stripe payment identifiers already exist.

drop view if exists public.my_active_supporter_entitlements;

create or replace function public.get_my_active_supporter_entitlement()
returns table (
  status text,
  quantity integer,
  amount_cents integer
)
language sql
security definer
set search_path = ''
stable
as $function$
  select
    ss.status,
    ss.quantity,
    ss.amount_cents
  from public.supporter_subscriptions ss
  where ss.user_id = auth.uid()
    and ss.status in ('active', 'trialing')
    and ss.metadata ->> 'environment' = 'live'
  order by ss.updated_at desc nulls last, ss.created_at desc nulls last
  limit 1;
$function$;

revoke all on function public.get_my_active_supporter_entitlement() from public;
revoke all on function public.get_my_active_supporter_entitlement() from anon;
revoke all on function public.get_my_active_supporter_entitlement() from authenticated;
grant execute on function public.get_my_active_supporter_entitlement() to authenticated;

create or replace function public.guard_profile_entitlement_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_claims jsonb := '{}'::jsonb;
  v_jwt_role text;
  v_safe_profile_types constant text[] := array['none', 'customer_free', 'partner_free'];
  v_safe_insert_statuses constant text[] := array['none', 'free', 'customer_free', 'partner_free'];
  v_old_type text;
  v_new_type text;
begin
  begin
    v_claims := coalesce(nullif(pg_catalog.current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  exception
    when others then
      v_claims := '{}'::jsonb;
  end;

  v_jwt_role := coalesce(
    nullif(v_claims ->> 'role', ''),
    nullif(pg_catalog.current_setting('request.jwt.claim.role', true), ''),
    pg_catalog.current_user
  );

  -- Trusted backend/server workflows, including Stripe webhook service-role writes,
  -- remain authoritative for payment-derived profile cache fields.
  if v_jwt_role = 'service_role' or pg_catalog.current_user = 'service_role' then
    return new;
  end if;

  v_actor_id := auth.uid();
  if v_actor_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_new_type := coalesce(new.subscription_type, 'none');

    if not (v_new_type = any (v_safe_profile_types)) then
      raise exception 'Authenticated clients cannot create paid supporter profile entitlement'
        using errcode = '42501';
    end if;

    if new.subscription_active is true then
      raise exception 'Authenticated clients cannot create active supporter profile entitlement'
        using errcode = '42501';
    end if;

    if coalesce(new.subscription_amount, 0) <> 0 then
      raise exception 'Authenticated clients cannot create supporter payment amount'
        using errcode = '42501';
    end if;

    if new.subscription_status is not null
       and not (new.subscription_status = any (v_safe_insert_statuses)) then
      raise exception 'Authenticated clients cannot create supporter subscription status'
        using errcode = '42501';
    end if;

    if new.stripe_customer_id is not null or new.stripe_subscription_id is not null then
      raise exception 'Authenticated clients cannot create Stripe identity fields'
        using errcode = '42501';
    end if;

    if coalesce(new.freebird_contributions, 0) <> 0 then
      raise exception 'Authenticated clients cannot create contribution totals'
        using errcode = '42501';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.subscription_active is distinct from old.subscription_active then
      raise exception 'Authenticated clients cannot change supporter active state'
        using errcode = '42501';
    end if;

    if new.subscription_amount is distinct from old.subscription_amount then
      raise exception 'Authenticated clients cannot change supporter amount'
        using errcode = '42501';
    end if;

    if new.subscription_status is distinct from old.subscription_status then
      raise exception 'Authenticated clients cannot change supporter subscription status'
        using errcode = '42501';
    end if;

    if new.stripe_customer_id is distinct from old.stripe_customer_id then
      raise exception 'Authenticated clients cannot change Stripe customer identity'
        using errcode = '42501';
    end if;

    if new.stripe_subscription_id is distinct from old.stripe_subscription_id then
      raise exception 'Authenticated clients cannot change Stripe subscription identity'
        using errcode = '42501';
    end if;

    if new.freebird_contributions is distinct from old.freebird_contributions then
      raise exception 'Authenticated clients cannot change contribution totals'
        using errcode = '42501';
    end if;

    if new.subscription_type is distinct from old.subscription_type then
      v_old_type := coalesce(old.subscription_type, 'none');
      v_new_type := coalesce(new.subscription_type, 'none');

      if not (v_old_type = any (v_safe_profile_types))
         or not (v_new_type = any (v_safe_profile_types)) then
        raise exception 'Authenticated clients cannot change paid or protected subscription type'
          using errcode = '42501';
      end if;
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_profile_entitlement_fields() from public;
revoke all on function public.guard_profile_entitlement_fields() from anon;
revoke all on function public.guard_profile_entitlement_fields() from authenticated;

drop trigger if exists b_profiles_entitlement_guard on public.profiles;
create trigger b_profiles_entitlement_guard
before insert or update on public.profiles
for each row
execute function public.guard_profile_entitlement_fields();

do $migration$
begin
  if exists (
    select 1
    from public.contributions
    where stripe_payment_id is not null
    group by stripe_payment_id
    having count(*) > 1
  ) then
    raise exception 'Duplicate non-null contributions.stripe_payment_id values exist; aborting constraint creation';
  end if;
end;
$migration$;

do $migration$
begin
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
    alter table public.contributions
      add constraint contributions_stripe_payment_id_unique unique (stripe_payment_id);
  end if;
end;
$migration$;

-- Entitlement source table: browser reads must use
-- public.get_my_active_supporter_entitlement(). Direct base table access is
-- removed for anon/authenticated; service_role remains the backend writer.
revoke all on table public.supporter_subscriptions from public;
revoke all on table public.supporter_subscriptions from anon;
revoke all on table public.supporter_subscriptions from authenticated;
grant all on table public.supporter_subscriptions to service_role;

revoke all on table public.supporter_payments from public;
revoke all on table public.supporter_payments from anon;
revoke all on table public.supporter_payments from authenticated;
grant all on table public.supporter_payments to service_role;

revoke all on table public.contributions from public;
revoke all on table public.contributions from anon;
revoke all on table public.contributions from authenticated;
grant all on table public.contributions to service_role;

revoke all on table public.profiles from public;
revoke all on table public.profiles from anon;
revoke truncate, references, trigger on table public.profiles from authenticated;
grant select, insert, update, delete on table public.profiles to authenticated;
grant all on table public.profiles to service_role;
