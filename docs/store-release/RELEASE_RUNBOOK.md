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

## 2. Database review gates

The SQL packet in `supabase/review_only/store_release` is not a migration.
Before any live change, obtain explicit database approval, inspect the live
schema, review grants/RLS, apply manually in an authorized context, and verify
the deletion receipt and 13-field public projection. Preserve evidence.

The current client allowlists the exact 13 fields when reading the existing
public view, but that is not a backend security boundary. Store activation is
blocked until the dedicated review-only projection exists live, exposes only
those 13 fields, and the client is switched to it in a separately reviewed
release. The deletion RPC is an equally strict activation gate: review and
apply it separately, then verify a repeat call returns the same receipt.

## 3. Android release candidate

Configure repository environment `store-review` with:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `HEHA_ANDROID_KEYSTORE_BASE64`
- `HEHA_ANDROID_KEYSTORE_PASSWORD`
- `HEHA_ANDROID_KEY_ALIAS`
- `HEHA_ANDROID_KEY_PASSWORD`

Dispatch **Store release candidate** manually. The job refuses to build a
release when any signing value is missing and uploads a signed `.aab` artifact
for review only. It does not upload to Google Play.

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
- Confirm public cards function with only the 13-field allowlist.
- Open Privacy, Support, and Account deletion from signed-out and signed-in UI.
- Submit a deletion request and preserve the receipt; verify the UI does not say
  deletion is complete.
- Confirm Google Play and Apple icons render without transparent/unsafe edges.
- Capture the required current phone screenshots from the final signed/running
  build; repository graphics do not satisfy this external store-console gate.

## 6. Known external gates

- Publish and verify `https://hehaswipe.app`, its legal/support routes, SPA
  recovery behavior, TLS, and Supabase confirmation/reset redirect allowlist.
- Apply and verify the dedicated 13-field backend projection only after database
  approval, then switch and retest the client query.
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
