-- Test-only synthetic baseline for PR #82 cloud proof.
-- This file is never intended for production application.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists app_private;

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_roles_role_check check (
    role = any (
      array[
        'super_admin',
        'pm_admin',
        'developer_admin',
        'content_editor',
        'wix_support',
        'community_events_admin',
        'viewer'
      ]::text[]
    )
  )
);

alter table public.user_roles enable row level security;

create table public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  action_type text not null,
  related_type text,
  related_id uuid,
  previous_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_audit_logs enable row level security;

create table public.partners (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  category text not null,
  tagline text,
  status text not null default 'approved',
  heha_partner boolean not null default false,
  website_eligible boolean,
  swipe_eligible boolean,
  local_eligible boolean,
  routing_status text not null default 'suggested',
  items jsonb not null default '[]'::jsonb,
  total_swipes integer not null default 0,
  total_saves integer not null default 0,
  total_profile_views integer not null default 0,
  is_test_record boolean not null default true
);

alter table public.partners enable row level security;
grant select, update on table public.partners to authenticated;

create policy partners_owner_read
on public.partners
for select
to authenticated
using (auth.uid() = owner_id);

create policy partners_owner_update
on public.partners
for update
to authenticated
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

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

create or replace function app_private.has_internal_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.active = true
      and ur.role = any(required_roles)
  );
$$;

revoke all on function app_private.has_internal_role(text[]) from public, anon, authenticated;

insert into auth.users (
  id,
  aud,
  role,
  email,
  email_confirmed_at,
  confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_sso_user,
  is_anonymous,
  created_at,
  updated_at
) values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'authenticated',
    'authenticated',
    'claim-owner-a@example.invalid',
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    false,
    false,
    now(),
    now()
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'authenticated',
    'authenticated',
    'claim-owner-b@example.invalid',
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    false,
    false,
    now(),
    now()
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'authenticated',
    'authenticated',
    'claim-admin@example.invalid',
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    false,
    false,
    now(),
    now()
  );

insert into public.user_roles (user_id, role, active)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'developer_admin', true);

insert into public.partners (
  id,
  owner_id,
  name,
  category,
  tagline,
  status,
  heha_partner,
  website_eligible,
  swipe_eligible,
  local_eligible,
  routing_status,
  items,
  total_swipes,
  total_saves,
  total_profile_views,
  is_test_record
) values
  (
    '11111111-1111-4111-8111-111111111111',
    null,
    'Synthetic Business A',
    'Nourish',
    'Original A tagline',
    'approved',
    false,
    true,
    true,
    false,
    'reviewed',
    '[{"name":"Synthetic Item A"}]'::jsonb,
    12,
    4,
    31,
    true
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    null,
    'Synthetic Business B',
    'Elevate',
    'Original B tagline',
    'approved',
    false,
    true,
    true,
    false,
    'reviewed',
    '[]'::jsonb,
    8,
    2,
    16,
    true
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'Synthetic Already Owned Business',
    'Relax',
    'Already owned',
    'approved',
    false,
    true,
    true,
    false,
    'reviewed',
    '[]'::jsonb,
    1,
    1,
    1,
    true
  ),
  (
    '44444444-4444-4444-8444-444444444444',
    null,
    'Synthetic Opted-Out Business',
    'Educate',
    'Opted out fixture',
    'approved',
    false,
    false,
    false,
    false,
    'reviewed',
    '[]'::jsonb,
    0,
    0,
    0,
    true
  ),
  (
    '55555555-5555-4555-8555-555555555555',
    null,
    'Synthetic Official Partner',
    'Nourish',
    'Official relationship fixture',
    'approved',
    true,
    true,
    true,
    true,
    'reviewed',
    '[{"name":"Official Synthetic Item"}]'::jsonb,
    5,
    3,
    22,
    true
  ),
  (
    '66666666-6666-4666-8666-666666666666',
    null,
    'Synthetic Atomicity Business',
    'Elevate',
    'Atomicity fixture',
    'approved',
    false,
    true,
    true,
    false,
    'reviewed',
    '[]'::jsonb,
    0,
    0,
    0,
    true
  );

insert into public.saves (user_id, partner_id)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111');

insert into public.swipes (user_id, partner_id, direction)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'right');
