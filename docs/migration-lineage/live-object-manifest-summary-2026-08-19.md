# HEHA Swipe Live Object Manifest Summary — 2026-08-19

Status: **READ-ONLY PRODUCTION METADATA / NO PRODUCTION CHANGE**  
Task: `SWP-016`  
Related: issue #85, PR #69, PR #128, PR #131

## Evidence boundary

An authorized read-only Supabase connector query inspected `pg_catalog`, `information_schema`, `pg_policies`, and extension metadata for the canonical HEHA Swipe Production project at approximately `2026-08-19 23:14 UTC`.

The query did **not** read customer, partner, payment, profile, order, waitlist, contact, message, review, save, or other business rows. It did not read secrets, raw webhook payloads, Auth tokens, storage objects, or provider credentials.

No DDL, DML, configuration, function, policy, grant, migration-ledger, Auth, storage, cron, Edge Function, or provider mutation occurred.

This file is a sanitized object-name/count checkpoint. It is not a schema dump, an executable baseline, or proof that a fresh environment reproduces Production behavior.

## Top-level inventory

| Object class | Live count | Notes |
|---|---:|---|
| Public base tables | 45 | All 45 report RLS enabled; none report `FORCE ROW LEVEL SECURITY` |
| Public views/materialized views | 5 | All five are ordinary views; no public materialized view was returned |
| Public functions | 39 | Mix of invoker and SECURITY DEFINER functions; exact bodies/ACLs remain a later capture |
| Non-internal triggers on public tables | 46 | Spread across operational, partner, Scout, supporter, profile, order, and messaging tables |
| Public RLS policies | 133 | Policy expressions and table grants require separate exact capture/review |
| Installed extensions | 6 | Includes Supabase-managed and application-used extensions |

## Public base tables — 45

```text
account_deletion_requests
admin_actions
admin_approval_requests
admin_audit_logs
admin_certification_reviews
admin_content_requests
admin_deal_requests
admin_hubspot_links
admin_missing_items
admin_partner_readiness
admin_platform_visibility
admin_pm_tasks
admin_weekly_reports
community_offer_redemptions
community_offers_public
community_outreach
contributions
customer_profiles
discount_interest_requests
event_applications
event_concepts
event_recaps
featured_items
founding_business_recommendations
founding_neighbor_waitlist
in_app_messages
invite_list
notifications
order_items
orders
partner_media_requests
partner_photos
partner_profile_change_requests
partner_services
partners
profiles
reviews
saves
scout_contacts
scout_leads
supporter_payments
supporter_subscriptions
swipe_events
user_roles
vibe_settings
```

### RLS checkpoint

- RLS enabled: **45 / 45 tables**
- FORCE RLS enabled: **0 / 45 tables**
- All listed table owners: `postgres`

This is a structural fact, not a vulnerability verdict. The canonical baseline must preserve intentional owner/service behavior, exact grants, policies, and SECURITY DEFINER boundaries. Whether any table should use FORCE RLS is a separate security decision and must not be changed silently during baseline reconstruction.

## Public views — 5

```text
admin_hubspot_sync_queue_view
heha_pricing
public_local_partners
public_partner_directory
public_swipe_partners
```

The next evidence layer must capture each view definition, `security_invoker`/`security_barrier` options, owner, dependencies, and role grants. Existing launch audits already treat `heha_pricing` and the public partner projections as review-sensitive surfaces; this summary does not resolve those gates.

## Public functions — 39

```text
admin_touch_updated_at()
apply_partner_routing_suggestions()
approve_partner(p_partner_id uuid)
claim_hubspot_sync_queue(p_limit integer)
cleanup_test_hubspot()
cleanup_test_readiness()
confirm_community_offer_code(p_partner_id uuid, p_code text)
confirm_community_offer_outcome(p_redemption_id uuid, p_outcome text, p_problem_note text)
delete_event_application_by_id(p_id uuid)
delete_partner_by_id(p_id uuid)
ensure_scout_event_artifact(p_lead_id uuid)
ensure_scout_pm_task(p_lead_id uuid)
get_my_active_supporter_entitlement()
guard_profile_entitlement_fields()
handle_new_user()
heha_set_updated_at()
increment_partner_swipe_stats()
issue_community_offer_redemption(p_deal_id uuid)
notify_make_new_user()
notify_make_partner_approved()
notify_partner_registration_saved()
partner_cta_label_for_lane(p_lane text)
partner_cta_path_for_lane(p_lane text, p_partner_id uuid)
record_swipe(p_partner_id uuid, p_direction text, p_session_id text)
release_hubspot_sync_queue(p_limit integer)
requeue_hubspot_for_scout_contact()
requeue_hubspot_for_scout_lead()
reset_partner_routing_suggestion(p_partner_id uuid)
review_partner_routing(p_partner_id uuid, p_heha_pillar text, p_website_eligible boolean, p_swipe_eligible boolean, p_local_eligible boolean, p_local_lane text, p_primary_cta_destination text, p_primary_cta_label text, p_primary_cta_path text, p_routing_notes text, p_finalize boolean)
rls_auto_enable()
scout_pm_task_wrapper()
scout_touch_updated_at()
suggest_partner_local_lane(p_category text, p_business_type text, p_product_price_policy text, p_service_fee_type text, p_delivery_days text[])
suggest_partner_pillar(p_category text, p_business_type text)
sync_partner_platform_visibility()
sync_partner_save_stats()
sync_scout_partner_artifacts()
sync_scout_swipe_card_fields()
update_updated_at()
```

The metadata query found both invoker and SECURITY DEFINER functions. A later exact manifest must record function body hash, language, volatility, owner, `proconfig`/search path, EXECUTE ACL, dependencies, and intended caller role. This summary does not approve any existing function boundary.

## Trigger coverage

The 46 non-internal triggers are attached to these public tables:

```text
admin_approval_requests
admin_certification_reviews
admin_content_requests
admin_deal_requests
admin_hubspot_links
admin_missing_items
admin_partner_readiness
admin_platform_visibility
admin_pm_tasks
admin_weekly_reports
community_offer_redemptions
community_outreach
event_applications
event_concepts
event_recaps
invite_list
orders
partner_media_requests
partner_profile_change_requests
partners
profiles
saves
scout_contacts
scout_leads
supporter_payments
supporter_subscriptions
swipe_events
user_roles
vibe_settings
```

The canonical manifest must preserve trigger order, timing, event, function dependency, enabled state, and any interactions between owner guards, routing, public projections, webhooks, counters, queueing, and entitlement protection.

## RLS policies — 133

The live database returned 133 public-table RLS policies. The set includes:

- public/anonymous insert or read paths for founding waitlists and selected public content;
- customer-owned profile, notification, message, order, review, save, and swipe paths;
- partner-owner self-service paths;
- internal/admin/SOM/Scout paths on operational tables;
- supporter payment/subscription self-read paths;
- community-offer issue/confirmation/read paths.

Names and command/role metadata were captured in the connector receipt, but this summary intentionally does not reproduce every expression. The next exact evidence file must include `USING`, `WITH CHECK`, role arrays, permissive/restrictive mode, and matching table grants. Policy names or role labels alone are not sufficient to prove BOLA resistance.

## Installed extensions — 6

| Extension | Version | Schema |
|---|---|---|
| `pg_net` | `0.20.3` | `public` |
| `pg_stat_statements` | `1.11` | `extensions` |
| `pgcrypto` | `1.3` | `extensions` |
| `plpgsql` | `1.0` | `pg_catalog` |
| `supabase_vault` | `0.3.1` | `vault` |
| `uuid-ossp` | `1.1` | `extensions` |

The canonical baseline must distinguish provider-managed extensions from application-required extensions and must not embed secrets or Vault contents in source control.

## Domain grouping for baseline planning

The 45 public tables can be grouped for dependency review as follows:

1. **Identity and account lifecycle** — `profiles`, `customer_profiles`, `user_roles`, `account_deletion_requests`, `vibe_settings`.
2. **Partner/catalog/publication** — `partners`, `partner_services`, `partner_photos`, `partner_media_requests`, `partner_profile_change_requests`, `featured_items`, public partner views.
3. **Orders and customer activity** — `orders`, `order_items`, `reviews`, `saves`, `swipe_events`, notifications/messages.
4. **Community and founding programs** — founding waitlists/recommendations, community offers/redemptions/outreach, events, invite list.
5. **Admin and operations** — admin request/review/readiness/visibility/task/report/audit tables and HubSpot links/queue view.
6. **Scout and partner acquisition** — `scout_leads`, `scout_contacts`, routing/sync functions and triggers.
7. **Legacy supporter/payment authority** — `supporter_payments`, `supporter_subscriptions`, profile entitlement cache/guard, contributions.

The new Community Pass Package A objects are not present in Production and therefore are not part of this 45-table checkpoint. They remain additive draft objects in PR #128.

## What remains to capture before an executable canonical baseline

1. Table columns, data types, generated/identity/default expressions, nullability and comments.
2. Primary, foreign, unique, exclusion and check constraints with ordered columns and actions.
3. Complete index definitions, predicates, expressions and ownership.
4. View definitions, options, dependencies and grants.
5. Function bodies/hashes, owners, security mode, search paths, ACLs and dependencies.
6. Trigger definitions, ordering and enabled state.
7. Complete RLS policy expressions plus table/schema/function grants.
8. Required non-public schemas, types, sequences, storage configuration, cron jobs and provider-managed settings.
9. A repository↔96-row-live-ledger compatibility map and explicit treatment of unknown historical SQL.
10. Independent database/security review before any executable baseline file exists.

## No-go conditions

Do not use this summary to:

- create or approve executable baseline SQL;
- modify the Production ledger;
- claim full schema parity;
- copy business data into a fixture or branch;
- merge PR #128 or begin Package B;
- alter existing RLS, grants, functions, views, triggers, Auth, storage, cron, or provider settings;
- create another paid branch without a separate cost estimate and Geronimo approval.

Production impact: **NONE**.
