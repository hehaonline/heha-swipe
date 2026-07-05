# HubSpot handoff

The Scout Pipeline does not place HubSpot private credentials in the browser.

Partner-oriented scout leads create or refresh an `admin_hubspot_links` row with:

- `partner_id`
- `lifecycle_stage = lead`
- `lead_category = scout_<lead_type>`
- `open_task_status = todo`
- `sync_status = not_synced`

A future Make.com or server-side worker should:

1. Read eligible `not_synced` rows.
2. Load the associated `partners`, `scout_leads`, and `scout_contacts` data.
3. Match or create a HubSpot company.
4. Match or create known contacts.
5. Add field-visit notes.
6. Update HubSpot follow-up state.
7. Save HubSpot IDs and mark the queue row `success`.
8. On failure, set `failed` and write `sync_error_notes`.

This keeps Supabase as the HEHA operational source of truth while HubSpot remains the external CRM execution layer.
