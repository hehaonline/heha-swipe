# HEHA Swipe Stripe setup

This document defines the Stripe setup for HEHA Swipe subscriptions, paid SuperSwoops, and optional prototype/team support.

## Payment products

Create these Stripe products/prices in the Stripe Dashboard.

### 1. HEHA Swipe Supporter Membership

Purpose: optional monthly supporter subscription for HEHA Swipe users and partners.

Recommended MVP setup:

- Product name: `HEHA Swipe Supporter Membership`
- Price type: recurring
- Billing interval: monthly
- MVP amount: `$10/month` unless HEHA decides to keep the existing choose-your-own amount slider.

Current app status:

- `src/components/OnboardingScreen.jsx` already looks for `VITE_STRIPE_SUPPORTER_CHECKOUT_URL`.
- The onboarding flow stores `supporter_checkout_started` before redirecting to Stripe.
- The current slider shows a variable monthly amount, but a plain Stripe Payment Link is best treated as a fixed-price checkout unless a backend Checkout Session is added.

Best short-term choice:

- Use one fixed monthly supporter link first, likely `$10/month`.
- Hide or simplify the slider if the fixed-link model is used.

Best scalable choice:

- Add a Supabase Edge Function that creates a Stripe Checkout Session server-side.
- Pass `user_id`, `role`, `support_amount`, and `return_url` to the function.
- Store `stripe_customer_id`, `stripe_subscription_id`, `subscription_status`, and `subscription_amount` back to Supabase through Stripe webhooks.

### 2. HEHA Swipe SuperSwoop

Purpose: paid one-time boost/support action inside HEHA Swipe.

- Product name: `HEHA Swipe SuperSwoop`
- Price type: one-time
- Amount: `$2.00`
- Currency: `USD`

Recommended MVP payment link:

- Create a Stripe Payment Link for the `$2.00` one-time price.
- Add the live link to Vercel as `VITE_STRIPE_SUPERSWOOP_CHECKOUT_URL`.

Behavior goal:

1. User taps SuperSwoop on a partner card.
2. App redirects to Stripe for `$2.00` payment.
3. After payment success, Stripe returns user to HEHA Swipe.
4. Webhook confirms payment and records the SuperSwoop as paid.

Important: do not rely only on the frontend success URL to grant paid SuperSwoops. The final paid status should come from Stripe webhook verification.

### 3. HEHA Prototype Support Push

Purpose: optional pre-splash support prompt to create small prototype funding for the team while HEHA Swipe and HEHA Local are shared publicly.

- Product name: `HEHA Prototype Support Push`
- Price type: one-time
- Amount: `$1.00`
- Currency: `USD`
- Button copy: `Tap to support — $1 per push`

Recommended MVP payment link:

- Create a Stripe Payment Link for the `$1.00` one-time price.
- Add the live link to Vercel as `VITE_STRIPE_DOLLAR_SUPPORT_CHECKOUT_URL`.
- Use this as a non-blocking pre-splash prompt with a clear Skip button.

Behavior goal:

1. Visitor opens HEHA Swipe.
2. Visitor sees the optional support prompt before the normal splash screen.
3. Visitor can tap the round `$1` support button or skip.
4. If they support, Stripe processes the $1 payment and returns them to the app.
5. If they skip, the regular splash/app flow continues.

Important: this should stay optional during prototype sharing. It should create support, not friction.

## Required Vercel env variables

```bash
VITE_STRIPE_SUPPORTER_CHECKOUT_URL=
VITE_STRIPE_SUPERSWOOP_CHECKOUT_URL=
VITE_STRIPE_DOLLAR_SUPPORT_CHECKOUT_URL=
```

These are publishable frontend URLs only. Never place the Stripe secret key in Vite/frontend code.

## Webhook events to handle

For subscriptions:

- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_succeeded`
- `invoice.payment_failed`

For SuperSwoops and $1 support pushes:

- `checkout.session.completed`
- `payment_intent.succeeded`
- `payment_intent.payment_failed`

## Suggested Supabase tables/fields

### Add to `profiles`

```sql
alter table public.profiles
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists subscription_status text,
  add column if not exists subscription_amount numeric default 0,
  add column if not exists subscription_current_period_end timestamptz;
```

### New `superswoops` table

```sql
create table if not exists public.superswoops (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  partner_id uuid not null,
  amount numeric not null default 2.00,
  currency text not null default 'usd',
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
```

Recommended statuses:

- `pending`
- `checkout_started`
- `paid`
- `failed`
- `refunded`

### New `support_pushes` table

```sql
create table if not exists public.support_pushes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  amount numeric not null default 1.00,
  currency text not null default 'usd',
  source text not null default 'pre_splash',
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
```

## MVP implementation decision

Because HEHA Swipe is a frontend Vite app, the cleanest safe architecture is:

- Frontend: calls Supabase Edge Function or opens a Stripe Payment Link.
- Backend/Supabase Edge Function: creates Checkout Sessions and verifies Stripe webhooks.
- Supabase database: stores the final paid subscription/SuperSwoop/support-push state.

For the fastest test launch, payment links are acceptable, but final production should move to a backend Checkout Session so every SuperSwoop and support push can be tied to the correct `user_id`, `partner_id`, and/or funding source without manual reconciliation.
