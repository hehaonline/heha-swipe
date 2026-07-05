alter table public.scout_contacts enable row level security;

drop policy if exists scout_contacts_internal_select on public.scout_contacts;
create policy scout_contacts_internal_select on public.scout_contacts
for select to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']));

drop policy if exists scout_contacts_internal_insert on public.scout_contacts;
create policy scout_contacts_internal_insert on public.scout_contacts
for insert to authenticated
with check (
  app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin'])
  and coalesce(created_by, (select auth.uid())) = (select auth.uid())
);

drop policy if exists scout_contacts_internal_update on public.scout_contacts;
create policy scout_contacts_internal_update on public.scout_contacts
for update to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']))
with check (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']));

drop policy if exists scout_contacts_admin_delete on public.scout_contacts;
create policy scout_contacts_admin_delete on public.scout_contacts
for delete to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','developer_admin']));
