# HEHA Scout → HubSpot Sync Runbook

## Architecture

Supabase remains HEHA's operational source of truth. HubSpot is the CRM mirror for companies, researched contacts, relationship notes, and Myren's follow-up workflow.

The deployed Supabase Edge Function is `hubspot-sync`.

It processes `admin_hubspot_links` rows with `sync_status` of `not_synced` or `needs_review`.

For each queued partner lead it:

1. Loads the partner and latest Scout lead from Supabase.
2. Finds a HubSpot company by stored HubSpot ID, then domain, then exact company name.
3. Creates or updates the HubSpot company.
4. Best-effort syncs `google_maps_link` and maps Scout fit score 1–5 to HEHA Fit Score Low / Medium / High.
5. Creates or updates the person met during the field visit and any `scout_contacts` records.
6. Associates synced contacts with the company.
7. Creates an HEHA Scout field-visit note and associates it with the company and synced contacts.
8. Saves HubSpot IDs and fingerprints to `admin_hubspot_links`.
9. Marks the queue row `success`, or `failed` with a bounded error message.

Scout lead edits and Scout contact insert/update/delete events automatically set the queue row to `needs_review`, unless the queue is explicitly `paused`.

## Security boundary

Never put a HubSpot access token in Vite/browser environment variables.

The Edge Function reads only:

`HUBSPOT_ACCESS_TOKEN`

from Supabase Edge Function secrets.

The function uses Supabase server-side secret/service credentials for queue processing and is deployed with JWT verification enabled.

## HubSpot private app access

Use a HubSpot private app with access to the CRM objects used by this worker:

- companies: read + write
- contacts: read + write
- notes: write

The worker also creates CRM object associations between companies, contacts, and notes.

## Activation

1. In HubSpot, create or select the HEHA private app used for CRM automation.
2. Copy its access token once.
3. In Supabase Dashboard → Edge Functions → Secrets, add:

   `HUBSPOT_ACCESS_TOKEN=<private app access token>`

4. Do not commit the token to GitHub or `.env` files.
5. Invoke `hubspot-sync` once with a small limit and verify the response.
6. Verify the test company, contact(s), and Scout note in HubSpot.
7. Confirm `admin_hubspot_links.sync_status = success` and HubSpot IDs are stored.
8. Only after the test passes, schedule the function.

## Recommended schedule

Every 5 minutes is sufficient for field-visit/CRM intake. This is not an order-dispatch workflow.

Supabase supports scheduled Edge Function invocation with `pg_cron` + `pg_net`; store the invocation values in Vault rather than embedding credentials in SQL.

Recommended cron expression:

`*/5 * * * *`

Recommended request body:

`{"limit":10}`

## Failure behavior

- `503 configured=false`: `HUBSPOT_ACCESS_TOKEN` is missing. Do not enable cron yet.
- `failed`: review `sync_error_notes`, correct the data or integration issue, then set `sync_status` back to `needs_review`.
- `paused`: no automatic requeue from Scout edits.
- Duplicate protection: the worker stores a payload hash and note fingerprint. Unchanged data does not create a second field-visit note.

## HEHA approval boundary

HubSpot sync does not approve a partner, publish a HEHA Swipe card, send outreach, promise pricing, approve a deal, or make a partnership commitment. Geronimo retains those decisions.
