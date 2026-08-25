-- Follow-up for Package A review-only foundation.
-- Qualifies every Community Pass entitlement column referenced by the
-- RETURNS TABLE trial-activation RPC so PostgreSQL cannot confuse table columns
-- with output variables such as `state`, `trial_start_at`, or `trial_end_at`.
--
-- Additive/review-only. No data mutation occurs when this migration is applied.

begin;

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

  select a.*
  into v_account
  from public.community_pass_accounts a
  where a.user_id = v_user_id
    and a.status <> 'deleted'
  for update;

  if not found or v_account.trial_used_at is not null then
    raise exception 'HEHA_COMMUNITY_PASS_TRIAL_NOT_AVAILABLE'
      using errcode = 'P0001';
  end if;

  select e.*
  into v_entitlement
  from public.community_pass_entitlements e
  where e.account_id = v_account.id
    and e.user_id = v_user_id
    and e.source_type = 'free_trial'
    and e.state in ('invited', 'activation_available')
    and e.invitation_sent_at is not null
    and e.invitation_expires_at is not null
    and e.invitation_expires_at >= v_now
  order by e.invitation_sent_at desc
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

  update public.community_pass_entitlements e
  set state = 'trial_active',
      trial_start_at = v_now,
      trial_end_at = v_now + interval '30 days',
      active_start_at = v_now,
      active_end_at = v_now + interval '30 days'
  where e.id = v_entitlement.id
  returning e.* into v_entitlement;

  update public.community_pass_accounts a
  set status = 'trial_active',
      trial_used_at = v_now
  where a.id = v_account.id;

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
  )
  on conflict (environment, idempotency_key)
    where idempotency_key is not null
  do nothing;

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

commit;
