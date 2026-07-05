alter table public.scout_contacts enable row level security;

drop policy if exists scout_contacts_internal_select on public.scout_contacts;
create policy scout_contacts_internal_select on public.scout_contacts
for select to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']));
