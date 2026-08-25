# Hybrid Community Pass Contract — Binding Corrections Addendum

**Date:** 2026-08-18  
**Parent contract:** `docs/community-pass-founding-presale-execution-contract-2026-08-18.md`  
**Canonical implementation issue:** https://github.com/hehaonline/heha-swipe/issues/125  
**HEHA-wide finance, tax, reward, and restaurant-order authority:** https://github.com/hehaonline/heha-order-hub/issues/234  
**Status:** REVIEW-ONLY / BINDING FOR THE IMPLEMENTATION SUCCESSOR / LIVE ACTION BLOCKED

## 1. Authority, corrected links, and exact supersession ledger

This addendum closes the required corrections raised by the independent review of parent-contract head `59bf60d5b7ca3d0a30d265c59a66acc66a90c0dd`.

It is binding wherever it adds detail to or conflicts with the parent contract. The parent contract remains controlling for approved prices, benefits, refund rules, activation rules, and the final live gate.

### Corrected authority links

The duplicated link in the earlier parent header is corrected in the parent source. The valid HEHA-wide authority is:

- https://github.com/hehaonline/heha-order-hub/issues/234

### Supersession ledger

| Earlier source | Current treatment |
|---|---|
| Original prepaid-only issue body and documentation head `7b9c965bc874d042e72c0254027aabad4bb82963` | **Superseded for the monthly option only.** Monthly is recurring. Six- and twelve-month prepaid rules remain preserved unless later modified explicitly. |
| Swipe #125 founder correction comment `5326455569` | Controls the hybrid offer: free no-card access; recurring `$2–$100/month`; `$15` six-month prepaid; `$25` twelve-month prepaid. |
| Order Hub #234 hybrid correction comment `5326475528` | Controls HEHA-wide finance/reward integration and the recurring-versus-prepaid correction. |
| Swipe #125 founder visual/copy comment `5328777557` | Controls the `$2–$100` slider UX and exact impact wording. |
| PR #126 founder copy-lock comment `5329293565` | Controls placement, copy consistency, and the fixed-allocation prohibition for the implementation successor. |
| Parent contract head `59bf60d5b7ca3d0a30d265c59a66acc66a90c0dd`, as corrected by later heads | Controls the hybrid architecture, except where this addendum supplies the required exact contracts below. |

No agent may revive the old `$1` minimum, present every paid plan as non-renewing, auto-convert the free trial, or apply six-/twelve-month reservation rules to an already active monthly subscription.

## 2. Founder-approved public impact copy

Use this exact sentence beneath or directly beside the Community Pass amount selector and on aligned Community Pass explanation surfaces:

> **Your support helps HEHA expand member benefits, support local healthy businesses, and strengthen its community mission.**

### Copy boundaries

- Keep the sentence unchanged unless Geronimo later approves a replacement.
- Keep **“Renews monthly until canceled.”** separate, prominent, and visible before monthly Checkout.
- The sentence may support the monthly, six-month, and twelve-month choices.
- It does not describe a donation, investment, equity purchase, ownership interest, ROI product, tax-deductible contribution, or fixed allocation.
- Do not publish `40% supports the Freebird Fund`, `20% of this payment`, or any other fixed Community Pass allocation until Finance/Governance and Geronimo approve that exact policy.
- Use the same wording on the canonical website, HEHA Swipe, HEHA Local Community Pass explanations, and the final before/after packet to prevent copy drift.

## 3. Payment finality and exact Stripe event contract

### 3.1 General finality rule

No Checkout success page, browser redirect, client callback, subscription creation event, or unverified metadata grants membership or creates a funded prepaid reservation.

Every provider event must:

1. enter the durable `community_pass_stripe_event_inbox` using `(stripe_event_id, environment)` as the unique key;
2. be signature-verified from the raw request body;
3. resolve the internal account/attempt through server-owned metadata;
4. retrieve the current Stripe object when finality or ordering is material;
5. verify flow, environment, product/Price, plan, amount, currency, user/account, offer version, and benefit version;
6. complete all intended state, entitlement, acceptance, and ledger writes atomically or remain retryable;
7. set `processed_at` only after successful completion.

Duplicate, replayed, delayed, concurrent, and out-of-order events must produce the same final state without duplicate entitlement, charge, invoice, refund, reward, or waiver.

### 3.2 Monthly recurring subscription event matrix

The beta monthly lane uses Stripe Checkout `mode='subscription'` and a new Community Pass recurring product identity.

#### Initial activation

`checkout.session.completed` may create or link the internal subscription attempt, but it does **not** activate benefits.

Monthly entitlement becomes `monthly_subscription_active` only when all of the following are true:

- a matching `invoice.paid` event has been verified;
- the server-retrieved invoice is paid;
- the server-retrieved Subscription is `active` or another explicitly approved paid state;
- product/Price, selected amount, quantity, currency, user/account, environment, offer version, and metadata all match;
- the acceptance record exists for the exact recurring-billing, cancellation, Terms, Privacy, and refund versions.

#### Required recurring events

- `checkout.session.completed`
- `checkout.session.expired`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.payment_action_required`
- `invoice.voided` where applicable
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `refund.created`
- `refund.updated`
- `refund.failed`
- `charge.refunded` for aggregate charge reconciliation only
- `charge.dispute.created`
- `charge.dispute.updated`
- `charge.dispute.closed`
- `charge.dispute.funds_withdrawn`
- `charge.dispute.funds_reinstated`

`customer.subscription.created` or `updated` alone can synchronize provider state but cannot unlock access without a verified paid invoice.

Refund-object events are authoritative for an individual refund lifecycle. `charge.refunded` is a consistency and aggregate-reconciliation signal; it must not replace `refund.created`, `refund.updated`, or `refund.failed`, and it must not create a second refund transition.

#### Seven-day payment recovery

On `invoice.payment_failed` or `invoice.payment_action_required` for a renewal:

1. set the internal state to `monthly_payment_recovery`;
2. record `recovery_started_at` and `recovery_deadline_at = server_event_time + 7 days`;
3. preserve benefits already approved for an order while payment was current;
4. block new Community Pass reward earning, new `$300+` delivery waivers, and any benefit that requires current payment;
5. show a clear payment-update action without claiming cancellation or successful recovery;
6. if `invoice.paid` arrives before the deadline and all verification passes, restore `monthly_subscription_active`;
7. at the deadline, a server worker retrieves the current Stripe invoice and Subscription;
8. if still unpaid, set `monthly_subscription_inactive_unpaid` and remove active benefit authorization;
9. final cancel/unpaid behavior must match the approved Stripe Billing recovery configuration and Customer Portal terms.

A late paid event may restore future entitlement only after server verification; it cannot retroactively create credits or delivery waivers for orders placed while payment was unresolved.

#### Cancellation

- Customer Portal or the approved internal action schedules cancellation at period end.
- `customer.subscription.updated` records `cancel_at_period_end` and the final paid access boundary.
- `customer.subscription.deleted` ends provider status but cannot erase invoices, acceptance evidence, ledger entries, or open liabilities.
- No future renewal occurs after cancellation takes effect.

### 3.3 Six-/twelve-month prepaid finality

The controlled beta should display only immediate-confirmation methods for six-/twelve-month prepaid Checkout when Stripe configuration allows that restriction.

The webhook must nevertheless fail safely if Stripe reports a delayed payment state:

- `checkout.session.completed` + server-retrieved `payment_status='paid'` → `reserved_prepaid_paid`;
- `checkout.session.completed` with unpaid/processing state → `prepaid_payment_pending`, no reservation benefit and no earned revenue;
- `checkout.session.async_payment_succeeded` + full server verification → `reserved_prepaid_paid`;
- `checkout.session.async_payment_failed` → `prepaid_payment_failed`;
- `checkout.session.expired` → `prepaid_checkout_expired`;
- `refund.created`, `refund.updated`, and `refund.failed` update the canonical refund attempt, settled-refund amount, refundable liability, reservation, entitlement, and human-resolution state after server retrieval and verification;
- `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed`, `charge.dispute.funds_withdrawn`, and `charge.dispute.funds_reinstated` update the canonical dispute, cash, liability, entitlement-risk, and reconciliation states without browser authority;
- `charge.refunded` is retained only as an aggregate charge-reconciliation check and cannot substitute for Refund-object events.

A pending prepaid payment never starts the founding trial, creates an active paid term, or authorizes member benefits.

#### Exact refund state transitions

- `refund.created`: record one provider refund attempt and its amount. Set `refund_pending` unless the server-retrieved Refund is already `succeeded`; never decrement an open liability or end access from event metadata alone.
- `refund.updated`: retrieve the Refund and reconcile its current status and amount. A verified `succeeded` Refund increments settled `refunded_cents` exactly once and applies the approved full or partial entitlement/reservation transition. A pending, canceled, or otherwise non-final Refund remains non-settled.
- `refund.failed`: set `refund_failed`, preserve the unresolved customer liability, record the bounded failure reason, and route a retryable human-resolution case. It cannot be treated as refunded revenue or settled cash.
- A partial refund changes only the verified refunded amount and the corresponding unused entitlement value; it cannot double-revoke the retained paid period or remove legitimately earned HEHA Credit.

#### Exact dispute state transitions

- `charge.dispute.created`: set `dispute_open`, record the contested amount and provider IDs, place the financial record into reconciliation review, and prevent duplicate refund/credit remedies for the same contested value.
- `charge.dispute.updated`: synchronize evidence deadline, status, and contested amount from the server-retrieved Dispute without independently granting or revoking benefits.
- `charge.dispute.funds_withdrawn`: record the Stripe cash withdrawal and disputed-liability movement exactly once; this is not a customer refund.
- `charge.dispute.funds_reinstated`: reverse the matching cash-withdrawal reconciliation entry exactly once without creating new revenue or a new entitlement.
- `charge.dispute.closed`: set the canonical won/lost/other final outcome. A verified lost dispute may end future entitlement according to the approved risk policy and paid-period boundary, but it cannot retroactively add delivery charges or silently reverse legitimately earned credits. A won dispute restores only the applicable financial/reconciliation state.

Refund and dispute handling must be source-ordered by provider object state rather than arrival order. A refund event arriving before a late payment or invoice event must remain safely reconcilable and must not create negative refunded balances, duplicate entitlement changes, or revenue recognition.

### 3.4 Payment-finality tests

Prove at minimum:

- Checkout completion without `invoice.paid` does not activate monthly benefits;
- Subscription creation/update without a paid invoice does not activate benefits;
- paid invoice + inactive/mismatched Subscription fails closed;
- recurring payment failure enters the exact seven-day state;
- payment recovery before and after the deadline;
- late/out-of-order invoice and subscription events;
- prepaid `completed` while processing remains pending;
- async prepaid success/failure;
- full and partial `refund.created`/`refund.updated` success exactly once;
- `refund.failed` preserves an open liability and retry route;
- `charge.refunded` cannot duplicate a Refund-object transition;
- dispute creation, update, close, funds withdrawal, and funds reinstatement;
- refund-before-late-payment-event and dispute-before-refund ordering;
- duplicate event replay and worker/event concurrency;
- server-retrieved state overrides tampered or stale event metadata.

## 4. Account deletion, retention, redaction, and liability survival

### 4.1 Core deletion rule

Deleting an HEHA Auth account must revoke every reusable entitlement while preserving the minimum records required to reconcile payments, refunds, disputes, policy acceptance, taxes, and open support obligations.

No deleted account may remain benefit-active or be reusable by a later account that receives the same email address or device.

### 4.2 Auth foreign-key behavior

Financial and audit tables use nullable user linkage with `ON DELETE SET NULL` or an equivalent controlled deletion procedure. Before the Auth deletion completes:

1. set the Community Pass account to `deleted`;
2. revoke or end active entitlements;
3. cancel or schedule cancellation of an active monthly subscription according to the customer’s request and paid-period rights;
4. preserve open prepaid refund rights and unresolved liabilities;
5. replace reusable identity fields with a non-reversible, salted `account_reference_hash`;
6. record `account_deleted_at` and one append-only deletion event;
7. remove ordinary profile/contact data not required for the retained record.

### 4.3 Table-level deletion and retention proposal

This is the review-only beta schedule. Legal/CPA review may shorten or extend it before Production, and the final Terms/Privacy must disclose the approved schedule.

| Record | After account deletion | Provisional retention and purpose |
|---|---|---|
| `community_pass_accounts` | `user_id` cleared; status `deleted`; raw email/name/phone removed; salted account hash retained; trial entitlement revoked | 24 months for duplicate-trial review, refund/support routing, and abuse investigation; then delete or retain only where legal hold applies |
| `community_pass_subscriptions` | `user_id` cleared; provider IDs and immutable financial facts retained; no active entitlement authority | 7 years after final invoice/refund/dispute activity for accounting, tax, chargeback, and audit evidence, subject to written professional confirmation |
| `community_pass_purchases` | `user_id` cleared; provider IDs, amount, refundable liability, and policy references retained | 7 years after final payment/refund/dispute activity, subject to written professional confirmation |
| `community_pass_entitlements` | state changed to `revoked_account_deleted` or ended; user link cleared; no reusable token/state | 24 months after end/revocation for access disputes and audit; financial facts remain in purchase/subscription records |
| `community_pass_acceptances` | user link cleared; pseudonymous account reference and immutable policy/version evidence retained | 7 years with the associated financial contract, subject to legal review |
| `community_pass_events` | ordinary PII redacted; immutable financial, state-transition, actor-role, and reason facts retained | financial/contract events 7 years; non-financial operational events 24 months; legal hold overrides deletion |
| `community_pass_stripe_event_inbox` | no full raw payload retained; user/contact data absent; provider event and bounded processing facts retained | 24 months after successful processing, or longer while linked to an open refund, dispute, reconciliation exception, or legal hold |
| support/refund cases | contact fields minimized after closure; provider receipt/payment reference retained | 24 months after closure unless linked to a longer financial/legal retention requirement |

These periods are proposed operating limits, not a claim that every period is legally mandated. Production remains blocked until the CPA/legal memo confirms the approved schedule and lawful purpose.

### 4.4 Redaction rules

Remove or redact after deletion unless specifically required for an open case:

- display name;
- raw email address;
- phone number;
- delivery addresses;
- dietary or health preference data;
- device identifiers;
- full IP address;
- full user-agent string;
- free-text notes containing personal information.

Do not store full Stripe webhook payloads in the ordinary event inbox. Keep only required normalized fields and a bounded error summary.

### 4.5 Deleted-account refund/support verification

A former customer may request a refund or support after account deletion through the verified support route. Staff verifies identity using a controlled combination of:

- Stripe receipt or invoice identifier;
- payment amount/date;
- original payment-method verification available through Stripe;
- verified email ownership where still available through the provider;
- any additional low-risk verification approved in the support runbook.

Staff may resolve the financial obligation but cannot recreate a Community Pass entitlement without a new account and a separately authorized migration or purchase.

### 4.6 Deletion/reuse tests

Prove:

- active monthly account deletion revokes Local benefit authorization;
- prepaid reservation deletion preserves refund liability but no benefit;
- same email reused by a new Auth account receives no old purchase, trial, credit, waiver, or entitlement;
- deleted account can complete a valid refund through support verification;
- redacted records still reconcile to Stripe and accounting;
- no financial liability is erased;
- no deleted PII remains outside the approved retention set;
- legal hold prevents only the records covered by the hold from deletion.

## 5. Swipe-to-Local benefit trust boundary

### 5.1 One versioned server-to-server decision interface

HEHA Local must not read Swipe browser state, copy the Community Pass ledger, accept a customer-provided entitlement token, or infer membership from a Stripe object.

Prepare one fail-closed interface, provisionally:

`POST /functions/v1/resolve-community-pass-benefit-v1`

The final name may change, but the contract below is required.

### 5.2 Caller authentication and binding

- Called only from an HEHA Local server/Edge Function, never directly from a browser.
- Uses a dedicated server-to-server credential stored only in managed secrets.
- Request authentication is short-lived and replay-resistant.
- Bind `issuer`, `audience`, `environment`, `issued_at`, `expires_at`, and unique `jti/request_id`.
- Production Local may call only Production Swipe; test/staging environments cannot cross into Production.
- The canonical ONE HEHA account identifier must be mapped and verified before this bridge activates.

### 5.3 Minimal request

- canonical `heha_account_id`;
- `benefit_code` such as `restaurant_group_credit` or `restaurant_300_delivery_waiver`;
- `at_time` from the Local server;
- Local order/reference ID;
- unique decision request ID;
- caller environment and audience.

Do not send Stripe IDs, selected support amount, billing history, or unnecessary PII.

### 5.4 Minimal response

- `eligible: true|false`;
- sanitized entitlement state;
- `benefit_version`;
- `valid_from` and `valid_until`;
- `issued_at` and `expires_at`;
- opaque `decision_id`;
- bounded `reason_code`;
- issuer, audience, and environment.

The response TTL must be short; proposed maximum is five minutes. Local records the `decision_id`, benefit version, order reference, and outcome for audit but does not copy the subscription or purchase ledger.

### 5.5 Timeout, cache, revocation, and outage behavior

- Local timeout target: two seconds.
- One bounded retry is allowed only with the same idempotent decision request ID.
- A previously verified response may be cached for no more than five minutes and never beyond `valid_until`.
- Cancellation, payment failure, refund, account deletion, or revocation emits an outbox event that invalidates any local entitlement cache as quickly as practicable.
- A stale, expired, mismatched, unsigned, cross-environment, or unverifiable response fails closed.
- If Swipe or the bridge is unavailable, new group-order credits and new `$300+` delivery waivers remain disabled and unpublished.
- A bridge outage never adds a retroactive fee or removes a benefit already confirmed for an accepted order while entitlement was valid.
- AI cannot create, alter, or override a benefit decision.

### 5.6 Trust-boundary tests

Prove:

- valid active monthly, prepaid, and free-trial states;
- every inactive, pending, refund, payment-recovery, deleted, expired, and reconciliation-exception state;
- wrong issuer/audience/environment;
- expired token/response;
- replayed request ID/JTI;
- account mismatch;
- timeout and retry;
- revocation within the cache window;
- service outage;
- no browser-direct access;
- no Local database row can independently unlock a benefit;
- no retroactive charge after a confirmed decision.

Until this exact bridge passes proof, HEHA Local Community Pass credits and the `$300+` restaurant delivery waiver remain disabled and unpublished.

## 6. Immutable clickwrap evidence and Community Pass tax gate

### 6.1 Canonical acceptance record

Add an append-only table or equivalent immutable record:

`community_pass_acceptances`

Minimum fields:

- acceptance ID;
- user/account ID, nullable after deletion;
- pseudonymous account reference;
- subscription or purchase attempt ID;
- plan code and selected amount where applicable;
- offer version;
- benefit version;
- Terms version;
- Privacy version;
- recurring-billing disclosure version for monthly;
- cancellation-policy version;
- refund-policy version;
- exact accepted disclosure text hash;
- accepted timestamp from the server;
- locale;
- app/surface version;
- environment;
- server request/idempotency ID;
- deletion/redaction state.

The browser sends only the user’s explicit acceptance action and the version identifiers rendered by the server. The server verifies that those are the current versions for the quoted offer.

No purchase Session or monthly subscription Checkout may be created without the matching immutable acceptance record.

### 6.2 Required monthly disclosure

Before monthly Checkout, show and record a clear equivalent of:

> **$X per month. Renews monthly until canceled. Cancel before your next renewal to avoid the next charge.**

The selected amount, frequency, cancellation route, benefit-start timing, and current live/future benefit matrix must be visible before acceptance.

The approved mission sentence is supportive copy and cannot replace recurring-billing disclosure.

### 6.3 Prepaid disclosure

Before six-/twelve-month Checkout, show and record:

- exact one-time charge;
- no automatic renewal;
- reserved/founding-access timing;
- October 31 protection;
- pre-start refund right;
- post-start unused-future-month proration summary;
- support route.

### 6.4 Deletion behavior

On account deletion, clear `user_id` and ordinary PII but retain the pseudonymous acceptance evidence for the approved financial/legal retention period. Acceptance evidence cannot recreate an entitlement.

### 6.5 CPA/tax decision remains a hard gate

Restaurant-order tax analysis in Order Hub #234 does not decide Community Pass tax treatment.

Before Production, obtain a written CPA decision covering:

- taxability of the recurring monthly Community Pass in Florida and any other launch jurisdiction;
- taxability of six-/twelve-month prepaid passes;
- whether stated or bundled benefits change tax treatment;
- taxable amount and sourcing rules;
- treatment of discounts, free delivery, HEHA Credit, refunds, partial refunds, and cancellation;
- sales-tax calculation and refund reversal;
- recurring revenue recognition versus prepaid/unearned liability;
- processor fees, disputes, and failed refunds;
- exact ledger/account mappings and reporting cadence.

Until that memo is attached and reconciled, tax configuration, public Checkout, and revenue-recognition automation remain blocked.

## 7. Additional acceptance tests required by this addendum

The implementation successor must add exact-head proof for:

### Supersession and copy

- old `$1` and prepaid-only monthly copy absent from every new Community Pass surface;
- exact approved mission sentence rendered consistently;
- recurring disclosure remains separate and prominent;
- no fixed Freebird percentage claim;
- no donation/investment/tax-deductible implication.

### Acceptance evidence

- stale policy version rejected;
- missing recurring disclosure acceptance rejected;
- mismatched amount/plan/offer rejected;
- acceptance record immutable;
- account deletion redacts linkage without erasing evidence;
- success URL cannot manufacture acceptance.

### Accounting/tax gate

- tax remains feature-flagged/blocked until the CPA decision is recorded;
- monthly and prepaid entries never share the same liability/revenue classification by accident;
- refund and tax reversal reconcile to Stripe and the internal record;
- missing professional decision forces `KEEP BLOCKED`.

## 8. Execution boundary

This addendum authorizes only source-controlled review, draft implementation, disposable-environment testing, Stripe test mode, and preparation of the final evidence packet under issue #125.

It does **not** authorize:

- live Stripe product, Price, Checkout, subscription, charge, invoice, or refund changes;
- Production Supabase migration or function deployment;
- public website/app publication;
- live customer communication;
- Community Pass benefit activation;
- tax configuration;
- fixed Freebird allocation claims;
- merge to `main`;
- final go-live.

The next review must assess the parent contract and this addendum together at one exact head. Only after a `PASS` may the single-writer implementation successor open. Geronimo retains the final `APPROVE LIVE` / `KEEP BLOCKED` decision.
