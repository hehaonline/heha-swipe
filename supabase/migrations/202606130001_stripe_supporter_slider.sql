-- HEHA Swipe Stripe supporter slider support
-- Adds the database fields needed for custom monthly Stripe subscriptions,
-- paid SuperSwoops, and optional $1 prototype support pushes.

alter table public.profiles
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists subscription_status text,
  add column if not exists subscription_amount numeric default 0,
  add column if not exists subscription_current_period_end timestamptz;

create index if not exists profiles_stripe_customer_id_idx
  on public.profiles (stripe_customer_id);

create index if not exists profiles_stripe_subscription_id_idx
  on public.profiles (stripe_subscription_id);

create table if not exists public.superswoops (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  partner_id uuid not null,
  amount numeric not null default 2.00,
  currency text not null default 'usd',
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create index if not exists superswoops_user_id_idx
  on public.superswoops (user_id);

create index if not exists superswoops_partner_id_idx
  on public.superswoops (partner_id);

create index if not exists superswoops_status_idx
  on public.superswoops (status);

create table if not exists public.support_pushes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  amount numeric not null default 1.00,
  currency text not null default 'usd',
  source text not null default 'pre_splash',
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create index if not exists support_pushes_user_id_idx
  on public.support_pushes (user_id);

create index if not exists support_pushes_status_idx
  on public.support_pushes (status);
