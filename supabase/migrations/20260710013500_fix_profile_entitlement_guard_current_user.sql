-- Hotfix: repair profile entitlement guard role fallback.
--
-- PostgreSQL CURRENT_USER is SQL syntax and must not be schema-qualified.
-- The prior function used pg_catalog.current_user, which caused authenticated
-- profile writes to fail before the entitlement guard could evaluate them.
--
-- No data is rewritten. This preserves the PR #71 entitlement boundary.

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
    current_user
  );

  -- Trusted backend/server workflows, including Stripe webhook service-role writes,
  -- remain authoritative for payment-derived profile cache fields.
  if v_jwt_role = 'service_role' or current_user = 'service_role' then
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
