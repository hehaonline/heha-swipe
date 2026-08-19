# Community Pass Hybrid Implementation — Current-State and Collision Receipt

**Date:** 2026-08-19  
**Canonical implementation issue:** [#125](https://github.com/hehaonline/heha-swipe/issues/125)  
**Architecture authority:** draft [PR #126](https://github.com/hehaonline/heha-swipe/pull/126) at `cc78c9bc7a6559dcff23f009c45cacf895248fc4`  
**Implementation base:** `main@82ec41a27150847f3d461716bc58636e24babfe6`  
**Implementation branch:** `agent/community-pass-hybrid-implementation-20260819`  
**Status:** REVIEW-ONLY IMPLEMENTATION PREP / LIVE BILLING BLOCKED

## 1. Purpose and non-authorization

This receipt completes the first implementation step required by #125: identify the current source, live-provider state, overlapping pull requests, historical records, and exact file boundaries before runtime code is changed.

It authorizes no live action. In particular, it does not authorize:

- merge to `main`;
- Production Supabase migration or function deployment;
- live Stripe product, Price, Checkout Session, subscription, invoice, charge, refund, webhook, tax, or Customer Portal mutation;
- public website/app copy;
- member benefit activation;
- customer communication or real billing.

## 2. Current repository behavior at the implementation base

### 2.1 Customer UI — `src/components/CommunityPassTab.jsx`

Current behavior:

- public terminology mixes **Community Pass** and **supporter**;
- advertises `$1–$100/month`;
- default amount is `$5`;
- quick action starts at `$1/month`;
- active status is derived from the legacy supporter entitlement row;
- cancellation modal still says “Even $1/month helps” and “Lower to $1/month”;
- current benefits are discovery/community promises and several future local-deal surfaces;
- there is no six-month `$15` or twelve-month `$25` prepaid choice;
- there is no no-card founding-trial lifecycle or accurate reserved/recovery/refund state UI.

Collision decision:

- evolve this one customer-facing Community Pass surface rather than create a competing program or duplicate dashboard;
- retain the business Partner Hub portion unless a separate reviewed partner PR changes it;
- replace legacy supporter authority with the new sanitized Community Pass status contract;
- use the exact approved impact sentence and separate recurring disclosure.

### 2.2 Client Checkout helper — `src/lib/supporterCheckout.js`

Current behavior:

- accepts integer quantity `1–100`;
- invokes the deployed `create-supporter-checkout` function;
- assumes a fixed `$1/month` recurring Price;
- redirects directly to the returned Stripe Checkout URL.

Collision decision:

- do not change its meaning silently for old callers;
- prepare a versioned `communityPassCheckout` client entry that accepts a server-owned plan code and selected monthly amount only where permitted;
- monthly is recurring `$2–$100`; six/twelve months are fixed one-time prices;
- browser cannot provide Price IDs, customer IDs, currency, redirect origins, provider state, entitlement dates, or refund values.

### 2.3 Client entitlement helper — `src/lib/supporterStatus.js`

Current behavior:

- calls `get_my_active_supporter_entitlement()`;
- exposes only status, quantity, and amount from a live active/trialing legacy supporter subscription.

Collision decision:

- keep the old helper available only for historical/legacy display if a reviewed migration decision requires it;
- new Community Pass UI and HEHA Local benefits must use a new sanitized canonical status result;
- legacy supporter rows and `profiles.subscription_*` cannot unlock the new Community Pass contract.

### 2.4 Checkout Edge Function — `supabase/functions/create-supporter-checkout/index.ts`

Current behavior:

- `mode='subscription'`;
- CORS origin is `*`;
- clamps browser quantity to `1–100` instead of rejecting tampering;
- uses one environment-provided legacy supporter Price;
- metadata identifies `supporter_membership` and `heha_swipe`;
- sends success/cancel to `/support/success` and `/support/cancel`;
- creates no internal attempt, immutable acceptance, offer version, benefit version, or durable idempotency record;
- does not prevent multiple active subscriptions for the same HEHA account.

Collision decision:

- preserve the deployed legacy function until historical exposure and rollback are understood;
- preferred successor is a versioned `create-community-pass-checkout` function with monthly and prepaid server-owned branches;
- exact HEHA origin allowlist, permanent authenticated account, immutable acceptance, internal attempt ID, provider idempotency key, product/Price/environment binding, and duplicate-subscription prevention are mandatory;
- success/cancel routes are navigation only.

### 2.5 Stripe webhook — `supabase/functions/stripe-webhook/index.ts`

Current behavior:

- verifies Stripe signature;
- processes `checkout.session.completed`, `customer.subscription.updated`, and `customer.subscription.deleted`;
- infers some one-time support types from amount;
- writes legacy supporter tables, contributions, and profile payment cache;
- creates active profile state from Subscription status without requiring verified `invoice.paid`;
- has no source-controlled durable event inbox;
- does not implement the approved invoice-failure/action-required recovery, async prepaid finality, Refund-object lifecycle, dispute lifecycle, replay/out-of-order state contract, or immutable acceptance validation.

Collision decision:

- historical supporter events must remain isolated;
- new Community Pass events must route by exact versioned metadata, never by amount;
- use a dedicated Community Pass endpoint or an explicitly isolated branch inside the verified webhook only after exact review;
- every event enters the durable inbox and remains retryable until all intended state and ledger writes finish;
- verified `invoice.paid` plus valid server-retrieved Subscription state is required for monthly access;
- Refund-object events are authoritative for individual refunds; `charge.refunded` is aggregate reconciliation only.

### 2.6 Legacy entitlement migration — `20260707062836_supporter_entitlement_security.sql`

Current behavior:

- protects legacy supporter base tables from browser reads;
- exposes a minimal active/trialing legacy entitlement RPC;
- guards browser writes to profile payment-cache fields;
- gives service-role authority over the legacy supporter/payment tables;
- does not define free founding access, prepaid terms, immutable acceptance, deletion/redaction, refund/dispute liability, event inbox, or the Swipe-to-Local benefit bridge.

Collision decision:

- preserve this migration and historical rows;
- add a forward-only Community Pass foundation after migration-lineage reconciliation;
- do not rewrite old migrations or reinterpret old supporter records.

## 3. Live Stripe read-only audit — 2026-08-19

Verified from the connected Healthy Habit LLC Stripe account:

- active legacy product **HEHA Supporter Membership** with one recurring `$1/month` support-unit Price;
- active **SuperSwoop** `$2` one-time product;
- active **HEHA Swipe Support** `$1` one-time product;
- no separate **HEHA Community Pass** product or approved `$15`/`$25` prepaid Prices exist;
- the sole live webhook points to the current Supabase `stripe-webhook` and subscribes only to:
  - `checkout.session.completed`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
- a direct `status=active` subscription query returned zero active subscriptions;
- historical QA/test-origin subscriptions remain as canceled records and must not be deleted or silently reclassified.

Provider decision:

- do not mutate the live legacy product, Price, webhook, subscriptions, or records during implementation;
- create test-mode Community Pass objects only after the test naming/metadata/environment packet is source-controlled and reviewed;
- before live approval, repeat the active-subscription and customer-impact audit and prepare an explicit legacy-object retirement/retention decision.

## 4. Open pull-request and source-lineage collisions

### PR #69 — legacy supporter migration source

- adds the missing source for the live supporter foundation migration;
- directly affects whether a disposable database can reproduce the current supporter tables;
- do not duplicate that migration in this implementation branch;
- before representative replay, either compose the reviewed #69 source or attach an equivalent exact lineage receipt approved by the database reviewer.

### PR #113 — Swipe launch candidate

- changes `src/App.jsx`, `src/main.jsx`, auth/entry surfaces, support-success evidence, and design files;
- does not directly change `CommunityPassTab.jsx`, but it owns route/session/guest/auth composition around the Community surface and `/support/success` behavior;
- this implementation branch is cut from current `main`, not #113;
- do not stack silently on #113 or merge #113 independently as a Community Pass dependency;
- after implementation proof, create one explicit composition/rebase plan that preserves the approved entry/auth behavior while replacing unverified support-return authority.

### PR #116 — downloadable/native readiness audit

- records that the Stripe Community Pass purchase provides digital in-app benefits;
- first native iOS/Android binaries should omit the purchase/entitlement sales surface unless StoreKit/Play Billing or an explicitly eligible external-purchase program is separately approved and implemented;
- the current implementation lane is web/PWA and Stripe-test only.

### Partner publication and benefit dependencies

- partner-publication RC #127 and its donor PRs govern whether local offers and listings are truthful and approved;
- they are not part of this Community Pass implementation branch;
- day-one paid benefit copy may not promise unapproved partner deals;
- HEHA Local restaurant rewards and the `$300+` waiver remain disabled until the versioned server-to-server entitlement bridge and restaurant-order evidence pass.

### Legal acceptance and account deletion

- current legal-acceptance/account-deletion work must be reconciled before schema or UI implementation is called complete;
- Community Pass requires immutable Terms, Privacy, recurring-billing, cancellation and refund acceptance tied to the exact account, offer, amount, surface, time and versions;
- account deletion must revoke reusable entitlement while preserving minimal payment/refund/dispute/tax evidence and open liabilities.

## 5. New blockers discovered in this audit

1. **Canonical issue drift — fixed:** issue #125 still contained the old prepaid-only body while its title/comments were hybrid. The body was replaced on 2026-08-19.
2. **Architecture review — closed:** PR #126 received exact-head architecture PASS at `cc78c9b…`.
3. **Live event coverage:** the current webhook lacks every required invoice failure/action, paid-invoice, refund, dispute, and async prepaid event except the three legacy events listed above.
4. **Live object identity:** no separate Community Pass product/Prices exist; legacy supporter objects cannot be renamed or reused without a reviewed migration/customer-impact decision.
5. **Migration lineage:** supporter source lineage remains incomplete on `main` while PR #69 is open.
6. **ONE HEHA identity:** Swipe and Local still lack a proven canonical account mapping for server-authorized benefits.
7. **Minimum day-one benefit:** monthly checkout must remain private until HEHA can deliver at least one truthful, usable benefit immediately after verified payment.
8. **Professional advice:** Community Pass tax, monthly revenue, prepaid liability, refunds, benefit allocation, retention and exact ledger mapping lack a written CPA decision; legal policy versions also remain unapproved.
9. **Native billing:** web Stripe billing cannot be assumed valid inside the first native store binaries.
10. **Repository governance:** `main` is currently unprotected; direct pushes and accidental merges must be operationally prohibited for this money/entitlement lane until repository protection is configured.

## 6. File-level implementation order

### Package A — additive data and authority foundation

Proposed files:

- one forward-only Community Pass migration after lineage review;
- SQL proof for table grants, RLS/BOLA, immutable events/acceptance, deletion/reuse and entitlement transitions;
- canonical sanitized status RPC;
- server-only benefit-decision function/interface contract;
- transition/refund/recovery workers or narrowly scoped functions.

Do not build Checkout first. The server-owned attempt, acceptance, event-inbox and entitlement objects must exist before provider events can be handled safely.

### Package B — versioned Checkout and provider events

Proposed files:

- `supabase/functions/create-community-pass-checkout/index.ts`;
- dedicated or explicitly isolated Community Pass Stripe webhook;
- tests/fixtures for monthly, prepaid, invoice, refund, dispute, replay, concurrency and out-of-order handling;
- Customer Portal session function if a static portal URL cannot meet account-binding and return-origin requirements.

### Package C — customer UI and status

Proposed files:

- versioned Community Pass Checkout/status client helpers;
- evolve the customer portion of `CommunityPassTab.jsx`;
- styles and focused UI tests;
- accurate status, live/future benefit, cancellation/refund and support states;
- exact approved mission copy and recurring disclosure;
- no false active state from redirect or legacy profile cache.

### Package D — HEHA Local benefit bridge

Separate repository/lane after Package A proof:

- authenticated server-to-server call only;
- canonical account mapping;
- short TTL, audience/environment binding, replay protection, decision ID and fail-closed outage behavior;
- no copied subscription/purchase ledger;
- no retroactive delivery fee after an already confirmed benefit decision.

### Package E — evidence and final packet

- disposable Supabase replay and rollback;
- Stripe test objects and receipts;
- amount boundaries and duplicate-session/subscription prevention;
- monthly initial/renewal/failure/recovery/cancel tests;
- prepaid reservation/activation/October-31/day-90/refund/proration tests;
- RLS/BOLA, deletion/reuse, event replay/concurrency and cross-app tests;
- mobile, keyboard, screen-reader-oriented and 200% reflow QA;
- Stripe/internal/accounting reconciliation;
- Terms/Privacy/clickwrap and CPA status;
- public before/after matrix, monitoring and rollback;
- one final `APPROVE LIVE` or `KEEP BLOCKED` recommendation.

## 7. Immediate execution status

Ready now:

- architecture and public offer;
- reserved single-writer branch;
- current source collision receipt;
- live Stripe read-only baseline;
- exact implementation order and stop rule.

Still blocked from live activation:

- all ten blockers in Section 5 plus complete test evidence and Geronimo’s final go-live approval.

The next safe code action is **Package A only**. No other agent should open a second Community Pass implementation branch or modify live provider/database state.