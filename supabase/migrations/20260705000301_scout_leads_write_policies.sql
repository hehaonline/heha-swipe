drop policy if exists scout_leads_internal_insert on public.scout_leads;
create policy scout_leads_internal_insert on public.scout_leads
for insert to authenticated
with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']) and coalesce(created_by, auth.uid()) = auth.uid());

drop policy if exists scout_leads_admin_delete on public.scout_leads;
create policy scout_leads_admin_delete on public.scout_leads
for delete to authenticated
using (app_private.has_internal_role(array['super_admin','developer_admin']));
