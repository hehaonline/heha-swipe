-- HEHA Swipe Vibe Setter
-- Stores user passions/interests and a preferred accent theme for personalized discovery.

alter table public.profiles
  add column if not exists vibe_passions text[] default '{}',
  add column if not exists vibe_interests text[] default '{}',
  add column if not exists vibe_theme text default 'earth';

create index if not exists profiles_vibe_passions_gin_idx
  on public.profiles using gin (vibe_passions);

create index if not exists profiles_vibe_interests_gin_idx
  on public.profiles using gin (vibe_interests);

create index if not exists profiles_vibe_theme_idx
  on public.profiles (vibe_theme);
