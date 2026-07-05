alter table public.admin_pm_tasks drop constraint if exists admin_pm_tasks_category_check;
alter table public.admin_pm_tasks add constraint admin_pm_tasks_category_check
check (category = any (array[
  'app_shahid','wix_raj','content','outreach_shakil','pm_myren',
  'approval_geronimo','hubspot','google_sheets','qa','community_events'
]));

drop policy if exists community_events_insert_scout_tasks on public.admin_pm_tasks;
create policy community_events_insert_scout_tasks on public.admin_pm_tasks
for insert to authenticated
with check (
  app_private.has_internal_role(array['community_events_admin'])
  and category = 'community_events'
  and related_type = 'scout_lead'
);

drop policy if exists som_insert_scout_tasks on public.admin_pm_tasks;
create policy som_insert_scout_tasks on public.admin_pm_tasks
for insert to authenticated
with check (
  app_private.has_internal_role(array['som_admin'])
  and category = any (array['pm_myren','community_events'])
  and related_type = 'scout_lead'
);

drop policy if exists community_events_update_scout_tasks on public.admin_pm_tasks;
create policy community_events_update_scout_tasks on public.admin_pm_tasks
for update to authenticated
using (
  app_private.has_internal_role(array['community_events_admin'])
  and category = 'community_events'
  and related_type = 'scout_lead'
)
with check (
  app_private.has_internal_role(array['community_events_admin'])
  and category = 'community_events'
  and related_type = 'scout_lead'
);

drop policy if exists som_read_scout_tasks on public.admin_pm_tasks;
create policy som_read_scout_tasks on public.admin_pm_tasks
for select to authenticated
using (app_private.has_internal_role(array['som_admin']) and related_type = 'scout_lead');
