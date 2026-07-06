-- Partner self-service security foundation.
--
-- Goals:
-- 1. Owner-created partner rows always enter a non-public pending state.
-- 2. Owners may directly edit only explicit profile fields while the listing is pre-approval.
-- 3. HEHA-controlled status, certification, visibility, routing, media, analytics, and pricing fields
--    cannot be changed through direct partner-owner writes.
-- 4. Approved/live/listed and other review/import states are locked from owner direct UPDATE.
--
-- This migration intentionally does not normalize existing partner statuses and does not broaden
-- public discovery. Public visibility remains governed by the existing approved/live views.

create or replace function app_private.partner_completion_pct(partner_row public.partners)
returns integer
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select 10 * (
    case when nullif(btrim(partner_row.name), '') is not null then 1 else 0 end +
    case when nullif(btrim(partner_row.category), '') is not null then 1 else 0 end +
    case when nullif(btrim(partner_row.neighborhood), '') is not null then 1 else 0 end +
    case when nullif(btrim(partner_row.tagline), '') is not null then 1 else 0 end +
    case when nullif(btrim(partner_row.bio), '') is not null then 1 else 0 end +
    case when nullif(btrim(coalesce(partner_row.phone, partner_row.contact)), '') is not null then 1 else 0 end +
    case when nullif(btrim(partner_row.website), '') is not null then 1 else 0 end +
    case when nullif(btrim(partner_row.instagram), '') is not null then 1 else 0 end +
    case when coalesce(cardinality(partner_row.offerings), 0) > 0 then 1 else 0 end +
    case
      when jsonb_typeof(coalesce(partner_row.items, '[]'::jsonb)) = 'array'
        and jsonb_array_length(coalesce(partner_row.items, '[]'::jsonb)) > 0
      then 1 else 0
    end
  );
$$;

revoke all on function app_private.partner_completion_pct(public.partners) from public, anon, authenticated;

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

    return new;
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

drop trigger if exists a_partner_owner_self_service_guard on public.partners;
create trigger a_partner_owner_self_service_guard
before insert or update on public.partners
for each row
execute function app_private.guard_partner_owner_self_service();

-- Tighten the existing owner policies to authenticated users and pre-approval UPDATE states.
drop policy if exists "Owners can insert partner" on public.partners;
create policy "Owners can insert partner"
on public.partners
for insert
to authenticated
with check (auth.uid() = owner_id);

drop policy if exists "Owners can update own partner" on public.partners;
drop policy if exists "Owners can update own preapproval partner profile" on public.partners;
create policy "Owners can update own preapproval partner profile"
on public.partners
for update
to authenticated
using (
  auth.uid() = owner_id
  and coalesce(status, '') = any (array['draft', 'submitted', 'pending', 'missing_info']::text[])
)
with check (
  auth.uid() = owner_id
  and coalesce(status, '') = any (array['draft', 'submitted', 'pending', 'missing_info']::text[])
);

comment on function app_private.guard_partner_owner_self_service() is
  'Sanitizes owner-created partner rows and restricts owner direct edits to explicit pre-approval profile fields. Protected HEHA/admin fields remain backend-controlled.';
