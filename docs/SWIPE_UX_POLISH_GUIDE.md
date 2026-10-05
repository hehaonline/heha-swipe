# HEHA Swipe — UX Polish Guide

**Purpose:** Keep HEHA Swipe simple, friendly, local, and easy to use.

HEHA Swipe is not Order Hub. It should not feel like an operations dashboard.

---

## 1. Main User Question

Every Swipe screen should answer:

```text
Do I want to save, visit, learn more, or skip this business?
```

---

## 2. Main Screen Focus

The main discovery card should show:

- business name
- category
- neighborhood or area
- short reason it fits HEHA
- main photo or logo
- simple action buttons

Avoid long descriptions on the main card.

---

## 3. Best Primary Actions

Use simple actions:

- Save
- Skip
- Learn More
- View Offer
- Share

Later:

- SuperSwoop
- Visit
- Order

Do not add too many buttons at once.

---

## 4. Friendly Empty States

Examples:

```text
No more local picks right now. Check back soon for more HEHA finds.
```

```text
You have not saved any businesses yet. Swipe to build your local list.
```

---

## 5. Trust Language

Use careful wording:

- local pick
- pending review
- HEHA partner
- community favorite
- clean-food focused

Do not call a business HEHA-approved unless Geronimo/Nova has approved that status.

---

## 6. Do Not Connect Too Early

Do not trigger Order Hub operations from Swipe yet.

No live:

- dispatch
- driver assignment
- payment release
- delivery workflow

Safe early outputs:

- saved business
- partner lead
- feedback
- newsletter signup
- interest signal

---

## 7. Smooth UX Rule

Swipe should feel quick and light.

```text
One card. One clear reason. One easy action.
```

---

## 8. October 5, 2026 — user-endorsed visual direction

Geronimo explicitly selected the orange, photo-led Swipe phone/card concept in the email-review conversation as the direction for the app. Reference screenshot SHA-256: `855c3bc9c8e756c82187ba0874c87716945fdf249df06cee209077e2f9020aa2` (user upload, October 5, 11:28:05 AM). This is a visual standard for the next controlled implementation, not evidence that the app has changed.

### Adopt from the reference

- Orange-led header, cream/white breathing room, one large relevant business photograph, rounded cards and short readable copy.
- Clear, touch-friendly Save/Skip actions and a simple route to details. Preserve existing action semantics; a heart must not silently send an inquiry, place an order or trigger a paid action.
- A recognizable HEHA identity across the website, Local, Swipe and emails. No dashboard-like density.
- Reuse the existing `src/heha-brand-theme.css` token system: `#ff8a24` orange, `#fff1df` orange-soft, `#fffaf2` cream, `#ffffff` white, `#191715` ink. Green remains a restrained existing accent/status color, not a new primary identity. Use dark text or approved darker orange where needed for contrast.

### Logo and source truth

Use the actual approved HEHA logo asset, not a generated leaf wordmark. Check `public/heha-logo.svg` against the canonical approved asset; the current public landing page uses `https://heha.online/assets/heha-logo-orange.svg`. Preserve the original mark without tracing or redesigning it. On orange, use an existing approved reverse variant or a cream/white logo panel.

The user likes the generated wordmark's readability, but has not approved retiring the existing logo. Any simplified replacement is a separate optional brand-evolution proposal. Do not adopt the invented “Healthy Eats. Happier Adventures.” expansion or the `.co` contact/domain used in prior concepts. Use `heha.online` / `hello@heha.online`.

HEHA Local stays predominantly white/cream and orange. A modest sage accent can be previewed; a wholesale green rebrand is not approved. All named business/food photographs must be relevant and licensed. Keep suggested/listed/accepted partner status distinct.

### Release and review boundaries

Implement only within the existing app project and owner/review workflow. This decision does not change Test6 approved/paused state, source-version controls, authentication/data/consent/routing behavior, provider settings, pricing or any release gate. No deployment, merge, migration, messages or public listing updates are authorized by this documentation change.

Marketing previews remain marked “Preview” or “In development” where appropriate. No unsupported App Store/Google Play availability, firm launch date, fabricated reviews, invented benefits or unverified features.

Check original-logo fidelity, visual consistency, keyboard/touch labels, reduced motion, contrast and horizontal overflow at 320/375/768/1440 px before release. Native-store readiness remains distinct from web-preview readiness.
