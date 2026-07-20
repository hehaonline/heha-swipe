# ONE HEHA Connected Workspace Contract

Status: implementation contract for HEHA Swipe, HEHA Local / Order Hub, and future `ops.heha.online`.

## North star

**ONE HEHA. Zero bureaucracy.**

A user should understand one five-domain system even when individual functions are implemented in different applications. An approved change should be entered once, reviewed once, and propagated to every authorized surface.

## Permanent domain taxonomy

| Domain | Color | Primary responsibility |
|---|---:|---|
| 01 CTRL | `#49B654` | Governance, approvals, finance controls, issues, permissions, audit, and final source-of-truth decisions |
| 02 OPS | `#F47C35` | Orders, customers, partners, drivers, dispatch, fulfillment, payouts, support, and service delivery |
| 03 TECH | `#3478F6` | Product, integrations, Supabase, automations, security, releases, bugs, and architecture |
| 04 GROW | `#8B4DE8` | Scout, CRM, onboarding, readiness, partnerships, sales follow-up, referrals, and expansion |
| 05 COMM | `#F5B82E` | Brand, content, HEHA Journal, community, events, offers, media, and launch assets |

These codes, numbers, labels, colors, and ordering must remain consistent across all HEHA applications.

## Product ownership

### HEHA Swipe

Canonical home for:

- discovery and saved partners;
- community participation and events;
- Scout and partner-growth workflows;
- partner readiness and public visibility preparation;
- Swipe-specific profile, content, and community interactions.

### HEHA Local / Order Hub

Canonical home for:

- customer orders and account operations;
- restaurant/vendor/market/chef operations;
- drivers, dispatch, fulfillment, payouts, and support;
- structured items, ingredients, macros, photos, and HEHA review;
- shared requests, assignments, escalation, and administrator resolution.

### `ops.heha.online`

Future unified internal shell for:

- cross-product summaries;
- executive CTRL view;
- global search and navigation;
- approval and issue aggregation;
- links into canonical object editors.

It must not become another duplicate database or editor.

## Visibility versus permission

Every authorized dashboard may show all five domains. Visibility does not grant write permission.

Each domain/module must display one of these access modes:

- **Operate** — the user can complete the canonical work.
- **Participate** — the user may submit or collaborate but cannot make the final protected decision.
- **View** — informative/read-only.
- **Request** — sends one structured request to the canonical queue.

Restricted modules must not disappear. They remain informative and offer a request path.

## Role defaults

### Customer

- CTRL: Request
- OPS: Operate customer account and orders
- TECH: Request
- GROW: Discover
- COMM: Participate

### Partner

- CTRL: Request
- OPS: Operate partner account, items, and orders
- TECH: Request
- GROW: Participate
- COMM: Participate

### Driver

- CTRL: Request
- OPS: Operate assigned delivery work
- TECH: Request
- GROW: View
- COMM: View

### SOM

- CTRL: View / Request
- OPS: Operate
- TECH: View / Request
- GROW: Participate or operate assigned workflows
- COMM: Participate

### Project Manager

- CTRL: Prepare / Request; no automatic final authority
- OPS: View or coordinate assigned operational projects
- TECH: Coordinate; no production/security authority by default
- GROW: Operate assigned readiness/project workflows
- COMM: Operate assigned coordination workflows

### District Manager

Future regional escalation role between SOM and founder. It may resolve approved regional exceptions but does not inherit unrestricted finance, legal, architecture, or public-claim authority.

### Super Admin / Founder

Full visibility. Final authority remains limited by legal, financial, security, and architecture safeguards; the UI must not bypass explicit approval gates.

## Request hierarchy

Default temporary owner: Geronimo, configured through routing data rather than hardcoded identity.

Target hierarchy:

1. SOM or assigned first owner
2. District Manager or domain lead
3. Geronimo / final authority

The Project Manager coordinates status, missing information, and handoffs but is not automatically the final approver.

## Navigation rules

1. The five-domain strip remains familiar across every protected dashboard.
2. Local operational actions link to HEHA Local rather than being duplicated in Swipe.
3. Swipe growth/community actions remain in Swipe.
4. Cross-app links must be explicit until shared authentication is implemented.
5. A link must never imply that cross-app session sharing or a backend migration is already complete.
6. Mobile navigation must stay compact and must not obscure primary task controls.

## Design rules

- HEHA Local is the structural reference.
- White or neutral workspace background.
- Restrained domain color accents.
- Compact typography; avoid oversized dashboard headings.
- Small-to-medium corner radii.
- Subtle borders and shadows.
- Dense but readable cards.
- Same status vocabulary across products.
- All actionable cards must be clickable and keyboard accessible.

## Data rules

- Every real object has one canonical record.
- Cross-product views reference the canonical object rather than cloning it.
- No dual writes before an approved migration/compatibility design.
- No backend consolidation before ADR-001 approval.
- No role or RLS weakening to simplify navigation.
- No public HEHA Reviewed/Certified badge without approved terminology, criteria version, and audit state.

## Claude Code execution rules

Before editing:

1. inspect the current implementation and open PR stack;
2. identify the canonical product and object;
3. list affected files, risks, tests, and rollback;
4. stop when the work crosses authentication, RLS, payments, production migrations, public health claims, or ADR-001.

During implementation:

- one focused branch/PR per capability;
- preserve existing operations unless explicitly replacing them;
- never work directly on `main`;
- never hide a failing test or weaken authorization;
- include build, lint, role, mobile, and route verification;
- use feature flags for incomplete public behavior where appropriate.

## Definition of done

A connected workspace package is complete only when:

- all five domains are represented consistently;
- role access is explicit;
- canonical links lead to the correct product;
- restricted actions create a request instead of a dead end;
- mobile and desktop navigation work;
- builds and security checks pass;
- no duplicate canonical editor or database write is introduced;
- staging and RLS tests are complete for any database change;
- production remains unchanged until the reviewed PR is explicitly approved and deployed.
