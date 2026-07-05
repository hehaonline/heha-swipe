-- Applied to HEHA SWIPE Supabase on 2026-06-18.
-- Internal-only Niña Community / Events dashboard tables and RLS policies.
-- This migration relies on existing public.user_roles and app_private.has_internal_role().

create table if not exists public.event_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_name text not null,
  brand_or_business_name text,
  application_type text not null default 'community_lead',
  email text,
  phone text,
  instagram text,
  website text,
  category text,
  event_interest text,
  proposed_contribution text,
  needs_booth boolean not null default false,
  needs_performance_slot boolean not null default false,
  wants_to_sponsor boolean not null default false,
  notes text,
  status text not null default 'new',
  reviewed_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.event_concepts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_type text not null default 'community_activation',
  event_goal text,
  target_audience text,
  theme_or_vibe text,
  proposed_location text,
  proposed_date_window text,
  estimated_size text,
  possible_partners text,
  budget_needed text,
  sponsor_potential text,
  risks text,
  questions text,
  content_needed boolean not null default false,
  status text not null default 'draft',
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invite_list (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_method text,
  email text,
  phone text,
  instagram text,
  category text,
  neighborhood text,
  relationship_strength text,
  event_concept_id uuid references public.event_concepts(id) on delete set null,
  invite_status text not null default 'not_contacted',
  rsvp_status text not null default 'unknown',
  follow_up_date date,
  notes text,
  approval_needed boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_outreach (
  id uuid primary key default gen_random_uuid(),
  lead_name text not null,
  lead_type text,
  source text,
  contact_info text,
  interest_area text,
  conversation_notes text,
  next_step text,
  follow_up_date date,
  status text not null default 'new_lead',
  assigned_to uuid references auth.users(id),
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.event_recaps (
  id uuid primary key default gen_random_uuid(),
  event_concept_id uuid references public.event_concepts(id) on delete set null,
  event_name text not null,
  event_date date,
  location text,
  estimated_attendance integer,
  partners_involved text,
  new_leads_collected integer,
  app_signups integer,
  photos_videos_link text,
  what_worked text,
  what_did_not_work text,
  follow_up_needed text,
  next_event_recommendation text,
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.admin_content_requests add column if not exists dashboard_area text not null default 'pm';
alter table public.admin_content_requests add column if not exists request_title text;
alter table public.admin_content_requests add column if not exists related_type text;
alter table public.admin_content_requests add column if not exists related_id uuid;
alter table public.admin_content_requests add column if not exists related_event_id uuid references public.event_concepts(id) on delete set null;
alter table public.admin_content_requests add column if not exists related_application_id uuid references public.event_applications(id) on delete set null;
alter table public.admin_content_requests add column if not exists audience text;
alter table public.admin_content_requests add column if not exists assets_link text;
alter table public.admin_approval_requests add column if not exists dashboard_area text not null default 'pm';
alter table public.admin_approval_requests add column if not exists assigned_to uuid references auth.users(id);

alter table public.event_applications enable row level security;
alter table public.event_concepts enable row level security;
alter table public.invite_list enable row level security;
alter table public.community_outreach enable row level security;
alter table public.event_recaps enable row level security;

create policy event_applications_internal_select on public.event_applications for select to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy event_applications_internal_insert on public.event_applications for insert to authenticated with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']) and status <> 'approved');
create policy event_applications_internal_update on public.event_applications for update to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin'])) with check (app_private.has_internal_role(array['super_admin','developer_admin']) or status <> 'approved');
create policy event_applications_super_delete on public.event_applications for delete to authenticated using (app_private.has_internal_role(array['super_admin','developer_admin']));

create policy event_concepts_internal_select on public.event_concepts for select to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy event_concepts_internal_insert on public.event_concepts for insert to authenticated with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']) and status not in ('approved','scheduled','published'));
create policy event_concepts_internal_update on public.event_concepts for update to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin'])) with check (app_private.has_internal_role(array['super_admin','developer_admin']) or status not in ('approved','scheduled','published'));
create policy event_concepts_super_delete on public.event_concepts for delete to authenticated using (app_private.has_internal_role(array['super_admin','developer_admin']));

create policy invite_list_internal_select on public.invite_list for select to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy invite_list_internal_insert on public.invite_list for insert to authenticated with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy invite_list_internal_update on public.invite_list for update to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin'])) with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy invite_list_super_delete on public.invite_list for delete to authenticated using (app_private.has_internal_role(array['super_admin','developer_admin']));

create policy community_outreach_internal_select on public.community_outreach for select to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy community_outreach_internal_insert on public.community_outreach for insert to authenticated with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy community_outreach_internal_update on public.community_outreach for update to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin'])) with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy community_outreach_super_delete on public.community_outreach for delete to authenticated using (app_private.has_internal_role(array['super_admin','developer_admin']));

create policy event_recaps_internal_select on public.event_recaps for select to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy event_recaps_internal_insert on public.event_recaps for insert to authenticated with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy event_recaps_internal_update on public.event_recaps for update to authenticated using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin'])) with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','developer_admin']));
create policy event_recaps_super_delete on public.event_recaps for delete to authenticated using (app_private.has_internal_role(array['super_admin','developer_admin']));

create index if not exists event_applications_status_idx on public.event_applications(status);
create index if not exists event_concepts_status_idx on public.event_concepts(status);
create index if not exists invite_list_status_idx on public.invite_list(invite_status, rsvp_status);
create index if not exists community_outreach_status_idx on public.community_outreach(status);
create index if not exists event_recaps_event_date_idx on public.event_recaps(event_date);
create index if not exists admin_content_requests_dashboard_area_idx on public.admin_content_requests(dashboard_area, status);
create index if not exists admin_approval_requests_dashboard_area_idx on public.admin_approval_requests(dashboard_area, status);
