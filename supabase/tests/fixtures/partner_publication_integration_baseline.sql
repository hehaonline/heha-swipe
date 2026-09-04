-- Synthetic current-main baseline for the partner-publication integration RC.
-- Disposable proof database only. Never apply this fixture to Production.
--
-- The fixture deliberately preserves the pre-#118 raw/public exposure and the
-- owner-guard surface that #118 and #120 must reconcile. The workflow applies
-- the real reviewed migrations after this file in lexical order.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists app_private;

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  active boolean not null default true
);

create table public.partners (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  category text not null default 'Nourish',
  categories text[] not null default array['Nourish']::text[],
  location text,
  contact text,
  instagram text,
  website text,
  bio text,
  tags text[] default '{}'::text[],
  rating numeric not null default 0,
  review_count integer not null default 0,
  distance_text text,
  color text,
  photo_emoji text,
  heha_partner boolean not null default false,
  status text not null default 'approved',
  complete_pct integer not null default 0,
  contribution numeric not null default 0,
  total_swipes integer not null default 0,
  total_saves integer not null default 0,
  total_profile_views integer not null default 0,
  hours text,
  google_place_id text,
  business_type text,
  offerings text[] default '{}'::text[],
  neighborhood text,
  tagline text,
  items jsonb not null default '[]'::jsonb,
  phone text,
  image_url text,
  price_range text,
  gallery_urls jsonb not null default '[]'::jsonb,
  partner_type text,
  product_price_policy text,
  service_fee_type text,
  service_fee_amount numeric not null default 0,
  delivery_days text[] default '{}'::text[],
  pricing_notes text,
  heha_pillar text,
  website_eligible boolean,
  swipe_eligible boolean default true,
  local_eligible boolean,
  local_lane text,
  primary_cta_destination text,
  primary_cta_label text,
  primary_cta_path text,
  routing_status text not null default 'suggested',
  routing_notes text,
  routing_updated_by uuid,
  routing_updated_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  review_note text,
  approved_by uuid,
  is_test_record boolean not null default false
);



-- Exact retained current-main routing suggestion trigger surface from
-- main@1ab63290fda9a967a36831cef50ef01b68a8c0a4. This fixture intentionally
-- models derived suggestions without running historical backfills.
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
as $
  select case
    when lower(coalesce(p_category,'')) like '%private chef%'
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
$;

create or replace function public.partner_cta_label_for_lane(p_lane text)
returns text language sql immutable as $
  select case p_lane
    when 'meals' then 'Order Meals'
    when 'market' then 'Explore Market'
    when 'vendors' then 'Shop Local Vendor'
    when 'chef' then 'Explore Chef'
    when 'group_orders' then 'Group Orders'
    else 'Discover Partner'
  end;
$;

create or replace function public.partner_cta_path_for_lane(p_lane text, p_partner_id uuid)
returns text language sql immutable as $
  select case p_lane
    when 'meals' then '/restaurants'
    when 'market' then '/market'
    when 'vendors' then '/vendors'
    when 'chef' then '/chef'
    when 'group_orders' then '/group-orders'
    else '/?partner=' || p_partner_id::text
  end;
$;

create or replace function public.suggest_partner_pillar(p_category text, p_business_type text)
returns text
language sql
immutable
as $
  select case
    when lower(coalesce(p_category,'')) in ('restaurant','markets','vendor','catering','private chef')
      then 'nourish'
    when lower(coalesce(p_category,'')) = 'coach'
      then 'educate'
    when lower(coalesce(p_category,'')) = 'events'
      then 'elevate'
    when lower(coalesce(p_category,'')) = 'service'
      and lower(coalesce(p_business_type,'')) ~ '(education|coach|class|training)'
      then 'educate'
    when lower(coalesce(p_category,'')) = 'service'
      then 'relax'
    when lower(coalesce(p_category,'')) = 'wellness'
      and lower(coalesce(p_business_type,'')) ~ '(education|coach|class|herbal|nutrition)'
      then 'educate'
    when lower(coalesce(p_category,'')) = 'wellness'
      then 'relax'
    else null
  end;
$;

create or replace function public.apply_partner_routing_suggestions()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $
declare
  suggested_lane text;
  suggested_pillar text;
  is_public boolean;
begin
  if new.routing_status = 'approved' then return new; end if;

  suggested_lane := public.suggest_partner_local_lane(new.category, new.business_type, new.product_price_policy, new.service_fee_type, new.delivery_days);
  suggested_pillar := public.suggest_partner_pillar(new.category, new.business_type);
  is_public := new.status = any (array['approved','live','listed']);

  if new.heha_pillar is null then new.heha_pillar := suggested_pillar; end if;

  if is_public then
    if new.website_eligible is null then new.website_eligible := true; end if;
    if new.swipe_eligible is null then new.swipe_eligible := true; end if;
    if new.local_lane is null then new.local_lane := suggested_lane; end if;
    if new.local_eligible is null then new.local_eligible := new.local_lane is not null; end if;

    if new.primary_cta_destination is null then
      new.primary_cta_destination := case when new.local_eligible then 'local' else 'swipe' end;
    end if;

    if new.primary_cta_label is null then
      new.primary_cta_label := case
        when new.primary_cta_destination = 'local' then public.partner_cta_label_for_lane(new.local_lane)
        else 'Discover Partner'
      end;
    end if;

    if new.primary_cta_path is null then
      new.primary_cta_path := case
        when new.primary_cta_destination = 'local' then public.partner_cta_path_for_lane(new.local_lane, new.id)
        else '/?partner=' || new.id::text
      end;
    end if;

    if new.routing_status = 'suggested' then new.routing_status := 'needs_review'; end if;
    new.routing_updated_at := coalesce(new.routing_updated_at, now());
  end if;

  return new;
end;
$;

drop trigger if exists partners_apply_routing_suggestions on public.partners;
create trigger partners_apply_routing_suggestions
before insert or update of status, category, business_type, product_price_policy, service_fee_type, delivery_days, website_eligible, swipe_eligible, local_eligible, local_lane, primary_cta_destination, primary_cta_label, primary_cta_path, routing_status
on public.partners
for each row execute function public.apply_partner_routing_suggestions();

alter table public.partners enable row level security;
grant select on table public.partners to anon;
grant select, insert, update on table public.partners to authenticated;

create table public.saves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.swipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  direction text not null,
  created_at timestamptz not null default now()
);

create policy "Anyone can view approved partners"
on public.partners for select to anon, authenticated
using (status = any (array['approved', 'live']::text[]));

create policy "Saved partners visible to saver"
on public.partners for select to authenticated
using (
  exists (
    select 1 from public.saves s
    where s.partner_id = partners.id and s.user_id = auth.uid()
  )
);

create policy "Owners can view own partner"
on public.partners for select to authenticated
using (owner_id = auth.uid());

create policy partners_owner_insert
on public.partners for insert to authenticated
with check (owner_id = auth.uid());

create policy "Owners can update own preapproval partner profile"
on public.partners for update to authenticated
using (
  owner_id = auth.uid()
  and coalesce(status, '') = any (
    array['draft', 'submitted', 'pending', 'missing_info']::text[]
  )
)
with check (
  owner_id = auth.uid()
  and coalesce(status, '') = any (
    array['draft', 'submitted', 'pending', 'missing_info']::text[]
  )
);

create or replace function app_private.has_internal_role(required_roles text[])
returns boolean language sql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.active and r.role = any(required_roles)
  );
$$;
revoke all on function app_private.has_internal_role(text[])
  from public, anon, authenticated;
grant execute on function app_private.has_internal_role(text[])
  to anon, authenticated, service_role;

create policy partners_internal_read
on public.partners for select to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin']::text[]));

create or replace function app_private.normalize_partner_categories(
  selected_categories text[], primary_category text
) returns text[] language sql immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(array_agg(x.category order by x.first_position), array[]::text[])
  from (
    select btrim(e.value) as category, min(e.position) as first_position
    from unnest(
      coalesce(selected_categories, array[]::text[])
      || case
           when nullif(btrim(primary_category), '') is null then array[]::text[]
           else array[btrim(primary_category)]
         end
    ) with ordinality as e(value, position)
    where nullif(btrim(e.value), '') is not null
    group by btrim(e.value)
  ) x;
$$;
revoke all on function app_private.normalize_partner_categories(text[], text)
  from public, anon, authenticated;

create or replace function app_private.partner_completion_pct(partner_row public.partners)
returns integer language sql immutable
set search_path = pg_catalog, public, pg_temp
as $$ select 0; $$;
revoke all on function app_private.partner_completion_pct(public.partners)
  from public, anon, authenticated;

create or replace function public.partner_cta_label_for_lane(p_lane text)
returns text language sql immutable
set search_path = pg_catalog, pg_temp
as $$
  select case p_lane
    when 'chef' then 'Request a Chef'
    when 'group_orders' then 'Start a Group Order'
    when 'meals' then 'Order Meals'
    when 'market' then 'Shop Market'
    when 'vendors' then 'Shop Vendor'
    else 'Discover Partner'
  end;
$$;

-- Current main already carries the owner guard trigger. #120 replaces the
-- function body while retaining this trigger identity.
create or replace function app_private.guard_partner_owner_self_service()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$ begin return new; end $$;
revoke all on function app_private.guard_partner_owner_self_service()
  from public, anon, authenticated;

create trigger a_partner_owner_self_service_guard
before insert or update on public.partners
for each row execute function app_private.guard_partner_owner_self_service();

-- Deliberately vulnerable current-main public projections. #118 must replace
-- these with the reviewed explicit 33-column contract before #120 runs.
create view public.public_partner_directory with (security_invoker = true) as
select * from public.partners
where status = any (array['approved', 'live']::text[])
  and coalesce(website_eligible, false) = true
  and is_test_record = false;

create view public.public_swipe_partners with (security_invoker = true) as
select * from public.partners
where status = any (array['approved', 'live']::text[])
  and coalesce(swipe_eligible, false) = true
  and is_test_record = false;

create view public.public_local_partners with (security_invoker = true) as
select * from public.partners
where status = any (array['approved', 'live']::text[])
  and coalesce(local_eligible, false) = true
  and local_lane is not null
  and is_test_record = false;

grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'owner-a@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'authenticated', 'authenticated', 'owner-b@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'authenticated', 'authenticated', 'developer@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'authenticated', 'authenticated', 'super@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'authenticated', 'authenticated', 'unverified@example.invalid', null, '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'authenticated', 'authenticated', 'anonymous@example.invalid', now(), '{"provider":"anonymous","providers":["anonymous"]}', '{}', false, true, now(), now()),
  ('99999999-9999-4999-8999-999999999999', 'authenticated', 'authenticated', null, now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('12121212-1212-4212-8212-121212121212', 'authenticated', 'authenticated', 'pm@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('23232323-2323-4232-8232-232323232323', 'authenticated', 'authenticated', 'som@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('34343434-3434-4434-8434-343434343434', 'authenticated', 'authenticated', 'outsider@example.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now());

insert into public.user_roles(user_id, role, active) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'developer_admin', true),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'super_admin', true),
  ('12121212-1212-4212-8212-121212121212', 'pm_admin', true),
  ('23232323-2323-4232-8232-232323232323', 'som_admin', true);

-- The first six rows are the exact identities consumed by the #120 donor proof.
insert into public.partners (
  id, owner_id, name, status, heha_partner, swipe_eligible, is_test_record
) values
  ('11111111-1111-4111-8111-111111111111', null, 'Synthetic Business A', 'approved', false, true, false),
  ('22222222-2222-4222-8222-222222222222', null, 'Synthetic Business B', 'approved', false, true, false),
  ('33333333-3333-4333-8333-333333333333', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Already Owned Business', 'approved', false, true, false),
  ('44444444-4444-4444-8444-444444444444', null, 'Ambiguous Legacy Partner', 'approved', true, true, false),
  ('55555555-5555-4555-8555-555555555555', null, 'Redeem Race Business', 'approved', false, true, false),
  ('66666666-6666-4666-8666-666666666666', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Preapproval Owned Business', 'pending', false, true, false);

-- Dedicated integration row. Private sentinels must never reach any public view.
insert into public.partners (
  id, owner_id, name, category, categories, status, heha_partner,
  website_eligible, swipe_eligible, local_eligible, local_lane,
  primary_cta_destination, primary_cta_label, primary_cta_path,
  neighborhood, tagline, bio, website, instagram, location, contact, phone,
  routing_notes, routing_updated_by, reviewed_by, review_note, is_test_record
) values (
  '78787878-7878-4787-8787-787878787878',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Tampa Test Kitchen', 'Catering', array['Catering']::text[], 'approved', false,
  true, true, true, 'group_orders', 'local', 'Start a Group Order',
  '/group-orders/78787878-7878-4787-8787-787878787878',
  'Tampa Bay', 'Fresh local catering', 'Profile version one',
  'https://example.invalid', '@tampatestkitchen',
  'PRIVATE exact address', 'PRIVATE contact', '555-0177',
  'PRIVATE routing note', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'PRIVATE review note', false
);

insert into public.saves(user_id, partner_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111');
insert into public.swipes(user_id, partner_id, direction) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'right');
