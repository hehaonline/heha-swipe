-- Community Pass status must not expose an account-level state when the current
-- server environment has no matching entitlement row.

begin;

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
    and ent.id is not null
  limit 1;
$function$;

revoke all on function public.get_my_community_pass_status() from public;
revoke all on function public.get_my_community_pass_status() from anon;
revoke all on function public.get_my_community_pass_status() from authenticated;
grant execute on function public.get_my_community_pass_status() to authenticated;

commit;
