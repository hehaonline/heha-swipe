-- Partner relationship foundation.
--
-- Business model:
-- * LISTED != PARTNER.
-- * PARTNER != CERTIFIED.
-- * CLAIMED/OWNED != PARTNER.
--
-- HEHA-created directory listings may have owner_id = null. Attaching an owner
-- later is a separate claim/verification workflow and does not change
-- relationship_status by itself.
--
-- Safety:
-- * Existing partner rows receive safe defaults through new column defaults.
-- * No publication status, public views, routing, heha_partner, or certification
--   logic is changed.
-- * Partnership request state is advanced by database triggers only.
-- * Final official partnership approval is service_role/super_admin only.

alter table public.partners
  add column if not exists relationship_status text not null default 'listed_only',
  add column if not exists contract_status text not null default 'not_required',
  add column if not exists partnership_requested_at timestamptz,
  add column if not exists official_partner_since timestamptz,
  add column if not exists contract_signed_at timestamptz;

alter table public.partners
  drop constraint if exists partners_relationship_status_check,
  add constraint partners_relationship_status_check
    check (relationship_status in ('listed_only', 'partnership_requested', 'official_partner'));

alter table public.partners
  drop constraint if exists partners_contract_status_check,
  add constraint partners_contract_status_check
    check (contract_status in ('not_required', 'not_signed', 'signed', 'terminated'));

alter table public.partners
  drop constraint if exists partners_relationship_contract_consistency_check,
  add constraint partners_relationship_contract_consistency_check
    check (
      (
        relationship_status = 'listed_only'
        and contract_status in ('not_required', 'terminated')
      )
      or
      (
        relationship_status = 'partnership_requested'
        and contract_status = 'not_signed'
        and partnership_requested_at is not null
      )
      or
      (
        relationship_status = 'official_partner'
        and contract_status = 'signed'
        and partnership_requested_at is not null
        and official_partner_since is not null
        and contract_signed_at is not null
      )
    );

comment on column public.partners.relationship_status is
  'Relationship state: listed_only, partnership_requested, or official_partner. Separate from publication status and HEHA Certified/heha_partner.';
comment on column public.partners.contract_status is
  'Partner Agreement state for relationship_status. Separate from listing publication and certification.';
comment on column public.partners.owner_id is
  'Nullable claimed-owner link. NULL means no authenticated business owner is attached. Claim approval is separate and does not imply official HEHA partnership.';

create table if not exists public.partner_interest_requests (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
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
  updated_at timestamptz not null default now(),
  constraint partner_interest_requests_status_check
    check (status in ('submitted', 'reviewing', 'needs_info', 'converted', 'closed')),
  constraint partner_interest_requests_contact_consent_check
    check (contact_consent is true and contact_consent_at is not null),
  constraint partner_interest_requests_founding_circle_term_check
    check (
      (
        founding_circle_interest is true
        and founding_circle_term in ('3_months', '6_months', '12_months', 'open_ended')
      )
      or
      (
        founding_circle_interest is false
        and founding_circle_term is null
      )
    ),
  constraint partner_interest_requests_starter_items_array_check
    check (jsonb_typeof(starter_items) = 'array'),
  constraint partner_interest_requests_local_starter_items_check
    check (
      heha_local_interest is false
      or jsonb_array_length(starter_items) between 3 and 6
    )
);

create index if not exists partner_interest_requests_partner_idx
  on public.partner_interest_requests(partner_id, created_at desc);

create index if not exists partner_interest_requests_owner_idx
  on public.partner_interest_requests(owner_id, created_at desc);

create index if not exists partner_interest_requests_status_idx
  on public.partner_interest_requests(status, created_at desc);

alter table public.partner_interest_requests enable row level security;

revoke all on table public.partner_interest_requests from public;
revoke all on table public.partner_interest_requests from anon;
revoke all on table public.partner_interest_requests from authenticated;
grant select, insert, update on table public.partner_interest_requests to authenticated;
grant all on table public.partner_interest_requests to service_role;

comment on table public.partner_interest_requests is
  'Owner-submitted intake requests for voluntary HEHA partnership review. This does not publish, certify, or create orderable HEHA Local menu data.';
comment on column public.partner_interest_requests.contact_consent is
  'Consent for HEHA to contact the business about this partnership request only; not marketing, newsletter, or promotional SMS consent.';
comment on column public.partner_interest_requests.starter_items is
  'HEHA Local intake items only. Not public menu data, not approved, not orderable, and not HEHA Certified.';

create or replace function app_private.guard_partner_interest_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  owner_editable_keys constant text[] := array[
    'swipe_card_interest',
    'heha_local_interest',
    'events_interest',
    'interview_interest',
    'contribution_interest',
    'contribution_note',
    'journal_interest',
    'founding_circle_interest',
    'founding_circle_term',
    'certification_interest',
    'starter_items',
    'updated_at'
  ];
  internal_status_keys constant text[] := array[
    'status',
    'updated_at'
  ];
begin
  if actor_id is null then
    if tg_op = 'INSERT' then
      if new.contact_consent is true and new.contact_consent_at is null then
        new.contact_consent_at := now();
      end if;
      new.created_at := now();
      new.updated_at := now();
    elsif tg_op = 'UPDATE' then
      new.updated_at := now();
    end if;
    return new;
  end if;

  if app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']) then
    if tg_op = 'UPDATE' then
      new.updated_at := now();

      if new.owner_id is distinct from old.owner_id
         or new.partner_id is distinct from old.partner_id then
        raise exception using
          errcode = '42501',
          message = 'Internal users cannot retarget partnership interest requests.';
      end if;

      if (to_jsonb(new) - internal_status_keys) is distinct from (to_jsonb(old) - internal_status_keys) then
        raise exception using
          errcode = '42501',
          message = 'Internal users may only update partnership request workflow status.';
      end if;
    elsif tg_op = 'INSERT' then
      if new.contact_consent is true and new.contact_consent_at is null then
        new.contact_consent_at := now();
      end if;
      new.status := 'submitted';
      new.created_at := now();
      new.updated_at := now();
    end if;

    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      raise exception using
        errcode = '42501',
        message = 'Partnership interest requests must belong to the signed-in owner.';
    end if;

    if not exists (
      select 1
      from public.partners p
      where p.id = new.partner_id
        and p.owner_id = actor_id
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partnership interest requests may only target your own listing.';
    end if;

    if new.contact_consent is not true then
      raise exception using
        errcode = '42501',
        message = 'Partnership interest requests require contact consent.';
    end if;

    new.status := 'submitted';
    new.contact_consent_at := coalesce(new.contact_consent_at, now());
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.owner_id is distinct from actor_id then
      raise exception using
        errcode = '42501',
        message = 'Partnership interest requests may only be updated by the signed-in owner.';
    end if;

    if not (old.status = any (array['submitted', 'needs_info'])) then
      raise exception using
        errcode = '42501',
        message = 'Partnership interest requests are locked after HEHA review begins.';
    end if;

    if new.status is distinct from old.status
       or new.owner_id is distinct from old.owner_id
       or new.partner_id is distinct from old.partner_id then
      raise exception using
        errcode = '42501',
        message = 'Owners cannot change partnership request workflow, owner, or listing target.';
    end if;

    new.updated_at := now();

    if (to_jsonb(new) - owner_editable_keys) is distinct from (to_jsonb(old) - owner_editable_keys) then
      raise exception using
        errcode = '42501',
        message = 'Owners may only update partnership questionnaire fields while the request is open.';
    end if;

    return new;
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_partner_interest_request() from public, anon, authenticated;

drop trigger if exists partner_interest_request_guard on public.partner_interest_requests;
create trigger partner_interest_request_guard
before insert or update on public.partner_interest_requests
for each row
execute function app_private.guard_partner_interest_request();

create or replace function app_private.apply_partner_interest_request_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
begin
  perform pg_catalog.set_config('app.partner_interest_request_context', 'true', true);

  update public.partners
  set relationship_status = 'partnership_requested',
      contract_status = 'not_signed',
      partnership_requested_at = now(),
      updated_at = now()
  where id = new.partner_id
    and owner_id is not distinct from new.owner_id
    and relationship_status = 'listed_only';

  perform pg_catalog.set_config('app.partner_interest_request_context', '', true);

  return new;
end;
$$;

revoke all on function app_private.apply_partner_interest_request_state() from public, anon, authenticated;

drop trigger if exists partner_interest_request_apply_state on public.partner_interest_requests;
create trigger partner_interest_request_apply_state
after insert on public.partner_interest_requests
for each row
execute function app_private.apply_partner_interest_request_state();

drop policy if exists "Owners can view own partner interest requests" on public.partner_interest_requests;
create policy "Owners can view own partner interest requests"
on public.partner_interest_requests
for select
to authenticated
using (owner_id = auth.uid());

drop policy if exists "Owners can submit own partner interest requests" on public.partner_interest_requests;
create policy "Owners can submit own partner interest requests"
on public.partner_interest_requests
for insert
to authenticated
with check (
  owner_id = auth.uid()
  and exists (
    select 1
    from public.partners p
    where p.id = partner_id
      and p.owner_id = auth.uid()
  )
);

drop policy if exists "Owners can update open partner interest requests" on public.partner_interest_requests;
create policy "Owners can update open partner interest requests"
on public.partner_interest_requests
for update
to authenticated
using (
  owner_id = auth.uid()
  and status = any (array['submitted', 'needs_info']::text[])
)
with check (
  owner_id = auth.uid()
  and status = any (array['submitted', 'needs_info']::text[])
  and exists (
    select 1
    from public.partners p
    where p.id = partner_id
      and p.owner_id = auth.uid()
  )
);

drop policy if exists "Internal users can view partner interest requests" on public.partner_interest_requests;
create policy "Internal users can view partner interest requests"
on public.partner_interest_requests
for select
to authenticated
using (app_private.has_internal_role(array['super_admin', 'pm_admin', 'developer_admin']));

drop policy if exists "Internal users can update partner interest request status" on public.partner_interest_requests;
create policy "Internal users can update partner interest request status"
on public.partner_interest_requests
for update
to authenticated
using (app_private.has_internal_role(array['super_admin', 'pm_admin', 'developer_admin']))
with check (app_private.has_internal_role(array['super_admin', 'pm_admin', 'developer_admin']));

create or replace function app_private.guard_partner_owner_self_service()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  preapproval_statuses constant text[] := array['draft', 'submitted', 'pending', 'missing_info'];
  owner_editable_keys constant text[] := array[
    'name',
    'category',
    'location',
    'contact',
    'instagram',
    'website',
    'bio',
    'tags',
    'hours',
    'business_type',
    'offerings',
    'neighborhood',
    'tagline',
    'phone',
    'price_range',
    'delivery_days',
    'pricing_notes',
    'complete_pct',
    'updated_at'
  ];
  relationship_request_keys constant text[] := array[
    'relationship_status',
    'contract_status',
    'partnership_requested_at',
    'updated_at'
  ];
begin
  -- Service-role/backend writes do not carry an end-user auth.uid().
  if actor_id is null then
    return new;
  end if;

  -- Full HEHA technical/admin roles retain protected-field workflows.
  if app_private.has_internal_role(array['super_admin', 'developer_admin']) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- RLS separately requires actor_id = owner_id. Only sanitize the owner's self-service path.
    if new.owner_id is distinct from actor_id then
      return new;
    end if;

    -- Never trust public-client values for HEHA-controlled fields on initial registration.
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
    new.relationship_status := 'listed_only';
    new.contract_status := 'not_required';
    new.partnership_requested_at := null;
    new.official_partner_since := null;
    new.contract_signed_at := null;

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.owner_id = actor_id
     and pg_catalog.current_setting('app.partner_interest_request_context', true) = 'true' then
    if old.relationship_status = 'listed_only'
       and new.relationship_status = 'partnership_requested'
       and new.contract_status = 'not_signed'
       and new.partnership_requested_at is not null
       and new.official_partner_since is not distinct from old.official_partner_since
       and new.contract_signed_at is not distinct from old.contract_signed_at
       and (to_jsonb(new) - relationship_request_keys) is not distinct from (to_jsonb(old) - relationship_request_keys) then
      return new;
    end if;

    raise exception using
      errcode = '42501',
      message = 'Partnership request state can only advance through the partnership interest workflow.';
  end if;

  if tg_op = 'UPDATE' and old.owner_id = actor_id then
    if not (coalesce(old.status, '') = any (preapproval_statuses)) then
      raise exception using
        errcode = '42501',
        message = 'This partner listing is locked from direct owner edits after pre-approval review.';
    end if;

    if new.status is distinct from old.status then
      raise exception using
        errcode = '42501',
        message = 'Partner owners cannot change listing review or publication status.';
    end if;

    -- These two values are system-maintained during an allowed owner profile edit.
    new.complete_pct := app_private.partner_completion_pct(new);
    new.updated_at := now();

    -- Future columns are protected by default. Only keys explicitly removed here are owner-editable.
    if (to_jsonb(new) - owner_editable_keys) is distinct from (to_jsonb(old) - owner_editable_keys) then
      raise exception using
        errcode = '42501',
        message = 'Partner self-service may only change approved business profile fields.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_partner_owner_self_service() from public, anon, authenticated;

comment on function app_private.guard_partner_owner_self_service() is
  'Sanitizes owner-created partner rows and restricts owner direct edits to explicit pre-approval profile fields. Relationship, contract, publication, routing, and certification fields remain backend-controlled.';

create or replace function public.approve_heha_partnership(p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_jwt_role text := coalesce(
    nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
begin
  if not (
    v_jwt_role = 'service_role'
    or app_private.has_internal_role(array['super_admin'])
  ) then
    raise exception 'Not authorized to approve HEHA partnerships'
      using errcode = '42501';
  end if;

  update public.partners
  set relationship_status = 'official_partner',
      contract_status = 'signed',
      contract_signed_at = pg_catalog.now(),
      official_partner_since = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where id = p_partner_id
    and relationship_status = 'partnership_requested'
    and contract_status = 'not_signed';

  if not found then
    raise exception 'Partner is not in a valid partnership-requested state'
      using errcode = '23514';
  end if;
end;
$function$;

revoke execute on function public.approve_heha_partnership(uuid) from public;
revoke execute on function public.approve_heha_partnership(uuid) from anon;
grant execute on function public.approve_heha_partnership(uuid) to authenticated;
grant execute on function public.approve_heha_partnership(uuid) to service_role;

comment on function public.approve_heha_partnership(uuid) is
  'Final official HEHA Partnership approval. service_role/super_admin only; does not publish, certify, or set heha_partner.';
