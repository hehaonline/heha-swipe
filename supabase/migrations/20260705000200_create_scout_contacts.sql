create table if not exists public.scout_contacts (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.scout_leads(id) on delete cascade,
  contact_name text,
  contact_role text,
  phone text,
  email text,
  instagram text,
  linkedin text,
  is_primary boolean not null default false,
  contact_status text not null default 'identified',
  notes text,
  created_by uuid default auth.uid(),
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.scout_contacts enable row level security;
