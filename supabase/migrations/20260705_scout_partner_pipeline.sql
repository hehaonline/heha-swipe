-- HEHA Scout & Partner Pipeline
-- Shared internal lead intake for Admin, Project Manager, SOM, and Community Events.

create table if not exists public.scout_leads (
  id uuid primary key default gen_random_uuid(),
  business_name text,
  lead_type text not null default 'potential_partner'
    check (lead_type = any (array[
      'potential_partner', 'heha_swipe_business', 'event_partner',
      'event_venue', 'event_vendor', 'sponsor', 'artist_musician',
      'community_organization', 'app_affiliate_partner'
    ])),
  pipeline_status text not null default 'new_visit'
    check (pipeline_status = any (array[
      'new_visit', 'researching', 'contact_ready', 'outreach',
      'responded', 'onboarding', 'partner', 'paused', 'not_a_fit'
    ])),
  heha_pillar text
    check (heha_pillar is null or heha_pillar = any (array['nourish', 'educate', 'relax', 'elevate'])),
  business_category text,
  address text,
  city text,
  state text,
  postal_code text,
  phone text,
  email text,
  website text,
  instagram text,
  google_maps_url text,
  primary_contact_name text,
  primary_contact_role text,
  visit_notes text,
  first_impression text,
  heha_fit_notes text,
  fit_score smallint check (fit_score is null or fit_score between 1 and 5),
  products_services text,
  potential_offer text,
  image_url text,
  logo_url text,
  gallery_urls jsonb not null default '[]'::jsonb,
  event_capacity text,
  indoor_outdoor text,
  parking_notes text,
  food_vendor_policy text,
  alcohol_policy text,
  music_noise_policy text,
  power_notes text,
  restroom_notes text,
  rental_cost_notes text,
  availability_notes text,
  source text not null default 'field_visit',
  source_detail text,
  partner_id uuid references public.partners(id) on delete set null,
  event_application_id uuid references public.event_applications(id) on delete set null,
  pm_task_id uuid references public.admin_pm_tasks(id) on delete set null,
  hubspot_status text not null default 'queued'
    check (hubspot_status = any (array['queued', 'synced', 'needs_review', 'failed', 'paused'])),
  hubspot_last_error text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
  contact_status text not null default 'identified'
    check (contact_status = any (array['identified', 'ready', 'contacted', 'responded', 'not_a_fit'])),
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists scout_leads_status_idx on public.scout_leads (pipeline_status, created_at desc);
create index if not exists scout_leads_type_idx on public.scout_leads (lead_type, created_at desc);
create index if not exists scout_leads_partner_idx on public.scout_leads (partner_id);
create index if not exists scout_contacts_lead_idx on public.scout_contacts (lead_id, created_at);

alter table public.scout_leads enable row level security;
alter table public.scout_contacts enable row level security;

drop policy if exists user_roles_select_own_assignment on public.user_roles;
create policy user_roles_select_own_assignment
on public.user_roles for select to authenticated
using (user_id = auth.uid());

drop policy if exists scout_leads_internal_select on public.scout_leads;
create policy scout_leads_internal_select
on public.scout_leads for select to authenticated
using (app_private.has_internal_role(array[
  'super_admin', 'pm_admin', 'community_events_admin', 'som_admin', 'developer_admin'
]));

drop policy if exists scout_leads_internal_insert on public.scout_leads;
create policy scout_leads_internal_insert
on public.scout_leads for insert to authenticated
with check (
  app_private.has_internal_role(array[
    'super_admin', 'pm_admin', 'community_events_admin', 'som_admin', 'developer_admin'
  ])
  and coalesce(created_by, auth.uid()) = auth.uid()
);

drop policy if exists scout_leads_internal_update on public.scout_leads;
create policy scout_leads_internal_update
on public.scout_leads for update to authenticated
using (
  app_private.has_internal_role(array['super_admin', 'pm_admin', 'developer_admin', 'som_admin'])
  or (
    app_private.has_internal_role(array['community_events_admin'])
    and lead_type = any (array[
      'event_partner', 'event_venue', 'event_vendor', 'sponsor',
      'artist_musician', 'community_organization'
    ])
  )
)
with check (
  app_private.has_internal_role(array['super_admin', 'pm_admin', 'developer_admin', 'som_admin'])
  or (
    app_private.has_internal_role(array['community_events_admin'])
    and lead_type = any (array[
      'event_partner', 'event_venue', 'event_vendor', 'sponsor',
      'artist_musician', 'community_organization'
    ])
  )
);

drop policy if exists scout_leads_admin_delete on public.scout_leads;
create policy scout_leads_admin_delete
on public.scout_leads for delete to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin']));

drop policy if exists scout_contacts_internal_select on public.scout_contacts;
create policy scout_contacts_internal_select
on public.scout_contacts for select to authenticated
using (app_private.has_internal_role(array[
  'super_admin', 'pm_admin', 'community_events_admin', 'som_admin', 'developer_admin'
]));

drop policy if exists scout_contacts_internal_insert on public.scout_contacts;
create policy scout_contacts_internal_insert
on public.scout_contacts for insert to authenticated
with check (
  app_private.has_internal_role(array[
    'super_admin', 'pm_admin', 'community_events_admin', 'som_admin', 'developer_admin'
  ])
  and coalesce(created_by, auth.uid()) = auth.uid()
);

drop policy if exists scout_contacts_internal_update on public.scout_contacts;
create policy scout_contacts_internal_update
on public.scout_contacts for update to authenticated
using (app_private.has_internal_role(array[
  'super_admin', 'pm_admin', 'community_events_admin', 'som_admin', 'developer_admin'
]))
with check (app_private.has_internal_role(array[
  'super_admin', 'pm_admin', 'community_events_admin', 'som_admin', 'developer_admin'
]));

drop policy if exists scout_contacts_admin_delete on public.scout_contacts;
create policy scout_contacts_admin_delete
on public.scout_contacts for delete to authenticated
using (app_private.has_internal_role(array['super_admin', 'pm_admin', 'developer_admin']));

alter table public.admin_pm_tasks drop constraint if exists admin_pm_tasks_category_check;
alter table public.admin_pm_tasks add constraint admin_pm_tasks_category_check
check (category = any (array[
  'app_shahid', 'wix_raj', 'content', 'outreach_shakil', 'pm_myren',
  'approval_geronimo', 'hubspot', 'google_sheets', 'qa', 'community_events'
]));

create or replace function public.scout_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists scout_leads_touch_updated_at on public.scout_leads;
create trigger scout_leads_touch_updated_at
before update on public.scout_leads
for each row execute function public.scout_touch_updated_at();

drop trigger if exists scout_contacts_touch_updated_at on public.scout_contacts;
create trigger scout_contacts_touch_updated_at
before update on public.scout_contacts
for each row execute function public.scout_touch_updated_at();

create or replace function public.ensure_scout_event_artifact(p_lead_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  lead_row public.scout_leads%rowtype;
  linked_id uuid;
  display_name text;
begin
  select * into lead_row from public.scout_leads where id = p_lead_id;
  if not found then return; end if;
  if lead_row.lead_type <> all (array[
    'event_partner', 'event_venue', 'event_vendor', 'sponsor',
    'artist_musician', 'community_organization'
  ]) then return; end if;

  linked_id := lead_row.event_application_id;
  display_name := coalesce(
    nullif(btrim(lead_row.business_name), ''),
    nullif(btrim(lead_row.primary_contact_name), ''),
    'Untitled event lead'
  );

  if linked_id is null and (
    nullif(btrim(lead_row.business_name), '') is not null
    or nullif(btrim(lead_row.primary_contact_name), '') is not null
  ) then
    insert into public.event_applications (
      applicant_name, brand_or_business_name, application_type,
      email, phone, instagram, website, category, event_interest,
      proposed_contribution, notes, status, created_by, updated_by
    )
    values (
      coalesce(nullif(lead_row.primary_contact_name, ''), display_name),
      lead_row.business_name,
      lead_row.lead_type,
      lead_row.email,
      lead_row.phone,
      lead_row.instagram,
      lead_row.website,
      lead_row.business_category,
      coalesce(lead_row.heha_fit_notes, lead_row.availability_notes),
      lead_row.potential_offer,
      concat_ws(E'\n',
        nullif(lead_row.visit_notes, ''),
        nullif(lead_row.first_impression, ''),
        nullif(lead_row.parking_notes, ''),
        nullif(lead_row.rental_cost_notes, '')
      ),
      'new',
      lead_row.created_by,
      lead_row.updated_by
    )
    returning id into linked_id;

    update public.scout_leads
    set event_application_id = linked_id
    where id = p_lead_id;
  elsif linked_id is not null then
    update public.event_applications
    set applicant_name = coalesce(nullif(lead_row.primary_contact_name, ''), applicant_name),
        brand_or_business_name = coalesce(nullif(lead_row.business_name, ''), brand_or_business_name),
        email = coalesce(nullif(lead_row.email, ''), email),
        phone = coalesce(nullif(lead_row.phone, ''), phone),
        instagram = coalesce(nullif(lead_row.instagram, ''), instagram),
        website = coalesce(nullif(lead_row.website, ''), website),
        category = coalesce(nullif(lead_row.business_category, ''), category),
        event_interest = coalesce(nullif(lead_row.heha_fit_notes, ''), event_interest),
        proposed_contribution = coalesce(nullif(lead_row.potential_offer, ''), proposed_contribution),
        updated_by = lead_row.updated_by,
        updated_at = now()
    where id = linked_id and status <> 'approved';
  end if;
end;
$$;

create or replace function public.sync_scout_partner_artifacts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_partner_id uuid;
  v_readiness_id uuid;
  v_location text;
begin
  if new.lead_type = any (array[
    'event_partner', 'event_venue', 'event_vendor', 'sponsor',
    'artist_musician', 'community_organization'
  ]) then
    perform public.ensure_scout_event_artifact(new.id);
    return new;
  end if;

  if new.lead_type <> all (array[
    'potential_partner', 'heha_swipe_business', 'app_affiliate_partner'
  ]) then return new; end if;

  v_partner_id := new.partner_id;
  v_location := concat_ws(', ',
    nullif(btrim(new.address), ''),
    nullif(btrim(new.city), ''),
    nullif(btrim(new.state), ''),
    nullif(btrim(new.postal_code), '')
  );

  if v_partner_id is null and nullif(btrim(new.business_name), '') is not null then
    insert into public.partners (
      owner_id, name, category, location, contact, instagram, website,
      bio, status, phone, image_url, business_type, partner_type, neighborhood
    )
    values (
      null,
      new.business_name,
      coalesce(nullif(new.business_category, ''), 'Local Business'),
      nullif(v_location, ''),
      new.email,
      new.instagram,
      new.website,
      coalesce(nullif(new.heha_fit_notes, ''), nullif(new.first_impression, ''), nullif(new.visit_notes, '')),
      'pending',
      new.phone,
      new.image_url,
      new.business_category,
      new.lead_type,
      new.city
    )
    returning id into v_partner_id;

    update public.scout_leads set partner_id = v_partner_id where id = new.id;
  elsif v_partner_id is not null then
    update public.partners
    set name = coalesce(nullif(new.business_name, ''), name),
        category = coalesce(nullif(new.business_category, ''), category),
        location = coalesce(nullif(v_location, ''), location),
        contact = coalesce(nullif(new.email, ''), contact),
        instagram = coalesce(nullif(new.instagram, ''), instagram),
        website = coalesce(nullif(new.website, ''), website),
        bio = coalesce(nullif(new.heha_fit_notes, ''), nullif(new.first_impression, ''), nullif(new.visit_notes, ''), bio),
        phone = coalesce(nullif(new.phone, ''), phone),
        image_url = coalesce(nullif(new.image_url, ''), image_url),
        business_type = coalesce(nullif(new.business_category, ''), business_type),
        partner_type = new.lead_type
    where id = v_partner_id and coalesce(status, 'pending') in ('pending', 'review_needed');
  end if;

  if v_partner_id is not null then
    select id into v_readiness_id
    from public.admin_partner_readiness
    where partner_id = v_partner_id
    order by created_at
    limit 1;

    if v_readiness_id is null then
      insert into public.admin_partner_readiness (
        partner_id, business_name, partner_category, pipeline_status,
        profile_status, next_step, approval_needed, hubspot_linked,
        internal_notes, created_by, updated_by
      )
      values (
        v_partner_id,
        new.business_name,
        new.business_category,
        'new_lead',
        'draft',
        'Research business and establish a second contact.',
        false,
        false,
        concat_ws(E'\n', nullif(new.visit_notes, ''), nullif(new.first_impression, ''), nullif(new.heha_fit_notes, '')),
        new.created_by,
        new.updated_by
      );
    end if;

    insert into public.admin_hubspot_links (
      partner_id, lifecycle_stage, lead_category, open_task_status, sync_status
    )
    values (
      v_partner_id,
      'lead',
      concat('scout_', new.lead_type),
      'todo',
      'not_synced'
    )
    on conflict (partner_id) do update
    set lead_category = excluded.lead_category,
        open_task_status = coalesce(public.admin_hubspot_links.open_task_status, excluded.open_task_status),
        sync_status = case
          when public.admin_hubspot_links.sync_status = 'success' then 'needs_review'
          else public.admin_hubspot_links.sync_status
        end,
        updated_at = now();

    update public.scout_leads
    set hubspot_status = case when hubspot_status = 'synced' then 'needs_review' else hubspot_status end
    where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists a_scout_sync_partner_artifacts on public.scout_leads;
create trigger a_scout_sync_partner_artifacts
after insert or update of
  business_name, lead_type, business_category, address, city, state,
  postal_code, phone, email, website, instagram, visit_notes,
  first_impression, heha_fit_notes, image_url
on public.scout_leads
for each row execute function public.sync_scout_partner_artifacts();

drop policy if exists community_events_insert_scout_tasks on public.admin_pm_tasks;
create policy community_events_insert_scout_tasks
on public.admin_pm_tasks for insert to authenticated
with check (
  app_private.has_internal_role(array['community_events_admin'])
  and category = 'community_events'
  and related_type = 'scout_lead'
);

drop policy if exists som_insert_scout_tasks on public.admin_pm_tasks;
create policy som_insert_scout_tasks
on public.admin_pm_tasks for insert to authenticated
with check (
  app_private.has_internal_role(array['som_admin'])
  and category = any (array['pm_myren', 'community_events'])
  and related_type = 'scout_lead'
);

drop policy if exists community_events_update_scout_tasks on public.admin_pm_tasks;
create policy community_events_update_scout_tasks
on public.admin_pm_tasks for update to authenticated
using (
  app_private.has_internal_role(array['community_events_admin'])
  and category = 'community_events'
  and related_type = 'scout_lead'
)
with check (
  app_private.has_internal_role(array['community_events_admin'])
  and category = 'community_events'
  and related_type = 'scout_lead'
);

drop policy if exists som_read_scout_tasks on public.admin_pm_tasks;
create policy som_read_scout_tasks
on public.admin_pm_tasks for select to authenticated
using (
  app_private.has_internal_role(array['som_admin'])
  and related_type = 'scout_lead'
);

comment on table public.scout_leads is
  'Shared HEHA Scout & Partner Pipeline source used by Admin, PM, SOM, and Community Events role views.';

comment on table public.scout_contacts is
  'Contact research attached to scout leads, including second-contact development for partner outreach.';
