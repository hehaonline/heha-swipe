create or replace function public.sync_scout_partner_artifacts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  linked_partner uuid;
  readiness_id uuid;
  location_text text;
begin
  if new.lead_type = any (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization']) then
    perform public.ensure_scout_event_artifact(new.id);
    return new;
  end if;

  if new.lead_type <> all (array['potential_partner','heha_swipe_business','app_affiliate_partner']) then return new; end if;

  linked_partner := new.partner_id;
  location_text := concat_ws(', ', nullif(btrim(new.address), ''), nullif(btrim(new.city), ''), nullif(btrim(new.state), ''), nullif(btrim(new.postal_code), ''));

  if linked_partner is null and nullif(btrim(new.business_name), '') is not null then
    insert into public.partners (
      owner_id, name, category, location, contact, instagram, website, bio,
      status, phone, image_url, business_type, partner_type, neighborhood
    ) values (
      null,
      new.business_name,
      coalesce(nullif(new.business_category, ''), 'Local Business'),
      nullif(location_text, ''),
      new.email,
      new.instagram,
      new.website,
      coalesce(new.bio, new.heha_fit_notes, new.first_impression, new.visit_notes),
      'pending',
      new.phone,
      new.image_url,
      new.business_category,
      new.lead_type,
      coalesce(new.neighborhood, new.city)
    ) returning id into linked_partner;

    update public.scout_leads set partner_id = linked_partner where id = new.id;
  end if;

  if linked_partner is not null then
    select id into readiness_id from public.admin_partner_readiness where partner_id = linked_partner order by created_at limit 1;

    if readiness_id is null then
      insert into public.admin_partner_readiness (
        partner_id, business_name, partner_category, pipeline_status, profile_status,
        next_step, approval_needed, hubspot_linked, internal_notes, created_by, updated_by
      ) values (
        linked_partner,
        new.business_name,
        new.business_category,
        'new_lead',
        'draft',
        'Research business and establish a second contact.',
        false,
        false,
        concat_ws(E'\n', new.visit_notes, new.first_impression, new.heha_fit_notes, new.featured_items_text),
        new.created_by,
        new.updated_by
      );
    end if;

    insert into public.admin_hubspot_links (partner_id, lifecycle_stage, lead_category, open_task_status, sync_status)
    values (linked_partner, 'lead', concat('scout_', new.lead_type), 'todo', 'not_synced')
    on conflict (partner_id) do update
    set lead_category = excluded.lead_category,
        open_task_status = coalesce(public.admin_hubspot_links.open_task_status, excluded.open_task_status),
        sync_status = case when public.admin_hubspot_links.sync_status = 'success' then 'needs_review' else public.admin_hubspot_links.sync_status end,
        updated_at = now();
  end if;

  return new;
end;
$$;

drop trigger if exists a_scout_sync_partner_artifacts on public.scout_leads;
create trigger a_scout_sync_partner_artifacts
after insert or update of business_name, lead_type, business_category, address, city, state, postal_code, phone, email, website, instagram, visit_notes, first_impression, heha_fit_notes, image_url
on public.scout_leads
for each row execute function public.sync_scout_partner_artifacts();
