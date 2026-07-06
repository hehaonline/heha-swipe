-- Partner media manager foundation.
--
-- Current public partner imagery remains on partners.image_url / gallery_urls and legacy
-- partner_photos. New owner uploads are stored privately and reviewed before replacing public media.

alter table public.partners
  add column if not exists logo_url text;

create table if not exists public.partner_media_requests (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  owner_id uuid not null,
  media_type text not null,
  change_type text not null default 'add',
  storage_path text,
  replaces_url text,
  original_filename text,
  mime_type text,
  file_size_bytes bigint,
  position integer not null default 0,
  status text not null default 'submitted',
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint partner_media_requests_media_type_check
    check (media_type in ('logo', 'cover', 'gallery')),
  constraint partner_media_requests_change_type_check
    check (change_type in ('add', 'replace', 'remove')),
  constraint partner_media_requests_status_check
    check (status in ('submitted', 'needs_info', 'approved', 'rejected', 'applied', 'cancelled')),
  constraint partner_media_requests_position_check
    check (position between 0 and 5),
  constraint partner_media_requests_file_size_check
    check (file_size_bytes is null or file_size_bytes between 1 and 8388608),
  constraint partner_media_requests_change_payload_check
    check (
      (change_type = 'remove' and storage_path is null and replaces_url is not null)
      or
      (change_type = 'add' and storage_path is not null)
      or
      (change_type = 'replace' and storage_path is not null and replaces_url is not null)
    )
);

create index if not exists partner_media_requests_partner_idx
  on public.partner_media_requests(partner_id, submitted_at desc);

create index if not exists partner_media_requests_status_idx
  on public.partner_media_requests(status, submitted_at desc);

alter table public.partner_media_requests enable row level security;

revoke all on table public.partner_media_requests from anon;
revoke all on table public.partner_media_requests from authenticated;
grant select, insert on table public.partner_media_requests to authenticated;
grant update on table public.partner_media_requests to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'partner-media-pending',
  'partner-media-pending',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function app_private.guard_partner_logo_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is not null
     and new.owner_id = actor_id
     and not app_private.has_internal_role(array['super_admin', 'developer_admin']) then
    new.logo_url := null;
  end if;
  return new;
end;
$$;

revoke all on function app_private.guard_partner_logo_insert() from public, anon, authenticated;

drop trigger if exists b_partner_logo_insert_guard on public.partners;
create trigger b_partner_logo_insert_guard
before insert on public.partners
for each row
execute function app_private.guard_partner_logo_insert();

create or replace function app_private.guard_partner_media_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  active_gallery_count integer;
begin
  if actor_id is null then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
    end if;
    return new;
  end if;

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
        message = 'Partner media requests must belong to the signed-in owner.';
    end if;

    if not exists (
      select 1
      from public.partners p
      where p.id = new.partner_id
        and p.owner_id = actor_id
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partner media requests may only target your own listing.';
    end if;

    if new.storage_path is not null
       and new.storage_path not like actor_id::text || '/' || new.partner_id::text || '/%' then
      raise exception using
        errcode = '42501',
        message = 'Partner media storage path does not match the signed-in owner and listing.';
    end if;

    if new.media_type = 'gallery' and new.change_type <> 'remove' then
      select count(*)
      into active_gallery_count
      from public.partner_media_requests r
      where r.partner_id = new.partner_id
        and r.media_type = 'gallery'
        and r.status in ('submitted', 'needs_info', 'approved');

      if active_gallery_count >= 6 then
        raise exception using
          errcode = '23514',
          message = 'A maximum of six active gallery uploads is allowed while media is under review.';
      end if;
    end if;

    if new.media_type in ('logo', 'cover')
       and new.change_type <> 'remove'
       and exists (
         select 1
         from public.partner_media_requests r
         where r.partner_id = new.partner_id
           and r.media_type = new.media_type
           and r.status in ('submitted', 'needs_info')
       ) then
      raise exception using
        errcode = '23505',
        message = 'A logo or cover upload is already waiting for HEHA review.';
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
    message = 'Partner owners cannot directly modify media requests after submission.';
end;
$$;

revoke all on function app_private.guard_partner_media_request() from public, anon, authenticated;

drop trigger if exists partner_media_request_guard on public.partner_media_requests;
create trigger partner_media_request_guard
before insert or update on public.partner_media_requests
for each row
execute function app_private.guard_partner_media_request();

drop policy if exists "Owners can view own partner media requests" on public.partner_media_requests;
create policy "Owners can view own partner media requests"
on public.partner_media_requests
for select
to authenticated
using (owner_id = auth.uid());

drop policy if exists "Owners can submit own partner media requests" on public.partner_media_requests;
create policy "Owners can submit own partner media requests"
on public.partner_media_requests
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

drop policy if exists "Internal users can view partner media requests" on public.partner_media_requests;
create policy "Internal users can view partner media requests"
on public.partner_media_requests
for select
to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']));

drop policy if exists "Internal users can update partner media requests" on public.partner_media_requests;
create policy "Internal users can update partner media requests"
on public.partner_media_requests
for update
to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']))
with check (app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']));

-- Private pending media. Owners may access only their own owner/partner path.
drop policy if exists "Owners can upload own pending partner media" on storage.objects;
create policy "Owners can upload own pending partner media"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'partner-media-pending'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.partners p
    where p.owner_id = auth.uid()
      and p.id::text = (storage.foldername(name))[2]
  )
);

drop policy if exists "Owners can view own pending partner media" on storage.objects;
create policy "Owners can view own pending partner media"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'partner-media-pending'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.partners p
    where p.owner_id = auth.uid()
      and p.id::text = (storage.foldername(name))[2]
  )
);

drop policy if exists "Owners can delete own pending partner media" on storage.objects;
create policy "Owners can delete own pending partner media"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'partner-media-pending'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.partners p
    where p.owner_id = auth.uid()
      and p.id::text = (storage.foldername(name))[2]
  )
);

drop policy if exists "Internal users can view pending partner media" on storage.objects;
create policy "Internal users can view pending partner media"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'partner-media-pending'
  and app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin'])
);

drop policy if exists "Internal users can manage pending partner media" on storage.objects;
create policy "Internal users can manage pending partner media"
on storage.objects
for all
to authenticated
using (
  bucket_id = 'partner-media-pending'
  and app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin'])
)
with check (
  bucket_id = 'partner-media-pending'
  and app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin'])
);

comment on table public.partner_media_requests is
  'Private review queue for partner logo, cover, and gallery additions, replacements, and removals before public media changes.';
