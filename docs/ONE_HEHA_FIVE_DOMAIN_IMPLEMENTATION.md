# ONE HEHA — Five-Domain Implementation Contract

## North star

**ONE HEHA. ZERO BUREAUCRACY.**

The five domains are the permanent information architecture for HEHA Swipe, HEHA Local / Order Hub, `ops.heha.online`, and future HEHA workspaces.

1. `01 CTRL` — Control Center
2. `02 OPS` — Operations & Service Delivery
3. `03 TECH` — Product & Technology
4. `04 GROW` — Growth & Partnerships
5. `05 COMM` — Brand, Content & Community

These domains cover every current and planned HEHA function. They are navigation and ownership taxonomy, not separate databases.

## Coverage check

### 01 CTRL
Governance, executive overview, approvals, finance governance, issues, settings, audit, permissions, source-of-truth controls, analytics, legal/compliance decisions, and final HEHA review decisions.

### 02 OPS
Orders, dispatch, customers, restaurants, vendors, markets, chefs, drivers, shoppers, catering, service requests, payouts, refunds, support, incidents, inventory/availability, operational messaging, and fulfillment.

### 03 TECH
HEHA Swipe, HEHA Local, websites, Supabase, APIs, automations, GitHub, deployments, architecture, migrations, bugs, releases, security, observability, data quality, and system integrations.

### 04 GROW
Scout leads, CRM, outreach, onboarding, partner readiness, expansion, sales follow-up, referrals, account activation, institutional partnerships, community partnerships, and acquisition events.

### 05 COMM
Brand, content, campaigns, social media, HEHA Journal, community, events, offers, Community Pass, media/photo approval, launch assets, public messaging, newsletters, and education.

## Classification rule

Every page, feature, task, issue, notification, and record must have exactly one primary domain. Cross-domain links are allowed. Duplicate canonical editors are not.

Examples:

- Final approval of a meal badge: `CTRL`
- Menu and item operations: `OPS`
- Ingredient rules engine and macro provider: `TECH`
- Partner onboarding pipeline: `GROW`
- Meal photo and launch-content review: `COMM`

## Product boundaries

### HEHA Swipe
Primary: `GROW` + `COMM`
Supporting: selected `CTRL` and `TECH`
Limited `OPS`: explicit links/handoffs only

### HEHA Local / Order Hub
Primary: `OPS`
Supporting: `CTRL` + selected `TECH`
Limited `GROW` and `COMM`: activation and operational handoffs

### ops.heha.online
Cross-product operating shell for authorized users. It summarizes, routes, approves, and links to canonical workflows. It must not become a duplicate source of truth.

## Role visibility

- Super Admin: all five domains
- SOM: `OPS` + selected `GROW` + selected `COMM`
- PM/Myren: `GROW` + `COMM` + selected `CTRL`
- Community/Event Lead: `COMM` + selected `GROW`
- Driver/Shopper: assigned `OPS`
- Restaurant/Vendor/Market/Chef: assigned `OPS` + selected `COMM`
- Customer/Explorer: public discovery and personal workflows, not internal domain navigation

Backend authorization and RLS are mandatory. UI hiding is not security.

## Shared visual contract

- HEHA Local is the structural reference.
- White workspace background.
- Compact headers and typography.
- 14–18 px card radii.
- Subtle green-gray borders and restrained shadows.
- Orange is an accent, not a large surface treatment.
- Domain colors stay consistent:
  - CTRL green `#49B654`
  - OPS orange `#F47C35`
  - TECH blue `#3478F6`
  - GROW purple `#8B4DE8`
  - COMM yellow `#F5B82E`
- The same number, code, title, and color must appear across apps.

## Claude Code execution rules

1. Inspect before editing.
2. Work in a feature branch, never directly on `main`.
3. One capability per PR.
4. Do not consolidate Supabase projects before ADR-001 is signed.
5. Do not create duplicate canonical tables or records.
6. Preserve RLS, roles, payments, routing, realtime updates, and audit behavior.
7. Do not weaken tests or validation to pass CI.
8. Every PR must include affected files, risks, tests, rollback, screenshots/preview notes, and unresolved decisions.
9. Stop for approval before production migrations, destructive cleanup, payment changes, public certification claims, or architecture consolidation.
10. Prefer elimination, defaults, automation, and approval-by-exception over additional forms or statuses.

## Recommended build sequence

1. Shared domain registry and role-aware shell.
2. Shared design tokens and primitives.
3. HEHA Local SOM navigation repair.
4. Reciprocal workspace switching between Swipe and Local.
5. Canonical role/permission mapping.
6. Unified approval inbox.
7. Partner lifecycle and readiness handoff.
8. Item, ingredient, media, and review model.
9. Deterministic HEHA rules engine.
10. Macro calculator provider adapter and confidence model.
11. Public filters and reviewed badges.
12. Shared notifications and event audit log.
13. Canonical backend consolidation only after signed ADR and migration plan.

## Definition of done for the shell

- All five domains are visible to Super Admin.
- Each role sees only permitted modules.
- Existing working routes still open.
- Cross-app functions link to their canonical app instead of being duplicated.
- Domain configuration is data-driven and reusable.
- Mobile navigation is compact and professional.
- No schema, RLS, payment, or backend consolidation change is bundled with the shell.
