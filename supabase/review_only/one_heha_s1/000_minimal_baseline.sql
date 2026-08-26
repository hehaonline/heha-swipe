-- Synthetic PostgreSQL baseline for the ONE HEHA S1 review package.
--
-- This file is CI-only and deliberately lives outside supabase/migrations.
-- It is not a replacement for the canonical HEHA Swipe schema or migration
-- lineage and must never be applied to Production.

create extension if not exists pgcrypto;

set client_min_messages = warning;

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
  email text,
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

revoke all on function auth.uid() from public;
grant execute on function auth.uid() to anon, authenticated, service_role, supabase_auth_admin;

grant usage on schema auth to supabase_auth_admin;
grant select (id) on table auth.users to supabase_auth_admin;
grant delete on table auth.users to supabase_auth_admin;

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-0000000000a1', 'swipe-a@example.invalid'),
  ('00000000-0000-0000-0000-0000000000b2', 'swipe-b@example.invalid'),
  ('00000000-0000-0000-0000-0000000000c3', 'swipe-c@example.invalid')
on conflict (id) do nothing;
