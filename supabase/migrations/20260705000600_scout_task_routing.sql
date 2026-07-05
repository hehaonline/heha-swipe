create or replace function public.ensure_scout_pm_task(p_lead_id uuid)
returns void
language sql
security definer
as $$
  with lead as (
    select * from public.scout_leads where id = p_lead_id and pm_task_id is null
  ), created as (
    insert into public.admin_pm_tasks (task_title, related_partner_id, related_type, category, priority, status, next_step, approval_needed, created_by, updated_by)
    select 'Review scout lead', partner_id, 'scout_lead', case when lead_type like 'event_%' then 'community_events' else 'pm_myren' end, 'medium', 'todo', 'Research lead and prepare follow-up.', false, created_by, updated_by from lead
    returning id
  )
  update public.scout_leads set pm_task_id = (select id from created) where id = p_lead_id and exists (select 1 from created);
$$;

create or replace function public.scout_pm_task_wrapper()
returns trigger
language plpgsql
security definer
as 'begin perform public.ensure_scout_pm_task(new.id); return new; end;';

drop trigger if exists scout_pm_task_after_insert on public.scout_leads;
create trigger scout_pm_task_after_insert after insert on public.scout_leads for each row execute function public.scout_pm_task_wrapper();
