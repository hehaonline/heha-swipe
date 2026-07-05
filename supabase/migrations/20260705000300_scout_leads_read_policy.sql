alter table public.scout_leads enable row level security;

drop policy if exists scout_leads_internal_select on public.scout_leads;
create policy scout_leads_internal_select on public.scout_leads
for select to authenticated
using (app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']));
