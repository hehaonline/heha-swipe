# Scout HubSpot auto-sync

After an authenticated internal user saves a Scout lead, the dashboard invokes the JWT-protected `hubspot-sync` Supabase Edge Function. The Scout record is saved before sync begins, so HubSpot failures leave the queue recoverable in Supabase. HubSpot credentials remain server-side.
