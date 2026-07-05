-- HubSpot Scout CRM sync queue hardening.
-- Supabase remains the source of truth; HubSpot is a CRM mirror for relationship follow-up.

alter table public.admin_hubspot_links
  drop constraint if exists admin_hubspot_links_sync_status_check;

alter table public.admin_hubspot_links
  add constraint admin_hubspot_links_sync_status_check
  check (sync_status = any (array['not_synced','syncing','success','failed','needs_review','paused']));

alter table public.admin_hubspot_links
  add column if not exists hubspot_contact_ids jsonb not null default '{}'::jsonb,
  add column if not exists hubspot_note_id text,
  add column if not exists last_note_fingerprint text,
  add column if not exists last_payload_hash text,
  add column if not exists sync_attempts integer not null default 0,
  add column if not exists last_attempt_at timestamptz;

create or replace function public.claim_hubspot_sync_queue(p_limit integer default 10)
returns setof public.admin_hubspot_links
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with picked as (
    select h.id
    from public.admin_hubspot_links h
    where h.sync_status in ('not_synced','needs_review')
    order by h.updated_at asc
    limit greatest(1, least(coalesce(p_limit, 10), 25))
    for update skip locked
  )
  update public.admin_hubspot_links h
  set sync_status = 'syncing',
      sync_attempts = coalesce(h.sync_attempts, 0) + 1,
      last_attempt_at = now(),
      updated_at = now()
  from picked
  where h.id = picked.id
  returning h.*;
end;
$$;

revoke all on function public.claim_hubspot_sync_queue(integer) from public, anon, authenticated;
grant execute on function public.claim_hubspot_sync_queue(integer) to service_role;

create or replace function public.requeue_hubspot_for_scout_lead()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.partner_id is not null then
    update public.admin_hubspot_links
    set sync_status = case when sync_status = 'paused' then 'paused' else 'needs_review' end,
        updated_at = now()
    where partner_id = new.partner_id;
  end if;
  return new;
end;
$$;

revoke all on function public.requeue_hubspot_for_scout_lead() from public, anon, authenticated;

drop trigger if exists scout_leads_requeue_hubspot on public.scout_leads;
create trigger scout_leads_requeue_hubspot
after update of business_name, lead_type, heha_pillar, business_category, neighborhood,
  tagline, bio, hours, address, city, state, postal_code, phone, email, website,
  instagram, google_maps_url, primary_contact_name, primary_contact_role, visit_notes,
  first_impression, heha_fit_notes, fit_score, products_services, offerings_text,
  featured_items_text, potential_offer
on public.scout_leads
for each row execute function public.requeue_hubspot_for_scout_lead();

create or replace function public.requeue_hubspot_for_scout_contact()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_lead_id uuid;
  v_partner_id uuid;
begin
  v_lead_id := case when tg_op = 'DELETE' then old.lead_id else new.lead_id end;
  select partner_id into v_partner_id from public.scout_leads where id = v_lead_id;

  if v_partner_id is not null then
    update public.admin_hubspot_links
    set sync_status = case when sync_status = 'paused' then 'paused' else 'needs_review' end,
        updated_at = now()
    where partner_id = v_partner_id;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.requeue_hubspot_for_scout_contact() from public, anon, authenticated;

drop trigger if exists scout_contacts_requeue_hubspot on public.scout_contacts;
create trigger scout_contacts_requeue_hubspot
after insert or update or delete on public.scout_contacts
for each row execute function public.requeue_hubspot_for_scout_contact();

create index if not exists admin_hubspot_links_sync_queue_idx
  on public.admin_hubspot_links (sync_status, updated_at);
