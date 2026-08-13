-- Caller-supplied lifecycle context is never authorization. PR #120 repairs.
-- REVIEW ONLY / PRODUCTION FROZEN.
--
-- Review finding P1 (discussion_r3770655341): the capability gate exempted the
-- literal context value `owner_release` from the missing-capability rejection.
-- An authenticated owner of a pre-approval profile could `set_config(
-- 'app.hybrid_partner_context','owner_release')`, change any non-lifecycle
-- protected column (ratings, routing metadata, analytics, media), have the gate
-- return early because no lifecycle field changed, and then have
-- `guard_partner_owner_self_service` wave the write through on the same trusted
-- string. Reproduced against cef9af2: rating 0 -> 5 and routing_status
-- 'suggested' -> 'approved' both succeeded with the context set and were denied
-- without it.
--
-- Review finding P2 (discussion_r3770655342): the Auth-FK-cleanup exemption was
-- satisfied by any UPDATE that nulled `claimed_by` and changed nothing else.
-- An ordinary owner could issue exactly that write through the owner UPDATE
-- policy, so the row kept `claim_status='claimed'` and a live `owner_id` while
-- its claim provenance was erased and the write was audited as an owner release.
-- Reproduced against cef9af2: claimed_by went to NULL with claim_status still
-- 'claimed'.
--
-- Repair shape:
--   1. Every non-empty context, including `owner_release`, must be backed by a
--      private capability row keyed to (backend_pid, transaction_id, partner_id).
--   2. Only the gate itself may mint an `owner_release` capability, and only on
--      structural evidence that the referenced Auth account is actually gone.
--   3. The downstream status guard and the owner self-service guard verify the
--      capability rather than trusting the GUC string.

-- ---------------------------------------------------------------------------
-- 1. `owner_release` becomes a real, mintable capability operation.
-- ---------------------------------------------------------------------------
alter table app_private.partner_lifecycle_mutation_capabilities
  drop constraint if exists partner_lifecycle_mutation_capabilities_operation_check,
  add constraint partner_lifecycle_mutation_capabilities_operation_check
    check (operation in (
      'claim','partnership_request','partnership_review','listing_change','owner_release'
    ));

-- Callable entry point stays restricted to the four caller-initiated operations;
-- `owner_release` is deliberately not reachable through it.
create or replace function app_private.authorize_partner_lifecycle_mutation(
  p_partner_id uuid,
  p_operation text
) returns void
language plpgsql security definer
set search_path = pg_catalog, app_private, pg_temp
as $$
begin
  if p_operation not in ('claim','partnership_request','partnership_review','listing_change') then
    raise exception using errcode='22023', message='Invalid partner lifecycle operation.';
  end if;

  insert into app_private.partner_lifecycle_mutation_capabilities(
    backend_pid, transaction_id, partner_id, operation
  ) values (
    pg_backend_pid(), txid_current(), p_partner_id, p_operation
  )
  on conflict (backend_pid, transaction_id, partner_id)
  do update set operation=excluded.operation, created_at=now();

  perform set_config('app.hybrid_partner_context', p_operation, true);
end;
$$;
revoke all on function app_private.authorize_partner_lifecycle_mutation(uuid,text)
  from public, anon, authenticated, service_role;

-- Single reader used by every guard: the operation actually backed by a private
-- capability for this backend, transaction and partner, or NULL.
create or replace function app_private.partner_lifecycle_capability(p_partner_id uuid)
returns text
language sql stable security definer
set search_path = pg_catalog, app_private, pg_temp
as $$
  select cap.operation
  from app_private.partner_lifecycle_mutation_capabilities as cap
  where cap.backend_pid=pg_backend_pid()
    and cap.transaction_id=txid_current()
    and cap.partner_id=p_partner_id;
$$;
revoke all on function app_private.partner_lifecycle_capability(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Capability gate.
-- ---------------------------------------------------------------------------
create or replace function app_private.gate_partner_lifecycle_capability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  op text := coalesce(current_setting('app.hybrid_partner_context', true), '');
  capability_op text := app_private.partner_lifecycle_capability(new.id);
  lifecycle_changed boolean;
  owner_account_gone boolean;
  exact_owner_release boolean;
  auth_reference_cleanup boolean;
begin
  lifecycle_changed :=
       new.owner_id is distinct from old.owner_id
    or new.claim_status is distinct from old.claim_status
    or new.partnership_status is distinct from old.partnership_status
    or new.contract_status is distinct from old.contract_status
    or new.contract_evidence_id is distinct from old.contract_evidence_id
    or new.listing_status is distinct from old.listing_status
    or new.claimed_at is distinct from old.claimed_at
    or new.claimed_by is distinct from old.claimed_by
    or new.partnership_requested_at is distinct from old.partnership_requested_at
    or new.official_partner_since is distinct from old.official_partner_since
    or new.contract_signed_at is distinct from old.contract_signed_at
    or new.opted_out_at is distinct from old.opted_out_at
    or new.opted_out_by is distinct from old.opted_out_by
    or new.heha_partner is distinct from old.heha_partner;

  -- P1 repair: no context string is trusted on its own. `owner_release` is held
  -- to exactly the same standard as every other value, so a caller-supplied GUC
  -- can no longer buy an early return past the owner guard for any column.
  if op <> '' and capability_op is distinct from op then
    raise exception using
      errcode='42501',
      message='Partner lifecycle context lacks a private single-use capability.';
  end if;

  if not lifecycle_changed then
    return new;
  end if;

  -- Auth account deletion drives owner_id to NULL through the existing FK. At
  -- this first trigger the release-provenance trigger has not yet normalized the
  -- remaining lifecycle fields, so only a pure owner unlink is accepted -- and
  -- only when the Auth account really is gone.
  owner_account_gone := old.owner_id is not null
    and not exists (select 1 from auth.users as u where u.id = old.owner_id);

  exact_owner_release :=
       owner_account_gone
   and new.owner_id is null
   and new.claim_status is not distinct from old.claim_status
   and new.partnership_status is not distinct from old.partnership_status
   and new.contract_status is not distinct from old.contract_status
   and new.contract_evidence_id is not distinct from old.contract_evidence_id
   and new.listing_status is not distinct from old.listing_status
   and new.claimed_at is not distinct from old.claimed_at
   and new.claimed_by is not distinct from old.claimed_by
   and new.partnership_requested_at is not distinct from old.partnership_requested_at
   and new.official_partner_since is not distinct from old.official_partner_since
   and new.contract_signed_at is not distinct from old.contract_signed_at
   and new.opted_out_at is not distinct from old.opted_out_at
   and new.opted_out_by is not distinct from old.opted_out_by
   and new.heha_partner is not distinct from old.heha_partner;

  -- P2 repair: ON DELETE SET NULL may clean either or both provenance actor
  -- references in a separate statement. The distinguishing condition an
  -- owner-authored UPDATE cannot satisfy is that the referenced Auth account no
  -- longer exists -- a normal owner nulling claimed_by is still a live account,
  -- so that write now falls through to the capability requirement and is denied.
  auth_reference_cleanup :=
       new.owner_id is not distinct from old.owner_id
   and new.claim_status is not distinct from old.claim_status
   and new.partnership_status is not distinct from old.partnership_status
   and new.contract_status is not distinct from old.contract_status
   and new.contract_evidence_id is not distinct from old.contract_evidence_id
   and new.listing_status is not distinct from old.listing_status
   and new.claimed_at is not distinct from old.claimed_at
   and new.partnership_requested_at is not distinct from old.partnership_requested_at
   and new.official_partner_since is not distinct from old.official_partner_since
   and new.contract_signed_at is not distinct from old.contract_signed_at
   and new.opted_out_at is not distinct from old.opted_out_at
   and new.heha_partner is not distinct from old.heha_partner
   and (
     (old.claimed_by is not null and new.claimed_by is null
       and not exists (select 1 from auth.users as u where u.id = old.claimed_by)
       and new.opted_out_by is not distinct from old.opted_out_by)
     or
     (old.opted_out_by is not null and new.opted_out_by is null
       and not exists (select 1 from auth.users as u where u.id = old.opted_out_by)
       and new.claimed_by is not distinct from old.claimed_by)
     or
     (old.claimed_by is not null and new.claimed_by is null
       and old.opted_out_by is not null and new.opted_out_by is null
       and not exists (select 1 from auth.users as u where u.id = old.claimed_by)
       and not exists (select 1 from auth.users as u where u.id = old.opted_out_by))
   );

  if exact_owner_release or auth_reference_cleanup then
    -- Minted here, never by a caller: `authorize_partner_lifecycle_mutation`
    -- rejects 'owner_release', so this is the only path that can produce one.
    insert into app_private.partner_lifecycle_mutation_capabilities(
      backend_pid, transaction_id, partner_id, operation
    ) values (
      pg_backend_pid(), txid_current(), new.id, 'owner_release'
    )
    on conflict (backend_pid, transaction_id, partner_id)
    do update set operation='owner_release', created_at=now();
    perform set_config('app.hybrid_partner_context','owner_release',true);
    return new;
  end if;

  if op = ''
     or capability_op is distinct from op
     or op not in ('claim','partnership_request','partnership_review','listing_change') then
    raise exception using
      errcode='42501',
      message='Partner lifecycle mutation lacks a private single-use capability.';
  end if;

  return new;
end;
$$;
revoke all on function app_private.gate_partner_lifecycle_capability()
  from public, anon, authenticated, service_role;

drop trigger if exists a00_hybrid_lifecycle_capability_gate on public.partners;
create trigger a00_hybrid_lifecycle_capability_gate
before update on public.partners
for each row execute function app_private.gate_partner_lifecycle_capability();

-- ---------------------------------------------------------------------------
-- 3. Protected-state guard now verifies the capability, not the string.
-- ---------------------------------------------------------------------------
create or replace function app_private.guard_hybrid_partner_statuses()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  ctx text := coalesce(current_setting('app.hybrid_partner_context', true), '');
  capability_op text;
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  if new.claim_status is not distinct from old.claim_status
     and new.partnership_status is not distinct from old.partnership_status
     and new.contract_status is not distinct from old.contract_status
     and new.contract_evidence_id is not distinct from old.contract_evidence_id
     and new.listing_status is not distinct from old.listing_status
     and new.claimed_at is not distinct from old.claimed_at
     and new.claimed_by is not distinct from old.claimed_by
     and new.partnership_requested_at is not distinct from old.partnership_requested_at
     and new.official_partner_since is not distinct from old.official_partner_since
     and new.contract_signed_at is not distinct from old.contract_signed_at
     and new.opted_out_at is not distinct from old.opted_out_at
     and new.opted_out_by is not distinct from old.opted_out_by
     and new.heha_partner is not distinct from old.heha_partner
     and new.owner_id is not distinct from old.owner_id then
    return new;
  end if;

  capability_op := app_private.partner_lifecycle_capability(new.id);
  if ctx <> ''
     and capability_op is not distinct from ctx
     and ctx in ('claim','owner_release','partnership_request','partnership_review','listing_change') then
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Partner lifecycle fields may only change through approved server workflows.';
end;
$$;
revoke all on function app_private.guard_hybrid_partner_statuses()
  from public, anon, authenticated, service_role;

drop trigger if exists aa_guard_hybrid_partner_statuses on public.partners;
create trigger aa_guard_hybrid_partner_statuses
before update on public.partners
for each row execute function app_private.guard_hybrid_partner_statuses();

-- ---------------------------------------------------------------------------
-- 4. Owner self-service guard: the workflow exception is capability-backed.
-- Every column outside `owner_editable_keys` stays denied by default, so new
-- protected columns such as `contract_evidence_id` are covered automatically.
-- ---------------------------------------------------------------------------
create or replace function app_private.guard_partner_owner_self_service()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  ctx text := coalesce(current_setting('app.hybrid_partner_context', true), '');
  capability_op text;
  preapproval_statuses constant text[] := array['draft', 'submitted', 'pending', 'missing_info'];
  owner_editable_keys constant text[] := array[
    'name','category','categories','location','contact','instagram','website','bio','tags','hours',
    'business_type','offerings','neighborhood','tagline','phone','price_range','delivery_days',
    'pricing_notes','complete_pct','updated_at'
  ];
begin
  if actor_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    capability_op := app_private.partner_lifecycle_capability(new.id);
    -- P1 repair: the workflow exception requires a private capability that only
    -- an approved SECURITY DEFINER workflow, or the gate's structural
    -- Auth-deletion path, can have minted. A caller-set GUC alone is worthless.
    if ctx <> ''
       and capability_op is not distinct from ctx
       and ctx in ('claim','owner_release','partnership_request','partnership_review','listing_change') then
      return new;
    end if;
  end if;

  if app_private.has_internal_role(array['super_admin', 'developer_admin']) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      return new;
    end if;

    new.categories := app_private.normalize_partner_categories(new.categories, new.category);
    if coalesce(cardinality(new.categories), 0) = 0 then
      raise exception using errcode = '23514', message = 'Choose at least one business category.';
    end if;
    new.category := new.categories[1];
    new.status := 'pending';
    new.heha_partner := false;
    new.complete_pct := app_private.partner_completion_pct(new);
    new.contribution := 0;
    new.total_swipes := 0;
    new.total_saves := 0;
    new.total_profile_views := 0;
    new.rating := 0;
    new.review_count := 0;
    new.google_place_id := null;
    new.image_url := null;
    new.gallery_urls := '[]'::jsonb;
    new.partner_type := null;
    new.product_price_policy := null;
    new.service_fee_type := null;
    new.service_fee_amount := 0;
    new.heha_pillar := null;
    new.website_eligible := null;
    new.swipe_eligible := null;
    new.local_eligible := null;
    new.local_lane := null;
    new.primary_cta_destination := null;
    new.primary_cta_label := null;
    new.primary_cta_path := null;
    new.routing_status := 'suggested';
    new.routing_notes := null;
    new.routing_updated_by := null;
    new.routing_updated_at := null;
    new.is_test_record := false;
    new.claim_status := 'claimed';
    new.claimed_at := now();
    new.claimed_by := actor_id;
    new.partnership_status := 'not_requested';
    new.contract_status := 'not_required';
    new.contract_evidence_id := null;
    new.listing_status := 'hidden';
    return new;
  end if;

  if tg_op = 'UPDATE' and old.owner_id = actor_id then
    if not (coalesce(old.status, '') = any (preapproval_statuses)) then
      raise exception using errcode = '42501', message = 'This partner listing is locked from direct owner edits after pre-approval review.';
    end if;
    if new.status is distinct from old.status then
      raise exception using errcode = '42501', message = 'Partner owners cannot change listing review or publication status.';
    end if;
    new.categories := app_private.normalize_partner_categories(new.categories, new.category);
    if coalesce(cardinality(new.categories), 0) = 0 then
      raise exception using errcode = '23514', message = 'Choose at least one business category.';
    end if;
    new.category := new.categories[1];
    new.complete_pct := app_private.partner_completion_pct(new);
    new.updated_at := now();
    if (to_jsonb(new) - owner_editable_keys) is distinct from (to_jsonb(old) - owner_editable_keys) then
      raise exception using errcode = '42501', message = 'Partner self-service may only change approved business profile fields.';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_partner_owner_self_service()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Owner-release provenance keeps its deletion-safe actor handling and now
-- relies on the capability the gate minted rather than setting a trusted string.
-- ---------------------------------------------------------------------------
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
    if app_private.partner_lifecycle_capability(new.id) is distinct from 'owner_release' then
      raise exception using
        errcode='42501',
        message='Owner release requires a verified account-deletion capability.';
    end if;

    before_receipt := app_private.partner_lifecycle_receipt(old);
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
    if event_actor = old.owner_id
       or not exists (select 1 from auth.users as u where u.id = event_actor) then
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
        'contract_evidence_id',new.contract_evidence_id,
        'listing_status',new.listing_status,
        'heha_partner',new.heha_partner
      )
    );
    return new;
  end if;

  if old.owner_id is null and new.owner_id is not null then
    if app_private.partner_lifecycle_capability(new.id) is distinct from 'claim' then
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

drop trigger if exists a0_hybrid_owner_release_provenance on public.partners;
create trigger a0_hybrid_owner_release_provenance
before update of owner_id on public.partners
for each row execute function app_private.record_partner_owner_release();
