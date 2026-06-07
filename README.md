# HEHA Swipe

HEHA Swipe is the discovery and marketing layer for Healthy Habit LLC / HEHA. It helps Tampa Bay customers discover healthy local restaurants, wellness partners, markets, coaches, service providers, and community offers.

## Product purpose

HEHA Swipe is not just a swipe UI. It is a lightweight local marketing engine:

- Customers discover and save healthy businesses.
- Businesses can submit themselves for HEHA review.
- SuperSwoop / Super Swipe events show strong customer interest.
- HEHA can use saves, swipes, and partner submissions for outreach, partner visibility, and future automated marketing.

## Relationship to HEHA Order Hub

HEHA Swipe is the discovery layer.

HEHA Order Hub is the operations layer.

They should connect over time, but they should not be merged too early.

```text
HEHA Swipe
  ↓
Partner discovery, saves, submissions, SuperSwoop interest
  ↓
HEHA Order Hub / Wix / Customer App
  ↓
Ordering, fulfillment, restaurant confirmations, drivers, SOM, admin
```

See the integration planning document:

- [`docs/HEHA_SWIPE_ORDER_HUB_INTEGRATION.md`](docs/HEHA_SWIPE_ORDER_HUB_INTEGRATION.md)

## Current stack

- React + Vite
- Supabase Auth
- Supabase public tables: `profiles`, `partners`, `saves`, `swipe_events`, `customer_profiles`, and future order/contribution tables
- Optional Make.com webhooks for new user and partner approval notifications

## Required env variables

Copy `.env.example` into `.env.local` and fill:

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

Optional:

```bash
VITE_MAKE_NEW_USER_WEBHOOK=
VITE_MAKE_PARTNER_APPROVAL_WEBHOOK=
```

## Local development

```bash
npm install
npm run dev
```

## Build check

```bash
npm run build
```

## HEHA design direction

The design should feel modern, clean, earthy, vibrant, warm, and aligned with the HEHA/Wix brand direction:

- Warm orange / peach
- Clean white and off-white surfaces
- Earthy green accents
- Soft sand backgrounds
- Rounded cards and mobile-first interaction
- Trust-building language instead of aggressive ads

## Feature boundaries

Build HEHA Swipe as a lightweight discovery engine first.

Do not add these too early:

- full checkout
- restaurant order management
- driver dispatch
- payouts
- complex admin finance
- live delivery tracking
- full Community Pass payment logic
- native app packaging before the web flow is stable

Those functions belong to HEHA Order Hub or later customer app phases.

## Important implementation notes

- Do not expose Supabase service-role keys in the frontend.
- Do not add payments until the discovery and partner flows are stable.
- Keep Supabase schema changes in separate migrations.
- SuperSwoop currently records a `swipe_events.direction = "super"` event.
- Partner listings submit with `status = "pending"`; admin approval should happen outside the public UI for now.
