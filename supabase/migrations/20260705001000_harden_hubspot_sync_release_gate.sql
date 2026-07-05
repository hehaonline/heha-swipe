alter table public.admin_hubspot_links
  add column if not exists sync_released_at timestamptz;

alter table public.admin_hubspot_links
  add column if not exists sync_released_by uuid references auth.users(id) on delete set null;

create or replace function public.release_hubspot_sync_queue(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  released_count integer;
begin
  if not app_private.has_internal_role(array['super_admin','pm_admin','community_events_admin','som_admin','developer_admin']) then
    raise exception 'HEHA internal role required';
  end if;

  with picked as (
    select h.id
    from public.admin_hubspot_links h
    where h.sync_status in ('not_synced','failed','needs_review')
      and h.sync_released_at is null
    order by h.updated_at asc
    limit greatest(1, least(coalesce(p_limit, 10), 25))
    for update skip locked
  )
  update public.admin_hubspot_links h
  set sync_released_at = now(),
      sync_released_by = auth.uid(),
      updated_at = now()
  from picked
  where h.id = picked.id;

  get diagnostics released_count = row_count;
  return released_count;
end;
$$;

revoke all on function public.release_hubspot_sync_queue(integer) from public, anon;
grant execute on function public.release_hubspot_sync_queue(integer) to authenticated;

create or replace function public.claim_hubspot_sync_queue(p_limit integer default 10)
returns setof public.admin_hubspot_links
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with picked as (
    select h.id
    from public.admin_hubspot_links h
    where h.sync_status in ('not_synced','failed','needs_review')
      and h.sync_released_at is not null
    order by h.sync_released_at asc, h.updated_at asc
    limit greatest(1, least(coalesce(p_limit, 10), 25))
    for update skip locked
  )
  update public.admin_hubspot_links h
  set sync_status = 'syncing',
      sync_released_at = null,
      sync_released_by = null,
      sync_attempts = coalesce(h.sync_attempts, 0) + 1,
      last_attempt_at = now(),
      updated_at = now()
  from picked
  where h.id = picked.id
  returning h.*;
end;
$$;

revoke all on function public.claim_hubspot_sync_queue(integer) from public, anon, authenticated;

create or replace view public.admin_hubspot_sync_queue_view
with (security_invoker = true)
as
select
  h.id,
  h.partner_id,
  p.name as partner_name,
  h.lifecycle_stage,
  h.lead_category,
  h.open_task_status,
  h.sync_status,
  h.sync_error_notes,
  h.hubspot_company_id,
  h.hubspot_contact_id,
  h.last_synced_at,
  h.last_attempt_at,
  h.sync_attempts,
  h.updated_at,
  h.sync_released_at,
  h.sync_released_by
from public.admin_hubspot_links h
join public.partners p on p.id = h.partner_id;
