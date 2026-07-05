# Scout Pipeline release checklist

- [x] Shared `scout_leads` and `scout_contacts` schema created in HEHA SWIPE Supabase.
- [x] RLS restricted to internal HEHA roles.
- [x] Partner scout leads create pending Swipe partner drafts.
- [x] Partner scout leads create partner-readiness records.
- [x] Partner scout leads queue HubSpot linkage records.
- [x] Event scout leads create or update Community Events application records.
- [x] Internal `/internal` route added with Admin, PM, SOM, and Events role lenses.
- [x] Mobile-first field visit form added.
- [x] Event venue intelligence fields added.
- [x] Pipeline status updates map to existing partner-readiness status.
- [x] Follow-up tasks route to `pm_myren` or `community_events`.
- [x] Public publishing remains approval-gated.
- [x] Production build workflow added.
- [ ] Assign `pm_admin`, `community_events_admin`, and `som_admin` roles only after the matching HEHA Swipe accounts are verified.
- [ ] Connect a server-side / Make.com worker to consume `admin_hubspot_links.sync_status = not_synced` and perform HubSpot writes.
