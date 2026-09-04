# HEHA Swipe 0.1.0 (1) release runbook

Scope: review candidate only. This runbook does not deploy, apply SQL, migrate a
database, submit to a store, or promote a production build.

## 1. Verify the repository

Set the approved public `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`, then
run from the repository root:

```sh
npm ci
npm run release:verify
```

Expected results:

- store-policy and client-contract tests pass;
- generated assets match deterministic tracked bytes;
- Vite builds with `VITE_RELEASE_CHANNEL=store`;
- Capacitor sync succeeds for Android and iOS.

Every pull request also runs **Android pull request validation** with
nonfunctional CI fixtures. That job uses no repository or environment secrets,
syncs only Android, runs `testDebugUnitTest`, and builds an unsigned debug
package with `assembleDebug`. It uploads nothing. A passing result is
repository evidence only; it is not a signed AAB, live-backend proof, an
internal-track install, or store authorization.

Every pull request also runs **iOS pull request validation** on a current
macOS 26/Xcode 26 runner. It syncs iOS and compiles the shared App scheme for a
generic iOS Simulator with code signing disabled. It uploads nothing and is
compile evidence only, not an archive, signed device build, or TestFlight run.

## 2. Database review gates

The SQL packet in `supabase/review_only/store_release` is not a migration.
Before any live change, obtain explicit database approval, inspect the live
schema, review grants/RLS, apply manually in an authorized context, and preserve
the proof.

**Deployment ordering is strict.** This candidate already selects one of
`list_public_swipe_partner_cards()` (store/native) and
`list_public_swipe_partner_details()` (ordinary web), while the website
directory calls `list_public_partner_directory()`. None has a fallback to the
legacy wide views. First review, approve, and apply Phase A
(`002_public_partner_card_projection.sql`), then prove all three RPCs as `anon`
and `authenticated` against their exact typed fields and eligible ID sets. Only
after that proof may this client head be deployed or tested in a hosted
environment. Deploying the client first would fail closed.

Phase B (`003_close_legacy_partner_browser_paths.sql`) is separate and remains
blocked until HEHA Local, Wix, Make, website, and every external consumer is
certified or cut over. The deletion packet is another independent gate: review
and apply it separately, then prove repeat calls return the same receipt and
that direct access is limited by role and column. The pricing-view packet also
requires external-consumer proof and its own approval.

## 3. Android release candidate

Configure repository environment `store-review` with:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `HEHA_ANDROID_KEYSTORE_BASE64`
- `HEHA_ANDROID_KEYSTORE_PASSWORD`
- `HEHA_ANDROID_KEY_ALIAS`
- `HEHA_ANDROID_KEY_PASSWORD`

The workflow cannot be dispatched from this unmerged PR because GitHub accepts
`workflow_dispatch` only after the workflow exists on the default branch.
After a separately approved merge places it on the default branch, dispatch
**Store release candidate** manually. The job refuses to build a release when
any signing value is missing and uploads a signed `.aab` artifact for review
only. It does not upload to Google Play. This signed job remains manual and
separate from the automatic unsigned pull-request workflow.

Local unsigned validation may run `./gradlew tasks` or debug builds. A release
task without the four signing environment values must fail.

Android 16 may ignore orientation restrictions on displays at least 600dp wide.
Treat portrait as a phone preference and explicitly review tablet/foldable
behavior instead of claiming a universal orientation lock.

## 4. iOS release candidate

On an authorized Mac with Xcode 26 or newer and the iOS 26 SDK:

1. Set the approved public Supabase runtime values, then run
   `npm ci && npm run env:check:store && npm run assets:check && npm run native:sync`.
2. Open `ios/App/App.xcodeproj`.
3. Confirm bundle ID `online.heha.swipe`, version `0.1.0`, build `1`, iPhone
   family only, and portrait preference.
4. Select the correct Healthy Habit LLC team and automatic/manual signing as
   approved by the Apple account owner.
5. Archive and validate. Do not upload or submit without explicit approval.

## 5. Manual review checklist

- Create account and sign in with email/password.
- Confirm social/passwordless buttons, Instagram gate, precise geolocation,
  payment controls, partner self-service, and admin shortcuts are absent.
- Swipe public cards, save/unsave a card, and reopen the saved list.
- Confirm native/store cards come only from the 13-field RPC, ordinary web
  cards come only from the 24-field web-detail RPC, and the directory comes
  only from the 17-field RPC; direct legacy/base reads must not be used.
- In ordinary web, verify approved gallery, item, website, Instagram, and
  partner-specific HEHA Local actions. Generic Local lane roots must not be
  presented as a partner's menu, and item links must be absolute HTTP(S).
- Open Privacy, Support, and Account deletion from signed-out and signed-in UI.
- Submit a deletion request and preserve the receipt; verify the UI does not say
  deletion is complete.
- Confirm Google Play and Apple icons render without transparent/unsafe edges.
- Capture the required current phone screenshots from the final signed/running
  build; repository graphics do not satisfy this external store-console gate.

## 6. Known external gates

- Publish and verify `https://hehaswipe.app`, its legal/support routes, SPA
  recovery behavior, TLS, and Supabase confirmation/reset redirect allowlist.
- Before deploying this client head, separately approve/apply and prove all
  three Phase-A bounded RPCs; the clients are already switched and fail closed
  without them.
- Inventory/cut over every HEHA Local, Wix, Make, website, and external consumer
  before any separately approved Phase-B legacy-path closure.
- Apply and verify the deletion RPC only after database approval.
- Capture final phone screenshots for both store listings.
- Reconcile Apple App Privacy and Google Data Safety answers with the verified
  live backend, retention, support, and infrastructure logs.
- Create store-review demo credentials securely.
- Complete Google Play and Apple developer account/security requirements.
- Run a signed Android bundle build and an authorized Xcode archive.

This branch is review-candidate material, not upload-ready. Only after every
gate above and a separate approval may anyone upload artifacts or submit store
metadata.
