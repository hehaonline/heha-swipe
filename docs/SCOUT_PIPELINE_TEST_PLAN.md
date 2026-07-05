# Scout Pipeline smoke test

1. Sign in with an active `super_admin` or `developer_admin` HEHA Swipe account.
2. Open `/internal`.
3. Create a potential partner lead with a business name.
4. Confirm the lead appears in the internal pipeline.
5. Confirm a pending `partners` row, `admin_partner_readiness` row, `admin_hubspot_links` queue row, and `admin_pm_tasks` task are linked.
6. Create an event venue lead.
7. Confirm an `event_applications` row and `community_events` PM task are created.
8. Change a partner lead status to Outreach and confirm readiness moves to Contacted.
9. Confirm neither test lead is publicly visible in the customer Swipe feed unless the existing admin approval flow changes partner status to an approved/live state.
10. Remove test records after validation.
