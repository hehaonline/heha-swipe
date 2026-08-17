-- Synthetic, disposable baseline for the public partner privacy proof only.
-- It deliberately begins in the vulnerable state: browser roles can select raw
-- approved/live partner rows and all three public views expose every base column.

do $roles$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$roles$;

create schema if not exists auth;
create schema if not exists app_private;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema app_private to authenticated, service_role;

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

revoke all on function auth.uid() from public;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.user_roles (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  role text not null,
  active boolean not null default true
);

create or replace function app_private.has_internal_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.user_roles r
    where r.user_id = auth.uid()
      and r.active
      and r.role = any (required_roles)
  );
$function$;

revoke all on function app_private.has_internal_role(text[]) from public, anon, authenticated;
grant execute on function app_private.has_internal_role(text[]) to authenticated, service_role;

create table public.partners (
  id uuid primary key,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  owner_id uuid,
  name text not null,
  category text not null default 'Nourish',
  categories text[] not null default array['Nourish']::text[],
  location text,
  contact text,
  instagram text,
  website text,
  bio text,
  tags text[] not null default array[]::text[],
  rating numeric not null default 0,
  review_count integer not null default 0,
  distance_text text,
  color text,
  photo_emoji text,
  heha_partner boolean not null default false,
  status text not null default 'pending',
  complete_pct integer not null default 0,
  contribution numeric not null default 0,
  total_swipes integer not null default 0,
  total_saves integer not null default 0,
  total_profile_views integer not null default 0,
  hours text,
  google_place_id text,
  business_type text,
  offerings text[] not null default array[]::text[],
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
  delivery_days text[] not null default array[]::text[],
  pricing_notes text,
  heha_pillar text,
  website_eligible boolean,
  swipe_eligible boolean,
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

create table public.saves (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  partner_id uuid not null references public.partners(id) on delete cascade
);

alter table public.partners enable row level security;

grant select on table public.partners to anon;
grant select, insert, update on table public.partners to authenticated;

create policy "Anyone can view approved partners"
on public.partners
for select
to anon, authenticated
using (status = any (array['approved', 'live']::text[]));

create policy "Saved partners visible to saver"
on public.partners
for select
to authenticated
using (
  exists (
    select 1
    from public.saves s
    where s.partner_id = partners.id
      and s.user_id = (select auth.uid())
  )
);

create policy "Owners can view own partner"
on public.partners
for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy partners_internal_read
on public.partners
for select
to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin']::text[]));

create view public.public_partner_directory
with (security_invoker = true)
as
select *
from public.partners
where status = any (array['approved', 'live']::text[])
  and coalesce(website_eligible, false) = true
  and is_test_record = false;

create view public.public_swipe_partners
with (security_invoker = true)
as
select *
from public.partners
where status = any (array['approved', 'live']::text[])
  and coalesce(swipe_eligible, false) = true
  and is_test_record = false;

create view public.public_local_partners
with (security_invoker = true)
as
select *
from public.partners
where status = any (array['approved', 'live']::text[])
  and coalesce(local_eligible, false) = true
  and local_lane is not null
  and is_test_record = false;

grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

insert into public.user_roles(user_id, role, active)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'developer_admin', true);

insert into public.partners (
  id,
  owner_id,
  name,
  status,
  website_eligible,
  swipe_eligible,
  local_eligible,
  local_lane,
  is_test_record,
  location,
  contact,
  phone,
  routing_notes,
  routing_updated_by,
  reviewed_by,
  review_note
)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Approved Everywhere',
    'approved', true, true, true, 'meals', false,
    'private exact location A', 'private contact A', '555-0101',
    'private routing A', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review A'
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'Live Everywhere',
    'live', true, true, true, 'vendors', false,
    'private exact location B', 'private contact B', '555-0102',
    'private routing B', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review B'
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Pending Everywhere',
    'pending', true, true, true, 'meals', false,
    'private exact location C', 'private contact C', '555-0103',
    'private routing C', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review C'
  ),
  (
    '44444444-4444-4444-8444-444444444444',
    null,
    'Not Website Eligible',
    'approved', false, true, true, 'meals', false,
    'private exact location D', 'private contact D', '555-0104',
    'private routing D', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review D'
  ),
  (
    '55555555-5555-4555-8555-555555555555',
    null,
    'Not Swipe Eligible',
    'approved', true, false, true, 'meals', false,
    'private exact location E', 'private contact E', '555-0105',
    'private routing E', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review E'
  ),
  (
    '66666666-6666-4666-8666-666666666666',
    null,
    'Not Local Eligible',
    'approved', true, true, false, null, false,
    'private exact location F', 'private contact F', '555-0106',
    'private routing F', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review F'
  ),
  (
    '77777777-7777-4777-8777-777777777777',
    null,
    'Explicit Test Record',
    'approved', true, true, true, 'meals', true,
    'private exact location G', 'private contact G', '555-0107',
    'private routing G', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'private review G'
  );

-- Before the hardening migration this saved-row policy lets owner A read owner
-- B's entire raw partner record, including every private sentinel above.
insert into public.saves(user_id, partner_id)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '22222222-2222-4222-8222-222222222222'
);
