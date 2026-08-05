# launch-rc-20260805 — HEHA Swipe release-candidate QA evidence

**Build under test:** `claude/heha-launch-readiness-uf0atq` = main `82ec41a` (incl. #108) + PR #112 head `eb99c7ed` (carries stack #105→#112; ancestry verified pairwise with `git merge-base --is-ancestor`). Zero merge conflicts; the entry-gate layer slots ahead of the existing `!session → AuthScreen` gate in `App.jsx` with the splash → support-status → auth sequence intact (verified by build + browser).
**Runtime:** Node 20.20.2 / npm 11.4.2. Gates: `npm ci` ✓, `build` ✓, `node --test src/lib/entryGate.test.js` ✓ **12/12**. (This repo has **no** test/lint/typecheck scripts — reported honestly, not invented.)
**QA method:** Playwright Chromium against the **production-preview build** (`vite build` + `vite preview`, port 4174), `.env.example` placeholder keys — no live backend, no production reads/writes. Every capture waits out the mandatory 3.4s splash. Harness: `capture-harness.mjs`; raw `results-raw.json`; screenshots in `shots/`.

## Triaged results (Swipe: 22 captures)

| Capture(s) | Verdict | Notes |
|---|---|---|
| `S-gate-{320..1440}` (6) | **PASS** | `/?entry=landing` entry gate renders at all six breakpoints; clean at 320px |
| `S-gate-zoom` (720×450) | **PASS** | No horizontal scroll at 200%-zoom equivalent |
| `S-auth-{320..1440}` (6) | **PASS** (raw FAIL corrected) | Direct `/` shows the early-access Customer/Business role chooser — correct first screen; harness regex simply expected sign-in copy. Layout intact at all breakpoints |
| `S-auth-create-390` | **PASS** | Gate → "Create an account" → create mode renders. **No stray G/A/f letters — provider labels plain, marks `aria-hidden` + CSS-hidden** (also verified statically: `AuthScreen.jsx:289-297`, `heha-premium-clean.css:179`) |
| `S-guest-browse-390` | **PASS** | Gate → "Continue as guest" → guest shell: guest banner with Log in/Create, Discover tab, category chips, bottom nav |
| `S-discover-390` | **PASS (shell) / data-blocked (cards)** | Graceful empty state ("You caught up with the current map"); live card stack unverifiable without data |
| `S-saved-390`, `S-community-390` | **PASS** | Guest-safe tabs render |
| `S-wizard-basics-390`, `S-wizard-review-390` | **BLOCKED** ⚠ | Partner wizard requires an authenticated session — auth wall captured, wizard (incl. #108 day-picker) NOT validated in-browser |
| `S-support-success-390` | **PASS** | Public checkout-status page |
| `S-embed-partners-1440` | **PASS** | Public embed |

## Launch blockers from this run

- **P1 — Partner onboarding wizard untestable** (auth wall; no safe test account). #108's day-picker/time-selection UI and the `delivery_days` write are NOT browser-validated.
- **P1 — `partners.delivery_days` column has no migration** in `supabase/migrations/` yet #108's client writes it on wizard submit. Verify the live schema has the column before launch, else partner submissions may fail.
- **P1 — Live discovery card stack unvalidated** (no data). Guest shell/empty state verified only.
- **P3 — "Refreshing businesses…" hangs silently** when the backend is unreachable; consider an error state.

**Not launch-ready until Geronimo approves. Nothing merged, deployed, or published by this QA run.**
