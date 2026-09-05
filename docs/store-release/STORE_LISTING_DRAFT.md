# HEHA Swipe store listing draft

Status: review draft for version 0.1.0 (build 1). Nothing in this file is a
store submission or a claim that the URLs are already published.

## Shared identity

- App name: **HEHA Swipe**
- Bundle / package ID: `online.heha.swipe`
- Category: Food & Drink (primary), Lifestyle (secondary)
- Support email: `hello@heha.online`
- Target audience: Tampa Bay adults discovering local food, wellness, market,
  service, and community businesses

## Short copy

### Apple subtitle

Healthy local discovery

### Google Play short description

Swipe, save, and discover healthy local favorites around Tampa Bay.

### Promotional text

Discover Tampa Bay restaurants, markets, wellness spaces, and community
businesses in a simple swipe-and-save experience.

## Full description

HEHA Swipe helps you discover and save healthier local favorites around Tampa
Bay. Browse public cards for restaurants, markets, wellness spaces, coaches,
services, events, and community businesses. Swipe through the discovery deck,
save places you want to remember, and return to your personal list anytime.

This first store-review release focuses on the stable discovery experience.
Social sign-in, passwordless sign-in, precise device location, payments,
partner self-service, and internal admin tools are not included in the native
release.

HEHA stands for Healthy Habit: a local-first network designed to make healthier
options easier to find while helping independent businesses become visible.

## URLs to verify before submission

- Marketing: `https://hehaswipe.app/`
- Privacy: `https://hehaswipe.app/privacy`
- Support: `https://hehaswipe.app/support`
- Account deletion: `https://hehaswipe.app/account-deletion`

The routes exist in this app, but the release owner must confirm the public
domain and TLS responses before pasting them into a store console.

## Review notes draft

- Version/build: 0.1.0 (1)
- Authentication offered in the store build: email and password
- Social and passwordless authentication: intentionally hidden
- Payments/subscriptions: intentionally hidden; no digital purchase is offered
- Location: manual area/address entry only; precise geolocation is hidden
- App privacy draft: email, optional name/phone/address, user ID, and product
  interactions are linked to the account for app functionality; no tracking.
  Use `STORE_PRIVACY_ANSWERS.md` as the cross-store working sheet and reconcile
  it with the final signed binaries and live operations before submission
- Account deletion: Profile → Request account deletion invokes the
  authenticated no-argument `request_my_account_deletion()` RPC
- Public partner client contract: 13 allowlisted fields; the dedicated backend
  projection remains an activation gate until separately applied and verified
- iOS: iPhone only, portrait preference
- Android: min / target / compile API 24 / 36 / 36

Demo review credentials must be created and verified by the release owner; do
not commit credentials to this repository or paste them into this draft.

Final phone screenshots must be captured from the signed/running builds. Android
16 can ignore orientation restrictions on displays at least 600dp wide, so the
listing and QA evidence must not overclaim universal portrait locking.

## Google Play graphics

- Icon: `store-assets/google-play/icon-512.png` (512 × 512)
- Feature graphic: `store-assets/google-play/feature-graphic-1024x500.png`
  (1024 × 500)

## Apple graphic

- App icon: `store-assets/apple/app-icon-1024.png` (1024 × 1024, opaque)
