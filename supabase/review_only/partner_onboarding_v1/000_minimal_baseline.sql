-- Synthetic PostgreSQL baseline for the HEHA partner-onboarding V1 proof.
--
-- REVIEW ONLY. This file is intentionally outside supabase/migrations and must
-- never be applied to a hosted HEHA project. It supplies only the roles, Auth
-- shim, and representative partner columns needed by disposable CI.

-- CI must opt in from outside SQL, for example:
-- PGOPTIONS='-c heha.review_only=on' psql ...
-- Keeping the opt-in outside this file prevents a copied script from
-- self-authorizing against a hosted database.
-- The guard runs inside the transaction so a client without ON_ERROR_STOP
-- cannot continue into mutation after the exception.
begin;

do $review_only_guard$
begin
  if coalesce(pg_catalog.current_setting('heha.review_only', true), '') <> 'on'
     or pg_catalog.current_database() <> 'partner_onboarding_review'
     or coalesce(pg_catalog.inet_server_addr()::text, '') not in ('127.0.0.1', '::1') then
    raise exception 'HEHA_REVIEW_ONLY_GUARD'
      using errcode = '42501',
            hint = 'Requires loopback database partner_onboarding_review and externally supplied heha.review_only=on.';
  end if;
end;
$review_only_guard$;

set local client_min_messages = warning;

create extension if not exists pgcrypto with schema public;

do $pgcrypto_schema_guard$
declare
  v_schema text;
begin
  select nsp.nspname
    into v_schema
  from pg_catalog.pg_extension ext
  join pg_catalog.pg_namespace nsp
    on nsp.oid = ext.extnamespace
  where ext.extname = 'pgcrypto';

  if v_schema is distinct from 'public' then
    raise exception 'HEHA_REVIEW_ONLY_PGCRYPTO_SCHEMA'
      using errcode = '55000',
            detail = pg_catalog.format(
              'Expected pgcrypto in public for the disposable baseline; found %s.',
              coalesce(v_schema, '<missing>')
            );
  end if;
end;
$pgcrypto_schema_guard$;

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
  else
    alter role service_role bypassrls;
  end if;

  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin nologin;
  end if;
end;
$roles$;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text not null unique,
  email_confirmed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now()
);

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

revoke all on schema auth from public, anon, authenticated, service_role, supabase_auth_admin;
grant usage on schema auth to anon, authenticated, service_role, supabase_auth_admin;

revoke all on function auth.uid() from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function auth.uid() to anon, authenticated, service_role, supabase_auth_admin;

revoke all on table auth.users from public, anon, authenticated, service_role, supabase_auth_admin;
grant select (id, email, email_confirmed_at) on table auth.users to supabase_auth_admin;

insert into auth.users (id, email, email_confirmed_at)
values
  ('00000000-0000-4000-8000-0000000000a1', 'operator-a@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-0000000000b2', 'signer-b@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-0000000000c3', 'applicant-c@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-0000000000d4', 'other-d@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-0000000000e5', 'reviewer-e@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000101', 'swipe-attestor@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000102', 'website-attestor@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000103', 'local-attestor@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000104', 'legal-admin@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000105', 'evidence-reviewer@example.invalid', '2026-08-31 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000106', 'release-reviewer@example.invalid', '2026-08-31 12:00:00+00')
on conflict (id) do update
set email = excluded.email,
    email_confirmed_at = excluded.email_confirmed_at;

create table if not exists public.partners (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  legal_name text,
  postal_code text,
  category text,
  categories text[] not null default '{}'::text[],
  location text,
  contact text,
  instagram text,
  website text,
  bio text,
  tags text[] not null default '{}'::text[],
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
  hours jsonb not null default '{}'::jsonb,
  google_place_id text,
  business_type text,
  offerings text[] not null default '{}'::text[],
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
  delivery_days text[] not null default '{}'::text[],
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
  routing_updated_by uuid references auth.users(id) on delete set null,
  routing_updated_at timestamptz,
  is_test_record boolean not null default false,
  constraint partners_status_check check (
    status in ('draft', 'submitted', 'pending', 'missing_info', 'approved', 'live', 'paused')
  ),
  constraint partners_local_lane_check check (
    local_lane is null
    or local_lane in ('meals', 'market', 'vendors', 'chef', 'group_orders')
  )
);

alter table public.partners enable row level security;
alter table public.partners force row level security;

revoke all on table public.partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select on table public.partners to anon, authenticated;
-- Model the legacy owner-write surface that the successor foundation must
-- explicitly remove. These policies intentionally permit pending self-service
-- profile creation/editing and are proven absent after 001 applies.
grant insert, update on table public.partners to authenticated;

drop policy if exists "Legacy partner owner inserts pending profile" on public.partners;
create policy "Legacy partner owner inserts pending profile"
on public.partners
for insert
to authenticated
with check (
  (select auth.uid()) = owner_id
  and status in ('draft', 'submitted', 'pending', 'missing_info')
  and is_test_record = false
);

drop policy if exists "Legacy partner owner updates pending profile" on public.partners;
create policy "Legacy partner owner updates pending profile"
on public.partners
for update
to authenticated
using (
  (select auth.uid()) = owner_id
  and status in ('draft', 'submitted', 'pending', 'missing_info')
)
with check (
  (select auth.uid()) = owner_id
  and status in ('draft', 'submitted', 'pending', 'missing_info')
  and is_test_record = false
);

drop policy if exists "Synthetic legacy public status visibility" on public.partners;
create policy "Synthetic legacy public status visibility"
on public.partners
for select
to anon, authenticated
using (
  status in ('approved', 'live')
  and is_test_record = false
);

drop policy if exists "Synthetic partner owner reads private profile" on public.partners;
create policy "Synthetic partner owner reads private profile"
on public.partners
for select
to authenticated
using ((select auth.uid()) = owner_id);

create or replace view public.public_partner_directory
with (security_invoker = true)
as
select p.*
from public.partners p
where p.status in ('approved', 'live')
  and coalesce(p.website_eligible, false)
  and p.is_test_record = false;

create or replace view public.public_swipe_partners
with (security_invoker = true)
as
select p.*
from public.partners p
where p.status in ('approved', 'live')
  and coalesce(p.swipe_eligible, false)
  and p.is_test_record = false;

create or replace view public.public_local_partners
with (security_invoker = true)
as
select p.*
from public.partners p
where p.status in ('approved', 'live')
  and coalesce(p.local_eligible, false)
  and p.local_lane is not null
  and p.is_test_record = false;

revoke all on table public.public_partner_directory
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on table public.public_swipe_partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on table public.public_local_partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

comment on table public.partners is
  'Synthetic compatibility surface for disposable partner-onboarding proof only.';

commit;
