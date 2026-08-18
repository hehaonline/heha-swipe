# Founding Community Pass Pre-Sale — Execution Contract

**Date:** 2026-08-18  
**Canonical implementation issue:** [#125](https://github.com/hehaonline/heha-swipe/issues/125)  
**HEHA-wide finance/tax/reward authority:** [heha-order-hub#234](https://github.com/hehaonline/heha-order-hub/issues/234)  
**Status:** REVIEW-ONLY / IMPLEMENTATION DESIGN AUTHORIZED / LIVE ACTION BLOCKED

## 1. Founder authorization

Geronimo approved the Community Pass founder-policy sequence and authorized the agents to proceed with the **review-only implementation and evidence phase**.

This contract allows:

- repository and live-state collision analysis;
- one isolated technical implementation lane;
- source-controlled schema, Edge Function, UI, test, accounting, Terms, copy, monitoring, and rollback plans;
- Stripe **test-mode** and disposable-environment proof only after the exact test packet is reviewed;
- preparation of one final `APPROVE LIVE` / `KEEP BLOCKED` packet.

This contract does **not** allow:

- live Stripe product, Price, Payment Link, Checkout Session, webhook, charge, or refund changes;
- Production Supabase migration, function deployment, or data mutation;
- Production deployment or public checkout;
- website publication, customer communication, advertising, or benefit activation;
- automatic renewal, card-required trial, automatic paid conversion, or browser-owned entitlement;
- investment, equity, ROI, ownership, charitable-donation, or tax-deductible claims.

Geronimo remains the sole final live go/no-go authority.

## 2. Current-state collision receipt

HEHA Swipe already contains a legacy supporter stack on `main`:

| Layer | Current file | Current behavior / collision |
|---|---|---|
| Customer UI | `src/components/CommunityPassTab.jsx` | Advertises recurring monthly support, `$1–$100/month`, active supporter state, and legacy benefits. |
| Client entry | `src/lib/supporterCheckout.js` | Maps the selected dollar amount directly to quantity of a `$1/month` recurring Price. |
| Checkout | `supabase/functions/create-supporter-checkout/index.ts` | Uses Stripe Checkout `mode='subscription'`, clamps quantity to 1–100, and writes `support_type='supporter_membership'`. |
| Webhook | `supabase/functions/stripe-webhook/index.ts` | Processes existing supporter subscription and one-time support events and updates `supporter_subscriptions`, `supporter_payments`, `contributions`, and profile cache fields. |
| Entitlement | `20260707062836_supporter_entitlement_security.sql` | Returns only live `active`/`trialing` subscription rows and guards profile payment fields. |
| Proof | `supabase/tests/supporter_entitlement_security_proof.sql` | Proves the legacy recurring entitlement boundary, not the prepaid trial/reservation/refund lifecycle. |

### Collision decision

The legacy supporter flow must remain historically intact and must not be silently reinterpreted as Community Pass.

The approved Community Pass contract is materially different:

- one-time prepaid terms rather than subscriptions;
- no automatic renewal;
- no-card internal founding trial;
- payment creates a reservation, not immediate access;
- member-started 30-day trial after invitation;
- 60-day self-service window and day-90 refund protection;
- pre-start and post-start refund/proration rules;
- restaurant-order reward and free-delivery dependencies;
- prepaid/unearned revenue and refundable-liability accounting.

For that reason, the safest successor is a **versioned Community Pass lane** with explicit metadata, tables, events, functions, and test-mode webhook isolation. It may reuse common Stripe/Supabase utilities, but it may not reuse the legacy recurring Price, legacy subscription rows, or legacy profile cache as its authority.

## 3. Approved offer contract

### Free founding trial

- 30 days of Community Pass access for invited founding waitlist members.
- No card.
- No automatic paid conversion.
- One trial per verified person or business account, with human review for suspected duplicates.

### Optional founding pre-sale

All paid options are one-time, prepaid, and non-auto-renewing:

| Term | Price | Notes |
|---|---:|---|
| 1 month | customer-selected `$2–$100` | suggested display `$5`; presets `$2/$5/$10/$15/$25/$50/$100`; same benefits at every amount |
| 6 months | `$15` | fixed one-time price |
| 12 months | `$25` | fixed one-time price |

Payment creates a reserved paid term. The paid term begins only after the member activates and completes the free 30 days.

### Invitation and activation

1. HEHA sends an invitation only when the approved benefits are genuinely usable.
2. The member has 60 days to select **Start My 30 Days**.
3. Only a server-confirmed activation action starts the trial.
4. Reminders occur approximately on days 7, 30, and 53.
5. Day 60 closes ordinary self-service activation.
6. Days 61–90 allow assisted activation or refund.
7. No response by day 90 triggers a full unused-term refund attempt.
8. Failed refunds remain open liabilities for human resolution.

Payment, success URL, invitation delivery/open, login, or browser state cannot start access.

### October 31 protection

If founding access has not opened by 2026-10-31, the purchaser receives a clear choice to:

- refund the unused prepaid term; or
- voluntarily retain the reservation and continue supporting the launch.

No silent extension or forfeiture.

## 4. Time and proration rules

All canonical timestamps are stored in UTC and displayed in the user’s approved locale/time zone.

### Trial

- `trial_started_at` = server timestamp of the successful activation transition.
- `trial_ends_at` = `trial_started_at + 30 days`.
- Paid access starts at `trial_ends_at` exactly once.

### Paid terms

Paid terms use calendar-month anniversaries anchored to `paid_term_started_at`:

- one month ends at `paid_term_started_at + 1 calendar month`;
- six months ends at `paid_term_started_at + 6 calendar months`;
- twelve months ends at `paid_term_started_at + 12 calendar months`.

Month boundaries are computed from the original paid-term anchor, not by repeatedly adding one month to a previously shortened month. The implementation must include end-of-month test cases such as January 31, February, leap years, and daylight-saving transitions.

### Post-start cancellation

- One-month access is ordinarily nonrefundable after start and remains active to its end.
- Six-/twelve-month access retains the currently started month and refunds completely unused future months.
- Six-month refund = `unused_months × $2.50`.
- Twelve-month refund = `ceil(2500 cents × unused_months / 12)` so rounding cannot disadvantage the customer.
- Entitlement ends at the retained-current-month boundary.
- Duplicate charges, payment errors, and documented material HEHA failures remain separately reviewable.

## 5. Recommended successor architecture

### 5.1 Dedicated versioned checkout function

Add a new function:

`supabase/functions/create-community-pass-checkout/index.ts`

Rationale: changing the deployed legacy `create-supporter-checkout` from subscription behavior to one-time prepaid behavior could silently alter historical supporter expectations and break existing records. The new function is not a second competing Community Pass system; it is the explicit versioned successor while the legacy flow is isolated and later parked through a separate reviewed release.

Requirements:

- authenticated permanent HEHA user required;
- accepts only `plan_code` and, for the one-month plan, `selected_amount_cents`;
- server validates:
  - `founding_1_month`: 200–10,000 cents inclusive;
  - `founding_6_month`: exactly 1,500 cents;
  - `founding_12_month`: exactly 2,500 cents;
- Stripe Checkout `mode='payment'`;
- server-owned product/price/description and offer version;
- one active Checkout attempt per internal purchase attempt;
- Stripe idempotency key derived from the internal attempt ID and offer version;
- explicit metadata:
  - `heha_flow=community_pass_prepaid_v1`
  - `purchase_id`
  - `user_id`
  - `plan_code`
  - `term_months`
  - `amount_cents`
  - `offer_version`
  - `environment`
- success/cancel URLs are navigation only;
- no entitlement change inside the checkout function;
- no saved card or future off-session charge requirement;
- no client-provided customer, product, Price, currency, term, or redirect destination.

### 5.2 Dedicated versioned webhook/event route

Recommended test successor:

`supabase/functions/community-pass-stripe-webhook/index.ts`

Use a dedicated webhook signing secret and subscribe only to the required Community Pass test events. This isolates the new event contract from the currently deployed supporter webhook while preserving one Community Pass authority.

Minimum event handling:

- `checkout.session.completed`
- `checkout.session.expired`
- `payment_intent.payment_failed`
- `charge.refunded` and/or the final Stripe refund event set selected from current Stripe docs
- `charge.dispute.created`, `charge.dispute.closed` where needed for reconciliation

Requirements:

- signature verification on raw request body;
- durable event inbox keyed by Stripe event ID and environment;
- event stays retryable until all intended writes finish;
- duplicate/replayed/out-of-order events are safe;
- verify exact flow metadata, internal purchase, user, plan, amount, currency, environment, and offer version;
- no amount-based inference;
- no success-page authority;
- explicit partial/full refund and dispute state handling;
- no full raw event payload in ordinary UI, logs, or evidence.

A final implementation review may choose safely isolated routing inside the existing webhook instead, but only if it proves that deployment cannot regress the legacy supporter flow. The issue and PR must record that decision explicitly before code is merged.

### 5.3 Canonical tables

Prepare an additive migration, proposed path:

`supabase/migrations/20260818_create_community_pass_prepaid_foundation.sql`

#### `community_pass_purchases`

Canonical payment/reservation record:

- `id uuid primary key`
- `user_id uuid not null`
- `plan_code text not null`
- `term_months integer not null`
- `selected_amount_cents integer not null`
- `currency text not null default 'usd'`
- `offer_version text not null`
- `environment text not null`
- provider IDs: Checkout Session, PaymentIntent, Charge, Customer
- payment/refund/reconciliation states
- `gross_cents`, `refunded_cents`, `refundable_unearned_cents`, `earned_cents`
- created/updated/paid/refunded timestamps
- unique provider IDs where non-null
- immutable amount/plan/offer facts after Checkout creation

#### `community_pass_entitlements`

Canonical access record:

- `id uuid primary key`
- `user_id uuid not null`
- `purchase_id uuid null` for the free trial
- one trial identity key per verified account
- state
- reserved term months
- invitation sent/expiry
- trial activated/start/end
- paid term start/end
- cancellation requested
- retained current-month end
- access end
- refund and support-review timestamps
- policy/benefit version
- human override audit references

#### `community_pass_events`

Append-only lifecycle audit:

- internal event ID
- purchase/entitlement/user references
- event type
- provider event ID and environment where applicable
- idempotency key
- prior/new state
- reason code
- actor type/ID
- created timestamp
- no update/delete by ordinary clients

#### `community_pass_stripe_event_inbox`

Retry-safe provider inbox:

- Stripe event ID + environment unique key
- event type
- received/claimed/processed timestamps
- attempt count
- bounded error status
- purchase reference after trusted resolution
- no public/authenticated direct access

### 5.4 Server-owned APIs/RPCs

Proposed narrow interfaces:

- `get_my_community_pass_status()` — sanitized current purchase/entitlement state only.
- `activate_my_founding_trial(entitlement_id, idempotency_key)` — authenticated, exact account, state/window/version checks, atomic transition.
- `request_my_community_pass_refund(purchase_id, reason_code, idempotency_key)` — creates a request; does not let the browser choose amount or provider IDs.
- staff refund/exception functions separated from customer functions and restricted to approved roles.
- transition worker/functions calculate reminders, day-60 expiry, trial-to-paid activation, paid expiry, day-90 refund queue, and cancellation end dates from server time.

The client may request an allowed action but cannot set state, dates, term, amount, refund amount, entitlement ownership, Stripe identity, benefit eligibility, or audit facts.

### 5.5 Derived compatibility fields

The existing `profiles.subscription_*` fields must not remain a second entitlement authority.

Preferred direction:

- new UI reads `get_my_community_pass_status()`;
- benefit checks use a server-owned `is_community_pass_active(user_id, at_time)` contract or equivalent;
- any profile field retained for legacy compatibility is explicitly derived, non-authoritative, and safe to rebuild.

Historical `supporter_subscriptions`, `supporter_payments`, and `contributions` rows remain intact and are not migrated into Community Pass automatically.

## 6. UI plan

### Community Pass surface

Replace legacy recurring-support purchase copy in the successor branch with:

- free waitlist choice;
- optional founding pre-sale choice;
- one-month `$2–$100` slider with `$5` suggested display and approved presets;
- fixed six-month `$15` and twelve-month `$25` cards;
- clear “Pay once” and “No automatic renewal” language;
- 30 founding days, invitation/start sequence, October 31 protection, and refund summary before checkout;
- accurate `Reserved`, `Invitation ready`, `Trial active`, `Paid term active`, `Ending`, `Refund pending`, `Refunded`, and `Support review` states;
- no “active” badge based only on the success URL or legacy subscription cache.

### Accessibility and mobile

- native range input or equivalent with visible value and instructions;
- 44px targets;
- keyboard operation and visible focus;
- status changes announced appropriately;
- error and recovery actions named;
- no color-only state;
- 320/390/430/768/1280 widths and 200% zoom;
- screen-reader-oriented labels, descriptions, and status semantics.

## 7. Benefit-gating contract

Only these states count as active membership:

- `trial_active`
- `paid_term_active`

The following never unlock benefits:

- checkout pending/failed/expired;
- reserved paid;
- invited/activation available;
- activation-window expired;
- support review;
- refund requested/pending/failed after access has ended;
- refunded;
- expired;
- reconciliation exception.

Community Pass benefits include the founder-approved restaurant-only `$300+` delivery waiver and group-order HEHA Credit tiers defined in `heha-order-hub#234`. HEHA Local must consume a minimal, server-verifiable entitlement result; it must not copy or calculate Community Pass state independently.

## 8. Accounting contract

Pending CPA confirmation:

- successful pre-sale receipt posts to prepaid/unearned Community Pass liability;
- no revenue is recognized merely because Checkout succeeded;
- refundable unused value remains visible;
- revenue is recognized according to the approved accounting method as paid access is delivered;
- pending/failed refunds remain liabilities;
- processor fees are separate expenses;
- Community Pass money remains separate from restaurant gross/payables, driver pay, gratuity, sales tax, HEHA Credit liability, and Freebird accrual;
- every Stripe object and entitlement/refund event reconciles to one internal purchase;
- no charitable contribution or tax-deductible receipt language.

## 9. Public copy and legacy cleanup

Review-only canonical copy:

> Joining the waitlist is free. Founding support is optional today.
>
> Founding waitlist members receive 30 days of Community Pass access when invitations open—no card required. After the free period, choose HEHA Free, 1 month from $2, 6 months for $15, or 12 months for $25. Pay once. Nothing renews automatically.

Before public checkout:

- update the canonical root;
- retire/redirect/correct `/how-heha-delivery-works` and all conflicting `$8.33/month`, `$1/month`, recurring, or “coming soon” Community Pass copy;
- publish stable Terms, Privacy, refund/cancellation, and support routes;
- show the exact activation and refund protections before payment;
- never describe the pre-sale as equity crowdfunding, an investment, profit share, ROI, donation, or tax-deductible support.

## 10. Required proof

### Payment boundaries

- `$1.99` rejected; `$2.00` accepted; `$100.00` accepted; `$100.01` rejected.
- Exact `$15` and `$25` fixed terms.
- Tampered plan/amount/user/currency/environment/offer version rejected.
- Duplicate Checkout attempts do not create duplicate payable Sessions.
- Payment success without a valid webhook grants no access.
- Failed/expired payment does not reserve access.

### Entitlement lifecycle

- payment → reservation only;
- invitation → no access;
- activation day 1/day 59 succeeds;
- day 60+ self-service fails closed;
- 30-day transition and 1/6/12-month term transitions occur once;
- concurrent/two-device activation is idempotent;
- calendar-month edge cases pass;
- benefit checks fail closed outside active states.

### Refunds

- full pre-start refund for all terms;
- refund before invitation, after invitation, and during free trial;
- October 31 choice;
- day-90 refund attempt;
- retryable failed refund;
- one-month post-start rule;
- six-/twelve-month retained-current-month proration;
- customer-favorable rounding;
- duplicate/replayed refund does not double-refund;
- entitlement closes on the correct boundary.

### Security

- RLS/BOLA and privilege/function matrix;
- User A cannot inspect or act on User B;
- browser cannot set protected fields;
- service functions have fixed, minimal authority;
- event inbox handles retry, replay, concurrency, and out-of-order events;
- no secrets/payment data/private event payload leakage.

### UX/operations

- responsive/accessibility matrix;
- accurate receipt and account status;
- refund/support case routing;
- no false “sent”, “active”, “refunded”, or “renewing” claim;
- manual/non-AI route exists.

### Finance/legal

- Stripe/internal-ledger/accounting reconciliation;
- CPA status/memo;
- Terms/Privacy/refund version and clickwrap proof;
- public before/after copy matrix;
- rollback/monitoring and customer-impact summary.

## 11. Execution sequence and ownership

1. **Current-state audit:** exact repository head, live function/webhook/product/price exposure, schema lineage, and customer-impact map.
2. **Architecture review:** confirm dedicated successor vs safely isolated existing webhook routing.
3. **Draft implementation:** one branch/PR, no Production.
4. **Disposable/test-mode evidence:** synthetic accounts and Stripe test objects only.
5. **Independent exact-head review:** security, Stripe, database, finance, UX/accessibility.
6. **Final founder packet:** exact `APPROVE LIVE` / `KEEP BLOCKED` recommendation.

Ownership:

- single HEHA Swipe implementation writer;
- Shahid independently reviews technical/security/release evidence;
- Nova reconciles collisions and the final packet;
- Myren owns support/refund-operational readiness and evidence tracking;
- Finance/Governance obtains CPA/legal confirmation;
- Geronimo approves live Stripe, Production, publication, spend/contracts, and final activation.

Target for the consolidated final packet: **2026-08-26 through 2026-08-28**, conditional on external CPA/legal response and clean tests.

## 12. Final live gate

The final packet must show, on one exact reviewed head:

- exact customer offer and public copy;
- exact Stripe test products/prices/metadata and receipts;
- entitlement state machine and dates;
- full refund/proration proof;
- RLS/BOLA/idempotency/replay/concurrency proof;
- accounting/tax/legal status and unresolved professional advice;
- website before/after matrix;
- support, monitoring, rollback, and incident ownership;
- known limitations and exact customer impact;
- one recommendation: **APPROVE LIVE** or **KEEP BLOCKED**.

No intermediary test, green preview, merged code, or successful Checkout by itself authorizes live payment or public activation.