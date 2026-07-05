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
  if lead_row.lead_type <> all (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization']) then return; end if;

  linked_id := lead_row.event_application_id;
  display_name := coalesce(nullif(btrim(lead_row.business_name), ''), nullif(btrim(lead_row.primary_contact_name), ''), 'Untitled event lead');

  if linked_id is null and (nullif(btrim(lead_row.business_name), '') is not null or nullif(btrim(lead_row.primary_contact_name), '') is not null) then
    insert into public.event_applications (
      applicant_name, brand_or_business_name, application_type, email, phone,
      instagram, website, category, event_interest, proposed_contribution,
      notes, status, created_by, updated_by
    ) values (
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
      concat_ws(E'\n', lead_row.visit_notes, lead_row.first_impression, lead_row.parking_notes, lead_row.rental_cost_notes),
      'new',
      lead_row.created_by,
      lead_row.updated_by
    ) returning id into linked_id;

    update public.scout_leads set event_application_id = linked_id where id = p_lead_id;
  end if;
end;
$$;
