-- Allow one HEHA Swipe partner to appear in multiple discovery categories while
-- retaining the existing category column as the primary/backward-compatible value.

alter table public.partners
  add column if not exists categories text[] not null default '{}'::text[];

update public.partners
set categories = array[category]
where coalesce(cardinality(categories), 0) = 0
  and nullif(btrim(category), '') is not null;

create index if not exists partners_categories_gin_idx
  on public.partners using gin (categories);

create or replace function app_private.normalize_partner_categories(
  selected_categories text[],
  primary_category text
)
returns text[]
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(array_agg(normalized.category order by normalized.first_position), array[]::text[])
  from (
    select
      btrim(entry.value) as category,
      min(entry.position) as first_position
    from unnest(
      coalesce(selected_categories, array[]::text[])
      || case
           when nullif(btrim(primary_category), '') is not null then array[btrim(primary_category)]
           else array[]::text[]
         end
    ) with ordinality as entry(value, position)
    where nullif(btrim(entry.value), '') is not null
    group by btrim(entry.value)
  ) as normalized;
$$;

revoke all on function app_private.normalize_partner_categories(text[], text)
  from public, anon, authenticated;

create or replace function app_private.partner_completion_pct(partner_row public.partners)
returns integer
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select 10 * (
    case when nullif(btrim(partner_row.name), '') is not null then 1 else 0 end +
    case when coalesce(cardinality(partner_row.categories), 0) > 0
           or nullif(btrim(partner_row.category), '') is not null then 1 else 0 end +
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

revoke all on function app_private.partner_completion_pct(public.partners)
  from public, anon, authenticated;

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
    'categories',
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

    new.categories := app_private.normalize_partner_categories(new.categories, new.category);
    if coalesce(cardinality(new.categories), 0) = 0 then
      raise exception using
        errcode = '23514',
        message = 'Choose at least one business category.';
    end if;
    new.category := new.categories[1];

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

    new.categories := app_private.normalize_partner_categories(new.categories, new.category);
    if coalesce(cardinality(new.categories), 0) = 0 then
      raise exception using
        errcode = '23514',
        message = 'Choose at least one business category.';
    end if;
    new.category := new.categories[1];

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

revoke all on function app_private.guard_partner_owner_self_service()
  from public, anon, authenticated;

create or replace function app_private.guard_partner_profile_change_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  owner_editable_keys constant text[] := array[
    'name',
    'category',
    'categories',
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
    'pricing_notes'
  ];
begin
  -- Backend/service writes do not carry an end-user auth.uid().
  if actor_id is null then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
    end if;
    return new;
  end if;

  -- HEHA technical/admin users may manage the review workflow.
  if app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']) then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
      if new.status in ('approved', 'rejected', 'applied', 'needs_info') and new.reviewed_at is null then
        new.reviewed_at := now();
        new.reviewed_by := actor_id;
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      raise exception using
        errcode = '42501',
        message = 'Partner change requests must belong to the signed-in owner.';
    end if;

    if not exists (
      select 1
      from public.partners p
      where p.id = new.partner_id
        and p.owner_id = actor_id
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partner change requests may only target your own listing.';
    end if;

    if new.proposed_changes is null
       or jsonb_typeof(new.proposed_changes) <> 'object'
       or new.proposed_changes = '{}'::jsonb then
      raise exception using
        errcode = '22023',
        message = 'Partner change requests need at least one proposed profile change.';
    end if;

    if exists (
      select 1
      from jsonb_object_keys(new.proposed_changes) as proposed_key
      where not (proposed_key = any (owner_editable_keys))
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partner change requests may only contain approved business profile fields.';
    end if;

    new.status := 'submitted';
    new.submitted_at := now();
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_note := null;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Partner owners cannot directly modify profile change requests after submission.';
end;
$$;

revoke all on function app_private.guard_partner_profile_change_request()
  from public, anon, authenticated;

-- Existing view columns must retain their current order. The new categories column
-- is appended at the end so CREATE OR REPLACE VIEW remains backward-compatible.
create or replace view public.public_swipe_partners as
select
  id,
  created_at,
  updated_at,
  owner_id,
  name,
  category,
  location,
  contact,
  instagram,
  website,
  bio,
  tags,
  rating,
  review_count,
  distance_text,
  color,
  photo_emoji,
  heha_partner,
  status,
  complete_pct,
  contribution,
  total_swipes,
  total_saves,
  total_profile_views,
  hours,
  google_place_id,
  business_type,
  offerings,
  neighborhood,
  tagline,
  items,
  phone,
  image_url,
  price_range,
  gallery_urls,
  partner_type,
  product_price_policy,
  service_fee_type,
  service_fee_amount,
  delivery_days,
  pricing_notes,
  heha_pillar,
  website_eligible,
  swipe_eligible,
  local_eligible,
  local_lane,
  primary_cta_destination,
  primary_cta_label,
  primary_cta_path,
  routing_status,
  routing_notes,
  routing_updated_by,
  routing_updated_at,
  is_test_record,
  categories
from public.partners
where status = any (array['approved'::text, 'live'::text])
  and coalesce(swipe_eligible, false) = true
  and is_test_record = false;

comment on column public.partners.categories is
  'Ordered discovery categories selected by the partner. The first value is mirrored to category as the primary category for backward compatibility.';
