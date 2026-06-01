# HEHA Swipe Roadmap

## Stage 1 — Stabilize MVP

Status: first priority.

- Restore clean `src/App.jsx` app shell.
- Wire save, pass, and SuperSwoop events.
- Use existing Supabase tables without schema changes.
- Add clean fallback states for empty partners and loading errors.
- Add `.env.example` and README.

## Stage 2 — Customer discovery

- Partner cards should feel curated and trustworthy.
- Add categories for Food, Market, Wellness, Coaches, Services, and Events.
- Saved tab becomes the customer's personal HEHA map.
- Sharing should invite people into the local healthy economy, not just link spam.

## Stage 3 — Partner attraction

- Make the profile tab a clear listing funnel.
- Business onboarding should explain the value:
  - visibility
  - community trust
  - local health audience
  - future Deal of the Day / SuperSwoop promotion
- Submitted businesses remain `pending` until HEHA approval.

## Stage 4 — Marketing automation

Use Make.com to notify HEHA when:

- a new user joins
- a business submits a listing
- a partner gets a SuperSwoop
- a partner receives a high number of saves

Potential outbound flows:

- Telegram or email alert to Geronimo
- partner approval task creation
- CRM lead update
- weekly partner-performance digest

## Stage 5 — Future app features

- Public partner profile URLs: `/p/:slug`
- Deal of the Day
- Freebird Fund donation tracking connected to SuperSwoop
- Choose-your-own monthly membership
- Partner dashboard
- Admin approval dashboard
- Location-aware neighborhood discovery
