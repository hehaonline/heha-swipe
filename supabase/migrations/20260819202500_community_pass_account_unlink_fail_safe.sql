-- Package A deletion hardening.
--
-- The account-unlink fallback must revoke local entitlement without falsely
-- claiming that Stripe has been canceled. A server-owned deletion workflow is
-- still required to cancel/schedule the provider contract before Auth deletion.
-- If that workflow fails to supply its keyed account reference, this fallback
-- creates an opaque random tombstone rather than a predictable unsalted hash.
--
-- Review-only. No rows are changed when this migration is applied.

begin;

create or replace function public.revoke_community_pass_on_account_unlink()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.user_id is not null and new.user_id is null then
    new.account_reference_hash := coalesce(
      new.account_reference_hash,
      pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '')
    );
    new.account_reference_hash_version := coalesce(
      new.account_reference_hash_version,
      'random_tombstone_v1'
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

create or replace function public.cascade_community_pass_account_unlink()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.user_id is not null and new.user_id is null then
    -- Local access fails closed immediately, but provider cancellation is never
    -- fabricated. Open provider contracts move to reconciliation_exception so a
    -- trusted worker/support case must retrieve Stripe and finish the action.
    update public.community_pass_subscriptions s
    set user_id = null,
        status = case
          when s.status in ('active', 'payment_recovery', 'cancel_scheduled')
            then 'reconciliation_exception'
          else s.status
        end,
        reconciliation_state = case
          when s.status in ('active', 'payment_recovery', 'cancel_scheduled')
            then 'exception'
          else s.reconciliation_state
        end,
        metadata = case
          when s.status in ('active', 'payment_recovery', 'cancel_scheduled')
            then coalesce(s.metadata, '{}'::jsonb) || pg_catalog.jsonb_build_object(
              'account_unlinked_at', pg_catalog.now(),
              'account_unlink_reason', 'provider_reconciliation_required'
            )
          else s.metadata
        end
    where s.account_id = new.id;

    update public.community_pass_purchases p
    set user_id = null
    where p.account_id = new.id;

    update public.community_pass_entitlements e
    set user_id = null,
        state = case
          when e.state in (
            'trial_active',
            'monthly_subscription_active',
            'prepaid_term_active',
            'payment_recovery',
            'cancel_scheduled'
          ) then 'revoked_account_deleted'
          else e.state
        end,
        ended_at = case
          when e.state in (
            'trial_active',
            'monthly_subscription_active',
            'prepaid_term_active',
            'payment_recovery',
            'cancel_scheduled'
          ) then coalesce(e.ended_at, pg_catalog.now())
          else e.ended_at
        end
    where e.account_id = new.id;

    update public.community_pass_acceptances ca
    set user_id = null,
        account_reference_hash = new.account_reference_hash,
        redacted_at = coalesce(ca.redacted_at, pg_catalog.now())
    where ca.account_id = new.id
      and ca.user_id is not null;

    update public.community_pass_events ce
    set user_id = null
    where ce.account_id = new.id
      and ce.user_id is not null;
  end if;

  return null;
end;
$function$;

revoke all on function public.cascade_community_pass_account_unlink() from public;
revoke all on function public.cascade_community_pass_account_unlink() from anon;
revoke all on function public.cascade_community_pass_account_unlink() from authenticated;

commit;
