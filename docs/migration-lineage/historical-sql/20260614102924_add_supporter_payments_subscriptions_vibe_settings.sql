-- HEHA Swipe Stripe/support readiness tables.
-- Recovered source for live migration 20260614102924 during pre-smoke
-- source-control reconciliation. Live schema, constraints, indexes, triggers and
-- RLS policies were verified against this source on 2026-07-08.
-- This file restores migration lineage in the correct HEHA Swipe repository;
-- it must not be manually re-applied to the already-migrated live project.

create table if not exists public.supporter_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id text,
  stripe_customer_id text,
  amount_cents integer not null default 0 check (amount_cents >= 0),
  currency text not null default 'usd',
  support_type text not null default 'other' check (support_type in ('dollar_support', 'superswoop', 'supporter_membership', 'other')),
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'cancelled', 'refunded')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.supporter_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  stripe_subscription_id text unique not null,
  stripe_customer_id text,
  stripe_price_id text,
  quantity integer not null default 1 check (quantity between 1 and 100),
  amount_cents integer not null default 100 check (amount_cents >= 0),
  currency text not null default 'usd',
  status text not null default 'incomplete',
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  canceled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vibe_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  passions text[] not null default '{}'::text[],
  interests text[] not null default '{}'::text[],
  discovery_goals text[] not null default '{}'::text[],
  dietary_preferences text[] not null default '{}'::text[],
  movement_preferences text[] not null default '{}'::text[],
  preferred_radius_miles integer not null default 10 check (preferred_radius_miles between 1 and 100),
  accent_color text not null default 'heha_orange',
  onboarding_complete boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_supporter_payments_user_id on public.supporter_payments(user_id);
create index if not exists idx_supporter_payments_stripe_customer_id on public.supporter_payments(stripe_customer_id);
create index if not exists idx_supporter_payments_support_type on public.supporter_payments(support_type);
create index if not exists idx_supporter_subscriptions_user_id on public.supporter_subscriptions(user_id);
create index if not exists idx_supporter_subscriptions_stripe_customer_id on public.supporter_subscriptions(stripe_customer_id);
create index if not exists idx_vibe_settings_user_id on public.vibe_settings(user_id);

create or replace function public.heha_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_supporter_payments_updated_at on public.supporter_payments;
create trigger set_supporter_payments_updated_at
before update on public.supporter_payments
for each row execute function public.heha_set_updated_at();

drop trigger if exists set_supporter_subscriptions_updated_at on public.supporter_subscriptions;
create trigger set_supporter_subscriptions_updated_at
before update on public.supporter_subscriptions
for each row execute function public.heha_set_updated_at();

drop trigger if exists set_vibe_settings_updated_at on public.vibe_settings;
create trigger set_vibe_settings_updated_at
before update on public.vibe_settings
for each row execute function public.heha_set_updated_at();

alter table public.supporter_payments enable row level security;
alter table public.supporter_subscriptions enable row level security;
alter table public.vibe_settings enable row level security;

create policy "Users can view own supporter payments"
on public.supporter_payments
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can view own supporter subscriptions"
on public.supporter_subscriptions
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can view own vibe settings"
on public.vibe_settings
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can insert own vibe settings"
on public.vibe_settings
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own vibe settings"
on public.vibe_settings
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
