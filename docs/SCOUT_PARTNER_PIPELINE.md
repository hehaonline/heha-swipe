# HEHA Scout & Partner Pipeline

## Purpose

The Scout & Partner Pipeline turns a real-world HEHA field visit into a structured internal lead. It is shared across Admin, Project Manager, Sales Operations, and Community Events role views.

Public HEHA Swipe publishing remains approval-gated. A scout lead must never become a public listing solely because a team member saved field notes.

## Internal route

The staff workspace is mounted at `/internal`.

Role lenses:

- `super_admin` / `developer_admin`: Admin, PM, SOM, and Events lenses
- `pm_admin`: Project Manager lens
- `som_admin`: Sales Operations lens
- `community_events_admin`: Events lens

## Scout lead types

- potential partner
- HEHA Swipe business
- event partner
- event venue / space
- event vendor
- sponsor
- artist / musician
- community organization
- app / affiliate partner

## Partner lead automation

For partner-oriented scout leads with a business name, Supabase creates or maintains:

1. a `partners` row with `status = pending`
2. an `admin_partner_readiness` row with a new-lead / draft state
3. an `admin_hubspot_links` queue row with `sync_status = not_synced`
4. a follow-up task created by the internal app and linked back through `scout_leads.pm_task_id`

The follow-up task routes to `pm_myren` and asks the project-management workflow to verify the business, identify a second decision-maker or partnership contact, and prepare outreach.

## Event lead automation

Event-oriented scout leads are routed to the existing Community Events foundation. Supabase creates or updates an `event_applications` record with `status = new`.

The internal app creates a `community_events` follow-up task for event fit, contact verification, and second-contact research.

Event venue intelligence may include capacity, indoor/outdoor notes, parking, food-vendor rules, alcohol rules, music/noise restrictions, power, restrooms, rental cost, and availability.

## Shared pipeline statuses

`new_visit` → `researching` → `contact_ready` → `outreach` → `responded` → `onboarding` → `partner`

Leads can also be moved to `paused` or `not_a_fit`.

For partner records, internal status changes map into the existing `admin_partner_readiness` pipeline.

## HubSpot boundary

`admin_hubspot_links` is the internal sync queue and source of truth for HubSpot linkage state. The Scout Pipeline queues partner leads there.

A separate server-side or Make.com processor is still required to consume `not_synced` rows and perform the external HubSpot company/contact/note writes. The browser app must not contain HubSpot private credentials.

## Role setup

The UI requires an active `user_roles` assignment. Myren, the Community Events lead, and SOM users should receive the appropriate role only after their HEHA Swipe user accounts exist and the correct user IDs are verified.
