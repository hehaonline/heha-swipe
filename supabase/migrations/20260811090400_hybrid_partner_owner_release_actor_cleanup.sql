-- Prevent account deletion from reintroducing a reference to the Auth user that
-- is currently being deleted. Review-only / Production-frozen with PR #120.

create or replace function app_private.record_partner_owner_release()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  before_receipt jsonb;
  event_actor uuid := auth.uid();
begin
  if old.owner_id is not null and new.owner_id is null then
    before_receipt := app_private.partner_lifecycle_receipt(old);
    perform set_config('app.hybrid_partner_context', 'owner_release', true);
    new.claim_status := 'unclaimed';
    new.claimed_at := null;
    new.claimed_by := null;
    if old.partnership_status = 'official_partner' then
      new.partnership_status := 'under_review';
      new.heha_partner := false;
    end if;

    -- During self/account deletion, auth.uid() can still contain the subject
    -- after auth.users has already become unavailable to new FK references.
    -- Preserve the lifecycle receipt without re-creating that child reference.
    if event_actor = old.owner_id then
      event_actor := null;
    end if;

    insert into public.partner_lifecycle_events(
      partner_id,event_type,actor_id,before_state,after_state
    ) values (
      old.id,
      'owner_released',
      event_actor,
      before_receipt,
      jsonb_build_object(
        'partner_id',old.id,
        'owner_id',null,
        'claim_status','unclaimed',
        'partnership_status',new.partnership_status,
        'contract_status',new.contract_status,
        'listing_status',new.listing_status,
        'heha_partner',new.heha_partner
      )
    );
    return new;
  end if;

  if old.owner_id is null and new.owner_id is not null then
    if coalesce(current_setting('app.hybrid_partner_context', true), '') <> 'claim' then
      raise exception using
        errcode='42501',
        message='Owner assignment requires a verified claim workflow.';
    end if;
    return new;
  end if;

  if old.owner_id is distinct from new.owner_id then
    raise exception using errcode='42501', message='Direct owner transfer is not allowed.';
  end if;
  return new;
end;
$$;

revoke all on function app_private.record_partner_owner_release()
  from public, anon, authenticated, service_role;
