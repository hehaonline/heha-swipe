-- Partner profile change-request queue.
--
-- Pending/pre-approval listings can be edited directly through the secured partners policy.
-- Approved/live/listed listings stay locked from direct owner UPDATE and instead submit
-- safe profile-field changes here for HEHA review.

create table if not exists public.partner_profile_change_requests (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  owner_id uuid not null,
  proposed_changes jsonb not null,
  status text not null default 'submitted',
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint partner_profile_change_requests_changes_object
    check (jsonb_typeof(proposed_changes) = 'object'),
  constraint partner_profile_change_requests_status_check
    check (status in ('submitted', 'needs_info', 'approved', 'rejected', 'applied', 'cancelled'))
);

create index if not exists partner_profile_change_requests_partner_idx
  on public.partner_profile_change_requests(partner_id, submitted_at desc);

create index if not exists partner_profile_change_requests_status_idx
  on public.partner_profile_change_requests(status, submitted_at desc);

alter table public.partner_profile_change_requests enable row level security;

revoke all on table public.partner_profile_change_requests from anon;
revoke all on table public.partner_profile_change_requests from authenticated;
grant select, insert, update on table public.partner_profile_change_requests to authenticated;

create or replace function app_private.guard_partner_profile_change_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  owner_editable_keys constant text[] := array[
    'name',
    'category',
    'location',
    'contact',
    'instagram',
    'website',
    'bio',
    'tags',
    'hours',
    'business_type',
    'offerings',
    'neighborhood',
    'tagline',
    'phone',
    'price_range',
    'delivery_days',
    'pricing_notes'
  ];
begin
  -- Backend/service writes do not carry an end-user auth.uid().
  if actor_id is null then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
    end if;
    return new;
  end if;

  -- HEHA technical/admin users may manage the review workflow.
  if app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']) then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
      if new.status in ('approved', 'rejected', 'applied', 'needs_info') and new.reviewed_at is null then
        new.reviewed_at := now();
        new.reviewed_by := actor_id;
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      raise exception using
        errcode = '42501',
        message = 'Partner change requests must belong to the signed-in owner.';
    end if;

    if not exists (
      select 1
      from public.partners p
      where p.id = new.partner_id
        and p.owner_id = actor_id
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partner change requests may only target your own listing.';
    end if;

    if new.proposed_changes is null
       or jsonb_typeof(new.proposed_changes) <> 'object'
       or new.proposed_changes = '{}'::jsonb then
      raise exception using
        errcode = '22023',
        message = 'Partner change requests need at least one proposed profile change.';
    end if;

    if exists (
      select 1
      from jsonb_object_keys(new.proposed_changes) as proposed_key
      where not (proposed_key = any (owner_editable_keys))
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partner change requests may only contain approved business profile fields.';
    end if;

    new.status := 'submitted';
    new.submitted_at := now();
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_note := null;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Partner owners cannot directly modify profile change requests after submission.';
end;
$$;

revoke all on function app_private.guard_partner_profile_change_request() from public, anon, authenticated;

drop trigger if exists partner_profile_change_request_guard on public.partner_profile_change_requests;
create trigger partner_profile_change_request_guard
before insert or update on public.partner_profile_change_requests
for each row
execute function app_private.guard_partner_profile_change_request();

drop policy if exists "Owners can view own partner profile change requests" on public.partner_profile_change_requests;
create policy "Owners can view own partner profile change requests"
on public.partner_profile_change_requests
for select
to authenticated
using (owner_id = auth.uid());

drop policy if exists "Owners can submit own partner profile change requests" on public.partner_profile_change_requests;
create policy "Owners can submit own partner profile change requests"
on public.partner_profile_change_requests
for insert
to authenticated
with check (
  owner_id = auth.uid()
  and exists (
    select 1
    from public.partners p
    where p.id = partner_id
      and p.owner_id = auth.uid()
  )
);

drop policy if exists "Internal users can view partner profile change requests" on public.partner_profile_change_requests;
create policy "Internal users can view partner profile change requests"
on public.partner_profile_change_requests
for select
to authenticated
using (
  app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin'])
);

drop policy if exists "Internal users can update partner profile change requests" on public.partner_profile_change_requests;
create policy "Internal users can update partner profile change requests"
on public.partner_profile_change_requests
for update
to authenticated
using (
  app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin'])
)
with check (
  app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin'])
);

comment on table public.partner_profile_change_requests is
  'Review queue for owner-proposed profile edits on listings that are locked from direct self-service updates.';
