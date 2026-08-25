-- Harden the private capability gate for PR #120.
-- Review-only and Production-frozen with the hybrid successor.
--
-- 1. A caller-supplied custom GUC without a private capability must not bypass
--    the current-main owner guard, even when no lifecycle column changes.
-- 2. Auth deletion may null claimed_by / opted_out_by in a separate FK action
--    before or after owner_id is cleared; those pure reference cleanups must not
--    block account deletion.

create or replace function app_private.gate_partner_lifecycle_capability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, pg_temp
as $$
declare
  op text := coalesce(current_setting('app.hybrid_partner_context', true), '');
  lifecycle_changed boolean;
  capability_exists boolean;
  exact_owner_release boolean;
  auth_reference_cleanup boolean;
begin
  lifecycle_changed :=
       new.owner_id is distinct from old.owner_id
    or new.claim_status is distinct from old.claim_status
    or new.partnership_status is distinct from old.partnership_status
    or new.contract_status is distinct from old.contract_status
    or new.listing_status is distinct from old.listing_status
    or new.claimed_at is distinct from old.claimed_at
    or new.claimed_by is distinct from old.claimed_by
    or new.partnership_requested_at is distinct from old.partnership_requested_at
    or new.official_partner_since is distinct from old.official_partner_since
    or new.contract_signed_at is distinct from old.contract_signed_at
    or new.opted_out_at is distinct from old.opted_out_at
    or new.opted_out_by is distinct from old.opted_out_by
    or new.heha_partner is distinct from old.heha_partner;

  select exists (
    select 1
    from app_private.partner_lifecycle_mutation_capabilities as cap
    where cap.backend_pid=pg_backend_pid()
      and cap.transaction_id=txid_current()
      and cap.partner_id=new.id
      and cap.operation=op
  ) into capability_exists;

  -- A spoofed GUC may not bypass the owner guard for any column, including
  -- non-lifecycle fields such as review status, ratings or routing metadata.
  if op <> '' and op <> 'owner_release' and not capability_exists then
    raise exception using
      errcode='42501',
      message='Partner lifecycle context lacks a private single-use capability.';
  end if;

  if not lifecycle_changed then
    return new;
  end if;

  exact_owner_release :=
       old.owner_id is not null
   and new.owner_id is null
   and new.claim_status is not distinct from old.claim_status
   and new.partnership_status is not distinct from old.partnership_status
   and new.contract_status is not distinct from old.contract_status
   and new.listing_status is not distinct from old.listing_status
   and new.claimed_at is not distinct from old.claimed_at
   and new.claimed_by is not distinct from old.claimed_by
   and new.partnership_requested_at is not distinct from old.partnership_requested_at
   and new.official_partner_since is not distinct from old.official_partner_since
   and new.contract_signed_at is not distinct from old.contract_signed_at
   and new.opted_out_at is not distinct from old.opted_out_at
   and new.opted_out_by is not distinct from old.opted_out_by
   and new.heha_partner is not distinct from old.heha_partner;

  if exact_owner_release then
    return new;
  end if;

  -- ON DELETE SET NULL may clean either or both provenance actor references in
  -- a separate statement. Only pure NULL cleanup is accepted here; the later
  -- guards still reject every other protected-field mutation.
  auth_reference_cleanup :=
       new.owner_id is not distinct from old.owner_id
   and new.claim_status is not distinct from old.claim_status
   and new.partnership_status is not distinct from old.partnership_status
   and new.contract_status is not distinct from old.contract_status
   and new.listing_status is not distinct from old.listing_status
   and new.claimed_at is not distinct from old.claimed_at
   and new.partnership_requested_at is not distinct from old.partnership_requested_at
   and new.official_partner_since is not distinct from old.official_partner_since
   and new.contract_signed_at is not distinct from old.contract_signed_at
   and new.opted_out_at is not distinct from old.opted_out_at
   and new.heha_partner is not distinct from old.heha_partner
   and (
     (old.claimed_by is not null and new.claimed_by is null
       and new.opted_out_by is not distinct from old.opted_out_by)
     or
     (old.opted_out_by is not null and new.opted_out_by is null
       and new.claimed_by is not distinct from old.claimed_by)
     or
     (old.claimed_by is not null and new.claimed_by is null
       and old.opted_out_by is not null and new.opted_out_by is null)
   );

  if auth_reference_cleanup then
    perform set_config('app.hybrid_partner_context','owner_release',true);
    return new;
  end if;

  if op not in ('claim','partnership_request','partnership_review','listing_change')
     or not capability_exists then
    raise exception using
      errcode='42501',
      message='Partner lifecycle mutation lacks a private single-use capability.';
  end if;

  return new;
end;
$$;

revoke all on function app_private.gate_partner_lifecycle_capability()
  from public, anon, authenticated, service_role;
