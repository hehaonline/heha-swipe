drop policy if exists scout_leads_internal_update on public.scout_leads;
create policy scout_leads_internal_update on public.scout_leads
for update to authenticated
using (
  app_private.has_internal_role(array['super_admin','pm_admin','developer_admin','som_admin'])
  or (app_private.has_internal_role(array['community_events_admin']) and lead_type = any (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization']))
)
with check (
  app_private.has_internal_role(array['super_admin','pm_admin','developer_admin','som_admin'])
  or (app_private.has_internal_role(array['community_events_admin']) and lead_type = any (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization']))
);
