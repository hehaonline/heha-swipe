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
  h.updated_at
from public.admin_hubspot_links h
join public.partners p on p.id = h.partner_id;
