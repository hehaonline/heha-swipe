alter table public.scout_leads enable row level security;

drop policy if exists user_roles_select_own_assignment on public.user_roles;
create policy user_roles_select_own_assignment on public.user_roles
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists scout_leads_internal_select on public.scout_leads;
create policy scout_leads_internal_select on public.scout_leads
for select to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']));

drop policy if exists scout_leads_internal_insert on public.scout_leads;
create policy scout_leads_internal_insert on public.scout_leads
for insert to authenticated
with check (
  app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin'])
  and coalesce(created_by, (select auth.uid())) = (select auth.uid())
);

drop policy if exists scout_leads_internal_update on public.scout_leads;
create policy scout_leads_internal_update on public.scout_leads
for update to authenticated
using (
  app_private.has_internal_role(array['super_admin','pm_admin','developer_admin','som_admin'])
  or (
    app_private.has_internal_role(array['community_events_admin'])
    and lead_type = any (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization'])
  )
)
with check (
  app_private.has_internal_role(array['super_admin','pm_admin','developer_admin','som_admin'])
  or (
    app_private.has_internal_role(array['community_events_admin'])
    and lead_type = any (array['event_partner','event_venue','event_vendor','sponsor','artist_musician','community_organization'])
  )
);

drop policy if exists scout_leads_admin_delete on public.scout_leads;
create policy scout_leads_admin_delete on public.scout_leads
for delete to authenticated
using (app_private.has_internal_role(array['super_admin','developer_admin']));
