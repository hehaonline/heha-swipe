# Clean Paws, Clean Planet 🐾🌿

**A local eco-conscious pet-care referral & booking concept — powered by HEHA Local / Healthy Habit LLC.**

Clean Paws, Clean Planet is a **pitch prototype** for a Tampa Bay pet-care
referral network connecting pet owners with trusted local grooming salons,
mobile groomers, dog walkers, pet sitters, and eco-conscious pet-care vendors.

It is built as a **standalone app** so it can be shown to potential partners
(grooming salons, mobile groomers, eco pet-care providers, and referral
partners) on its own — and easily paired with the wider HEHA Local ecosystem
later if the concept is approved.

> 🧪 **This is a concept prototype, not a production marketplace.** There are
> no live bookings, payments, partner payouts, real scheduling, or verified eco
> claims. Forms show a friendly success state and update local component state
> only. Partner profiles are demo data — no partnership has been agreed.

---

## What it is

- **Mobile-first, pitch-ready** marketing + concept site.
- Warm HEHA-inspired palette (cream / peach / orange) with soft green eco
  accents, rounded cards, and friendly icons.
- Built so partners can see what the concept could become and so HEHA Local can
  collect interest and referral leads.
- Honest, legally-safe copy: "potential partner", "pilot candidate", "demo
  profile", "self-reported", and "eco-conscious options" — no false
  partnership or eco claims.

## Tech stack

- **Next.js 14** (App Router) + **TypeScript**
- **Tailwind CSS** for styling
- Mock data in `src/lib/mockData.ts` (no external APIs, no database)
- Deployable on **Vercel** with zero configuration

## Local setup

```bash
cd clean-paws-clean-planet
npm install
npm run dev      # http://localhost:3000
```

Build / production check:

```bash
npm run build
npm run start
```

No environment variables are required — the prototype runs fully on mock data.

## Routes / pages

| Route               | Page                                                           |
| ------------------- | -------------------------------------------------------------- |
| `/`                 | Home / landing — pitches the concept to owners & partners      |
| `/request`          | Request Pet Care — multi-section demo form with success state  |
| `/partner`          | Become a Partner — onboarding + interest form with success     |
| `/partners`         | Demo Partners directory — card grid from mock data             |
| `/partners/[slug]`  | Partner detail demo page (dynamic, statically generated)       |
| `/pitch`            | Partner pitch page for salons & mobile groomers                |
| `/admin-demo`       | Demo request-triage dashboard (kanban + table, local state)    |
| `/roadmap`          | Product build roadmap + "not included yet" scope               |

## Key components (`src/components/`)

`Navbar`, `Footer`, `Logo`, `HeroSection`, `CTAButton`, `Section`,
`ServiceCard`, `PartnerCard`, `StatusBadge`, `RoadmapTimeline`,
`DemoFormSuccess`, `MockDashboard` (kanban/table), `EcoDisclaimer`,
`PartnerBenefitCard`.

All mock data lives in **`src/lib/mockData.ts`**: `partners`, `services`,
`bookingRequests`, `roadmapPhases`, `partnerBenefits`, `customerBenefits`,
`testimonials`, and form option lists.

## Deploying to Vercel

This app lives in the `clean-paws-clean-planet/` subfolder of the repo.

1. Import the repo into Vercel.
2. Set **Root Directory** to `clean-paws-clean-planet`.
3. Framework preset: **Next.js** (auto-detected). Build command `next build`,
   no env vars needed.
4. Deploy.

## Demo limitations (by design)

- ❌ No live booking calendar or real scheduling
- ❌ No real partner payouts, Stripe, or Stripe Connect
- ❌ No automated dispatch or route batching
- ❌ No vet / medical services
- ❌ No legal certification or verified eco badge
- ❌ No authentication on the admin demo (mock data only)
- Forms do **not** send, store, or share anything — success screens only.

## Future build notes

The intended phases (also shown on `/roadmap` and `/pitch`):

1. **Phase 1** — Partner interest + landing page (this prototype)
2. **Phase 2** — Manual referrals + intake forms
3. **Phase 3** — Partner dashboard + booking statuses
4. **Phase 4** — Recurring care plans + Stripe deposits
5. **Phase 5** — HEHA Swipe discovery + local pet marketplace

When approved, this app is structured to pair cleanly with HEHA Local: shared
brand language, a partner/request data model that maps to a future backend, and
a roadmap that connects into HEHA Swipe discovery.

---

© Healthy Habit LLC · HEHA Local. Concept prototype for partnership validation.
