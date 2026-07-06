drop policy if exists partners_internal_read on public.partners;
create policy partners_internal_read
on public.partners
for select
to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']));

create or replace function public.review_partner_routing(
  p_partner_id uuid,
  p_heha_pillar text,
  p_website_eligible boolean,
  p_swipe_eligible boolean,
  p_local_eligible boolean,
  p_local_lane text,
  p_primary_cta_destination text,
  p_primary_cta_label text,
  p_primary_cta_path text,
  p_routing_notes text,
  p_finalize boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not app_private.has_internal_role(array['super_admin','pm_admin','developer_admin']) then
    raise exception 'HEHA PM or Admin role required';
  end if;

  if p_finalize and not app_private.has_internal_role(array['super_admin']) then
    raise exception 'Geronimo / super_admin approval required to finalize routing';
  end if;

  if p_local_eligible and p_local_lane is null then
    raise exception 'HEHA Local eligible partners require a local lane';
  end if;

  update public.partners
  set heha_pillar = p_heha_pillar,
      website_eligible = p_website_eligible,
      swipe_eligible = p_swipe_eligible,
      local_eligible = p_local_eligible,
      local_lane = case when p_local_eligible then p_local_lane else null end,
      primary_cta_destination = p_primary_cta_destination,
      primary_cta_label = p_primary_cta_label,
      primary_cta_path = p_primary_cta_path,
      routing_notes = p_routing_notes,
      routing_status = case when p_finalize then 'approved' else 'needs_review' end,
      routing_updated_by = auth.uid(),
      routing_updated_at = now()
  where id = p_partner_id;

  if not found then raise exception 'Partner not found'; end if;
end;
$$;

revoke all on function public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean) from public, anon;
grant execute on function public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean) to authenticated;

create or replace function public.reset_partner_routing_suggestion(p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not app_private.has_internal_role(array['super_admin','pm_admin','developer_admin']) then
    raise exception 'HEHA PM or Admin role required';
  end if;

  update public.partners
  set website_eligible = null,
      swipe_eligible = null,
      local_eligible = null,
      local_lane = null,
      primary_cta_destination = null,
      primary_cta_label = null,
      primary_cta_path = null,
      routing_status = 'suggested',
      routing_updated_by = auth.uid(),
      routing_updated_at = now(),
      status = status
  where id = p_partner_id;
end;
$$;

revoke all on function public.reset_partner_routing_suggestion(uuid) from public, anon;
grant execute on function public.reset_partner_routing_suggestion(uuid) to authenticated;
