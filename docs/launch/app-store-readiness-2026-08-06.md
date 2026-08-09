# HEHA downloadable-app readiness audit — 2026-08-06

> Review-only launch evidence. This document does not authorize a wrapper implementation, signing, store account changes, submission, deployment, legal publication, or production configuration change.

## Audited state

| Surface | Exact audited head | Current form |
|---|---|---|
| HEHA Local RC | `hehaonline/heha-order-hub@7c47f1188b344c5365d8eec548ba9b267be0a602` (PR #226; code head `eebc96c651acb8104b4f8c69223c73dac8eafb8e`) | Current combined React/Vite web candidate; draft and not launch-ready |
| Local RC parent | `hehaonline/heha-order-hub@4b69774ef86a8133c7d623b010ca92ce3876ce7a` (PR #217) | Ancestor of #226; preserved for source evidence, not the current candidate |
| HEHA Swipe RC | `hehaonline/heha-swipe@885461f55f64ea56a9366e6573b6002769820f06` (PR #113) | React/Vite web app with a Web App Manifest and 192/512 icons |
| Swipe refresh sibling | `hehaonline/heha-swipe@e58de647de1f60e6546b972de11f75bf5da76552` (PR #114) | Separate draft; not part of the audited RC |

GitHub inspection found no Capacitor configuration, Xcode project, Android/Gradle app project, Expo configuration, Apple privacy manifest, Android Digital Asset Links file, native bundle/package identifier, or store-build script in either audited RC. Searches also found no service-worker registration. The existing manifests and icons are useful web-install foundations, but they are not App Store or Play Store packages.

## Decision-ready conclusion

**Recommended launch sequence:** soft-launch the verified web apps first, support home-screen installation after live HTTPS install testing, and begin native-store packaging only after the critical web journeys are stable. Use one approved Capacitor-based wrapper per product as the default store path unless native requirements discovered during design make that unsuitable.

This avoids freezing unfinished auth, ordering, legal, and discovery behavior inside signed store binaries while preserving a direct path to TestFlight and Google Play internal testing.

Alternatives:

1. **Web/PWA only for now — recommended for soft launch.** Fastest and reversible; no store review. It does not provide store discovery or native distribution.
2. **Capacitor wrappers after web launch — recommended store path.** Reuses the React/Vite apps on iOS and Android, but adds native projects, signing, deep-link, permission, privacy, device, and review work.
3. **Android Trusted Web Activity plus a separate iOS wrapper.** Potentially lighter Android packaging, but creates two release architectures. Android ownership verification also needs a signed package and `.well-known/assetlinks.json`.

## Confirmed readiness and gaps

### Current Local RC reconciliation — revalidated 2026-08-09

PR #226 is the current Local candidate at exact head `7c47f1188b344c5365d8eec548ba9b267be0a602`. It is nine commits ahead of the previously audited #217 head and integrates #222, #224, and #225 plus focused tests and evidence. It remains draft and not launch-ready.

The current candidate adds useful fail-closed Market/cart behavior, but exact-head review confirms three unresolved web-launch blockers that also block native packaging:

- **Group Orders contaminates the shared persisted cart.** The preview writes mock `pk-*` items without canonical catalog identity; the whole-cart safety guard then blocks those items and any later valid items until the customer manually removes the preview lines. The preview needs isolated local state and must not mutate the production cart.
- **Chef/Catering is publicly deceptive and discards sensitive requests.** Public chef pages render mock chefs as approved/bookable with fabricated ratings, prices, badges, and quote actions. Chef Match collects location and health-adjacent details, then shows a mock success toast without persisting a request. These routes must fail closed until real approved inventory, consent/retention handling, and a receipt/recovery path exist.
- **The exact-head evidence packet is incomplete.** Its SHA-256 manifest names `VERIFICATION-20260809.md`, but that file is absent. The committed browser evidence is synthetic and unauthenticated; authenticated order creation and recovery were not exercised.

Do not package or submit #226. Repair these boundaries in isolated current-main drafts, rebuild a successor RC, and re-audit the exact corrected head before any wrapper work.

Evidence:

- https://github.com/hehaonline/heha-order-hub/pull/226#issuecomment-5230646994
- https://github.com/hehaonline/heha-order-hub/pull/226#issuecomment-5230875595
- https://github.com/hehaonline/heha-order-hub/pull/226#issuecomment-5232872836

### Web install foundation

- Both RCs provide a manifest with `name`, `short_name`, `start_url`, standalone display, and 192/512 PNG icons.
- Both RCs reference their manifests and Apple touch icons from `index.html`.
- The Swipe RC corrected the old zoom-blocking viewport and now uses `width=device-width, initial-scale=1.0`.
- Live HTTPS installability, icon safe zones, installed launch behavior, cache/update behavior, and device-specific home-screen results were **not run** in this connector-only audit.
- Swipe includes `public/sw.js`, but the RC does not register it; Local has no worker or registration. Do not promise offline support or resilient cached operation.
- Both manifests use the same short name, `HEHA`, so installing both can be confusing.
- Local presents itself as “HEHA Order Hub” and describes real-time orders, drivers, and payouts, while the public product is HEHA Local. Approve truthful public naming before promoting installation.
- Each icon is declared as both `any maskable` using one asset. Maskable safe-zone appearance still needs visual validation.

### Anonymous public-partner projection privacy blocker — revalidated 2026-08-09

Swipe RC #113 carries #112's guest-browsing path. At exact RC head `885461f55f64ea56a9366e6573b6002769820f06`:

- `loadPublicPartners()` performs an unauthenticated `public_swipe_partners.select("*")`;
- the committed `security_invoker` view grants `SELECT` to `anon` and `authenticated`;
- the view projects far more than a discovery card, including `owner_id`, `contact`, `phone`, swipe/save/profile-view totals, pricing/service-fee fields, routing notes, routing staff IDs, and routing timestamps.

Row-level security and `security_invoker=true` can constrain which rows an invoker may read; they do not remove columns explicitly projected by the view. Hiding those fields in React also does not keep them out of the Data API response. The repository's migration-lineage evidence does not establish a verified live baseline for the prerequisite view/grants/RLS chain.

This is a web soft-launch privacy and reconnaissance blocker and therefore also blocks native packaging. Public contact details need an explicit publication/consent contract; owner/staff identifiers, internal routing/audit data, analytics, and commercial configuration should not be exposed by a public discovery projection.

Required fail-closed repair:

1. Define an explicit public-card projection containing only reviewed display fields; exclude owner/staff identifiers, routing/audit data, analytics, and commercial/admin configuration.
2. Omit contact/phone unless an approved public-contact consent rule explicitly permits them.
3. Replace the guest client's wildcard query with the same display-field allowlist as defense in depth.
4. Preserve explicit grants, `security_invoker=true`, and a public-row policy limited to approved/live, Swipe-eligible, non-test records.
5. Prove on an approved disposable Supabase target that anonymous and authenticated public reads cannot retrieve excluded columns or hidden rows, partner/admin private workflows remain intact, and the canonical migration chain replays cleanly.

Do not patch or apply a migration from this documentation branch. The data/authorization domain overlaps the deployment-frozen claim work in #117 and the stale predecessor #82; rebuild the eventual repair from the approved canonical database baseline and review it separately.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/112#issuecomment-5228082440
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/App.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/supabase/migrations/20260720093100_partner_multi_categories_view_security_invoker.sql

### Client-side account webhook privacy and integrity gate — revalidated 2026-08-09

Swipe RC #113 at exact head `885461f55f64ea56a9366e6573b6002769820f06` invokes `pingNewUserWebhook(session.user)` whenever an authenticated user ID becomes active. That includes an ordinary restored session on app load; the call is not tied to evidence that the account was newly created.

When `VITE_MAKE_NEW_USER_WEBHOOK` is configured, browser code posts `user_id`, email, phone, account creation time, and a product source value directly to the endpoint. Because Vite exposes `VITE_` values to the built client, this endpoint URL must be treated as public: it cannot serve as a secret or by itself authenticate that a request came from HEHA. The current call has no event ID or idempotency key, no signed server assertion, no response validation, and no durable delivery receipt; failures are silently ignored. The repository does not establish whether the variable is configured in preview or production, so live activation and delivery remain **unknown**, not passed.

This creates two launch risks if configured:

- account identifiers can be sent to a third-party automation on routine session restoration rather than a defined, consented new-account lifecycle event;
- a browser-visible webhook can be replayed, spoofed, or spammed, while repeated mounts/session activity can produce duplicate notifications without an idempotency contract.

Issue #86 separately tracks rotation and server-side protection for Make credentials embedded in database functions. It does not close this client-exposed path. Coordinate remediation so no replacement bearer endpoint is returned to frontend code.

Required fail-closed plan:

1. **Recommended soft-launch default:** verify the deployment variable by name only and leave `VITE_MAKE_NEW_USER_WEBHOOK` unset until an approved server-owned event path exists. Do not expose or paste its value into evidence.
2. Define the exact business event, minimum necessary fields, consent/privacy-inventory treatment, retention, and processor ownership. An app session or sign-in is not a “new user” event.
3. Emit the event from a trusted server/database boundary only after the intended account lifecycle transition, using an authenticated server-held destination, an immutable event ID, idempotent delivery, bounded retries, and a durable success/failure receipt.
4. Do not place replacement webhook credentials in `VITE_` variables, browser bundles, client logs, or public error responses.
5. Prove unconfigured fail-closed behavior, first account creation, ordinary sign-in, session restore, remount/Strict Mode, token refresh, replay, forged payload, rate limit, timeout, third-party failure/retry, and deletion/retention handling in a disposable environment.
6. Inventory the similarly named partner-approval webhook separately before changing shared Make scenarios or credentials; do not broaden this documentation draft into an integration repair.

No Vercel variable, Make scenario, Supabase function, credential, or production environment is changed or authorized by this audit.

Evidence:

- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/App.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/.env.example
- https://github.com/hehaonline/heha-swipe/issues/86

### Apple App Store blockers

- No iOS/Xcode or wrapper project.
- No approved bundle identifiers, version/build scheme, signing team, certificates, or provisioning.
- No App Store Connect records, store names/subtitles, screenshots, review notes, support URL, or approved privacy-policy URL evidenced in the repositories.
- No reviewed App Privacy answers covering account/profile data, location use, swipe/save activity, partner content, order/contact data, Supabase, Nominatim, HubSpot/Make, Stripe-related flows, and any wrapper SDKs.
- No device validation for OAuth redirects, universal links, camera/photo permissions, account deletion, safe areas, keyboard behavior, or interrupted-network recovery.
- No TestFlight build or rollback baseline.

Apple's current documentation says the App Store record's bundle ID must match the Xcode project, a privacy-policy URL is required, and app/third-party data practices must be disclosed:
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/help/app-store-connect/reference/app-privacy/
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile

### Google Play blockers

- No Android/Gradle or Trusted Web Activity project.
- No approved application IDs, version codes, signed Android App Bundle, upload key custody plan, or Play App Signing decision.
- No `.well-known/assetlinks.json` or certificate fingerprint for verified web-to-app ownership.
- No Play Console records, listing graphics/screenshots, support/privacy URLs, Data safety answers, content rating, tester track, or release notes evidenced in the repositories.
- No Android device/tablet, back-button, deep-link, auth, permission, offline, or update testing.

Google's current documentation requires release signing and uses Android App Bundles for new Play apps. A Trusted Web Activity also needs Digital Asset Links to prove site ownership:
- https://developer.android.com/studio/publish/
- https://developer.android.com/studio/publish/app-signing.html
- https://developer.chrome.com/docs/android/trusted-web-activity/quick-start
- https://developer.chrome.com/docs/android/trusted-web-activity/android-for-web-devs

### Store billing and external-checkout blocker — revalidated 2026-08-09

Swipe's audited RC sells a recurring Stripe supporter subscription from inside `CommunityPassTab.jsx`:

- the in-app buttons open `create-supporter-checkout`, which creates a Stripe `subscription` Checkout Session;
- the $1–$100 monthly payment unlocks an active supporter entitlement inside the app;
- the advertised digital benefits include early feature access, supporter-only deal drops, voting on future HEHA partners, first looks, community updates, and event invites.

This is not a payment for food, transportation, or another physical service. It is also not safe to treat as a no-benefit donation: the payment produces a digital entitlement and advertised in-app benefits, and no approved tax-exempt-donation eligibility is evidenced.

Apple's App Review Guideline 3.1.1 requires In-App Purchase when payment unlocks app features, subscriptions, or premium digital content. Apple's external-link rules vary by storefront and entitlement; United States treatment does not establish eligibility everywhere. Google Play's Payments policy likewise requires Play Billing for in-app functionality, digital content, and subscriptions unless an applicable exception or enrolled regional program applies, and otherwise prohibits buttons or flows that lead to another payment method.

Current primary references:

- https://developer.apple.com/app-store/review/guidelines/#in-app-purchase
- https://support.google.com/googleplay/android-developer/answer/9858738
- https://developer.android.com/google/play/billing/subscriptions.html

This is a store-packaging blocker independent of the existing session-verification defect. Fixing the Stripe return page would make the web checkout more trustworthy; it would not by itself make that checkout an approved store payment path.

Recommended default for the first TestFlight and Play internal builds:

1. Keep Stripe supporter purchase and digital entitlement surfaces web-only.
2. Omit or fail closed the supporter purchase CTA and paid-benefit unlocks in store builds; do not merely open the Stripe page in an in-app browser or external browser.
3. Preserve free discovery/community functionality so the initial binaries do not depend on monetization.
4. If paid supporter benefits are required in the native apps, implement StoreKit and Play Billing, verify receipts/tokens server-side, reconcile native and Stripe entitlements without double subscriptions, support restore/cancel/refund/grace-period states, and submit the products for review.
5. Treat storefront-specific external-link or alternative-billing programs as a separate approval and compliance project. Verify eligibility, enrollment, disclosures, fees, reporting, and geography before relying on one.

Required validation includes store-build feature-flag denial, direct/deep-link denial, existing-web-supporter behavior, duplicate-subscription prevention, restore, refund/revocation, billing retry/grace period, account deletion with active subscriptions, and exact reviewer notes. No billing product, store record, price, payment provider, or production configuration is authorized by this audit.

### Account-deletion store blocker — revalidated 2026-08-07

Swipe's audited RC does expose **Request account deletion** in `ProfileTab.jsx`, but the current behavior is only a partial request flow:

- it inserts an `account_deletion_requests` row;
- it immediately attempts to delete `saves`, `customer_profiles`, and `profiles`;
- its confirmation explicitly says the Supabase Auth login may remain active until an administrator removes it;
- it does not sign the requester out, revoke sessions, prove Auth-user removal, provide a completion receipt, or prove deletion from every app table and downstream processor.

A table insert is therefore not evidence that deletion was fulfilled. Supabase also documents that deleting an Auth user does not itself invalidate already-issued JWT access tokens until they expire, so the final server-owned workflow must revoke sessions and account for token lifetime rather than treating row deletion as immediate logout.

No dedicated public HEHA account-deletion resource was found during the repository/public-site inspection. The current HEHA privacy page only says users may request deletion “where legally allowed” and provides general contact information; it is not an app-specific, prominent request path with scope, identity verification, timing, retention exceptions, and completion expectations.

#### Approved contact and interim ownership — 2026-08-07

Geronimo approved `support@heha.online` as the canonical email destination for HEHA Local and HEHA Swipe support, privacy, and account-deletion requests, with Geronimo as the temporary soft-launch human request owner. This closes the contact/owner decision only; it does not make the mailbox, deletion workflow, or public request page operational.

Before public use, verify mailbox provisioning, inbound delivery, Geronimo's access, copyable fallback behavior, queue/status handling, escalation, and response/fulfillment targets. Opening an email draft is not proof that a request was sent, and receiving a deletion request is not proof that an account was deleted. The stable public deletion-request URL and server-owned fulfillment contract remain open blockers.

Decision evidence:
- https://github.com/hehaonline/heha-order-hub/issues/187#issuecomment-5222122308
- https://github.com/hehaonline/heha-swipe/issues/115#issuecomment-5222123150

This blocks both store packages:

- Apple requires apps that support account creation to let users initiate deletion within the app and offer deletion of the full account plus associated non-retained data.
- Google Play requires an intuitive in-app deletion path **and** a functional public web resource where users can request deletion without reinstalling the app.

Required before internal-store release:

1. Define one service-owned deletion contract for Swipe and Local: request, recent reauthentication, pending state, session revocation, Auth-user removal, app-data deletion/anonymization, approved retention exceptions, downstream-provider requests, completion/failure receipt, and retry-safe audit evidence.
2. Keep any retained order, fraud, tax, or security evidence minimal and disclose the exact reason and retention period in approved policy text.
3. Publish a stable, prominent web request page only after legal/operational approval; link it from both apps and the Google Play Data safety form.
4. Prove ordinary-user, partner, duplicate request, stale session, cross-user, partial-failure/retry, retained-record, and completed-deletion cases in a disposable environment.
5. Verify that a deleted user cannot refresh a session or continue reading/writing with an old token after the documented expiry/revocation boundary.
6. Geronimo is the approved temporary owner; verify mailbox access and monitoring, then define the fulfillment SLA and escalation path. Do not depend on an unmonitored email address or database queue.

Current primary references:
- https://developer.apple.com/support/offering-account-deletion-in-your-app/
- https://support.google.com/googleplay/android-developer/answer/13327111
- https://supabase.com/docs/guides/auth/managing-user-data
- https://supabase.com/docs/guides/auth/sessions

Browser install reference:
- https://web.dev/articles/install-criteria

### Supporter-payment return trust blocker — revalidated 2026-08-07

Swipe RC #113 at exact head `885461f55f64ea56a9366e6573b6002769820f06` does not bind the supporter success screen to the Checkout Session that returned the user:

- `src/App.jsx` selects `/support/success` before the unauthenticated-app branch, so a signed-out direct visit can render “Thank you for supporting HEHA Swipe.”
- `supabase/functions/create-supporter-checkout/index.ts` sets the success URL to `/support/success` without Stripe's `{CHECKOUT_SESSION_ID}` template.
- `src/lib/supporterStatus.js` asks for the current user's active supporter entitlement; it does not verify the returned Checkout Session.

The thank-you screen is therefore not proof that this checkout succeeded. An existing active entitlement could also make an unrelated return appear successful. This is a HEHA payment-trust and release-evidence blocker; it is not presented here as a store-policy claim.

Required before the supporter flow is eligible for a web soft launch or store packaging:

1. Require an authenticated return or fail closed without rendering success.
2. Include `{CHECKOUT_SESSION_ID}` in the checkout success URL.
3. Retrieve the exact session server-side and verify the authenticated user or `client_reference_id`, expected price/product, subscription mode, payment/subscription state, and environment.
4. Reject a missing, mismatched, unpaid, or replayed session. Do not let an older active entitlement prove the new checkout.
5. Keep entitlement fulfillment webhook-driven; the return page should only display a server-verified status and truthful pending/failure recovery.
6. Prove signed-out direct URL, missing session, wrong user, unpaid, stale/replayed, delayed webhook, pre-existing entitlement, successful return, cancellation, timeout, and retry cases in a non-production Stripe/Supabase environment.

Evidence: https://github.com/hehaonline/heha-swipe/pull/113#issuecomment-5221820682

## Smallest approval package

Before wrapper code starts, approve these exact decisions:

1. Public store products: separate **HEHA Local** and **HEHA Swipe** apps.
2. Initial channel: web soft launch first; TestFlight and Play internal testing second.
3. Default wrapper: Capacitor for both products.
4. Store monetization: omit supporter purchases and paid entitlements from the first binaries (recommended), or fund and implement StoreKit/Play Billing before they ship.
5. Bundle/application identifier namespace and Apple/Google account owner.
6. Final public names, manifest short names, support URL, and legally approved privacy-policy URL.
7. Whether partner/driver/SOM/admin functions ship inside HEHA Local's first binary or remain web-only until customer ordering is stable.
8. Account-deletion fulfillment SLA, retention exceptions, and the approved public deletion-request URL. The interim owner and email destination are approved; delivery/access and operations are not yet verified.

Recommended defaults:

- `com.hehaonline.local` and `com.hehaonline.swipe` as proposals only; verify ownership and availability before use.
- “HEHA Local” and “HEHA Swipe” as distinct installed names.
- Customer/discovery scope first; keep operational roles web-only until authenticated role-boundary QA passes.
- No payments, migrations, notifications, background location, or health claims added as part of packaging.

## Prepared implementation and validation order

1. Clear the existing Local and Swipe RC blockers, including the anonymous public-partner projection and session-bound supporter-return verification; do not package an unverified RC.
2. Approve the store monetization plan. Default to no supporter purchase or paid-entitlement surface in the first binaries; native billing is a separate reviewed implementation.
3. Approve final privacy/legal URLs, store data inventories, and the account-deletion fulfillment contract.
4. Create a separate wrapper branch per repository from a newly verified release base.
5. Add native projects without changing web business logic.
6. Add signing-safe configuration templates; keep keys and provisioning material out of Git.
7. Validate web manifests/icons, then generate full native icon/splash sets.
8. Test exact signed internal builds on supported phones and tablets:
   - cold start, update, offline/error recovery;
   - signup/sign-in/sign-out/account deletion;
   - guest/auth and role boundaries;
   - deep links and OAuth return;
   - catalog/discovery, cart/request, partner, driver/SOM/admin gates;
   - keyboard, screen reader, dynamic text/zoom, safe areas, rotation;
   - privacy permissions and denied-permission recovery.
9. Produce store metadata, privacy/data-safety answers, review notes, support path, release notes, and rollback receipt.
10. Submit only to TestFlight/Play internal testing after an exact approval. Public submission remains a separate approval.

## Rollback

This audit changes documentation only. Reverting its documentation commits removes the document. No application code, dependency, manifest, deployment, native project, signing material, store record, Supabase state, or external service is changed.
