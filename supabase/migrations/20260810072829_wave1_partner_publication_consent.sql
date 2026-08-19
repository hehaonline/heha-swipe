-- Wave 1 partner publication consent foundation.
--
-- Review-only migration. Do not apply to Production until the existing Swipe
-- migration lineage has been reconciled and this migration has passed a
-- disposable-database or confirmed Supabase-branch proof.
--
-- This migration:
--   * keeps partner contact and consent evidence private;
--   * records append-only preparation, publication, and withdrawal events;
--   * binds publication approval to the exact server-captured profile version;
--   * makes partner registration + draft authorization one transaction;
--   * requires current publication authorization before a Catering/PrivateChef
--     listing can be made live;
--   * repairs PrivateChef -> chef routing; and
--   * replaces public partner projections with explicit safe-column allowlists.

-- Compatibility definition for the shared #120 authority primitive. This is
-- intentionally byte-for-byte equivalent in behavior to the later #120
-- CREATE OR REPLACE: authority comes from the database-selected role/session,
-- never caller-writable request.jwt.* settings. The later migration remains
-- the final definition owner in lexical order.
create or replace function app_private.is_service_role_request()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(current_setting('role', true), '') = 'service_role'
      or session_user::text = 'service_role';
$$;

revoke all on function app_private.is_service_role_request()
  from public, anon, authenticated, service_role;

create table public.partner_publication_consent_events (
  id uuid primary key default gen_random_uuid(),
  event_sequence bigint generated always as identity unique,
  partner_id uuid not null references public.partners(id) on delete restrict,
  -- Immutable identity snapshots, deliberately not Auth FKs: deleting an Auth
  -- account must not rewrite historical consent evidence.
  owner_id uuid,
  destination text not null,
  action text not null,
  state text not null,
  authorized_representative_name text not null,
  authorized_representative_title text not null,
  representative_authority_confirmed boolean not null default false,
  profile_preparation_confirmed boolean not null default false,
  authorized_account_contact text not null,
  consent_statement_version text not null,
  evidence_channel text not null,
  evidence_reference text,
  service_areas text[] not null default array[]::text[],
  local_lane text,
  media_permission_confirmed boolean not null default false,
  service_area_attested boolean not null default false,
  profile_snapshot jsonb not null,
  profile_snapshot_hash text not null,
  request_key uuid not null,
  request_payload_hash text not null,
  recorded_by uuid,
  consented_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  constraint partner_publication_consent_destination_check
    check (destination = any (array['heha_swipe', 'heha_local']::text[])),
  constraint partner_publication_consent_action_check
    check (action = any (array['prepare_profile', 'publish_profile']::text[])),
  constraint partner_publication_consent_state_check
    check (state = any (array['granted', 'revoked']::text[])),
  constraint partner_publication_consent_channel_check
    check (evidence_channel = any (array['heha_swipe', 'verified_email', 'admin_record']::text[])),
  constraint partner_publication_consent_local_lane_check
    check (
      (destination = 'heha_local' and local_lane = any (array['chef', 'group_orders']::text[]))
      or (destination = 'heha_swipe' and local_lane is null)
    ),
  constraint partner_publication_consent_name_check
    check (char_length(btrim(authorized_representative_name)) between 2 and 120),
  constraint partner_publication_consent_title_check
    check (char_length(btrim(authorized_representative_title)) between 2 and 120),
  constraint partner_publication_consent_attestations_check
    check (
      state <> 'granted'
      or (representative_authority_confirmed and profile_preparation_confirmed)
    ),
  constraint partner_publication_consent_contact_check
    check (char_length(btrim(authorized_account_contact)) between 3 and 320),
  constraint partner_publication_consent_statement_check
    check (char_length(btrim(consent_statement_version)) between 3 and 80),
  constraint partner_publication_consent_service_area_check
    check (
      cardinality(service_areas) between 0 and 20
      and array_position(service_areas, null) is null
      and char_length(array_to_string(service_areas, '')) between 0 and 2400
      and (destination <> 'heha_local' or cardinality(service_areas) >= 1)
    ),
  constraint partner_publication_consent_evidence_reference_check
    check (
      evidence_reference is null
      or char_length(btrim(evidence_reference)) between 3 and 500
    ),
  constraint partner_publication_consent_snapshot_object_check
    check (jsonb_typeof(profile_snapshot) = 'object'),
  constraint partner_publication_consent_snapshot_hash_check
    check (profile_snapshot_hash ~ '^[0-9a-f]{64}$'),
  constraint partner_publication_consent_request_hash_check
    check (request_payload_hash ~ '^[0-9a-f]{64}$'),
  constraint partner_publication_consent_request_destination_action_key
    unique (request_key, destination, action)
);

comment on table public.partner_publication_consent_events is
  'Private append-only evidence ledger for partner profile preparation, exact-version publication authorization, and withdrawal. Never expose through public partner views.';

alter table public.partner_publication_consent_events enable row level security;

create or replace function app_private.guard_partner_publication_consent_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  raise exception using
    errcode = '42501',
    message = 'Partner publication consent evidence is append-only.';
end;
$function$;

revoke all on function app_private.guard_partner_publication_consent_immutability()
  from public, anon, authenticated, service_role;

drop trigger if exists partner_publication_consent_events_immutable
  on public.partner_publication_consent_events;
create trigger partner_publication_consent_events_immutable
before update or delete on public.partner_publication_consent_events
for each row execute function app_private.guard_partner_publication_consent_immutability();

create index partner_publication_consent_partner_timeline_idx
  on public.partner_publication_consent_events
  (partner_id, destination, action, event_sequence desc);

create index partner_publication_consent_owner_idx
  on public.partner_publication_consent_events(owner_id)
  where owner_id is not null;

revoke all on table public.partner_publication_consent_events from public, anon, authenticated, service_role;
revoke all on sequence public.partner_publication_consent_events_event_sequence_seq
  from public, anon, authenticated, service_role;
grant select on table public.partner_publication_consent_events to service_role;

drop policy if exists "Owners can view own partner publication consent" on public.partner_publication_consent_events;
drop policy if exists "Internal users can view partner publication consent" on public.partner_publication_consent_events;

-- The evidence rows contain private account contacts, representative identity,
-- evidence references, and immutable history. Browser roles never read the
-- ledger directly, including the current or a former owner. Owners receive only
-- the redacted, current-owner-scoped status returned by
-- get_my_partner_publication_status().

create or replace function app_private.is_wave1_food_partner(p_partner public.partners)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select
    lower(coalesce(p_partner.category, '')) in ('catering', 'privatechef', 'private chef')
    or exists (
      select 1
      from unnest(coalesce(p_partner.categories, array[]::text[])) as c(value)
      where lower(c.value) in ('catering', 'privatechef', 'private chef')
    );
$function$;

create or replace function app_private.is_supported_swipe_partner(p_partner public.partners)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select
    lower(coalesce(p_partner.category, '')) = any (
      array['restaurant','vendor','catering','privatechef','private chef','wellness','coach','service','events']::text[]
    )
    or exists (
      select 1
      from unnest(coalesce(p_partner.categories, array[]::text[])) as c(value)
      where lower(c.value) = any (
        array['restaurant','vendor','catering','privatechef','private chef','wellness','coach','service','events']::text[]
      )
    );
$function$;

create or replace function app_private.wave1_local_lane(p_partner public.partners)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    when lower(coalesce(p_partner.category, '')) in ('privatechef', 'private chef') then 'chef'
    when lower(coalesce(p_partner.category, '')) = 'catering' then 'group_orders'
    else (
      select case
        when lower(c.value) in ('privatechef', 'private chef') then 'chef'
        when lower(c.value) = 'catering' then 'group_orders'
        else null
      end
      from unnest(coalesce(p_partner.categories, array[]::text[]))
        with ordinality as c(value, position)
      where lower(c.value) in ('catering', 'privatechef', 'private chef')
      order by c.position
      limit 1
    )
  end;
$function$;

create or replace function app_private.partner_public_profile_snapshot(p_partner public.partners)
returns jsonb
language sql
immutable
set search_path = ''
as $function$
  select jsonb_build_object(
    'name', nullif(btrim(p_partner.name), ''),
    'category', p_partner.category,
    'categories', coalesce(p_partner.categories, array[]::text[]),
    'neighborhood', nullif(btrim(coalesce(p_partner.neighborhood, '')), ''),
    'tagline', nullif(btrim(coalesce(p_partner.tagline, '')), ''),
    'bio', nullif(btrim(coalesce(p_partner.bio, '')), ''),
    'tags', coalesce(p_partner.tags, array[]::text[]),
    'hours', nullif(btrim(coalesce(p_partner.hours, '')), ''),
    'business_type', nullif(btrim(coalesce(p_partner.business_type, '')), ''),
    'offerings', coalesce(p_partner.offerings, array[]::text[]),
    'website', nullif(btrim(coalesce(p_partner.website, '')), ''),
    'instagram', nullif(btrim(coalesce(p_partner.instagram, '')), ''),
    'items', case
      when app_private.is_wave1_food_partner(p_partner) then '[]'::jsonb
      else coalesce(p_partner.items, '[]'::jsonb)
    end,
    'photo_emoji', nullif(btrim(coalesce(p_partner.photo_emoji, '')), ''),
    'color', nullif(btrim(coalesce(p_partner.color, '')), ''),
    'image_url', nullif(btrim(coalesce(p_partner.image_url, '')), ''),
    'gallery_urls', coalesce(p_partner.gallery_urls, '[]'::jsonb),
    'price_range', case
      when app_private.is_wave1_food_partner(p_partner) then null
      else nullif(btrim(coalesce(p_partner.price_range, '')), '')
    end,
    'delivery_days', coalesce(p_partner.delivery_days, array[]::text[])
  );
$function$;

create or replace function app_private.partner_public_profile_hash(p_partner public.partners)
returns text
language sql
immutable
set search_path = ''
as $function$
  select pg_catalog.encode(
    extensions.digest(app_private.partner_public_profile_snapshot(p_partner)::text, 'sha256'),
    'hex'
  );
$function$;

revoke all on function app_private.is_wave1_food_partner(public.partners) from public, anon, authenticated;
revoke all on function app_private.is_supported_swipe_partner(public.partners) from public, anon, authenticated;
revoke all on function app_private.wave1_local_lane(public.partners) from public, anon, authenticated;
revoke all on function app_private.partner_public_profile_snapshot(public.partners) from public, anon, authenticated;
revoke all on function app_private.partner_public_profile_hash(public.partners) from public, anon, authenticated;

create or replace function app_private.latest_partner_consent_event(
  p_partner_id uuid,
  p_destination text,
  p_action text
)
returns public.partner_publication_consent_events
language sql
stable
security definer
set search_path = ''
as $function$
  select e
  from public.partner_publication_consent_events e
  where e.partner_id = p_partner_id
    and e.destination = p_destination
    and e.action = p_action
  order by e.event_sequence desc
  limit 1;
$function$;

revoke all on function app_private.latest_partner_consent_event(uuid, text, text)
  from public, anon, authenticated;

create or replace function app_private.has_current_partner_publication_authorization(
  p_partner public.partners,
  p_destination text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_prepare public.partner_publication_consent_events;
  v_publish public.partner_publication_consent_events;
  v_snapshot jsonb;
  v_snapshot_hash text;
  v_lane text;
begin
  if p_destination <> all (array['heha_swipe', 'heha_local']::text[]) then
    return false;
  end if;
  if p_destination = 'heha_swipe'
     and app_private.is_supported_swipe_partner(p_partner) is not true then
    return false;
  end if;
  if p_destination = 'heha_local'
     and app_private.is_wave1_food_partner(p_partner) is not true then
    return false;
  end if;

  v_prepare := app_private.latest_partner_consent_event(
    p_partner.id,
    p_destination,
    'prepare_profile'
  );
  v_publish := app_private.latest_partner_consent_event(
    p_partner.id,
    p_destination,
    'publish_profile'
  );
  if v_prepare.id is null
     or v_prepare.state <> 'granted'
     or v_prepare.representative_authority_confirmed is not true
     or v_prepare.profile_preparation_confirmed is not true
     or v_prepare.media_permission_confirmed is not true
     or v_publish.id is null
     or v_publish.state <> 'granted'
     or v_publish.representative_authority_confirmed is not true
     or v_publish.profile_preparation_confirmed is not true
     or v_publish.media_permission_confirmed is not true then
    return false;
  end if;
  if p_destination = 'heha_local' then
    v_lane := app_private.wave1_local_lane(p_partner);
    if v_prepare.service_area_attested is not true
       or v_lane is null
       or v_prepare.local_lane is distinct from v_lane
       or v_publish.local_lane is distinct from v_lane then
      return false;
    end if;
  end if;

  v_snapshot := app_private.partner_public_profile_snapshot(p_partner);
  v_snapshot_hash := app_private.partner_public_profile_hash(p_partner);
  return v_publish.profile_snapshot_hash = v_snapshot_hash
    and v_publish.profile_snapshot = v_snapshot
    and v_prepare.owner_id is not distinct from p_partner.owner_id
    and v_publish.owner_id is not distinct from p_partner.owner_id;
end;
$function$;

create or replace function app_private.has_partner_publication_permission_history(
  p_partner_id uuid,
  p_destination text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.partner_publication_consent_events e
    where e.partner_id = p_partner_id
      and e.destination = p_destination
  );
$function$;

create or replace function app_private.has_any_partner_publication_permission_history(
  p_partner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.partner_publication_consent_events e
    where e.partner_id = p_partner_id
  );
$function$;

create or replace function app_private.is_specific_local_partner_path(p_path text)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select coalesce(
    p_path ~ '^/(restaurants|vendors|market|chef)/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}([?].*)?$'
    or p_path ~ '^/chef/match[?]swipePartnerId=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}&service=(private_chef|catering)$',
    false
  );
$function$;

create or replace function app_private.is_specific_wave1_local_partner_path(
  p_path text,
  p_swipe_partner_id uuid,
  p_lane text
)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select coalesce(case p_lane
    when 'chef' then
      pg_catalog.split_part(p_path, '?', 1) = '/chef/' || p_swipe_partner_id::text
      or p_path = '/chef/match?swipePartnerId=' || p_swipe_partner_id::text || '&service=private_chef'
    when 'group_orders' then
      p_path = '/chef/match?swipePartnerId=' || p_swipe_partner_id::text || '&service=catering'
    else false
  end, false);
$function$;

revoke all on function app_private.has_current_partner_publication_authorization(public.partners, text)
  from public, anon, authenticated;
revoke all on function app_private.has_partner_publication_permission_history(uuid, text)
  from public, anon, authenticated;
revoke all on function app_private.has_any_partner_publication_permission_history(uuid)
  from public, anon, authenticated;
revoke all on function app_private.is_specific_local_partner_path(text)
  from public, anon, authenticated;
revoke all on function app_private.is_specific_wave1_local_partner_path(text, uuid, text)
  from public, anon, authenticated;

drop function if exists public.submit_partner_registration_with_consent(
  uuid, text, text[], text, text, text, text, text[], text, text, text,
  text, text, text, text[], jsonb, text, text, text[], text, text,
  boolean, boolean, text
);

create or replace function public.submit_partner_registration_with_consent(
  p_submission_key uuid,
  p_name text,
  p_categories text[],
  p_neighborhood text,
  p_tagline text,
  p_bio text,
  p_hours text default null,
  p_delivery_days text[] default array[]::text[],
  p_business_type text default null,
  p_phone text default null,
  p_contact text default null,
  p_website text default null,
  p_instagram text default null,
  p_location text default null,
  p_offerings text[] default array[]::text[],
  p_items jsonb default '[]'::jsonb,
  p_photo_emoji text default '🏪',
  p_color text default '#ff8a24',
  p_destinations text[] default array[]::text[],
  p_authorized_representative_name text default null,
  p_authorized_representative_title text default null,
  p_authority_confirmed boolean default false,
  p_profile_confirmed boolean default false,
  p_media_permission_confirmed boolean default false,
  p_tampa_bay_service_confirmed boolean default false,
  p_consent_statement_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_account_contact text;
  v_categories text[];
  v_destinations text[];
  v_partner public.partners;
  v_existing public.partners;
  v_existing_event public.partner_publication_consent_events;
  v_destination text;
  v_lane text;
  v_snapshot jsonb;
  v_snapshot_hash text;
  v_request_payload_hash text;
begin
  if v_actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in before submitting a partner registration.';
  end if;
  select coalesce(
    case when u.email_confirmed_at is not null then nullif(btrim(u.email), '') end,
    case when u.phone_confirmed_at is not null then nullif(btrim(u.phone), '') end
  )
  into v_account_contact
  from auth.users u
  where u.id = v_actor_id;
  if p_submission_key is null then
    raise exception using errcode = '22023', message = 'A submission key is required.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_submission_key::text, 0)
  );

  v_categories := app_private.normalize_partner_categories(p_categories, null);
  if cardinality(v_categories) = 0 then
    raise exception using errcode = '23514', message = 'Choose at least one business category.';
  end if;
  if exists (
    select 1 from unnest(v_categories) as c(value)
    where c.value <> all (array['Restaurant','Vendor','Catering','PrivateChef','Wellness','Coach','Service','Events']::text[])
  ) then
    raise exception using errcode = '23514', message = 'One or more business categories are not supported.';
  end if;

  select coalesce(array_agg(distinct d.value order by d.value), array[]::text[])
  into v_destinations
  from unnest(coalesce(p_destinations, array[]::text[])) as d(value)
  where d.value = any (array['heha_swipe', 'heha_local']::text[]);

  if cardinality(v_destinations) = 0
     or cardinality(v_destinations) <> cardinality(coalesce(p_destinations, array[]::text[])) then
    raise exception using errcode = '23514', message = 'Choose at least one valid HEHA destination.';
  end if;

  v_request_payload_hash := pg_catalog.encode(
    extensions.digest(
      jsonb_build_object(
        'name', btrim(coalesce(p_name, '')),
        'categories', v_categories,
        'neighborhood', btrim(coalesce(p_neighborhood, '')),
        'tagline', btrim(coalesce(p_tagline, '')),
        'bio', btrim(coalesce(p_bio, '')),
        'hours', nullif(btrim(coalesce(p_hours, '')), ''),
        'delivery_days', coalesce(p_delivery_days, array[]::text[]),
        'business_type', nullif(btrim(coalesce(p_business_type, '')), ''),
        'phone', nullif(btrim(coalesce(p_phone, '')), ''),
        'contact', nullif(btrim(coalesce(p_contact, '')), ''),
        'website', nullif(btrim(coalesce(p_website, '')), ''),
        'instagram', nullif(btrim(coalesce(p_instagram, '')), ''),
        'location', nullif(btrim(coalesce(p_location, '')), ''),
        'offerings', coalesce(p_offerings, array[]::text[]),
        'items', coalesce(p_items, '[]'::jsonb),
        'photo_emoji', nullif(btrim(coalesce(p_photo_emoji, '')), ''),
        'color', nullif(btrim(coalesce(p_color, '')), ''),
        'destinations', v_destinations,
        'representative_name', btrim(coalesce(p_authorized_representative_name, '')),
        'representative_title', btrim(coalesce(p_authorized_representative_title, '')),
        'authority_confirmed', coalesce(p_authority_confirmed, false),
        'profile_confirmed', coalesce(p_profile_confirmed, false),
        'media_permission', coalesce(p_media_permission_confirmed, false),
        'tampa_bay_service_confirmed', coalesce(p_tampa_bay_service_confirmed, false),
        'statement_version', p_consent_statement_version
      )::text,
      'sha256'
    ),
    'hex'
  );

  select * into v_existing_event
  from public.partner_publication_consent_events e
  where e.request_key = p_submission_key
    and e.action = 'prepare_profile'
  order by e.recorded_at desc
  limit 1;

  if found then
    if v_existing_event.owner_id is distinct from v_actor_id
       or v_existing_event.request_payload_hash is distinct from v_request_payload_hash then
      raise exception using errcode = '23505', message = 'This submission key was already used with different registration details.';
    end if;
    select * into v_existing from public.partners where id = v_existing_event.partner_id;
    return jsonb_build_object(
      'id', v_existing.id,
      'name', v_existing.name,
      'category', v_existing.category,
      'categories', v_existing.categories,
      'status', v_existing.status,
      'created_at', v_existing.created_at,
      'updated_at', v_existing.updated_at,
      'complete_pct', v_existing.complete_pct,
      'heha_partner', v_existing.heha_partner,
      'public_profile_snapshot', app_private.partner_public_profile_snapshot(v_existing),
      'public_profile_snapshot_hash', app_private.partner_public_profile_hash(v_existing)
    );
  end if;

  if 'heha_local' = any (v_destinations)
     and not exists (
       select 1 from unnest(v_categories) as c(value)
       where lower(c.value) in ('catering', 'privatechef', 'private chef')
     ) then
    raise exception using errcode = '23514', message = 'HEHA Local is currently available here for catering and private-chef profiles.';
  end if;

  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 160
     or char_length(btrim(coalesce(p_neighborhood, ''))) not between 2 and 160
     or char_length(btrim(coalesce(p_tagline, ''))) not between 2 and 80
     or char_length(btrim(coalesce(p_bio, ''))) not between 10 and 4000 then
    raise exception using errcode = '23514', message = 'Complete the required business profile fields.';
  end if;
  if char_length(btrim(coalesce(p_authorized_representative_name, ''))) not between 2 and 120
     or char_length(btrim(coalesce(p_authorized_representative_title, ''))) not between 2 and 120 then
    raise exception using errcode = '23514', message = 'Add the authorized representative name and role.';
  end if;
  if v_account_contact is null then
    raise exception using errcode = '23514', message = 'A verified account email or phone is required to record authorization.';
  end if;
  if p_authority_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm that you are authorized to represent this business.';
  end if;
  if p_profile_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm that HEHA may prepare this private profile for review.';
  end if;
  if p_media_permission_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm permission to use business media supplied to HEHA.';
  end if;
  if 'heha_local' = any (v_destinations)
     and p_tampa_bay_service_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm that this chef/catering business accepts requests in Tampa Bay.';
  end if;
  if p_consent_statement_version is distinct from 'wave1-profile-consent-2026-08-10' then
    raise exception using errcode = '23514', message = 'The current partner profile consent statement must be accepted.';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 50
     or cardinality(coalesce(p_offerings, array[]::text[])) > 50
     or cardinality(coalesce(p_delivery_days, array[]::text[])) > 7 then
    raise exception using errcode = '23514', message = 'The submitted profile contains too many items, offerings, or delivery days.';
  end if;

  insert into public.partners (
    owner_id,
    name,
    category,
    categories,
    neighborhood,
    tagline,
    bio,
    hours,
    delivery_days,
    business_type,
    phone,
    contact,
    website,
    instagram,
    location,
    offerings,
    items,
    photo_emoji,
    color,
    status,
    heha_partner
  ) values (
    v_actor_id,
    btrim(p_name),
    v_categories[1],
    v_categories,
    btrim(p_neighborhood),
    btrim(p_tagline),
    btrim(p_bio),
    nullif(btrim(coalesce(p_hours, '')), ''),
    coalesce(p_delivery_days, array[]::text[]),
    nullif(btrim(coalesce(p_business_type, '')), ''),
    nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_contact, '')), ''),
    nullif(btrim(coalesce(p_website, '')), ''),
    nullif(btrim(coalesce(p_instagram, '')), ''),
    nullif(btrim(coalesce(p_location, '')), ''),
    coalesce(p_offerings, array[]::text[]),
    coalesce(p_items, '[]'::jsonb),
    nullif(btrim(coalesce(p_photo_emoji, '')), ''),
    nullif(btrim(coalesce(p_color, '')), ''),
    'pending',
    false
  ) returning * into v_partner;

  v_lane := app_private.wave1_local_lane(v_partner);
  v_snapshot := app_private.partner_public_profile_snapshot(v_partner);
  v_snapshot_hash := app_private.partner_public_profile_hash(v_partner);

  foreach v_destination in array v_destinations loop
    insert into public.partner_publication_consent_events (
      partner_id,
      owner_id,
      destination,
      action,
      state,
      authorized_representative_name,
      authorized_representative_title,
      representative_authority_confirmed,
      profile_preparation_confirmed,
      authorized_account_contact,
      consent_statement_version,
      evidence_channel,
      service_areas,
      local_lane,
      media_permission_confirmed,
      service_area_attested,
      profile_snapshot,
      profile_snapshot_hash,
      request_key,
      request_payload_hash,
      recorded_by
    ) values (
      v_partner.id,
      v_actor_id,
      v_destination,
      'prepare_profile',
      'granted',
      btrim(p_authorized_representative_name),
      btrim(p_authorized_representative_title),
      true,
      true,
      v_account_contact,
      p_consent_statement_version,
      'heha_swipe',
      case when v_destination = 'heha_local' then array['Tampa Bay']::text[] else array[]::text[] end,
      case when v_destination = 'heha_local' then v_lane else null end,
      true,
      case when v_destination = 'heha_local' then coalesce(p_tampa_bay_service_confirmed, false) else false end,
      v_snapshot,
      v_snapshot_hash,
      p_submission_key,
      v_request_payload_hash,
      v_actor_id
    );
  end loop;

  return jsonb_build_object(
    'id', v_partner.id,
    'name', v_partner.name,
    'category', v_partner.category,
    'categories', v_partner.categories,
    'status', v_partner.status,
    'created_at', v_partner.created_at,
    'updated_at', v_partner.updated_at,
    'complete_pct', v_partner.complete_pct,
    'heha_partner', v_partner.heha_partner,
    'public_profile_snapshot', v_snapshot,
    'public_profile_snapshot_hash', v_snapshot_hash
  );
end;
$function$;

revoke all on function public.submit_partner_registration_with_consent(
  uuid, text, text[], text, text, text, text, text[], text, text, text,
  text, text, text, text[], jsonb, text, text, text[], text, text,
  boolean, boolean, boolean, boolean, text
) from public, anon, authenticated, service_role;
grant execute on function public.submit_partner_registration_with_consent(
  uuid, text, text[], text, text, text, text, text[], text, text, text,
  text, text, text, text[], jsonb, text, text, text[], text, text,
  boolean, boolean, boolean, boolean, text
) to authenticated;

drop function if exists public.authorize_existing_partner_profile_preparation(
  uuid, text[], text, text, boolean, boolean, uuid, text
);

create or replace function public.authorize_existing_partner_profile_preparation(
  p_partner_id uuid,
  p_destinations text[],
  p_authorized_representative_name text,
  p_authorized_representative_title text,
  p_authority_confirmed boolean,
  p_profile_confirmed boolean,
  p_media_permission_confirmed boolean,
  p_tampa_bay_service_confirmed boolean,
  p_request_key uuid,
  p_consent_statement_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_account_contact text;
  v_partner public.partners;
  v_destinations text[];
  v_destination text;
  v_lane text;
  v_snapshot jsonb;
  v_snapshot_hash text;
  v_request_payload_hash text;
  v_existing_event public.partner_publication_consent_events;
begin
  if v_actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in before authorizing profile preparation.';
  end if;
  if p_partner_id is null or p_request_key is null then
    raise exception using errcode = '22023', message = 'Partner and request keys are required.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );

  select coalesce(
    case when u.email_confirmed_at is not null then nullif(btrim(u.email), '') end,
    case when u.phone_confirmed_at is not null then nullif(btrim(u.phone), '') end
  )
  into v_account_contact
  from auth.users u
  where u.id = v_actor_id;

  select * into v_partner
  from public.partners
  where id = p_partner_id and owner_id = v_actor_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'This partner profile is not owned by the signed-in account.';
  end if;
  select coalesce(array_agg(distinct d.value order by d.value), array[]::text[])
  into v_destinations
  from unnest(coalesce(p_destinations, array[]::text[])) as d(value)
  where d.value = any (array['heha_swipe', 'heha_local']::text[]);
  if cardinality(v_destinations) = 0
     or cardinality(v_destinations) <> cardinality(coalesce(p_destinations, array[]::text[])) then
    raise exception using errcode = '23514', message = 'Choose at least one valid HEHA destination.';
  end if;
  if 'heha_swipe' = any (v_destinations)
     and app_private.is_supported_swipe_partner(v_partner) is not true then
    raise exception using errcode = '23514', message = 'This profile category is not supported for HEHA Swipe publication.';
  end if;
  if 'heha_local' = any (v_destinations)
     and app_private.is_wave1_food_partner(v_partner) is not true then
    raise exception using errcode = '23514', message = 'HEHA Local is currently available here for catering and private-chef profiles.';
  end if;
  if char_length(btrim(coalesce(p_authorized_representative_name, ''))) not between 2 and 120
     or char_length(btrim(coalesce(p_authorized_representative_title, ''))) not between 2 and 120
     or v_account_contact is null then
    raise exception using errcode = '23514', message = 'A verified authorized representative is required.';
  end if;
  if p_media_permission_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm permission to use business media supplied to HEHA.';
  end if;
  if p_authority_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm that you are authorized to represent this business.';
  end if;
  if p_profile_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm that HEHA may prepare this private profile for review.';
  end if;
  if 'heha_local' = any (v_destinations)
     and p_tampa_bay_service_confirmed is not true then
    raise exception using errcode = '23514', message = 'Confirm that this business accepts requests in Tampa Bay.';
  end if;
  if p_consent_statement_version is distinct from 'wave1-profile-consent-2026-08-10' then
    raise exception using errcode = '23514', message = 'The current partner profile permission statement must be accepted.';
  end if;

  v_request_payload_hash := pg_catalog.encode(
    extensions.digest(
      jsonb_build_object(
        'partner_id', v_partner.id,
        'destinations', v_destinations,
        'representative_name', btrim(p_authorized_representative_name),
        'representative_title', btrim(p_authorized_representative_title),
        'authority_confirmed', p_authority_confirmed,
        'profile_confirmed', p_profile_confirmed,
        'media_permission', p_media_permission_confirmed,
        'tampa_bay_service_confirmed', p_tampa_bay_service_confirmed,
        'statement_version', p_consent_statement_version
      )::text,
      'sha256'
    ),
    'hex'
  );

  select * into v_existing_event
  from public.partner_publication_consent_events
  where request_key = p_request_key and action = 'prepare_profile'
  order by event_sequence desc
  limit 1;
  if found then
    if v_existing_event.owner_id is distinct from v_actor_id
       or v_existing_event.partner_id is distinct from v_partner.id
       or v_existing_event.request_payload_hash is distinct from v_request_payload_hash then
      raise exception using errcode = '23505', message = 'This preparation request key was already used with different details.';
    end if;
    return jsonb_build_object(
      'partner_id', v_partner.id,
      'state', 'profile_preparation_authorized',
      'destinations', v_destinations,
      'profile_snapshot', v_existing_event.profile_snapshot,
      'profile_snapshot_hash', v_existing_event.profile_snapshot_hash
    );
  end if;

  v_lane := app_private.wave1_local_lane(v_partner);
  v_snapshot := app_private.partner_public_profile_snapshot(v_partner);
  v_snapshot_hash := app_private.partner_public_profile_hash(v_partner);
  foreach v_destination in array v_destinations loop
    insert into public.partner_publication_consent_events (
      partner_id,
      owner_id,
      destination,
      action,
      state,
      authorized_representative_name,
      authorized_representative_title,
      representative_authority_confirmed,
      profile_preparation_confirmed,
      authorized_account_contact,
      consent_statement_version,
      evidence_channel,
      evidence_reference,
      service_areas,
      local_lane,
      media_permission_confirmed,
      service_area_attested,
      profile_snapshot,
      profile_snapshot_hash,
      request_key,
      request_payload_hash,
      recorded_by
    ) values (
      v_partner.id,
      v_actor_id,
      v_destination,
      'prepare_profile',
      'granted',
      btrim(p_authorized_representative_name),
      btrim(p_authorized_representative_title),
      true,
      true,
      v_account_contact,
      p_consent_statement_version,
      'heha_swipe',
      'owner-authorized-existing-profile-preparation',
      case when v_destination = 'heha_local' then array['Tampa Bay']::text[] else array[]::text[] end,
      case when v_destination = 'heha_local' then v_lane else null end,
      true,
      case when v_destination = 'heha_local' then true else false end,
      v_snapshot,
      v_snapshot_hash,
      p_request_key,
      v_request_payload_hash,
      v_actor_id
    );
  end loop;

  return jsonb_build_object(
    'partner_id', v_partner.id,
    'state', 'profile_preparation_authorized',
    'destinations', v_destinations,
    'profile_snapshot', v_snapshot,
    'profile_snapshot_hash', v_snapshot_hash
  );
end;
$function$;

revoke all on function public.authorize_existing_partner_profile_preparation(
  uuid, text[], text, text, boolean, boolean, boolean, boolean, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.authorize_existing_partner_profile_preparation(
  uuid, text[], text, text, boolean, boolean, boolean, boolean, uuid, text
) to authenticated;

create or replace function public.authorize_partner_profile_publication(
  p_partner_id uuid,
  p_destinations text[],
  p_authorized_representative_name text,
  p_authorized_representative_title text,
  p_request_key uuid,
  p_consent_statement_version text,
  p_expected_profile_snapshot_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_account_contact text;
  v_partner public.partners;
  v_destinations text[];
  v_destination text;
  v_prepare public.partner_publication_consent_events;
  v_snapshot jsonb;
  v_snapshot_hash text;
  v_lane text;
  v_request_payload_hash text;
  v_existing_event public.partner_publication_consent_events;
begin
  if v_actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in before authorizing publication.';
  end if;
  select coalesce(
    case when u.email_confirmed_at is not null then nullif(btrim(u.email), '') end,
    case when u.phone_confirmed_at is not null then nullif(btrim(u.phone), '') end
  )
  into v_account_contact
  from auth.users u
  where u.id = v_actor_id;
  if p_partner_id is null or p_request_key is null then
    raise exception using errcode = '22023', message = 'Partner and request keys are required.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );

  select * into v_partner
  from public.partners
  where id = p_partner_id and owner_id = v_actor_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'This partner profile is not owned by the signed-in account.';
  end if;
  if coalesce(v_partner.status, '') <> all (
    array['draft','submitted','pending','missing_info','approved','listed','live']::text[]
  ) then
    raise exception using errcode = '42501', message = 'This profile cannot accept publication approval in its current state.';
  end if;

  select coalesce(array_agg(distinct d.value order by d.value), array[]::text[])
  into v_destinations
  from unnest(coalesce(p_destinations, array[]::text[])) as d(value)
  where d.value = any (array['heha_swipe', 'heha_local']::text[]);
  if cardinality(v_destinations) = 0
     or cardinality(v_destinations) <> cardinality(coalesce(p_destinations, array[]::text[])) then
    raise exception using errcode = '23514', message = 'Choose at least one valid HEHA destination.';
  end if;
  if 'heha_swipe' = any (v_destinations)
     and app_private.is_supported_swipe_partner(v_partner) is not true then
    raise exception using errcode = '23514', message = 'This profile category is not supported for HEHA Swipe publication.';
  end if;
  if 'heha_local' = any (v_destinations)
     and app_private.is_wave1_food_partner(v_partner) is not true then
    raise exception using errcode = '23514', message = 'HEHA Local is currently available here for catering and private-chef profiles.';
  end if;
  if char_length(btrim(coalesce(p_authorized_representative_name, ''))) not between 2 and 120
     or char_length(btrim(coalesce(p_authorized_representative_title, ''))) not between 2 and 120
     or v_account_contact is null then
    raise exception using errcode = '23514', message = 'Authorized representative details are required.';
  end if;
  if p_consent_statement_version is distinct from 'wave1-profile-consent-2026-08-10' then
    raise exception using errcode = '23514', message = 'The current partner profile consent statement must be accepted.';
  end if;
  if p_expected_profile_snapshot_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '23514', message = 'Reload the exact public profile preview before approving publication.';
  end if;

  v_snapshot := app_private.partner_public_profile_snapshot(v_partner);
  v_snapshot_hash := app_private.partner_public_profile_hash(v_partner);
  v_lane := app_private.wave1_local_lane(v_partner);
  v_request_payload_hash := pg_catalog.encode(
    extensions.digest(
      jsonb_build_object(
        'partner_id', v_partner.id,
        'destinations', v_destinations,
        'representative_name', btrim(p_authorized_representative_name),
        'representative_title', btrim(p_authorized_representative_title),
        'statement_version', p_consent_statement_version,
        'expected_profile_snapshot_hash', p_expected_profile_snapshot_hash
      )::text,
      'sha256'
    ),
    'hex'
  );

  select * into v_existing_event
  from public.partner_publication_consent_events
  where request_key = p_request_key and action = 'publish_profile'
  order by recorded_at desc
  limit 1;
  if found then
    if v_existing_event.owner_id is distinct from v_actor_id
       or v_existing_event.partner_id is distinct from v_partner.id
       or v_existing_event.request_payload_hash is distinct from v_request_payload_hash then
      raise exception using errcode = '23505', message = 'This publication request key was already used with different details.';
    end if;
    return jsonb_build_object(
      'partner_id', v_partner.id,
      'state', 'publication_authorized',
      'destinations', v_destinations,
      'profile_snapshot_hash', v_existing_event.profile_snapshot_hash
    );
  end if;

  if v_snapshot_hash is distinct from p_expected_profile_snapshot_hash then
    raise exception using errcode = '23514', message = 'The public profile changed after it was previewed. Reload and approve the new version.';
  end if;

  foreach v_destination in array v_destinations loop
    v_prepare := app_private.latest_partner_consent_event(p_partner_id, v_destination, 'prepare_profile');
    if v_prepare.id is null
       or v_prepare.owner_id is distinct from v_actor_id
       or v_prepare.state <> 'granted'
       or v_prepare.representative_authority_confirmed is not true
       or v_prepare.profile_preparation_confirmed is not true
       or v_prepare.media_permission_confirmed is not true then
      raise exception using errcode = '23514', message = 'Private profile preparation must be authorized for every selected destination first.';
    end if;
    if v_destination = 'heha_local'
       and (
         v_prepare.service_area_attested is not true
         or v_prepare.local_lane is distinct from v_lane
       ) then
      raise exception using errcode = '23514', message = 'The chef/catering service changed after profile preparation. Reconfirm the current HEHA Local lane before publishing.';
    end if;

    insert into public.partner_publication_consent_events (
      partner_id,
      owner_id,
      destination,
      action,
      state,
      authorized_representative_name,
      authorized_representative_title,
      representative_authority_confirmed,
      profile_preparation_confirmed,
      authorized_account_contact,
      consent_statement_version,
      evidence_channel,
      evidence_reference,
      service_areas,
      local_lane,
      media_permission_confirmed,
      service_area_attested,
      profile_snapshot,
      profile_snapshot_hash,
      request_key,
      request_payload_hash,
      recorded_by
    ) values (
      v_partner.id,
      v_actor_id,
      v_destination,
      'publish_profile',
      'granted',
      btrim(p_authorized_representative_name),
      btrim(p_authorized_representative_title),
      v_prepare.representative_authority_confirmed,
      v_prepare.profile_preparation_confirmed,
      v_account_contact,
      p_consent_statement_version,
      'heha_swipe',
      'owner-approved-current-profile',
      v_prepare.service_areas,
      case when v_destination = 'heha_local' then v_lane else null end,
      v_prepare.media_permission_confirmed,
      v_prepare.service_area_attested,
      v_snapshot,
      v_snapshot_hash,
      p_request_key,
      v_request_payload_hash,
      v_actor_id
    )
    on conflict (request_key, destination, action) do nothing;
  end loop;

  return jsonb_build_object(
    'partner_id', v_partner.id,
    'state', 'publication_authorized',
    'destinations', v_destinations,
    'profile_snapshot_hash', v_snapshot_hash
  );
end;
$function$;

revoke all on function public.authorize_partner_profile_publication(uuid, text[], text, text, uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.authorize_partner_profile_publication(uuid, text[], text, text, uuid, text, text)
  to authenticated;

create or replace function public.withdraw_partner_publication_authorization(
  p_partner_id uuid,
  p_destinations text[],
  p_authorized_representative_name text,
  p_authorized_representative_title text,
  p_request_key uuid,
  p_consent_statement_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_account_contact text;
  v_partner public.partners;
  v_destinations text[];
  v_destination text;
  v_lane text;
  v_snapshot jsonb;
  v_snapshot_hash text;
  v_request_payload_hash text;
  v_existing_count integer;
  v_swipe_remaining boolean;
  v_local_remaining boolean;
begin
  if v_actor_id is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception using errcode = '42501', message = 'Sign in with a permanent owner account before withdrawing publication authorization.';
  end if;
  if p_partner_id is null or p_request_key is null then
    raise exception using errcode = '22023', message = 'Partner and request keys are required.';
  end if;
  if char_length(btrim(coalesce(p_authorized_representative_name, ''))) not between 2 and 120
     or char_length(btrim(coalesce(p_authorized_representative_title, ''))) not between 2 and 120 then
    raise exception using errcode = '23514', message = 'Authorized representative details are required for the withdrawal record.';
  end if;
  if p_consent_statement_version is distinct from 'wave1-profile-consent-2026-08-10' then
    raise exception using errcode = '23514', message = 'The withdrawal must reference the current partner profile permission statement.';
  end if;

  select coalesce(array_agg(distinct d.value order by d.value), array[]::text[])
  into v_destinations
  from unnest(coalesce(p_destinations, array[]::text[])) as d(value)
  where d.value = any (array['heha_swipe', 'heha_local']::text[]);
  if cardinality(v_destinations) = 0
     or cardinality(v_destinations) <> cardinality(coalesce(p_destinations, array[]::text[])) then
    raise exception using errcode = '23514', message = 'Choose one or more valid destinations to withdraw.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );
  select * into v_partner
  from public.partners
  where id = p_partner_id and owner_id = v_actor_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'This partner profile is not owned by the signed-in account.';
  end if;

  select coalesce(
    case when u.email_confirmed_at is not null then nullif(btrim(u.email), '') end,
    case when u.phone_confirmed_at is not null then nullif(btrim(u.phone), '') end
  )
  into v_account_contact
  from auth.users u
  where u.id = v_actor_id;
  if v_account_contact is null then
    raise exception using errcode = '23514', message = 'A verified account email or phone is required to withdraw publication authorization.';
  end if;

  v_lane := app_private.wave1_local_lane(v_partner);
  if 'heha_local' = any (v_destinations) and v_lane is null then
    select e.local_lane into v_lane
    from public.partner_publication_consent_events e
    where e.partner_id = v_partner.id
      and e.destination = 'heha_local'
      and e.local_lane is not null
    order by e.event_sequence desc
    limit 1;
    if v_lane is null then
      raise exception using errcode = '23514', message = 'This profile has no HEHA Local permission lane to withdraw.';
    end if;
  end if;
  v_snapshot := app_private.partner_public_profile_snapshot(v_partner);
  v_snapshot_hash := app_private.partner_public_profile_hash(v_partner);
  v_request_payload_hash := pg_catalog.encode(
    extensions.digest(
      jsonb_build_object(
        'partner_id', v_partner.id,
        'destinations', v_destinations,
        'representative_name', btrim(p_authorized_representative_name),
        'representative_title', btrim(p_authorized_representative_title),
        'statement_version', p_consent_statement_version,
        'state', 'revoked'
      )::text,
      'sha256'
    ),
    'hex'
  );

  select count(*)::integer into v_existing_count
  from public.partner_publication_consent_events e
  where e.request_key = p_request_key
    and e.action = 'publish_profile';
  if v_existing_count > 0 then
    if v_existing_count <> cardinality(v_destinations)
       or exists (
         select 1
         from public.partner_publication_consent_events e
         where e.request_key = p_request_key
           and e.action = 'publish_profile'
           and (
             e.partner_id is distinct from v_partner.id
             or e.owner_id is distinct from v_actor_id
             or e.destination <> all (v_destinations)
             or e.state is distinct from 'revoked'
             or e.request_payload_hash is distinct from v_request_payload_hash
           )
       ) then
      raise exception using errcode = '23505', message = 'This withdrawal request key was already used with different details.';
    end if;
    return jsonb_build_object(
      'partner_id', v_partner.id,
      'state', 'publication_withdrawn',
      'destinations', v_destinations
    );
  end if;

  foreach v_destination in array v_destinations loop
    insert into public.partner_publication_consent_events (
      partner_id,
      owner_id,
      destination,
      action,
      state,
      authorized_representative_name,
      authorized_representative_title,
      authorized_account_contact,
      consent_statement_version,
      evidence_channel,
      evidence_reference,
      service_areas,
      local_lane,
      media_permission_confirmed,
      service_area_attested,
      profile_snapshot,
      profile_snapshot_hash,
      request_key,
      request_payload_hash,
      recorded_by
    ) values (
      v_partner.id,
      v_actor_id,
      v_destination,
      'publish_profile',
      'revoked',
      btrim(p_authorized_representative_name),
      btrim(p_authorized_representative_title),
      v_account_contact,
      p_consent_statement_version,
      'heha_swipe',
      'owner-withdrew-publication-authorization',
      case when v_destination = 'heha_local' then array['Tampa Bay']::text[] else array[]::text[] end,
      case when v_destination = 'heha_local' then v_lane else null end,
      false,
      false,
      v_snapshot,
      v_snapshot_hash,
      p_request_key,
      v_request_payload_hash,
      v_actor_id
    );
  end loop;

  v_swipe_remaining := coalesce(v_partner.swipe_eligible, false)
    and not ('heha_swipe' = any (v_destinations));
  -- Owner consent for Local may remain current, but raw Local activation stays
  -- off until the separately reviewed least-privilege exporter exists.
  v_local_remaining := false;
  -- Defined later in the reconciled #120 lineage. No migration-time call is
  -- made here; at RPC runtime this private single-use capability lets the
  -- security-definer withdrawal clear only publication/routing fields without
  -- weakening the owner mutation guard.
  perform app_private.authorize_partner_lifecycle_mutation(
    v_partner.id,
    'listing_change'
  );
  update public.partners
  set swipe_eligible = v_swipe_remaining,
      local_eligible = v_local_remaining,
      local_lane = case when v_local_remaining then local_lane else null end,
      status = case when v_swipe_remaining or v_local_remaining then status else 'pending' end,
      primary_cta_destination = case
        when v_swipe_remaining then 'swipe'
        when v_local_remaining then 'local'
        else null
      end,
      primary_cta_label = case
        when v_swipe_remaining then 'Discover Partner'
        when v_local_remaining then primary_cta_label
        else null
      end,
      primary_cta_path = case
        when v_swipe_remaining then '/?partner=' || id::text
        when v_local_remaining then primary_cta_path
        else null
      end,
      routing_status = case when v_swipe_remaining or v_local_remaining then routing_status else 'needs_review' end,
      routing_updated_by = v_actor_id,
      routing_updated_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where id = v_partner.id;

  return jsonb_build_object(
    'partner_id', v_partner.id,
    'state', 'publication_withdrawn',
    'destinations', v_destinations
  );
end;
$function$;

revoke all on function public.withdraw_partner_publication_authorization(
  uuid, text[], text, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.withdraw_partner_publication_authorization(
  uuid, text[], text, text, uuid, text
) to authenticated;

create or replace function public.get_my_partner_publication_status(p_partner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_partner public.partners;
  v_snapshot_hash text;
  v_prepare_destinations text[] := array[]::text[];
  v_publish_destinations text[] := array[]::text[];
  v_destination text;
  v_event public.partner_publication_consent_events;
begin
  if v_actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in to view partner publication status.';
  end if;
  select * into v_partner from public.partners where id = p_partner_id and owner_id = v_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'This partner profile is not owned by the signed-in account.';
  end if;
  v_snapshot_hash := app_private.partner_public_profile_hash(v_partner);

  foreach v_destination in array array['heha_swipe', 'heha_local']::text[] loop
    v_event := app_private.latest_partner_consent_event(p_partner_id, v_destination, 'prepare_profile');
    if v_event.id is not null
       and v_event.owner_id is not distinct from v_actor_id
       and v_event.state = 'granted' then
      v_prepare_destinations := array_append(v_prepare_destinations, v_destination);
      if app_private.has_current_partner_publication_authorization(v_partner, v_destination) then
        v_publish_destinations := array_append(v_publish_destinations, v_destination);
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'partner_id', v_partner.id,
    'profile_snapshot_hash', v_snapshot_hash,
    'profile_snapshot', app_private.partner_public_profile_snapshot(v_partner),
    'prepare_destinations', v_prepare_destinations,
    'publication_destinations', v_publish_destinations,
    'needs_publication_approval', v_prepare_destinations is distinct from v_publish_destinations
  );
end;
$function$;

revoke all on function public.get_my_partner_publication_status(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_partner_publication_status(uuid) to authenticated;

drop function if exists public.record_verified_partner_publication_consent(
  uuid, text, text, text, text, text, text, text, uuid, text, text,
  boolean, boolean, text[]
);

create or replace function public.record_verified_partner_publication_consent(
  p_partner_id uuid,
  p_destination text,
  p_action text,
  p_state text,
  p_authorized_representative_name text,
  p_authorized_representative_title text,
  p_authorized_representative_email text,
  p_evidence_reference text,
  p_request_key uuid,
  p_consent_statement_version text,
  p_expected_profile_snapshot_hash text default null,
  p_authority_confirmed boolean default false,
  p_profile_confirmed boolean default false,
  p_media_permission_confirmed boolean default false,
  p_tampa_bay_service_confirmed boolean default false,
  p_service_areas text[] default array['Tampa Bay']::text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_partner public.partners;
  v_lane text;
  v_event_id uuid;
  v_request_payload_hash text;
  v_existing_event public.partner_publication_consent_events;
  v_prepare public.partner_publication_consent_events;
begin
  if not (
    app_private.is_service_role_request()
    or (select app_private.has_internal_role(array['super_admin']::text[]))
  ) then
    raise exception using errcode = '42501', message = 'Only an authorized HEHA administrator may record verified external consent.';
  end if;
  if p_destination <> all (array['heha_swipe','heha_local']::text[])
     or p_action <> all (array['prepare_profile','publish_profile']::text[])
     or p_state <> all (array['granted','revoked']::text[]) then
    raise exception using errcode = '23514', message = 'Consent destination, action, or state is invalid.';
  end if;
  if p_request_key is null or nullif(btrim(coalesce(p_evidence_reference, '')), '') is null then
    raise exception using errcode = '23514', message = 'An idempotency key and verified evidence reference are required.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );
  if p_consent_statement_version is distinct from 'wave1-profile-consent-2026-08-10' then
    raise exception using errcode = '23514', message = 'The recorded consent does not match the current statement version.';
  end if;
  if lower(btrim(coalesce(p_authorized_representative_email, ''))) !~
     '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+[.][a-z]{2,63}$' then
    raise exception using errcode = '23514', message = 'A verified representative email address is required.';
  end if;

  select * into v_partner from public.partners where id = p_partner_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Partner profile not found.';
  end if;
  if p_state = 'granted'
     and p_destination = 'heha_swipe'
     and app_private.is_supported_swipe_partner(v_partner) is not true then
    raise exception using errcode = '23514', message = 'This profile category is not supported for HEHA Swipe publication.';
  end if;
  if p_state = 'granted'
     and p_destination = 'heha_local'
     and app_private.is_wave1_food_partner(v_partner) is not true then
    raise exception using errcode = '23514', message = 'HEHA Local is currently available here for catering and private-chef profiles.';
  end if;
  v_lane := app_private.wave1_local_lane(v_partner);
  if p_state = 'revoked'
     and p_destination = 'heha_local'
     and v_lane is null then
    select e.local_lane into v_lane
    from public.partner_publication_consent_events e
    where e.partner_id = v_partner.id
      and e.destination = 'heha_local'
      and e.local_lane is not null
    order by e.event_sequence desc
    limit 1;
    if v_lane is null then
      raise exception using errcode = '23514', message = 'This profile has no HEHA Local permission lane to revoke.';
    end if;
  end if;
  v_request_payload_hash := pg_catalog.encode(
    extensions.digest(
      jsonb_build_object(
        'partner_id', v_partner.id,
        'destination', p_destination,
        'action', p_action,
        'state', p_state,
        'representative_name', btrim(coalesce(p_authorized_representative_name, '')),
        'representative_title', btrim(coalesce(p_authorized_representative_title, '')),
        'representative_email', lower(btrim(coalesce(p_authorized_representative_email, ''))),
        'evidence_reference', btrim(coalesce(p_evidence_reference, '')),
        'statement_version', p_consent_statement_version,
        'expected_profile_snapshot_hash', p_expected_profile_snapshot_hash,
        'authority_confirmed', coalesce(p_authority_confirmed, false),
        'profile_confirmed', coalesce(p_profile_confirmed, false),
        'media_permission', coalesce(p_media_permission_confirmed, false),
        'tampa_bay_service_confirmed', coalesce(p_tampa_bay_service_confirmed, false),
        'service_areas', coalesce(p_service_areas, array['Tampa Bay']::text[])
      )::text,
      'sha256'
    ),
    'hex'
  );

  select * into v_existing_event
  from public.partner_publication_consent_events
  where request_key = p_request_key
    and destination = p_destination
    and action = p_action;
  if found then
    if v_existing_event.request_payload_hash is distinct from v_request_payload_hash then
      raise exception using errcode = '23505', message = 'This evidence request key was already used with different consent details.';
    end if;
    return v_existing_event.id;
  end if;

  if p_state = 'granted'
     and p_media_permission_confirmed is not true then
    raise exception using errcode = '23514', message = 'Current permission to use supplied business media is required for every granted profile action.';
  end if;
  if p_state = 'granted'
     and p_authority_confirmed is not true then
    raise exception using errcode = '23514', message = 'Verified representative-authority confirmation is required for every granted profile action.';
  end if;
  if p_state = 'granted'
     and p_profile_confirmed is not true then
    raise exception using errcode = '23514', message = 'Verified profile-preparation confirmation is required for every granted profile action.';
  end if;

  if p_action = 'publish_profile' and p_state = 'granted' then
    if p_expected_profile_snapshot_hash !~ '^[0-9a-f]{64}$' then
      raise exception using errcode = '23514', message = 'Verified publication evidence must identify the exact reviewed profile hash.';
    end if;
    v_prepare := app_private.latest_partner_consent_event(
      p_partner_id,
      p_destination,
      'prepare_profile'
    );
    if v_prepare.id is null
       or v_prepare.owner_id is distinct from v_partner.owner_id
       or v_prepare.state <> 'granted'
       or v_prepare.representative_authority_confirmed is not true
       or v_prepare.profile_preparation_confirmed is not true
       or v_prepare.media_permission_confirmed is not true then
      raise exception using errcode = '23514', message = 'Verified profile preparation permission must be recorded before publication permission.';
    end if;
    if p_destination = 'heha_local'
       and (
         v_prepare.service_area_attested is not true
         or v_prepare.local_lane is distinct from v_lane
       ) then
      raise exception using errcode = '23514', message = 'The chef/catering service changed after preparation permission. Record current HEHA Local preparation permission first.';
    end if;
    if app_private.partner_public_profile_hash(v_partner) is distinct from p_expected_profile_snapshot_hash then
      raise exception using errcode = '23514', message = 'The profile changed after the representative reviewed it. Send the new version for approval.';
    end if;
  end if;
  if p_destination = 'heha_local'
     and p_action = 'prepare_profile'
     and p_state = 'granted'
     and p_tampa_bay_service_confirmed is not true then
    raise exception using errcode = '23514', message = 'Verified Tampa Bay service-area confirmation is required before preparing a HEHA Local profile.';
  end if;

  insert into public.partner_publication_consent_events (
    partner_id,
    owner_id,
    destination,
    action,
    state,
    authorized_representative_name,
    authorized_representative_title,
    representative_authority_confirmed,
    profile_preparation_confirmed,
    authorized_account_contact,
    consent_statement_version,
    evidence_channel,
    evidence_reference,
    service_areas,
    local_lane,
    media_permission_confirmed,
    service_area_attested,
    profile_snapshot,
    profile_snapshot_hash,
    request_key,
    request_payload_hash,
    recorded_by
  ) values (
    v_partner.id,
    v_partner.owner_id,
    p_destination,
    p_action,
    p_state,
    btrim(p_authorized_representative_name),
    btrim(p_authorized_representative_title),
    case
      when p_action = 'publish_profile' and p_state = 'granted'
        then v_prepare.representative_authority_confirmed
      else coalesce(p_authority_confirmed, false)
    end,
    case
      when p_action = 'publish_profile' and p_state = 'granted'
        then v_prepare.profile_preparation_confirmed
      else coalesce(p_profile_confirmed, false)
    end,
    lower(btrim(p_authorized_representative_email)),
    p_consent_statement_version,
    'verified_email',
    btrim(p_evidence_reference),
    case
      when p_destination = 'heha_local' then coalesce(p_service_areas, array['Tampa Bay']::text[])
      else array[]::text[]
    end,
    case when p_destination = 'heha_local' then v_lane else null end,
    coalesce(p_media_permission_confirmed, false),
    case
      when p_action = 'publish_profile' and p_state = 'granted' then v_prepare.service_area_attested
      else coalesce(p_tampa_bay_service_confirmed, false)
    end,
    app_private.partner_public_profile_snapshot(v_partner),
    app_private.partner_public_profile_hash(v_partner),
    p_request_key,
    v_request_payload_hash,
    v_actor_id
  )
  returning id into v_event_id;

  if p_action = 'publish_profile' and p_state = 'revoked' then
    if p_destination = 'heha_swipe' then
      perform app_private.authorize_partner_lifecycle_mutation(
        v_partner.id,
        'listing_change'
      );
      update public.partners
      set swipe_eligible = false,
          status = case when coalesce(local_eligible, false) then status else 'pending' end,
          primary_cta_destination = case when coalesce(local_eligible, false) then 'local' else null end,
          primary_cta_label = case when coalesce(local_eligible, false) then public.partner_cta_label_for_lane(local_lane) else null end,
          primary_cta_path = case when coalesce(local_eligible, false) then primary_cta_path else null end,
          routing_status = case when coalesce(local_eligible, false) then 'approved' else 'needs_review' end,
          routing_updated_by = v_actor_id,
          routing_updated_at = pg_catalog.now(),
          updated_at = pg_catalog.now()
      where id = v_partner.id;
    else
      perform app_private.authorize_partner_lifecycle_mutation(
        v_partner.id,
        'listing_change'
      );
      update public.partners
      set local_eligible = false,
          local_lane = null,
          status = case when coalesce(swipe_eligible, false) then status else 'pending' end,
          primary_cta_destination = case when coalesce(swipe_eligible, false) then 'swipe' else null end,
          primary_cta_label = case when coalesce(swipe_eligible, false) then 'Discover Partner' else null end,
          primary_cta_path = case when coalesce(swipe_eligible, false) then '/?partner=' || id::text else null end,
          routing_status = case when coalesce(swipe_eligible, false) then 'approved' else 'needs_review' end,
          routing_updated_by = v_actor_id,
          routing_updated_at = pg_catalog.now(),
          updated_at = pg_catalog.now()
      where id = v_partner.id;
    end if;
  end if;

  return v_event_id;
end;
$function$;

revoke all on function public.record_verified_partner_publication_consent(
  uuid, text, text, text, text, text, text, text, uuid, text, text,
  boolean, boolean, boolean, boolean, text[]
) from public, anon, authenticated;
grant execute on function public.record_verified_partner_publication_consent(
  uuid, text, text, text, text, text, text, text, uuid, text, text,
  boolean, boolean, boolean, boolean, text[]
) to authenticated, service_role;

-- Repair the no-space PrivateChef category used by the current onboarding UI.
create or replace function public.suggest_partner_local_lane(
  p_category text,
  p_business_type text,
  p_product_price_policy text,
  p_service_fee_type text,
  p_delivery_days text[]
)
returns text
language sql
immutable
as $function$
  select case
    when lower(coalesce(p_category,'')) in ('privatechef', 'private chef')
      or lower(coalesce(p_category,'')) like '%private chef%'
      or lower(coalesce(p_business_type,'')) like '%private chef%'
      or lower(coalesce(p_business_type,'')) like '%retreat chef%'
      then 'chef'
    when lower(coalesce(p_category,'')) like '%catering%'
      or lower(coalesce(p_business_type,'')) like '%catering%'
      or lower(coalesce(p_business_type,'')) like '%food truck%'
      or lower(coalesce(p_business_type,'')) like '%group order%'
      or lower(coalesce(p_business_type,'')) like '%staff meal%'
      then 'group_orders'
    when lower(coalesce(p_category,'')) = 'restaurant'
      or lower(coalesce(p_business_type,'')) like '%restaurant%'
      or lower(coalesce(p_business_type,'')) like '%juice bar%'
      or lower(coalesce(p_business_type,'')) like '%beverage bar%'
      or lower(coalesce(p_business_type,'')) like '%meal prep%'
      then 'meals'
    when lower(coalesce(p_business_type,'')) like '%natural grocery%'
      or lower(coalesce(p_business_type,'')) like '%health market%'
      then 'market'
    when lower(coalesce(p_category,'')) = 'vendor' and (
      lower(coalesce(p_business_type,'')) ~ '(food|cottage|bakery|pantry|beverage|drink|herbal product)'
      or nullif(btrim(coalesce(p_product_price_policy,'')), '') is not null
      or nullif(btrim(coalesce(p_service_fee_type,'')), '') is not null
      or coalesce(cardinality(p_delivery_days), 0) > 0
    ) then 'vendors'
    when lower(coalesce(p_category,'')) = 'markets' and (
      lower(coalesce(p_business_type,'')) ~ '(natural grocery|health market|grocery)'
      or nullif(btrim(coalesce(p_product_price_policy,'')), '') is not null
      or nullif(btrim(coalesce(p_service_fee_type,'')), '') is not null
    ) then 'market'
    else null
  end;
$function$;

-- Retire the legacy one-step approval endpoint. Owner consent is necessary but
-- cannot itself be a staff review or activation decision. The integration RC
-- introduces a separate, internal-only exact-hash review ledger/RPC.
create or replace function public.approve_partner(p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception using
    errcode = '0A000',
    message = 'Legacy partner approval is retired. Record a separate exact-hash staff publication review.';
end;
$function$;

revoke all on function public.approve_partner(uuid)
  from public, anon, authenticated, service_role;

-- Raw partner rows are owner/internal-only. Public discovery is through the
-- safe projections below. The definer views deliberately bypass base-table RLS
-- only for the exact allowlisted columns and publication predicates.
drop policy if exists "Anyone can view approved partners" on public.partners;
drop policy if exists "Saved partners visible to saver" on public.partners;
drop policy if exists "Owners can view own partner" on public.partners;
create policy "Owners can view own partner"
on public.partners
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = owner_id);

revoke all on table public.partners from public, anon;
revoke delete, truncate, references, trigger on table public.partners from authenticated;
grant select, insert, update on table public.partners to authenticated;

-- PostgreSQL cannot remove columns with CREATE OR REPLACE VIEW. These views
-- have no dependent relations in the audited production schema, so recreate
-- them transactionally with the smaller public contract.
drop view if exists public.public_partner_directory;
drop view if exists public.public_swipe_partners;
drop view if exists public.public_local_partners;
drop view if exists app_private.partner_publication_projection;

-- Resolve private consent state behind the definer-owned public views without
-- granting browser roles EXECUTE on helpers that read the consent ledger.
create view app_private.partner_publication_projection
with (security_invoker = false, security_barrier = true)
as
with base as (
  select
    p.*,
    (
      lower(coalesce(p.category, '')) in ('catering', 'privatechef', 'private chef')
      or exists (
        select 1
        from unnest(coalesce(p.categories, array[]::text[])) as c(value)
        where lower(c.value) in ('catering', 'privatechef', 'private chef')
      )
    ) as publication_is_wave1_food_partner,
    case
      when lower(coalesce(p.category, '')) in ('privatechef', 'private chef') then 'chef'
      when lower(coalesce(p.category, '')) = 'catering' then 'group_orders'
      else (
        select case
          when lower(ordered_category.value) in ('privatechef', 'private chef') then 'chef'
          when lower(ordered_category.value) = 'catering' then 'group_orders'
          else null
        end
        from unnest(coalesce(p.categories, array[]::text[]))
          with ordinality as ordered_category(value, position)
        where lower(ordered_category.value) in ('catering', 'privatechef', 'private chef')
        order by ordered_category.position
        limit 1
      )
    end as publication_derived_wave1_local_lane,
    (
      lower(coalesce(p.category, '')) in ('catering', 'privatechef', 'private chef')
      or exists (
        select 1
        from unnest(coalesce(p.categories, array[]::text[])) as managed_category(value)
        where lower(managed_category.value) in ('catering', 'privatechef', 'private chef')
      )
      or exists (
        select 1
        from public.partner_publication_consent_events history
        where history.partner_id = p.id
      )
    ) as publication_consent_managed
  from public.partners p
), evaluated as (
  select
    b.*,
    jsonb_build_object(
      'name', nullif(btrim(b.name), ''),
      'category', b.category,
      'categories', coalesce(b.categories, array[]::text[]),
      'neighborhood', nullif(btrim(coalesce(b.neighborhood, '')), ''),
      'tagline', nullif(btrim(coalesce(b.tagline, '')), ''),
      'bio', nullif(btrim(coalesce(b.bio, '')), ''),
      'tags', coalesce(b.tags, array[]::text[]),
      'hours', nullif(btrim(coalesce(b.hours, '')), ''),
      'business_type', nullif(btrim(coalesce(b.business_type, '')), ''),
      'offerings', coalesce(b.offerings, array[]::text[]),
      'website', nullif(btrim(coalesce(b.website, '')), ''),
      'instagram', nullif(btrim(coalesce(b.instagram, '')), ''),
      'items', case
        when b.publication_is_wave1_food_partner then '[]'::jsonb
        else coalesce(b.items, '[]'::jsonb)
      end,
      'photo_emoji', nullif(btrim(coalesce(b.photo_emoji, '')), ''),
      'color', nullif(btrim(coalesce(b.color, '')), ''),
      'image_url', nullif(btrim(coalesce(b.image_url, '')), ''),
      'gallery_urls', coalesce(b.gallery_urls, '[]'::jsonb),
      'price_range', case
        when b.publication_is_wave1_food_partner then null
        else nullif(btrim(coalesce(b.price_range, '')), '')
      end,
      'delivery_days', coalesce(b.delivery_days, array[]::text[])
    ) as publication_current_profile_snapshot
  from base b
), latest_events as (
  select distinct on (event.partner_id, event.destination, event.action)
    event.*
  from public.partner_publication_consent_events event
  order by event.partner_id, event.destination, event.action, event.event_sequence desc
)
select
  evaluated.*,
  (
    swipe_prepare.state = 'granted'
    and swipe_prepare.media_permission_confirmed is true
    and swipe_publish.state = 'granted'
    and swipe_publish.media_permission_confirmed is true
    and swipe_publish.profile_snapshot = evaluated.publication_current_profile_snapshot
  ) as publication_current_swipe_authorized,
  (
    local_prepare.state = 'granted'
    and local_prepare.service_area_attested is true
    and local_prepare.media_permission_confirmed is true
    and local_prepare.local_lane = evaluated.publication_derived_wave1_local_lane
    and local_publish.state = 'granted'
    and local_publish.media_permission_confirmed is true
    and local_publish.local_lane = evaluated.publication_derived_wave1_local_lane
    and evaluated.local_lane = evaluated.publication_derived_wave1_local_lane
    and local_publish.profile_snapshot = evaluated.publication_current_profile_snapshot
  ) as publication_current_local_authorized,
  coalesce(case evaluated.publication_derived_wave1_local_lane
    when 'chef' then
      split_part(evaluated.primary_cta_path, '?', 1) = '/chef/' || evaluated.id::text
      or evaluated.primary_cta_path = '/chef/match?swipePartnerId=' || evaluated.id::text || '&service=private_chef'
    when 'group_orders' then
      evaluated.primary_cta_path = '/chef/match?swipePartnerId=' || evaluated.id::text || '&service=catering'
    else false
  end, false) as publication_wave1_local_path_is_specific
from evaluated
left join latest_events swipe_prepare
  on swipe_prepare.partner_id = evaluated.id
 and swipe_prepare.destination = 'heha_swipe'
 and swipe_prepare.action = 'prepare_profile'
left join latest_events swipe_publish
  on swipe_publish.partner_id = evaluated.id
 and swipe_publish.destination = 'heha_swipe'
 and swipe_publish.action = 'publish_profile'
left join latest_events local_prepare
  on local_prepare.partner_id = evaluated.id
 and local_prepare.destination = 'heha_local'
 and local_prepare.action = 'prepare_profile'
left join latest_events local_publish
  on local_publish.partner_id = evaluated.id
 and local_publish.destination = 'heha_local'
 and local_publish.action = 'publish_profile';

revoke all on table app_private.partner_publication_projection
  from public, anon, authenticated, service_role;

create view public.public_partner_directory
with (security_invoker = false, security_barrier = true)
as
select
  id, created_at, name, category, categories, instagram, website, bio,
  tags, rating, review_count, distance_text, color, photo_emoji, heha_partner,
  status, hours, business_type, offerings, neighborhood, tagline,
  case when publication_is_wave1_food_partner then '[]'::jsonb else items end as items,
  image_url,
  case when publication_is_wave1_food_partner then null else price_range end as price_range,
  gallery_urls, partner_type, delivery_days, heha_pillar,
  local_eligible, local_lane, primary_cta_destination, primary_cta_label,
  primary_cta_path
from app_private.partner_publication_projection
where status = any (array['approved','live']::text[])
  and coalesce(website_eligible, false) = true
  and publication_consent_managed is false
  and is_test_record = false;

create view public.public_swipe_partners
with (security_invoker = false, security_barrier = true)
as
select
  id, created_at, name, category, categories, instagram, website, bio,
  tags, rating, review_count, distance_text, color, photo_emoji, heha_partner,
  status, hours, business_type, offerings, neighborhood, tagline,
  case when publication_is_wave1_food_partner then '[]'::jsonb else items end as items,
  image_url,
  case when publication_is_wave1_food_partner then null else price_range end as price_range,
  gallery_urls, partner_type, delivery_days, heha_pillar,
  case when publication_consent_managed then false else local_eligible end as local_eligible,
  case when publication_consent_managed then null else local_lane end as local_lane,
  case when publication_consent_managed then 'swipe' else primary_cta_destination end as primary_cta_destination,
  case when publication_consent_managed then 'Discover Partner' else primary_cta_label end as primary_cta_label,
  case when publication_consent_managed then '/?partner=' || id::text else primary_cta_path end as primary_cta_path
from app_private.partner_publication_projection
where status = any (array['approved','live']::text[])
  and coalesce(swipe_eligible, false) = true
  -- Consent alone is never a staff publication decision. The integration RC
  -- replaces this temporary deny-by-default predicate only after adding its
  -- separate internal exact-hash review ledger.
  and publication_consent_managed is false
  and is_test_record = false;

create view public.public_local_partners
with (security_invoker = false, security_barrier = true)
as
select
  id, created_at, name, category, categories, instagram, website, bio,
  tags, rating, review_count, distance_text, color, photo_emoji, heha_partner,
  status, hours, business_type, offerings, neighborhood, tagline,
  case when publication_is_wave1_food_partner then '[]'::jsonb else items end as items,
  image_url,
  case when publication_is_wave1_food_partner then null else price_range end as price_range,
  gallery_urls, partner_type, delivery_days, heha_pillar,
  local_eligible, local_lane, primary_cta_destination, primary_cta_label,
  primary_cta_path
from app_private.partner_publication_projection
where status = any (array['approved','live']::text[])
  and coalesce(local_eligible, false) = true
  and publication_consent_managed is false
  and local_lane is not null
  and is_test_record = false;

revoke all on table public.public_partner_directory from public, anon, authenticated;
revoke all on table public.public_swipe_partners from public, anon, authenticated;
revoke all on table public.public_local_partners from public, anon, authenticated;
grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

comment on view public.public_swipe_partners is
  'Public-safe HEHA Swipe partner projection. Private contact, owner, consent, analytics, routing notes, and pricing internals are intentionally excluded.';
comment on view public.public_local_partners is
  'Public-safe HEHA Local bridge projection. Consent evidence stays private in HEHA Swipe.';
