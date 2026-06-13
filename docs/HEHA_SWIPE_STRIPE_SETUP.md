# HEHA Swipe Stripe setup

This document defines the Stripe setup for HEHA Swipe custom supporter subscriptions, paid SuperSwoops, and optional prototype/team support.

## What is now built in this branch

- The monthly supporter slider in `src/components/OnboardingScreen.jsx` now calls a backend Supabase Edge Function instead of a fixed Stripe Payment Link.
- `supabase/functions/create-supporter-checkout/index.ts` creates a real monthly Stripe subscription Checkout Session for the selected whole-dollar amount from `$1` to `$100`.
- `supabase/functions/stripe-webhook/index.ts` verifies Stripe webhook signatures and updates `profiles` after subscription lifecycle events.
- `supabase/migrations/202606130001_stripe_supporter_slider.sql` adds Stripe subscription fields plus tables for SuperSwoops and support pushes.

## Payment products

### 1. HEHA Swipe Supporter Membership

Purpose: optional monthly supporter subscription for HEHA Swipe users and partners.

Current custom-slider setup:

- No fixed Stripe product/price is required for the supporter slider.
- The Edge Function creates an inline Stripe monthly price using the selected slider amount.
- The supported amount range is `$1/month` to `$100/month`, whole dollars only.
- Metadata is attached to the Checkout Session and subscription:
  - `payment_type=supporter_subscription`
  - `user_id`
  - `role`
  - `support_amount`

Behavior goal:

1. User chooses Customer or Partner.
2. User selects Supporter.
3. User moves the slider to the chosen monthly amount.
4. App calls `create-supporter-checkout`.
5. Stripe opens a subscription Checkout Session for the exact selected amount.
6. Stripe webhook updates the user's `profiles` row after payment/subscription confirmation.

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

## Required frontend Vercel env variables

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_STRIPE_SUPERSWOOP_CHECKOUT_URL=
VITE_STRIPE_DOLLAR_SUPPORT_CHECKOUT_URL=
```

Supporter subscriptions do **not** use `VITE_STRIPE_SUPPORTER_CHECKOUT_URL` anymore. The supporter slider goes through the Supabase Edge Function.

Never place the Stripe secret key in Vite/frontend code.

## Required Supabase Edge Function secrets

Set these in Supabase before testing the custom slider:

```bash
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
HEHA_SWIPE_URL=https://hehaswipe.app
```

## Deploy commands

From a local machine with the Supabase CLI connected to the correct project:

```bash
supabase db push
supabase functions deploy create-supporter-checkout
supabase functions deploy stripe-webhook
```

Then set the Stripe webhook endpoint to the deployed `stripe-webhook` function URL.

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

## Database fields/tables

The migration file `supabase/migrations/202606130001_stripe_supporter_slider.sql` adds:

### `profiles` additions

```sql
stripe_customer_id text
stripe_subscription_id text
subscription_status text
subscription_amount numeric default 0
subscription_current_period_end timestamptz
```

### `superswoops`

Stores future paid $2 SuperSwoop records.

### `support_pushes`

Stores future $1 prototype support push records.

## Testing checklist

1. Deploy database migration.
2. Deploy both Edge Functions.
3. Set all Supabase secrets.
4. Add Stripe webhook endpoint and event list.
5. Open HEHA Swipe as a test user.
6. Choose Supporter.
7. Pick `$1/month` and complete test checkout.
8. Confirm `profiles.subscription_status = active` and `subscription_amount = 1`.
9. Repeat with `$10/month`.
10. Cancel/update subscription in Stripe test mode and confirm webhook updates Supabase.

## MVP implementation decision

The custom monthly slider is now the preferred supporter-subscription flow. SuperSwoop and the $1 support push still use simple Stripe Payment Links for speed, but both should eventually move to backend Checkout Sessions so every payment can be tied cleanly to a user, partner, and funding source without manual reconciliation.
