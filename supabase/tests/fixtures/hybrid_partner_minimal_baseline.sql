-- Synthetic, disposable baseline for PR #120 only. Never Production.
-- Mirrors the current-main partner columns touched by the hybrid migration,
-- owner guard and public projection closely enough to execute behavioral proofs.

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
  is_test_record boolean not null default false
);

alter table public.partners enable row level security;
grant select,insert,update on public.partners to authenticated;
create policy partners_owner_read on public.partners for select to authenticated using(owner_id=auth.uid());
create policy partners_owner_insert on public.partners for insert to authenticated with check(auth.uid()=owner_id);
-- Mirrors current main's pre-approval owner UPDATE policy from
-- 20260706093000_partner_owner_self_service_security.sql so the owner guard is
-- exercised under the same predicate Production uses.
create policy "Owners can update own preapproval partner profile" on public.partners
for update to authenticated
using (
  auth.uid()=owner_id
  and coalesce(status,'')=any(array['draft','submitted','pending','missing_info']::text[])
)
with check (
  auth.uid()=owner_id
  and coalesce(status,'')=any(array['draft','submitted','pending','missing_info']::text[])
);
create policy partners_public_read on public.partners for select to anon,authenticated using(status in ('approved','live'));

create table public.saves(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.swipes(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  direction text not null,
  created_at timestamptz not null default now()
);

create or replace function app_private.has_internal_role(required_roles text[])
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.active and r.role=any(required_roles));
$$;
revoke all on function app_private.has_internal_role(text[]) from public,anon,authenticated;
grant execute on function app_private.has_internal_role(text[]) to anon,authenticated,service_role;

create or replace function app_private.normalize_partner_categories(selected_categories text[],primary_category text)
returns text[] language sql immutable set search_path=pg_catalog,public,pg_temp
as $$
  select coalesce(array_agg(x.category order by x.first_position),array[]::text[])
  from (
    select btrim(e.value) category,min(e.position) first_position
    from unnest(coalesce(selected_categories,array[]::text[]) || case when nullif(btrim(primary_category),'') is null then array[]::text[] else array[btrim(primary_category)] end)
      with ordinality e(value,position)
    where nullif(btrim(e.value),'') is not null
    group by btrim(e.value)
  ) x;
$$;
revoke all on function app_private.normalize_partner_categories(text[],text) from public,anon,authenticated;

create or replace function app_private.partner_completion_pct(partner_row public.partners)
returns integer language sql immutable set search_path=pg_catalog,public,pg_temp
as $$ select 0; $$;
revoke all on function app_private.partner_completion_pct(public.partners) from public,anon,authenticated;

-- Current main installs the owner self-service guard trigger in
-- 20260706093000_partner_owner_self_service_security.sql. The hybrid migration
-- replaces the function body but not the trigger, so the fixture must carry the
-- trigger for the proof to exercise the real owner-guard surface. This stub is
-- overwritten by `create or replace` in the hybrid migration.
create or replace function app_private.guard_partner_owner_self_service()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$ begin return new; end $$;
revoke all on function app_private.guard_partner_owner_self_service() from public,anon,authenticated;

drop trigger if exists a_partner_owner_self_service_guard on public.partners;
create trigger a_partner_owner_self_service_guard
before insert or update on public.partners
for each row execute function app_private.guard_partner_owner_self_service();

insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous,created_at,updated_at)
values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','authenticated','authenticated','owner-a@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now()),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','authenticated','authenticated','owner-b@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now()),
('cccccccc-cccc-4ccc-8ccc-cccccccccccc','authenticated','authenticated','admin@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now()),
('dddddddd-dddd-4ddd-8ddd-dddddddddddd','authenticated','authenticated','super@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now()),
('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','authenticated','authenticated','unverified@example.invalid',null,'{"provider":"email","providers":["email"]}','{}',false,false,now(),now()),
('ffffffff-ffff-4fff-8fff-ffffffffffff','authenticated','authenticated','anonymous@example.invalid',now(),'{"provider":"anonymous","providers":["anonymous"]}','{}',false,true,now(),now()),
('99999999-9999-4999-8999-999999999999','authenticated','authenticated',null,now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now());

insert into public.user_roles(user_id,role,active) values
('cccccccc-cccc-4ccc-8ccc-cccccccccccc','developer_admin',true),
('dddddddd-dddd-4ddd-8ddd-dddddddddddd','super_admin',true);

insert into public.partners(id,owner_id,name,status,heha_partner,swipe_eligible,is_test_record)
values
('11111111-1111-4111-8111-111111111111',null,'Synthetic Business A','approved',false,true,false),
('22222222-2222-4222-8222-222222222222',null,'Synthetic Business B','approved',false,true,false),
('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Already Owned Business','approved',false,true,false),
('44444444-4444-4444-8444-444444444444',null,'Ambiguous Legacy Partner','approved',true,true,false),
('55555555-5555-4555-8555-555555555555',null,'Redeem Race Business','approved',false,true,false);

-- Pre-approval owned profile: the exact predicate the owner UPDATE policy allows,
-- used to prove a caller-supplied lifecycle context cannot widen owner self-service.
insert into public.partners(id,owner_id,name,status,heha_partner,swipe_eligible,is_test_record)
values('66666666-6666-4666-8666-666666666666','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Preapproval Owned Business','pending',false,true,false);

insert into public.saves(user_id,partner_id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111');
insert into public.swipes(user_id,partner_id,direction) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','right');
