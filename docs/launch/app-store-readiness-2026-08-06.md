# HEHA downloadable-app readiness audit — 2026-08-06

> Review-only launch evidence. This document does not authorize a wrapper implementation, signing, store account changes, submission, deployment, legal publication, or production configuration change.

## Audited state

| Surface | Exact audited head | Current form |
|---|---|---|
| HEHA Local RC | `hehaonline/heha-order-hub@4b69774ef86a8133c7d623b010ca92ce3876ce7a` (PR #217) | React/Vite web app with a Web App Manifest and 192/512 icons |
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

### Web install foundation

- Both RCs provide a manifest with `name`, `short_name`, `start_url`, standalone display, and 192/512 PNG icons.
- Both RCs reference their manifests and Apple touch icons from `index.html`.
- The Swipe RC corrected the old zoom-blocking viewport and now uses `width=device-width, initial-scale=1.0`.
- Live HTTPS installability, icon safe zones, installed launch behavior, cache/update behavior, and device-specific home-screen results were **not run** in this connector-only audit.
- No service worker was found. Do not promise offline support or resilient cached operation.
- Both manifests use the same short name, `HEHA`, so installing both can be confusing.
- Local presents itself as “HEHA Order Hub” and describes real-time orders, drivers, and payouts, while the public product is HEHA Local. Approve truthful public naming before promoting installation.
- Each icon is declared as both `any maskable` using one asset. Maskable safe-zone appearance still needs visual validation.

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

Browser install reference:
- https://web.dev/articles/install-criteria

## Smallest approval package

Before wrapper code starts, approve these exact decisions:

1. Public store products: separate **HEHA Local** and **HEHA Swipe** apps.
2. Initial channel: web soft launch first; TestFlight and Play internal testing second.
3. Default wrapper: Capacitor for both products.
4. Bundle/application identifier namespace and Apple/Google account owner.
5. Final public names, manifest short names, support URL, and legally approved privacy-policy URL.
6. Whether partner/driver/SOM/admin functions ship inside HEHA Local's first binary or remain web-only until customer ordering is stable.

Recommended defaults:

- `com.hehaonline.local` and `com.hehaonline.swipe` as proposals only; verify ownership and availability before use.
- “HEHA Local” and “HEHA Swipe” as distinct installed names.
- Customer/discovery scope first; keep operational roles web-only until authenticated role-boundary QA passes.
- No payments, migrations, notifications, background location, or health claims added as part of packaging.

## Prepared implementation and validation order

1. Clear the existing Local and Swipe RC blockers; do not package an unverified RC.
2. Approve final privacy/legal URLs and store data inventories.
3. Create a separate wrapper branch per repository from a newly verified release base.
4. Add native projects without changing web business logic.
5. Add signing-safe configuration templates; keep keys and provisioning material out of Git.
6. Validate web manifests/icons, then generate full native icon/splash sets.
7. Test exact signed internal builds on supported phones and tablets:
   - cold start, update, offline/error recovery;
   - signup/sign-in/sign-out/account deletion;
   - guest/auth and role boundaries;
   - deep links and OAuth return;
   - catalog/discovery, cart/request, partner, driver/SOM/admin gates;
   - keyboard, screen reader, dynamic text/zoom, safe areas, rotation;
   - privacy permissions and denied-permission recovery.
8. Produce store metadata, privacy/data-safety answers, review notes, support path, release notes, and rollback receipt.
9. Submit only to TestFlight/Play internal testing after an exact approval. Public submission remains a separate approval.

## Rollback

This audit changes documentation only. Reverting its single commit removes the document. No application code, dependency, manifest, deployment, native project, signing material, store record, Supabase state, or external service is changed.
