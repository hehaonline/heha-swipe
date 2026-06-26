create table if not exists public.supporter_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_checkout_session_id text,
  support_amount_cents integer not null check (support_amount_cents between 100 and 10000),
  status text not null default 'pending',
  current_period_start timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists supporter_subscriptions_stripe_subscription_id_uidx
  on public.supporter_subscriptions (stripe_subscription_id)
  where stripe_subscription_id is not null;

create unique index if not exists supporter_subscriptions_stripe_checkout_session_id_uidx
  on public.supporter_subscriptions (stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create index if not exists supporter_subscriptions_user_id_idx
  on public.supporter_subscriptions (user_id);

alter table public.supporter_subscriptions enable row level security;

grant select on table public.supporter_subscriptions to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'supporter_subscriptions'
      and policyname = 'Users can read own supporter subscriptions'
  ) then
    create policy "Users can read own supporter subscriptions"
      on public.supporter_subscriptions
      for select
      to authenticated
      using ((select auth.uid()) = user_id);
  end if;
end $$;
