-- HEHA hybrid partner lifecycle successor for Swipe issue #119 / PR #120.
-- REVIEW ONLY / PRODUCTION FROZEN.
--
-- Founder-approved model keeps four independent questions separate:
--   1) claim_status        - who controls the profile?
--   2) partnership_status  - what relationship does the business have with HEHA?
--   3) contract_status     - is the required agreement complete?
--   4) listing_status      - should the listing be publicly visible?
--
-- This migration reconciles the reviewed donor contracts from PR #117
-- (secure claim) and PR #72 (partnership-interest evidence) without creating a
-- second source of truth. It is forward-only and must not be applied to
-- Production until SWP-016 lineage, ADR, duplicate-profile, media-rights, RLS,
-- retention/deletion and exact-head proof gates close.

create schema if not exists app_private;

-- ---------------------------------------------------------------------------
-- 0. Fail closed if the superseded PR #120 draft claim table was ever populated.
-- The authoritative claim object is the reviewed #117 name: partner_claim_invites.
-- ---------------------------------------------------------------------------
do $cleanup$
begin
  if to_regclass('public.partner_claim_invitations') is not null then
    if exists (select 1 from public.partner_claim_invitations limit 1) then
      raise exception using
        errcode = '55000',
        message = 'Superseded partner_claim_invitations contains rows; reconcile manually before applying the hybrid successor.';
    end if;
    drop table public.partner_claim_invitations;
  end if;
end;
$cleanup$;

-- ---------------------------------------------------------------------------
-- 1. Independent lifecycle state on the canonical public.partners row.
-- ---------------------------------------------------------------------------
alter table public.partners
  add column if not exists claim_status text not null default 'unclaimed',
  add column if not exists partnership_status text not null default 'not_requested',
  add column if not exists contract_status text not null default 'not_required',
  add column if not exists listing_status text not null default 'hidden',
  add column if not exists claimed_at timestamptz,
  add column if not exists claimed_by uuid references auth.users(id) on delete set null,
  add column if not exists partnership_requested_at timestamptz,
  add column if not exists official_partner_since timestamptz,
  add column if not exists contract_signed_at timestamptz,
  add column if not exists opted_out_at timestamptz,
  add column if not exists opted_out_by uuid references auth.users(id) on delete set null;

alter table public.partners
  drop constraint if exists partners_claim_status_check,
  add constraint partners_claim_status_check
    check (claim_status in ('unclaimed', 'claim_invited', 'claimed')) not valid,
  drop constraint if exists partners_partnership_status_check,
  add constraint partners_partnership_status_check
    check (partnership_status in ('not_requested', 'requested', 'under_review', 'official_partner', 'terminated')) not valid,
  drop constraint if exists partners_contract_status_check,
  add constraint partners_contract_status_check
    check (contract_status in ('not_required', 'not_signed', 'signed', 'terminated')) not valid,
  drop constraint if exists partners_listing_status_check,
  add constraint partners_listing_status_check
    check (listing_status in ('listed', 'hidden', 'opted_out', 'removed')) not valid,
  drop constraint if exists partners_claim_owner_consistency,
  add constraint partners_claim_owner_consistency
    check ((claim_status = 'claimed') = (owner_id is not null)) not valid,
  drop constraint if exists partners_official_contract_consistency,
  add constraint partners_official_contract_consistency
    check (
      partnership_status <> 'official_partner'
      or (claim_status = 'claimed' and contract_status = 'signed')
    ) not valid,
  drop constraint if exists partners_partnership_contract_consistency,
  add constraint partners_partnership_contract_consistency
    check (
      (partnership_status = 'not_requested' and contract_status = 'not_required')
      or (partnership_status = 'requested' and contract_status = 'not_signed')
      or (partnership_status = 'under_review' and contract_status in ('not_signed', 'signed'))
      or (partnership_status = 'official_partner' and contract_status = 'signed')
      or (partnership_status = 'terminated' and contract_status = 'terminated')
    ) not valid;

-- Reconcile current main and either donor if one was ever applied in a disposable
-- or unknown environment. to_jsonb() lets this read donor-only relationship_status
-- without requiring that column to exist on current main.
update public.partners as p
set claim_status = case
      when p.owner_id is not null then 'claimed'
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'claim_invited' then 'claim_invited'
      else 'unclaimed'
    end,
    partnership_status = case
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'partnership_requested' then 'requested'
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'official_partner'
           and coalesce(to_jsonb(p)->>'contract_status', p.contract_status) = 'signed'
           and p.owner_id is not null then 'official_partner'
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'official_partner' then 'under_review'
      when coalesce(p.heha_partner, false) then 'under_review'
      else 'not_requested'
    end,
    contract_status = case
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'official_partner'
           and coalesce(to_jsonb(p)->>'contract_status', p.contract_status) = 'signed'
           and p.owner_id is not null then 'signed'
      when coalesce(to_jsonb(p)->>'relationship_status', '') in ('partnership_requested', 'official_partner')
           or coalesce(p.heha_partner, false) then 'not_signed'
      else 'not_required'
    end,
    listing_status = case
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'opted_out' then 'opted_out'
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'removed' then 'removed'
      when lower(coalesce(p.status, '')) in ('approved', 'live', 'listed') then 'listed'
      when lower(coalesce(p.status, '')) in ('removed', 'rejected') then 'removed'
      else 'hidden'
    end,
    claimed_at = case
      when p.owner_id is not null then coalesce(p.claimed_at, p.created_at, now())
      else null
    end,
    claimed_by = case
      when p.owner_id is not null then coalesce(p.claimed_by, p.owner_id)
      else null
    end,
    partnership_requested_at = case
      when coalesce(to_jsonb(p)->>'relationship_status', '') in ('partnership_requested', 'official_partner')
        then coalesce(p.partnership_requested_at, p.created_at, now())
      else p.partnership_requested_at
    end,
    official_partner_since = case
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'official_partner'
           and coalesce(to_jsonb(p)->>'contract_status', p.contract_status) = 'signed'
           and p.owner_id is not null
        then coalesce(p.official_partner_since, p.created_at, now())
      else p.official_partner_since
    end,
    contract_signed_at = case
      when coalesce(to_jsonb(p)->>'relationship_status', '') = 'official_partner'
           and coalesce(to_jsonb(p)->>'contract_status', p.contract_status) = 'signed'
           and p.owner_id is not null
        then coalesce(p.contract_signed_at, p.created_at, now())
      else p.contract_signed_at
    end;

-- Legacy heha_partner becomes a compatibility mirror, never an independent
-- source of truth. Existing ambiguous true values fail closed to under_review.
update public.partners
set heha_partner = (partnership_status = 'official_partner');

alter table public.partners
  drop constraint if exists partners_legacy_heha_partner_consistency,
  add constraint partners_legacy_heha_partner_consistency
    check (heha_partner = (partnership_status = 'official_partner')) not valid;

alter table public.partners validate constraint partners_claim_status_check;
alter table public.partners validate constraint partners_partnership_status_check;
alter table public.partners validate constraint partners_contract_status_check;
alter table public.partners validate constraint partners_listing_status_check;
alter table public.partners validate constraint partners_claim_owner_consistency;
alter table public.partners validate constraint partners_official_contract_consistency;
alter table public.partners validate constraint partners_partnership_contract_consistency;
alter table public.partners validate constraint partners_legacy_heha_partner_consistency;

-- Retire donor triggers that encode one-field relationship models. The columns,
-- if present from historical donor application, are left intact as evidence.
drop trigger if exists aa_partner_listing_origin on public.partners;
drop function if exists app_private.set_partner_listing_origin();

-- ---------------------------------------------------------------------------
-- 2. Secure claim invitations: exact #117 object name and recipient semantics.
-- ---------------------------------------------------------------------------
create table if not exists public.partner_claim_invites (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  token_hash bytea not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  outreach_channel text,
  intended_user_id uuid references auth.users(id) on delete set null,
  intended_email_normalized text,
  recipient_hint text not null,
  constraint partner_claim_invites_expiry_check check (expires_at > created_at),
  constraint partner_claim_invites_recipient_check check (
    num_nonnulls(intended_user_id, intended_email_normalized) <= 1
  ),
  constraint partner_claim_invites_email_normalized_check check (
    intended_email_normalized is null
    or (
      intended_email_normalized = lower(btrim(intended_email_normalized))
      and length(intended_email_normalized) between 3 and 320
      and position('@' in intended_email_normalized) > 1
    )
  ),
  constraint partner_claim_invites_terminal_state_check check (
    not (consumed_at is not null and revoked_at is not null)
  )
);

alter table public.partner_claim_invites alter column created_by drop not null;
alter table public.partner_claim_invites drop constraint if exists partner_claim_invites_partner_id_fkey;
alter table public.partner_claim_invites add constraint partner_claim_invites_partner_id_fkey
  foreign key (partner_id) references public.partners(id) on delete restrict;
alter table public.partner_claim_invites drop constraint if exists partner_claim_invites_created_by_fkey;
alter table public.partner_claim_invites add constraint partner_claim_invites_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;
alter table public.partner_claim_invites drop constraint if exists partner_claim_invites_intended_user_id_fkey;
alter table public.partner_claim_invites add constraint partner_claim_invites_intended_user_id_fkey
  foreign key (intended_user_id) references auth.users(id) on delete set null;
alter table public.partner_claim_invites drop constraint if exists partner_claim_invites_consumed_by_fkey;
alter table public.partner_claim_invites add constraint partner_claim_invites_consumed_by_fkey
  foreign key (consumed_by) references auth.users(id) on delete set null;
alter table public.partner_claim_invites drop constraint if exists partner_claim_invites_revoked_by_fkey;
alter table public.partner_claim_invites add constraint partner_claim_invites_revoked_by_fkey
  foreign key (revoked_by) references auth.users(id) on delete set null;
alter table public.partner_claim_invites drop constraint if exists partner_claim_invites_recipient_check;
alter table public.partner_claim_invites add constraint partner_claim_invites_recipient_check
  check (num_nonnulls(intended_user_id, intended_email_normalized) <= 1);

create index if not exists partner_claim_invites_partner_id_idx
  on public.partner_claim_invites(partner_id, created_at desc);
create unique index if not exists partner_claim_invites_one_active_per_partner_uidx
  on public.partner_claim_invites(partner_id)
  where consumed_at is null and revoked_at is null;

alter table public.partner_claim_invites enable row level security;
revoke all on table public.partner_claim_invites from public, anon, authenticated, service_role;
grant select on table public.partner_claim_invites to authenticated;
grant select, insert, update, delete on table public.partner_claim_invites to service_role;
drop policy if exists partner_claim_invites_internal_read on public.partner_claim_invites;
create policy partner_claim_invites_internal_read
on public.partner_claim_invites for select to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']::text[]));

-- ---------------------------------------------------------------------------
-- 3. Minimized lifecycle receipts. UUID PK avoids an identity-sequence privilege.
-- ---------------------------------------------------------------------------
create table if not exists public.partner_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  event_type text not null,
  actor_id uuid references auth.users(id) on delete set null,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.partner_lifecycle_events enable row level security;
revoke all on table public.partner_lifecycle_events from public, anon, authenticated, service_role;
grant select on table public.partner_lifecycle_events to authenticated;
grant select, insert on table public.partner_lifecycle_events to service_role;
drop policy if exists partner_lifecycle_internal_read on public.partner_lifecycle_events;
create policy partner_lifecycle_internal_read
on public.partner_lifecycle_events for select to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']::text[]));

create or replace function app_private.partner_lifecycle_receipt(p public.partners)
returns jsonb language sql stable
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'partner_id', p.id,
    'owner_id', p.owner_id,
    'claim_status', p.claim_status,
    'partnership_status', p.partnership_status,
    'contract_status', p.contract_status,
    'listing_status', p.listing_status,
    'heha_partner', p.heha_partner,
    'claimed_at', p.claimed_at,
    'partnership_requested_at', p.partnership_requested_at,
    'official_partner_since', p.official_partner_since,
    'contract_signed_at', p.contract_signed_at,
    'opted_out_at', p.opted_out_at
  );
$$;
revoke all on function app_private.partner_lifecycle_receipt(public.partners) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Protected-state guard and current-main owner guard integration.
-- Contexts are transaction-local and are set only inside non-client-executable
-- app_private functions after their caller-specific checks succeed.
-- ---------------------------------------------------------------------------
create or replace function app_private.guard_hybrid_partner_statuses()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  ctx text := coalesce(current_setting('app.hybrid_partner_context', true), '');
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  if new.claim_status is not distinct from old.claim_status
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
     and new.heha_partner is not distinct from old.heha_partner
     and new.owner_id is not distinct from old.owner_id then
    return new;
  end if;

  if ctx in ('claim', 'owner_release', 'partnership_request', 'partnership_review', 'listing_change') then
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Partner lifecycle fields may only change through approved server workflows.';
end;
$$;
revoke all on function app_private.guard_hybrid_partner_statuses() from public, anon, authenticated;

drop trigger if exists aa_guard_hybrid_partner_statuses on public.partners;
create trigger aa_guard_hybrid_partner_statuses
before update on public.partners
for each row execute function app_private.guard_hybrid_partner_statuses();

-- Current-main owner guard, preserved with two narrow context exceptions.
create or replace function app_private.guard_partner_owner_self_service()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  ctx text := coalesce(current_setting('app.hybrid_partner_context', true), '');
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

  if tg_op = 'UPDATE' and ctx in ('claim', 'owner_release', 'partnership_request', 'partnership_review', 'listing_change', 'owner_profile_rpc') then
    return new;
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
revoke all on function app_private.guard_partner_owner_self_service() from public, anon, authenticated;

-- Account deletion / owner release is safe, auditable, and does not retain stale
-- claim provenance. An Official Partner is downgraded to under_review, preserving
-- signed-contract evidence but removing the public legacy partner flag.
create or replace function app_private.record_partner_owner_release()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare before_receipt jsonb;
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
    insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
    values(old.id,'owner_released',auth.uid(),before_receipt,jsonb_build_object(
      'partner_id',old.id,'owner_id',null,'claim_status','unclaimed',
      'partnership_status',new.partnership_status,'contract_status',new.contract_status,
      'listing_status',new.listing_status,'heha_partner',new.heha_partner));
    return new;
  end if;

  if old.owner_id is null and new.owner_id is not null then
    if current_setting('app.hybrid_partner_context', true) <> 'claim' then
      raise exception using errcode='42501', message='Owner assignment requires a verified claim workflow.';
    end if;
    return new;
  end if;

  if old.owner_id is distinct from new.owner_id then
    raise exception using errcode='42501', message='Direct owner transfer is not allowed.';
  end if;
  return new;
end;
$$;
revoke all on function app_private.record_partner_owner_release() from public, anon, authenticated;
drop trigger if exists a0_hybrid_owner_release_provenance on public.partners;
create trigger a0_hybrid_owner_release_provenance
before update of owner_id on public.partners
for each row execute function app_private.record_partner_owner_release();

-- ---------------------------------------------------------------------------
-- 5. Claim RPCs: #117 names, verified binding, partner-first lock order.
-- ---------------------------------------------------------------------------
create or replace function app_private.apply_verified_partner_claim(
  p_partner_id uuid, p_actor_id uuid, p_claim_time timestamptz
) returns void language plpgsql security definer
set search_path = pg_catalog, public, app_private, pg_temp
as $$
begin
  perform set_config('app.hybrid_partner_context', 'claim', true);
  update public.partners
  set owner_id = p_actor_id,
      claim_status = 'claimed',
      claimed_at = p_claim_time,
      claimed_by = p_actor_id,
      updated_at = p_claim_time
  where id = p_partner_id and owner_id is null;
  if not found then
    raise exception using errcode='23505', message='Partner is already claimed or requires manual reconciliation.';
  end if;
end;
$$;
revoke all on function app_private.apply_verified_partner_claim(uuid,uuid,timestamptz) from public, anon, authenticated, service_role;

create or replace function public.create_partner_claim_invite(
  p_partner_id uuid,
  p_expires_in interval default interval '7 days',
  p_outreach_channel text default null,
  p_intended_user_id uuid default null,
  p_intended_email text default null
) returns table(invite_id uuid, partner_id uuid, raw_token text, expires_at timestamptz, recipient_hint text)
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  p public.partners%rowtype;
  raw text;
  normalized_email text := nullif(lower(btrim(p_intended_email)), '');
  bound_user uuid;
  bound_email text;
  account_email text;
  hint text;
  new_id uuid := gen_random_uuid();
  exp timestamptz;
begin
  if actor_id is null then raise exception using errcode='28000', message='Authentication required.'; end if;
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[]) then
    raise exception using errcode='42501', message='HEHA internal claim-invite access required.';
  end if;
  if p_expires_in is null or p_expires_in < interval '15 minutes' or p_expires_in > interval '30 days' then
    raise exception using errcode='22023', message='Claim invite expiry must be between 15 minutes and 30 days.';
  end if;
  if (p_intended_user_id is null) = (normalized_email is null) then
    raise exception using errcode='22023', message='Provide exactly one intended recipient user or email.';
  end if;
  if normalized_email is not null and (length(normalized_email) > 320 or position('@' in normalized_email) <= 1) then
    raise exception using errcode='22023', message='A valid intended recipient email is required.';
  end if;

  if p_intended_user_id is not null then
    select u.email into account_email from auth.users u where u.id=p_intended_user_id and u.email_confirmed_at is not null;
    if not found then raise exception using errcode='42501', message='Intended recipient account must have a verified email.'; end if;
    bound_user := p_intended_user_id;
  else
    select u.id,u.email into bound_user,account_email
    from auth.users u
    where lower(btrim(u.email))=normalized_email and u.email_confirmed_at is not null
    order by u.created_at asc limit 1;
    if bound_user is null then bound_email:=normalized_email; account_email:=normalized_email; end if;
  end if;
  hint := left(split_part(lower(account_email),'@',1),1)||'***@'||split_part(lower(account_email),'@',2);

  -- Canonical lock order starts with partner.
  select * into p from public.partners where id=p_partner_id for update;
  if not found then raise exception using errcode='P0002', message='Partner profile not found.'; end if;
  if p.owner_id is not null then raise exception using errcode='23505', message='This partner profile is already claimed.'; end if;
  if p.listing_status in ('opted_out','removed') then raise exception using errcode='42501', message='This listing is not eligible for a claim invitation.'; end if;

  update public.partner_claim_invites
  set revoked_at=now(), revoked_by=actor_id
  where partner_id=p_partner_id and consumed_at is null and revoked_at is null;

  raw := encode(extensions.gen_random_bytes(32),'hex');
  exp := now()+p_expires_in;
  insert into public.partner_claim_invites(id,partner_id,token_hash,created_by,expires_at,outreach_channel,intended_user_id,intended_email_normalized,recipient_hint)
  values(new_id,p_partner_id,extensions.digest(raw,'sha256'),actor_id,exp,nullif(btrim(p_outreach_channel),''),bound_user,bound_email,hint);

  perform set_config('app.hybrid_partner_context','claim',true);
  update public.partners set claim_status='claim_invited',updated_at=now() where id=p_partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p_partner_id,'claim_invite_created',actor_id,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p_partner_id,'claim_status','claim_invited','invite_id',new_id,'expires_at',exp));
  return query select new_id,p_partner_id,raw,exp,hint;
end;
$$;

create or replace function public.preview_partner_claim(p_raw_token text)
returns table(partner_id uuid, partner_name text, expires_at timestamptz, claimable boolean)
language plpgsql security definer stable
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
declare i public.partner_claim_invites%rowtype; p public.partners%rowtype; actor_email text;
begin
  if auth.uid() is null then raise exception using errcode='28000', message='Authentication required.'; end if;
  select * into i from public.partner_claim_invites
  where token_hash=extensions.digest(btrim(p_raw_token),'sha256') limit 1;
  if not found or i.consumed_at is not null or i.revoked_at is not null or i.expires_at<=now() then
    raise exception using errcode='P0002', message='This claim link is not valid.';
  end if;
  if i.intended_user_id is null and i.intended_email_normalized is null then
    raise exception using errcode='42501', message='This claim link is no longer valid.';
  end if;
  if i.intended_user_id is not null then
    if i.intended_user_id<>auth.uid() then raise exception using errcode='42501', message='This claim link belongs to a different account.'; end if;
  else
    select lower(btrim(u.email)) into actor_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
    if actor_email is null or actor_email<>i.intended_email_normalized then raise exception using errcode='42501', message='This claim link belongs to a different account.'; end if;
  end if;
  select * into p from public.partners where id=i.partner_id;
  if not found or p.owner_id is not null or p.listing_status in ('opted_out','removed') then
    raise exception using errcode='42501', message='This profile is not claimable.';
  end if;
  return query select p.id,p.name,i.expires_at,true;
end;
$$;

create or replace function public.claim_partner_profile(p_raw_token text)
returns table(partner_id uuid, partner_name text, claim_status text, claimed_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor uuid:=auth.uid(); i public.partner_claim_invites%rowtype; p public.partners%rowtype;
  actor_email text; claim_time timestamptz:=now();
begin
  if actor is null then raise exception using errcode='28000', message='Authentication required.'; end if;
  if nullif(btrim(p_raw_token),'') is null then raise exception using errcode='22023', message='Claim token is required.'; end if;

  -- Unlocked lookup only discovers partner id; no state from it is trusted.
  select * into i from public.partner_claim_invites where token_hash=extensions.digest(btrim(p_raw_token),'sha256');
  if not found then raise exception using errcode='P0002', message='This claim link is not recognized.'; end if;
  select * into p from public.partners where id=i.partner_id for update;
  if not found then raise exception using errcode='P0002', message='Partner profile not found.'; end if;
  select * into i from public.partner_claim_invites where id=i.id for update;
  if not found or i.consumed_at is not null or i.revoked_at is not null or i.expires_at<=claim_time then
    raise exception using errcode='P0002', message='This claim link is not valid.';
  end if;
  if i.intended_user_id is null and i.intended_email_normalized is null then
    raise exception using errcode='42501', message='This claim link is no longer valid.';
  end if;
  if i.intended_user_id is not null then
    if i.intended_user_id<>actor then raise exception using errcode='42501', message='This claim link belongs to a different account.'; end if;
  else
    select lower(btrim(u.email)) into actor_email from auth.users u where u.id=actor and u.email_confirmed_at is not null;
    if actor_email is null or actor_email<>i.intended_email_normalized then raise exception using errcode='42501', message='This claim link belongs to a different account.'; end if;
  end if;
  if p.owner_id is not null or p.claim_status not in ('unclaimed','claim_invited') or p.listing_status in ('opted_out','removed') then
    raise exception using errcode='23505', message='Partner is already claimed or requires manual reconciliation.';
  end if;

  perform app_private.apply_verified_partner_claim(p.id,actor,claim_time);
  update public.partner_claim_invites set consumed_at=claim_time,consumed_by=actor where id=i.id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'claim_redeemed',actor,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'owner_id',actor,'claim_status','claimed','claimed_at',claim_time));
  return query select p.id,p.name,'claimed'::text,claim_time;
end;
$$;

create or replace function public.revoke_partner_claim_invite(p_invite_id uuid)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare actor uuid:=auth.uid(); partner_key uuid; i public.partner_claim_invites%rowtype; p public.partners%rowtype;
begin
  if actor is null then raise exception using errcode='28000', message='Authentication required.'; end if;
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[]) then
    raise exception using errcode='42501', message='HEHA internal claim-invite access required.';
  end if;
  select partner_id into partner_key from public.partner_claim_invites where id=p_invite_id;
  if partner_key is null then return false; end if;
  select * into p from public.partners where id=partner_key for update;
  select * into i from public.partner_claim_invites where id=p_invite_id for update;
  if not found or i.consumed_at is not null or i.revoked_at is not null then return false; end if;
  update public.partner_claim_invites set revoked_at=now(),revoked_by=actor where id=p_invite_id;
  if p.owner_id is null and not exists(
    select 1 from public.partner_claim_invites x where x.partner_id=p.id and x.id<>p_invite_id and x.consumed_at is null and x.revoked_at is null
  ) then
    perform set_config('app.hybrid_partner_context','claim',true);
    update public.partners set claim_status='unclaimed',updated_at=now() where id=p.id;
  end if;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'claim_invite_revoked',actor,app_private.partner_lifecycle_receipt(p),jsonb_build_object('partner_id',p.id,'invite_id',p_invite_id,'revoked',true));
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Partnership-interest evidence from PR #72, adapted to hybrid statuses.
-- ---------------------------------------------------------------------------
create table if not exists public.partner_interest_requests (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  owner_id uuid not null,
  status text not null default 'submitted',
  contact_consent boolean not null default false,
  contact_consent_at timestamptz,
  swipe_card_interest boolean not null default false,
  heha_local_interest boolean not null default false,
  events_interest boolean not null default false,
  interview_interest boolean not null default false,
  contribution_interest boolean not null default false,
  contribution_note text,
  journal_interest boolean not null default false,
  founding_circle_interest boolean not null default false,
  founding_circle_term text,
  certification_interest boolean not null default false,
  starter_items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.partner_interest_requests drop constraint if exists partner_interest_requests_partner_id_fkey;
alter table public.partner_interest_requests add constraint partner_interest_requests_partner_id_fkey
  foreign key(partner_id) references public.partners(id) on delete restrict;
alter table public.partner_interest_requests drop constraint if exists partner_interest_requests_status_check;
alter table public.partner_interest_requests add constraint partner_interest_requests_status_check
  check(status in ('submitted','reviewing','needs_info','converted','closed'));
alter table public.partner_interest_requests drop constraint if exists partner_interest_requests_contact_consent_check;
alter table public.partner_interest_requests add constraint partner_interest_requests_contact_consent_check
  check(contact_consent is true and contact_consent_at is not null);
alter table public.partner_interest_requests drop constraint if exists partner_interest_requests_founding_circle_term_check;
alter table public.partner_interest_requests add constraint partner_interest_requests_founding_circle_term_check check(
  (founding_circle_interest and founding_circle_term in ('3_months','6_months','12_months','open_ended'))
  or (not founding_circle_interest and founding_circle_term is null)
);
alter table public.partner_interest_requests drop constraint if exists partner_interest_requests_starter_items_array_check;
alter table public.partner_interest_requests add constraint partner_interest_requests_starter_items_array_check check(jsonb_typeof(starter_items)='array');
alter table public.partner_interest_requests drop constraint if exists partner_interest_requests_local_starter_items_check;
alter table public.partner_interest_requests add constraint partner_interest_requests_local_starter_items_check check(
  heha_local_interest is false or jsonb_array_length(starter_items) between 3 and 6
);

create index if not exists partner_interest_requests_partner_idx on public.partner_interest_requests(partner_id,created_at desc);
create index if not exists partner_interest_requests_owner_idx on public.partner_interest_requests(owner_id,created_at desc);
create index if not exists partner_interest_requests_status_idx on public.partner_interest_requests(status,created_at desc);
create unique index if not exists partner_interest_requests_one_active_partner_idx
  on public.partner_interest_requests(partner_id) where status in ('submitted','reviewing','needs_info');

alter table public.partner_interest_requests enable row level security;
revoke all on table public.partner_interest_requests from public,anon,authenticated,service_role;
grant select,insert,update on table public.partner_interest_requests to authenticated;
grant select,insert,update,delete on table public.partner_interest_requests to service_role;

create or replace function app_private.guard_partner_interest_request()
returns trigger language plpgsql security definer set search_path=''
as $$
declare actor uuid:=auth.uid(); owner_keys constant text[]:=array[
  'swipe_card_interest','heha_local_interest','events_interest','interview_interest','contribution_interest','contribution_note',
  'journal_interest','founding_circle_interest','founding_circle_term','certification_interest','starter_items','updated_at'
]; internal_keys constant text[]:=array['status','updated_at'];
begin
  if actor is null then
    if tg_op='INSERT' then
      if new.contact_consent and new.contact_consent_at is null then new.contact_consent_at:=pg_catalog.now(); end if;
      new.created_at:=pg_catalog.now(); new.updated_at:=pg_catalog.now();
    else new.updated_at:=pg_catalog.now(); end if;
    return new;
  end if;
  if app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']) then
    if tg_op='UPDATE' then
      new.updated_at:=pg_catalog.now();
      if new.owner_id is distinct from old.owner_id or new.partner_id is distinct from old.partner_id then
        raise exception using errcode='42501',message='Internal users cannot retarget partnership requests.';
      end if;
      if (pg_catalog.to_jsonb(new)-internal_keys) is distinct from (pg_catalog.to_jsonb(old)-internal_keys) then
        raise exception using errcode='42501',message='Internal users may only update partnership request workflow status.';
      end if;
    end if;
    return new;
  end if;
  if tg_op='INSERT' then
    if new.owner_id is distinct from actor or not exists(select 1 from public.partners p where p.id=new.partner_id and p.owner_id=actor and p.claim_status='claimed') then
      raise exception using errcode='42501',message='Partnership requests may only target the signed-in owner''s claimed listing.';
    end if;
    if new.contact_consent is not true then raise exception using errcode='42501',message='Partnership requests require contact consent.'; end if;
    new.status:='submitted'; new.contact_consent_at:=pg_catalog.now(); new.created_at:=pg_catalog.now(); new.updated_at:=pg_catalog.now(); return new;
  end if;
  if old.owner_id is distinct from actor or old.status not in ('submitted','needs_info') then
    raise exception using errcode='42501',message='Partnership request is not editable by this owner.';
  end if;
  if new.status is distinct from old.status or new.owner_id is distinct from old.owner_id or new.partner_id is distinct from old.partner_id then
    raise exception using errcode='42501',message='Owners cannot change partnership request workflow, owner, or target.';
  end if;
  new.updated_at:=pg_catalog.now();
  if (pg_catalog.to_jsonb(new)-owner_keys) is distinct from (pg_catalog.to_jsonb(old)-owner_keys) then
    raise exception using errcode='42501',message='Owners may only update partnership questionnaire fields while open.';
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_partner_interest_request() from public,anon,authenticated;
drop trigger if exists partner_interest_request_guard on public.partner_interest_requests;
create trigger partner_interest_request_guard before insert or update on public.partner_interest_requests
for each row execute function app_private.guard_partner_interest_request();

create or replace function app_private.apply_partner_interest_request_state()
returns trigger language plpgsql security definer set search_path=''
as $$
declare p public.partners;
begin
  select * into p from public.partners where id=new.partner_id for update;
  if p.owner_id is distinct from new.owner_id or p.claim_status<>'claimed' or p.partnership_status not in ('not_requested','terminated') then
    raise exception using errcode='23514',message='Partner is not eligible to request partnership.';
  end if;
  perform pg_catalog.set_config('app.hybrid_partner_context','partnership_request',true);
  update public.partners set partnership_status='requested',contract_status='not_signed',partnership_requested_at=pg_catalog.now(),
    official_partner_since=null,contract_signed_at=null,heha_partner=false,updated_at=pg_catalog.now() where id=new.partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_requested',new.owner_id,app_private.partner_lifecycle_receipt(p),jsonb_build_object(
    'partner_id',p.id,'claim_status','claimed','partnership_status','requested','contract_status','not_signed','listing_status',p.listing_status));
  return new;
end;
$$;
revoke all on function app_private.apply_partner_interest_request_state() from public,anon,authenticated;
drop trigger if exists partner_interest_request_apply_state on public.partner_interest_requests;
create trigger partner_interest_request_apply_state after insert on public.partner_interest_requests
for each row execute function app_private.apply_partner_interest_request_state();

-- RLS is rebuilt idempotently.
drop policy if exists "Owners can view own partner interest requests" on public.partner_interest_requests;
create policy "Owners can view own partner interest requests" on public.partner_interest_requests
for select to authenticated using(owner_id=auth.uid());
drop policy if exists "Owners can submit own partner interest requests" on public.partner_interest_requests;
create policy "Owners can submit own partner interest requests" on public.partner_interest_requests
for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.partners p where p.id=partner_id and p.owner_id=auth.uid() and p.claim_status='claimed'));
drop policy if exists "Owners can update open partner interest requests" on public.partner_interest_requests;
create policy "Owners can update open partner interest requests" on public.partner_interest_requests
for update to authenticated using(owner_id=auth.uid() and status in ('submitted','needs_info'))
with check(owner_id=auth.uid() and status in ('submitted','needs_info'));
drop policy if exists "Internal users can view partner interest requests" on public.partner_interest_requests;
create policy "Internal users can view partner interest requests" on public.partner_interest_requests
for select to authenticated using(app_private.has_internal_role(array['super_admin','pm_admin','developer_admin']));
drop policy if exists "Internal users can update partner interest request status" on public.partner_interest_requests;
create policy "Internal users can update partner interest request status" on public.partner_interest_requests
for update to authenticated using(app_private.has_internal_role(array['super_admin','pm_admin','developer_admin']))
with check(app_private.has_internal_role(array['super_admin','pm_admin','developer_admin']));

-- ---------------------------------------------------------------------------
-- 7. Internal review/approval and listing visibility workflows.
-- ---------------------------------------------------------------------------
create or replace function public.review_partner_partnership(p_partner_id uuid,p_status text)
returns void language plpgsql security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$
declare p public.partners;
begin
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']) then
    raise exception using errcode='42501',message='Internal partnership review required.';
  end if;
  select * into p from public.partners where id=p_partner_id for update;
  if not found then raise exception using errcode='P0002',message='Partner not found.'; end if;
  if p_status='under_review' and p.partnership_status<>'requested' then raise exception using errcode='23514',message='Only requested partnerships may enter review.'; end if;
  if p_status='terminated' and p.partnership_status not in ('requested','under_review','official_partner') then raise exception using errcode='23514',message='Partnership cannot be terminated from current state.'; end if;
  if p_status not in ('under_review','terminated') then raise exception using errcode='22023',message='Invalid review transition.'; end if;
  perform set_config('app.hybrid_partner_context','partnership_review',true);
  update public.partners set partnership_status=p_status,
    contract_status=case when p_status='terminated' then 'terminated' else contract_status end,
    heha_partner=false,updated_at=now() where id=p_partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_reviewed',auth.uid(),app_private.partner_lifecycle_receipt(p),jsonb_build_object(
    'partner_id',p.id,'partnership_status',p_status,'contract_status',case when p_status='terminated' then 'terminated' else p.contract_status end,'heha_partner',false));
end;
$$;

create or replace function public.approve_heha_partnership(p_partner_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare p public.partners; jwt_role text:=coalesce(nullif(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
begin
  if not (jwt_role='service_role' or app_private.has_internal_role(array['super_admin'])) then
    raise exception using errcode='42501',message='Not authorized to approve HEHA partnerships.';
  end if;
  select * into p from public.partners where id=p_partner_id for update;
  if not found or p.claim_status<>'claimed' or p.partnership_status<>'under_review' then
    raise exception using errcode='23514',message='Partner is not in a valid reviewed and claimed state.';
  end if;
  perform pg_catalog.set_config('app.hybrid_partner_context','partnership_review',true);
  update public.partners set partnership_status='official_partner',contract_status='signed',contract_signed_at=pg_catalog.now(),
    official_partner_since=coalesce(official_partner_since,pg_catalog.now()),heha_partner=true,updated_at=pg_catalog.now() where id=p_partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_approved',auth.uid(),app_private.partner_lifecycle_receipt(p),jsonb_build_object(
    'partner_id',p.id,'claim_status','claimed','partnership_status','official_partner','contract_status','signed','heha_partner',true));
end;
$$;

create or replace function public.set_partner_listing_status(p_partner_id uuid,p_listing_status text)
returns void language plpgsql security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$
declare p public.partners;
begin
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']) then
    raise exception using errcode='42501',message='Internal listing review required.';
  end if;
  if p_listing_status not in ('listed','hidden','removed') then raise exception using errcode='22023',message='Invalid internal listing status.'; end if;
  select * into p from public.partners where id=p_partner_id for update;
  perform set_config('app.hybrid_partner_context','listing_change',true);
  update public.partners set listing_status=p_listing_status,
    opted_out_at=case when p_listing_status='listed' then null else opted_out_at end,
    opted_out_by=case when p_listing_status='listed' then null else opted_out_by end,
    updated_at=now() where id=p_partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'listing_status_changed',auth.uid(),app_private.partner_lifecycle_receipt(p),jsonb_build_object('partner_id',p.id,'listing_status',p_listing_status));
end;
$$;

create or replace function public.opt_out_partner_listing(p_partner_id uuid)
returns void language plpgsql security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$
declare p public.partners; actor uuid:=auth.uid();
begin
  select * into p from public.partners where id=p_partner_id for update;
  if actor is null or p.owner_id is distinct from actor or p.claim_status<>'claimed' then
    raise exception using errcode='42501',message='Only the claimed owner may opt out.';
  end if;
  perform set_config('app.hybrid_partner_context','listing_change',true);
  update public.partners set listing_status='opted_out',opted_out_at=now(),opted_out_by=actor,updated_at=now() where id=p_partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'listing_opted_out',actor,app_private.partner_lifecycle_receipt(p),jsonb_build_object('partner_id',p.id,'listing_status','opted_out'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Deterministic function ACLs.
-- ---------------------------------------------------------------------------
revoke all on function public.create_partner_claim_invite(uuid,interval,text,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.preview_partner_claim(text) from public,anon,authenticated,service_role;
revoke all on function public.claim_partner_profile(text) from public,anon,authenticated,service_role;
revoke all on function public.revoke_partner_claim_invite(uuid) from public,anon,authenticated,service_role;
revoke all on function public.review_partner_partnership(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.approve_heha_partnership(uuid) from public,anon,authenticated,service_role;
revoke all on function public.set_partner_listing_status(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.opt_out_partner_listing(uuid) from public,anon,authenticated,service_role;

grant execute on function public.create_partner_claim_invite(uuid,interval,text,uuid,text) to authenticated,service_role;
grant execute on function public.preview_partner_claim(text) to authenticated,service_role;
grant execute on function public.claim_partner_profile(text) to authenticated,service_role;
grant execute on function public.revoke_partner_claim_invite(uuid) to authenticated,service_role;
grant execute on function public.review_partner_partnership(uuid,text) to authenticated,service_role;
grant execute on function public.approve_heha_partnership(uuid) to authenticated,service_role;
grant execute on function public.set_partner_listing_status(uuid,text) to authenticated,service_role;
grant execute on function public.opt_out_partner_listing(uuid) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 9. Public-projection handoff for the combined publication RC.
--
-- The earlier publication-consent migration owns an established 33-column
-- public contract at this point in lexical migration order. PostgreSQL cannot
-- CREATE OR REPLACE that view with the lifecycle donor's reordered 59-column
-- shape, and exposing that wider shape would leak owner, contact, routing and
-- lifecycle data. Keep the consent-aware projection intact here. The final
-- 20260817171238 integration migration is the sole owner of the converged
-- private projection and all three public views.
-- ---------------------------------------------------------------------------
do $publication_projection_handoff$
declare
  expected_columns constant text[] := array[
    'id','created_at','name','category','categories','instagram','website','bio',
    'tags','rating','review_count','distance_text','color','photo_emoji',
    'heha_partner','status','hours','business_type','offerings','neighborhood',
    'tagline','items','image_url','price_range','gallery_urls','partner_type',
    'delivery_days','heha_pillar','local_eligible','local_lane',
    'primary_cta_destination','primary_cta_label','primary_cta_path'
  ]::text[];
  actual_columns text[];
  view_name text;
  view_options text[];
  view_owner oid;
  partner_owner oid;
begin
  if pg_catalog.to_regclass('app_private.partner_publication_projection') is null
     or pg_catalog.to_regclass('public.partner_publication_consent_events') is null then
    raise exception using
      errcode='55000',
      message='Publication-consent donor objects are required before the hybrid lifecycle migration.';
  end if;

  if pg_catalog.has_table_privilege('anon','public.partners','SELECT') then
    raise exception using
      errcode='55000',
      message='anon must not retain raw partner access during the publication handoff.';
  end if;

  select relowner into partner_owner
  from pg_catalog.pg_class
  where oid='public.partners'::regclass;

  foreach view_name in array array[
    'public_partner_directory',
    'public_swipe_partners',
    'public_local_partners'
  ]::text[] loop
    if pg_catalog.to_regclass(pg_catalog.format('public.%I',view_name)) is null then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('Required consent-aware view public.%I is missing.',view_name);
    end if;

    select pg_catalog.array_agg(column_name order by ordinal_position)
    into actual_columns
    from information_schema.columns
    where table_schema='public' and table_name=view_name;

    if actual_columns is distinct from expected_columns then
      raise exception using
        errcode='55000',
        message=pg_catalog.format(
          'Unsafe public.%I column contract before integration handoff: expected %s, found %s',
          view_name,
          expected_columns,
          actual_columns
        );
    end if;

    select reloptions,relowner into view_options,view_owner
    from pg_catalog.pg_class
    where oid=pg_catalog.to_regclass(pg_catalog.format('public.%I',view_name));

    if not ('security_barrier=true'=any(coalesce(view_options,array[]::text[])))
       or 'security_invoker=true'=any(coalesce(view_options,array[]::text[]))
       or view_owner is distinct from partner_owner
       or not pg_catalog.has_table_privilege(
         'anon',pg_catalog.format('public.%I',view_name),'SELECT'
       ) then
      raise exception using
        errcode='55000',
        message=pg_catalog.format(
          'Unsafe consent-aware security/owner/ACL contract for public.%I.',
          view_name
        );
    end if;
  end loop;
end;
$publication_projection_handoff$;

comment on column public.partners.claim_status is 'Profile-control state only: unclaimed, claim_invited, claimed.';
comment on column public.partners.partnership_status is 'HEHA relationship state only; claiming a profile does not imply official partnership.';
comment on column public.partners.contract_status is 'Partner agreement state, independent from claim and public listing.';
comment on column public.partners.listing_status is 'Public visibility state. public_swipe_partners requires listed in addition to legacy review gates.';
comment on column public.partners.heha_partner is 'Deprecated compatibility mirror of partnership_status=official_partner; not an independent source of truth.';
comment on table public.partner_claim_invites is 'Reviewed single-use claim invitation source of truth; raw token is returned once and only SHA-256 is stored.';
comment on table public.partner_interest_requests is 'Consent-bearing owner partnership-interest evidence; not publication, certification, or Local orderability.';
