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
  if new.lead_type = any (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization']) then
    perform public.ensure_scout_event_artifact(new.id);
    return new;
  end if;

  if new.lead_type <> all (array['potential_partner','heha_swipe_business','app_affiliate_partner']) then
    return new;
  end if;

  v_partner_id := new.partner_id;
  v_location := concat_ws(', ', nullif(btrim(new.address), ''), nullif(btrim(new.city), ''), nullif(btrim(new.state), ''), nullif(btrim(new.postal_code), ''));

  if v_partner_id is null and nullif(btrim(new.business_name), '') is not null then
    insert into public.partners (
      owner_id, name, category, location, contact, instagram, website, bio,
      status, phone, image_url, business_type, partner_type, neighborhood, heha_pillar
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
      new.city,
      new.heha_pillar
    )
    returning id into v_partner_id;

    update public.scout_leads
    set partner_id = v_partner_id
    where id = new.id;
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
        partner_type = new.lead_type,
        heha_pillar = coalesce(new.heha_pillar, heha_pillar)
    where id = v_partner_id
      and coalesce(status, 'pending') in ('pending','review_needed');
  end if;

  if v_partner_id is not null then
    select id into v_readiness_id
    from public.admin_partner_readiness
    where partner_id = v_partner_id
    order by created_at
    limit 1;

    if v_readiness_id is null then
      insert into public.admin_partner_readiness (
        partner_id, business_name, partner_category, pipeline_status, profile_status,
        next_step, approval_needed, hubspot_linked, internal_notes, created_by, updated_by
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
    set hubspot_status = case
      when hubspot_status = 'synced' then 'needs_review'
      else hubspot_status
    end
    where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists a_scout_sync_partner_artifacts on public.scout_leads;
create trigger a_scout_sync_partner_artifacts
after insert or update of
  business_name, lead_type, business_category, heha_pillar, address, city, state,
  postal_code, phone, email, website, instagram, visit_notes, first_impression,
  heha_fit_notes, image_url
on public.scout_leads
for each row execute function public.sync_scout_partner_artifacts();
