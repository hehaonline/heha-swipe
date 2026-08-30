# HEHA Partner Onboarding — Canonical Task List

Status: **Review-only implementation candidate**  
Primary pilot: **Pure Kitchen / Sachiko**  
Public launch: **Blocked until every applicable gate has evidence**

## Definition of done for one partner

A partner is complete only when all of these are true:

1. The correct business and authorized signer are bound through a protected
   invitation/claim flow; no duplicate profile exists.
2. Legal entity, DBA, licenses, W-9/tax model, insurance, contacts, service area,
   hours, capacity, menu/products, prices, availability, photos, and policies are
   verified for the relationship type.
3. The exact counsel-approved category agreement is accepted in HEHA Swipe and
   an immutable, downloadable receipt is retained.
4. HEHA Swipe and HEHA Local are added to the operator's home screen with clear
   device instructions.
5. A partner-specific HEHA Local profile exists. Generic category pages never
   count as orderable destinations.
6. An authenticated smoke test completes customer order → partner acceptance →
   driver assignment/pickup → delivery proof → customer/partner receipts, with
   cancellation, refund, and failure recovery also verified.
7. The partner approves the final preview and HEHA separately approves
   publication. Only then may the profile become visible/orderable.

## Work lanes and owners

| Task ID | Owner | Outcome | Current state / exit proof |
|---|---|---|---|
| `SWP-CLAIM-001` | Nova + security reviewer | Signed opaque partner invitation/claim binds Sachiko to Pure Kitchen | Blocked by SWP-016/#123 lineage; BOLA, expiry, replay, wrong-recipient and duplicate-profile proofs required |
| `LAW-REST-001` | Geronimo + Florida counsel | Restaurant Founding Beta Agreement approved | Must cover Fla. Stat. §509.103, fees, tax, disputes, price consent, insurance, removal, privacy and e-sign UI |
| `LAW-CAT-001` | Counsel | Separate approved agreements for vendor, market, catering, solo chef, driver and SOM | Each version receives its own hash and approval reference; catering also needs event SOW |
| `SWP-AGR-001` | Nova + database/security reviewer | In-app signing and immutable receipt | This branch supplies gated UI; PR #127 is donor; successor schema and exact-head synthetic proofs still required |
| `SWP-PROFILE-001` | Sachiko with Nova guidance | Pure Kitchen profile/menu/capacity complete | Private only; final menu/product editor and missing-field validation must pass |
| `SWP-MEDIA-001` | Sachiko + HEHA reviewer | Logo, cover and useful menu photos approved | Private upload/review exists; mobile HEIC/resize/EXIF handling and reviewer application path remain |
| `SWP-PWA-001` | Nova + device tester | Swipe installable on iPhone and Android | This branch restores SW registration, replaces corrupt icons and adds guided install; real-device proof required |
| `LOC-PWA-001` | Local engineer + device tester | Local independently installable and distinguishable | Private Local repo/access required; manifest, icons, SW and standalone launch must be verified separately |
| `LOC-PROFILE-001` | Nova + Local engineer | Pure Kitchen has a specific Local restaurant profile | Must use immutable cross-app identity, never a generic `/restaurants` path |
| `LOC-ORDER-001` | Local engineer + security reviewer | Menu/pricing/capacity/order path safe | Authenticated RLS, concurrency, idempotency, cancellation, refund and receipt proofs required |
| `DRV-APP-001` | Driver-product engineer + legal/ops | Driver app supports offered order → accept → pickup → delivery → incident | Classification, background/MVR consent, insurance, pay/tips/expenses, privacy and offline/failure behavior approved |
| `QA-SMOKE-001` | Independent tester | End-to-end smoke test receipt | Use synthetic/non-production first; then one explicitly approved controlled live order with two devices and evidence |
| `PUB-CONSENT-001` | Sachiko + HEHA reviewer | Final preview consent and admin publication | Separate append-only partner and HEHA approvals; agreement signing alone never publishes |
| `CRM-PILOT-001` | Nova | HubSpot has one deduplicated Pure Kitchen onboarding sequence | No outreach until the protected link works; relationship owner Kyoko, onboarding admin Sachiko, signer verified separately |
| `PARTNER-WAVE-001` | Nova | 3–5 caterers, 5–10 vendors, 5–8 restaurants, 3–5 grocery/markets ready | Tampa Bay + HEHA fit, consented outreach, one stage/task per record, no inactive businesses |

## Pure Kitchen one-link flow

Pure Kitchen roles stay deliberately simple: Sachiko is the primary onboarding
operator; Kyoko is the warm relationship owner. The protected claim service
must separately verify who has legal signing authority. If Sachiko is not the
authorized signer, she completes the operational steps and the same resumable
flow hands only the signing step to the verified signer—without duplicating the
profile or asking Kyoko to manage routine setup.

The link sent to Sachiko should open one resumable Partner Hub and present:

1. Verify invited account and business.
2. Confirm legal entity, DBA, license, tax, insurance, signer, and contacts.
3. Review/download and accept the Restaurant agreement in-app.
4. Complete menu, pricing, hours, cutoff, capacity, substitutions, allergens, and
   pickup/delivery settings.
5. Upload logo, cover, and menu/product photos.
6. Add HEHA Swipe and HEHA Local to the home screen using device pictures.
7. Run the test-order checklist.
8. Review the final Swipe/Local preview and approve publication.

If any validation fails, the flow preserves completed work, identifies one next
action, and stays private. Sachiko should receive one concise message only after
that exact protected link and the resume path are verified.

## Partner portfolio target and qualification funnel

“Onboarded” means published **and** orderable under the definition above—not a
contact, verbal yes, draft profile, or signed agreement alone.

| Category | Orderable goal | Tampa prospects to research | Qualified/warm target | Private onboarding target |
|---|---:|---:|---:|---:|
| Caterers | 3–5 | 12 | 8 | 5 |
| Product vendors | 5–10 | 25 | 15 | 10 |
| Restaurants | 5–8 | 20 | 12 | 8 |
| Grocery/farmers markets | 3–5 | 12 | 8 | 5 |

Every CRM record must be Tampa Bay + HEHA relevant, currently operating,
deduplicated, and assigned one current lifecycle stage and one next task.
Rockstar Café is inactive and must never receive another outreach task.
Advertising and broad outreach stay off until the complete Pure Kitchen path
passes in private. Then outreach expands one category cohort at a time.

## Zero-cash operating mode and team communication

HubSpot is the task and partner source of truth. A low-noise chat channel may
carry only alerts linking back to the HubSpot record; decisions, owners, due
dates, evidence, and blockers belong on the task. Use one weekly written brief
with: completed, next three, blockers, decisions, and smoke-test gate.

The dormant team receives one transparent status note only: operations are
being prepared founder-first, no paid hours or availability are assumed, and no
work is assigned until scope and compensation are explicitly agreed. Until
funding exists, Nova/Codex performs research, preparation, implementation, and
QA; Geronimo handles only founder approvals and external legal/business
authority. At smoke-test readiness, reactivation is a bounded role-by-role
decision:

| Role | First bounded responsibility after reactivation |
|---|---|
| Shahid / engineering | Exact-head Swipe, Local, and driver-app release proof; no independent deploy |
| Myren / partner ops | One partner at a time: missing assets, readiness evidence, and HubSpot stage hygiene |
| Shakil / outreach | Only approved Tampa records, one approved template, response logging, and opt-out handling |
| Raj / web | Approved public partner/onboarding surfaces only after publication gates pass |
| Independent QA | Two-device customer → partner → driver smoke test and failure-path evidence |

No former team member should be asked to perform unpaid operating work. A
status-only check-in or availability question is not a work assignment.

## Current no-go conditions

- Do not contact Sachiko with a generic `?becomePartner=1` URL; it can create a
  duplicate instead of claiming the intended profile.
- Do not enable the agreement runtime flag or register a legal version before
  counsel approval and the canonical database path are proven.
- Do not treat adding an icon, completing a Swipe profile, signing an agreement,
  or reaching a generic Local page as proof of orderability.
- Do not publish, advertise a named partner, take payments/orders, recruit
  drivers, or apply any database/Production change through this review lane.
