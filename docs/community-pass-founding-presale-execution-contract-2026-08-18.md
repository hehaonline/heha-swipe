# Founding Community Pass — Hybrid Subscription + Prepaid Execution Contract

**Date:** 2026-08-18  
**Canonical implementation issue:** [#125](https://github.com/hehaonline/heha-swipe/issues/125)  
**HEHA-wide finance/tax/reward authority:** [heha-order-hub#234](https://github.com/hehaonline/heha-order-hub/issues/234)  
**Status:** REVIEW-ONLY / IMPLEMENTATION DESIGN AUTHORIZED / LIVE ACTION BLOCKED

## 1. Founder correction and authority

Geronimo clarified on 2026-08-18 that the monthly Community Pass slider is intended to create real recurring Community Pass subscribers. The prior prepaid-only interpretation was too broad.

This contract therefore supersedes every earlier statement in this branch or issue that described all three paid choices as one-time or non-renewing.

The approved hybrid model is:

1. **Free founding waitlist access:** 30 days, no card, no automatic conversion.
2. **Monthly slider:** a recurring Community Pass subscription from **$2–$100 per month**, suggested at **$5**, renewing monthly until canceled.
3. **Six-month pass:** **$15 one-time prepaid**, non-auto-renewing.
4. **Twelve-month pass:** **$25 one-time prepaid**, non-auto-renewing.

The recurring monthly subscription is not a separate “supporter” program. It is one billing option for the single public program named **Community Pass**.

This contract allows review-only architecture, code, test, accounting, Terms, copy, monitoring, and rollback work on one isolated lane. It does **not** authorize live Stripe changes, Production Supabase changes, deployment, public checkout, customer charges, refunds, benefit activation, outbound messages, or publication. Geronimo retains the final live go/no-go.

## 2. Current-state collision receipt

HEHA Swipe already contains a recurring supporter stack on `main`:

| Layer | Current file | Current behavior / gap |
|---|---|---|
| Customer UI | `src/components/CommunityPassTab.jsx` | Recurring `$1–$100/month` supporter wording and legacy benefit copy. |
| Client entry | `src/lib/supporterCheckout.js` | Maps selected whole dollars to quantity of a fixed `$1/month` recurring Price. |
| Checkout | `supabase/functions/create-supporter-checkout/index.ts` | Stripe Checkout `mode='subscription'`; legacy `supporter_membership` metadata. |
| Webhook | `supabase/functions/stripe-webhook/index.ts` | Handles subscription events and writes supporter subscription/profile cache rows. |
| Entitlement | `20260707062836_supporter_entitlement_security.sql` | Recognizes live `active` or `trialing` legacy supporter subscriptions. |
| Proof | `supabase/tests/supporter_entitlement_security_proof.sql` | Proves the existing recurring boundary, not the full Community Pass hybrid lifecycle. |

### Collision decision

`mode='subscription'` is directionally correct for the **monthly slider**. It is not correct for the fixed six- and twelve-month prepaid options.

The existing stack must not be reused unchanged because it still has material contract gaps:

- minimum is `$1`, not `$2`;
- public terminology is “supporter,” not one Community Pass program;
- the Stripe product/Price and metadata identify the legacy supporter flow;
- it has no six- or twelve-month prepaid purchase path;
- no canonical free no-card founding-trial record;
- no 60-day invitation window, day-90 resolution, or October 31 protection;
- no complete Community Pass cancellation/refund/proration state machine;
- no durable source-controlled event inbox proving replay, retry, and out-of-order safety;
- no unified entitlement contract for recurring monthly plus prepaid terms;
- no Community Pass benefit-version, restaurant reward, or free-delivery dependency proof;
- no final accounting separation between recurring revenue, prepaid liability, refundable amounts, HEHA Credit liability, and restaurant-order money.

Historical supporter rows and Stripe IDs must remain intact. They may not be silently relabeled or reinterpreted as the new hybrid Community Pass contract.

## 3. Approved public offer

### 3.1 Free founding waitlist path

- Joining the waitlist remains free.
- Invited founding members receive 30 days of Community Pass access.
- No card is required.
- There is no automatic paid conversion.
- One founding trial per verified person or business account, with human review for suspected duplicates.
- A free user must explicitly choose a paid option later.

### 3.2 Monthly Community Pass subscription

- Customer chooses a whole-dollar monthly amount from **$2–$100**.
- Suggested/default display: **$5/month**.
- Presets: **$2, $5, $10, $15, $25, $50, $100**.
- Every valid amount receives the same approved Community Pass benefit level.
- Stripe Checkout uses recurring subscription mode.
- The initial charge occurs only after the customer clearly authorizes the recurring subscription.
- The subscription renews monthly until canceled.
- Cancellation normally takes effect at the end of the already-paid period.
- A failed renewal follows the approved seven-day recovery policy; new benefits are not granted while payment is unresolved.
- A free waitlist or free-trial account is never converted into this subscription automatically.

### 3.3 Six- and twelve-month prepaid passes

| Plan | Price | Renewal |
|---|---:|---|
| Six months | `$15` once | no automatic renewal |
| Twelve months | `$25` once | no automatic renewal |

These are one-time prepaid purchases. They may be offered as founding pre-sales and create a reserved future term until the approved activation sequence begins.

### 3.4 Minimum benefit truth before charging

The monthly subscription checkout may not be public until HEHA can truthfully deliver a documented minimum Community Pass benefit bundle immediately after verified payment. The final packet must list exactly which benefits are live on day one and which are future or beta-limited.

No public surface may charge a monthly subscriber while describing every meaningful benefit as “coming soon.” Restaurant-order rewards and free delivery may remain separately gated until the restaurant order system is certified, but their unavailable state must be explicit.

## 4. Trial, invitation, and activation boundaries

### Free waitlist trial

1. HEHA sends an invitation when founding trial access is genuinely usable.
2. The member has 60 days to press **Start My 30 Days**.
3. Only the server-confirmed action starts the 30-day trial.
4. Reminders occur approximately on days 7, 30, and 53.
5. Day 60 closes ordinary self-service activation.
6. A free member who paid nothing may later request another invitation; no money is forfeited.

### Prepaid six-/twelve-month reservation

1. Verified payment creates a reserved prepaid term, not active benefits by itself.
2. The member receives the founding invitation and explicitly starts the 30-day founding access.
3. The prepaid six- or twelve-month term begins exactly once after the 30 days end.
4. Days 61–90 after an unaccepted invitation offer assisted activation or refund.
5. No response by day 90 triggers a full unused-term refund attempt.
6. Failed refunds remain open liabilities for human resolution.

### Monthly subscription boundary

The paid monthly subscription is a separate explicit route. It is not placed into the 60-day reservation queue and is not an automatic continuation of the free founding trial.

A free member may subscribe at any time through a fresh, explicit monthly Checkout. After verified initial payment, recurring-monthly entitlement follows the subscription and invoice state. A success URL alone grants nothing.

## 5. October 31, 2026 protection

For an unused six- or twelve-month founding pre-sale, if founding access has not opened by **2026-10-31**, the purchaser receives a clear choice to:

- refund the unused prepaid term; or
- voluntarily retain the reservation while continuing to support the launch.

There is no silent extension or forfeiture.

The monthly subscription checkout should not be published before its minimum benefit bundle is usable, so HEHA should not accumulate recurring monthly charges against a delayed future activation promise.

## 6. Cancellation and refund contract

### Monthly recurring subscription

- Customer can cancel at any time; ordinary cancellation takes effect at the end of the current paid month.
- The current paid month is ordinarily nonrefundable after access has begun.
- No future renewal occurs after cancellation takes effect.
- Duplicate charges, payment errors, an entitlement activation failure after a successful charge, or a documented material HEHA service failure remain separately refundable.
- No forced HEHA Credit in place of an eligible cash refund.
- No retroactive delivery charge or reversal of legitimately earned HEHA Credit.

### Six-/twelve-month prepaid before access begins

- Customer may cancel the unused reservation at any time.
- Refund **100%** to the original payment method.
- No administrative, cancellation, or processing-fee deduction.
- HEHA initiates a valid refund within two business days.
- Failed refunds remain open liabilities until resolved.
- An independently eligible free founding trial is not automatically removed.

### Six-/twelve-month prepaid after access begins

- The currently started month remains active and nonrefundable.
- Completely unused future months are refunded to the original payment method.
- Six-month proration: `unused_months × $2.50`.
- Twelve-month proration: customer-favorable calculation; rounding never disadvantages the customer.
- Entitlement ends at the retained-current-month boundary.
- No cancellation fee, forced HEHA Credit, retroactive delivery charge, or reversal of legitimately earned credit.

## 7. Recommended hybrid Stripe architecture

### 7.1 One versioned Community Pass checkout entry point

Prepare a versioned successor function, recommended path:

`supabase/functions/create-community-pass-checkout/index.ts`

The function is one Community Pass entry point with server-owned branches by plan code. It is not a second program.

Accepted plan codes:

- `community_pass_monthly_slider_v1`
- `community_pass_6_month_prepaid_v1`
- `community_pass_12_month_prepaid_v1`

#### Monthly branch

- Stripe Checkout `mode='subscription'`.
- Use a new HEHA Community Pass recurring product/Price identity, not the legacy supporter product.
- A server-owned `$1/month` support-unit Price with quantity `2–100` is acceptable if exact test evidence proves the selected whole-dollar amount and receipt wording; the browser may never provide the Price ID.
- Require explicit recurring-billing disclosure before Checkout.
- Metadata must identify the exact user, plan, selected amount, offer version, environment, and Community Pass flow.
- Prevent multiple active monthly subscriptions for the same HEHA account unless an approved replacement/change flow exists.

#### Six-/twelve-month branches

- Stripe Checkout `mode='payment'`.
- Fixed server-owned one-time prices of `$15` and `$25`.
- Browser cannot select the amount, term, Price ID, currency, customer, or redirect destination.
- Verified payment creates a reserved prepaid entitlement, not immediate paid-term access.

#### Shared requirements

- authenticated permanent HEHA identity;
- server-owned quote and offer version;
- Stripe idempotency key tied to the internal attempt and offer version;
- one active payable Session per attempt;
- exact HEHA allowlist for success/cancel origins;
- success/cancel pages are navigation only;
- no client-owned entitlement or provider state.

### 7.2 Metadata contract

At minimum:

- `heha_flow=community_pass_hybrid_v1`
- `billing_model=recurring_monthly|prepaid_term`
- `user_id`
- `purchase_or_subscription_attempt_id`
- `plan_code`
- `selected_amount_cents`
- `term_months`
- `offer_version`
- `benefit_version`
- `environment`

Do not infer the plan from amount alone.

### 7.3 Webhook and event handling

Use one versioned Community Pass event contract, either in a dedicated endpoint or safely isolated inside the existing verified webhook. The exact-head review must prove that historical supporter events cannot be misrouted.

Required recurring events include the current Stripe event set needed for:

- Checkout completion/expiration;
- initial subscription payment success/failure;
- recurring invoice payment success/failure;
- subscription update/cancellation/deletion;
- refund/dispute handling where applicable.

Required prepaid events include:

- Checkout completion/expiration;
- payment failure;
- full/partial refund;
- dispute and reconciliation events where applicable.

Every provider event must enter a durable, retryable event inbox. An event is complete only after all intended state and ledger writes finish. Duplicate, replayed, delayed, concurrent, and out-of-order events must be safe.

### 7.4 Customer Portal

Use the Stripe Customer Portal for monthly subscribers unless the exact product rules require a custom action. The portal should support payment-method updates, invoice/receipt access, and cancel-at-period-end. HEHA’s internal webhook and entitlement state remain authoritative after the provider event arrives.

The six- and twelve-month prepaid passes are not recurring subscriptions and should not be represented as cancellable subscriptions in the portal.

## 8. Canonical data model

Do not use `profiles.subscription_*` as the canonical source. Those fields may remain a derived compatibility cache only when they are rebuildable and cannot unlock benefits by themselves.

### `community_pass_accounts`

One account-level program identity:

- user/account ID;
- trial-used status;
- current sanitized entitlement state;
- benefit/policy version;
- review/hold status;
- created/updated timestamps.

### `community_pass_subscriptions`

Recurring monthly contract:

- internal ID and user ID;
- Stripe Customer, Subscription, Price, latest Invoice IDs;
- selected monthly amount cents and quantity;
- status, current period start/end;
- cancel-at-period-end and canceled timestamps;
- failed-payment recovery state/deadline;
- offer/policy/benefit version;
- environment and reconciliation state;
- unique provider IDs.

### `community_pass_purchases`

One-time six-/twelve-month purchases:

- internal purchase ID and user ID;
- plan code and term months;
- amount/currency;
- Stripe Checkout Session, PaymentIntent/Charge, Customer and Refund IDs;
- payment, reservation, refund, and reconciliation states;
- gross/refunded/refundable-unearned/earned amounts;
- immutable offer/policy version;
- environment and timestamps.

### `community_pass_entitlements`

Canonical access periods:

- user/account and source type: free trial, recurring subscription, or prepaid purchase;
- source ID;
- state;
- invitation/start/end timestamps where applicable;
- active period start/end;
- retained-current-month end;
- cancellation/refund/revocation/support-review facts;
- policy/benefit version;
- human override audit reference.

### `community_pass_events`

Append-only internal lifecycle audit for payment, invoice, subscription, purchase, invitation, reminder, activation, benefit, cancellation, refund, correction, and human override events.

### `community_pass_stripe_event_inbox`

Retry-safe provider inbox keyed by Stripe event ID and environment, with bounded processing status, attempts, trusted source resolution, and `processed_at` only after completion.

## 9. Server-owned entitlement contract

Provide one sanitized method such as:

`get_my_community_pass_status()`

Provide one server-side authorization method such as:

`is_community_pass_active(user_id, at_time)`

Only verified active states may unlock benefits:

- `trial_active`
- `monthly_subscription_active`
- `prepaid_term_active`
- approved limited grace state where the exact benefit policy permits it.

Never unlock from:

- Checkout success URL;
- browser/local storage;
- reserved prepaid payment alone;
- invitation alone;
- pending/failed/refunded/reconciliation-exception state;
- legacy profile cache alone;
- unverified subscription or invoice metadata.

HEHA Local consumes a minimal server-verifiable entitlement result. It must not build a second Community Pass ledger or calculate membership independently.

## 10. Public UI and copy

The customer sees one Community Pass program with three paid choices and one free route.

### Required labels

**Free founding access**

> Join the free waitlist. No card. No automatic conversion.

**Monthly slider**

> Choose your monthly Community Pass support: $2–$100/month. Renews monthly until canceled.

**Six months**

> $15 once. Six months of Community Pass after your founding access. No automatic renewal.

**Twelve months**

> $25 once. Twelve months of Community Pass after your founding access. No automatic renewal.

Do not place “Pay once” or “Nothing renews automatically” over the monthly subscription option. Those statements apply only to the fixed prepaid terms.

Before payment, disclose:

- exact charge today;
- whether it renews;
- renewal amount/frequency;
- how to cancel;
- when benefits begin;
- which benefits are live now;
- trial/prepaid activation rules where applicable;
- refund/cancellation summary;
- October 31 protection for unused prepaid reservations;
- support route and policy version.

Public terminology is **Community Pass** and **Community Pass Member**. “Supporter” may appear descriptively, but it cannot create a second program or hide recurring billing.

## 11. Benefits and rewards

Only a verified active Community Pass entitlement may unlock member benefits.

Approved restaurant group-order reward tiers:

- 10–14 fulfilled portions → `$8 HEHA Credit`
- 15–19 → `$10`
- 20–29 → `$12`
- 30–39 → `$18`
- 40–49 → `$25`
- 50+ → `$30 maximum`

Approved restaurant-only free delivery:

- one `$12.50` waiver for each qualifying coordinated restaurant-food order with an eligible subtotal of `$300+`;
- no monthly beta limit;
- no groceries, Market shopping, vendors, wellness, events, taxes, fees, or gratuity in the threshold.

The detailed HEHA Credit expiration, release, no-reward-on-credit, redemption, refund, and ledger rules remain controlled by `heha-order-hub#234`.

Goodwill and voluntary refund-replacement credits remain available to nonmembers when warranted.

## 12. Accounting and reconciliation

Pending CPA confirmation:

### Monthly subscriptions

- initial and recurring receipts are Community Pass subscription receipts;
- recognize revenue according to the approved monthly service period;
- failed, refunded, disputed, or unearned amounts remain separately visible;
- Stripe fees are separate expenses;
- no charitable donation or tax-deductible receipt language.

### Six-/twelve-month prepaid passes

- receipt initially posts to prepaid/unearned Community Pass liability until access is delivered;
- recognize revenue according to the approved method over the delivered term;
- refundable unused value stays visible;
- pending/failed refunds remain liabilities.

### Separation

Community Pass money must remain separate from restaurant gross/payables, driver/SOM pay, gratuity, sales-tax reserve, HEHA Credit liability, and Freebird accrual. Every Stripe object and entitlement/refund event reconciles to one internal record and the accounting system.

## 13. Required test matrix

### Monthly slider subscription

- `$1` rejected; `$2` accepted; `$100` accepted; `$101` rejected;
- selected amount maps exactly to the server-owned recurring amount/quantity;
- correct receipt and recurring disclosure;
- client cannot choose Price ID, user, currency, metadata, or redirect;
- duplicate Checkout attempt does not create duplicate active subscriptions;
- success URL without verified webhook grants no benefit;
- initial payment failure;
- recurring renewal success;
- renewal failure and seven-day recovery;
- cancel-at-period-end;
- no renewal after cancellation;
- portal payment-method update;
- duplicate/replayed/out-of-order subscription and invoice events;
- old supporter subscription cannot unlock the new Community Pass contract without an explicit reviewed migration decision.

### Free founding trial

- no card;
- invitation grants no access;
- activation on day 1/day 59;
- day 60+ self-service denial;
- reminders suppress after activation;
- exact 30-day calculation;
- no automatic subscription or charge at trial end.

### Six-/twelve-month prepaid

- exact `$15` and `$25`;
- payment creates reservation only;
- trial-to-paid transition occurs once;
- six-/twelve-month calendar boundaries;
- full pre-start refund;
- day-90 refund attempt;
- October 31 choice;
- post-start retained-current-month proration;
- customer-favorable rounding;
- failed refund remains retryable/open;
- no auto-renewal.

### Security and reliability

- complete RLS/BOLA and function-execute matrix;
- User A cannot read or act on User B;
- browser cannot set protected states, dates, provider IDs, amounts, or refund values;
- service functions have narrow grants and fixed search paths where applicable;
- event inbox retry/replay/concurrency/out-of-order proof;
- no secret, raw payment data, private event payload, or unnecessary PII leakage;
- two-device and account-switch tests;
- idempotent human override with named actor/reason/timestamp.

### UX and operations

- 320/390/430/768/1280 widths and 200% zoom;
- keyboard, focus, 44px targets, status announcements, and screen-reader-oriented labels;
- exact monthly recurring versus prepaid wording;
- clear cancellation/refund/support paths;
- no false “active,” “sent,” “refunded,” “free,” or “non-renewing” claim;
- manual/non-AI route exists.

### Finance and legal

- Stripe/internal ledger/accounting reconciliation;
- monthly revenue and prepaid-liability treatment confirmed;
- Terms/Privacy/cancellation/refund versions and clickwrap proof;
- public before/after copy matrix;
- monitoring, rollback, customer-impact summary, and professional-advice status.

## 14. Execution sequence to evidence-backed 100%

1. **Correct source of truth:** this hybrid contract, #125, #234, Launch Control, and MASTER TASKS agree.
2. **Independent architecture review:** exact-head PASS/CHANGES REQUIRED.
3. **Single-writer draft implementation:** one branch/PR; no competing checkout or entitlement lane.
4. **Disposable Supabase + Stripe test mode:** no Production data or live customer charge.
5. **Automated and adversarial proof:** checkout, subscription, invoice, prepaid, entitlement, refund, RLS/BOLA, replay, concurrency, accounting, and accessibility.
6. **Independent exact-head review:** security, Stripe, database, finance, legal/copy, and operations.
7. **Final packet:** one evidence table, known limitations, rollback, and `APPROVE LIVE` or `KEEP BLOCKED` recommendation.
8. **Geronimo final go/no-go:** live Stripe, Production, public copy, and customer charges remain blocked until this approval.

“100%” means every required gate has current dated evidence. It never means estimating completion from a draft PR, green preview, or agent activity.

## 15. Final live gate

The final packet must show on one exact reviewed head:

- exact free, recurring monthly, six-month, and twelve-month customer offers;
- exact Stripe test product/Price/metadata/Checkout/invoice/refund receipts;
- recurring subscription and prepaid entitlement lifecycles;
- cancellation, failed-payment, refund, and proration proof;
- RLS/BOLA/idempotency/replay/concurrency proof;
- accounting/tax/legal status;
- website/app before-and-after matrix;
- support, monitoring, rollback, and incident ownership;
- live versus future benefit matrix;
- known limitations and exact customer impact;
- one recommendation: **APPROVE LIVE** or **KEEP BLOCKED**.

No intermediary test, merge, deployment, successful Checkout, or Stripe subscription by itself authorizes live payment or public activation.
