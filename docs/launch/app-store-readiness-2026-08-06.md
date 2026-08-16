# HEHA downloadable-app readiness audit — 2026-08-06

> Review-only launch evidence. This document does not authorize a wrapper implementation, signing, store account changes, submission, deployment, legal publication, or production configuration change.

## Audited state

| Surface | Exact audited head | Current form |
|---|---|---|
| HEHA Local RC | `hehaonline/heha-order-hub@799b565ea3bda6197ce01fafe0a879650e6d110d` (PR #226; tested application head `d8c5a19cde1852ccb8422008a54fea021dfb75e3`, final commit evidence-only) | Current combined React/Vite web candidate; draft and not launch-ready |
| Local RC parent | `hehaonline/heha-order-hub@4b69774ef86a8133c7d623b010ca92ce3876ce7a` (PR #217) | Ancestor of #226; preserved for source evidence, not the current candidate |
| HEHA Swipe RC | `hehaonline/heha-swipe@885461f55f64ea56a9366e6573b6002769820f06` (PR #113) | React/Vite web app with a Web App Manifest and 192/512 icons |
| Swipe refresh sibling | `hehaonline/heha-swipe@e58de647de1f60e6546b972de11f75bf5da76552` (PR #114) | Separate draft; not part of the audited RC |
| Local RC successor | `hehaonline/heha-order-hub@3677407d6de2cbd1c8f900c31269b9a476d1bc7b` (PR #232, stacked on #226; tested app head `207b1876c347696a076013766b909ff9c7967830`, final commit evidence-only) | Review-only successor; cart, filtered-empty, and catalog-control accessibility/reflow repairs evidenced, scheduling submission parked, and not launch-ready |
| Local RFQ composition checkpoint | `hehaonline/heha-order-hub@b511056e394449cedfc1f65619e66baf911cfabb` (PR #233, stacked on #232) | Exact PR #227 Chef/Catering delta reconciled onto the current RC lineage; review-only, independently audited, and not launch-ready |
| Local customer recovery | `hehaonline/heha-order-hub@23fe5f9913b0e7b5595e43788e7eee6071f6d9f8` (PR #230, based on main) | Independent draft; announced retry and 44px recovery controls repaired, hosted lint/build gates green, focused Vitest/authenticated/browser/assistive-technology QA unexecuted |
| Local driver recovery | `hehaonline/heha-order-hub@1648411d023a728a73f8bfb6162eb580adea31b1` (PR #231, based on main) | Independent Night Builder draft; timeout, Realtime-loss, stale-action false-success, and retry-target blockers unresolved |
| Swipe hybrid-security successor | `hehaonline/heha-swipe@cb15e6ab5106985b706498068b389d51d7e026d5` (PR #120) | Deployment-frozen draft; proof workflow failing and repair not pushed |

GitHub inspection found no Capacitor configuration, Xcode project, Android/Gradle app project, Expo configuration, Apple privacy manifest, Android Digital Asset Links file, native bundle/package identifier, or store-build script in either audited RC. Searches also found no service-worker registration. The existing manifests and icons are useful web-install foundations, but they are not App Store or Play Store packages.

## Decision-ready conclusion

**Recommended launch sequence:** soft-launch the verified web apps first, support home-screen installation after live HTTPS install testing, and begin native-store packaging only after the critical web journeys are stable. Use one approved Capacitor-based wrapper per product as the default store path unless native requirements discovered during design make that unsuitable.

This avoids freezing unfinished auth, ordering, legal, and discovery behavior inside signed store binaries while preserving a direct path to TestFlight and Google Play internal testing.

Alternatives:

1. **Web/PWA only for now — recommended for soft launch.** Fastest and reversible; no store review. It does not provide store discovery or native distribution.
2. **Capacitor wrappers after web launch — recommended store path.** Reuses the React/Vite apps on iOS and Android, but adds native projects, signing, deep-link, permission, privacy, device, and review work.
3. **Android Trusted Web Activity plus a separate iOS wrapper.** Potentially lighter Android packaging, but creates two release architectures. Android ownership verification also needs a signed package and `.well-known/assetlinks.json`.

## Confirmed readiness and gaps

### Current Local RC reconciliation — revalidated 2026-08-16

PR #226 is the current Local candidate at exact head `799b565ea3bda6197ce01fafe0a879650e6d110d`. Its final commit is evidence-only; the recorded application/browser-QA head remains `d8c5a19cde1852ccb8422008a54fea021dfb75e3`. The formerly missing verification receipt and Group Orders shared-cart contamination were repaired and should no longer be carried as open blockers against this exact head. PR #226 remains draft, mergeable, and not launch-ready.

Five active drafts now divide the remaining web-launch work:

- **PR #232** at evidence head `3677407d6de2cbd1c8f900c31269b9a476d1bc7b` (tested app head `207b1876c347696a076013766b909ff9c7967830`) is stacked on #226. It restores catalog navigation and 44px targets, removes the false Community Pass waitlist/contact claim, parks order submission because no truthful customer-selected scheduling flow exists, repairs the reviewed cart-editing, filtered-empty recovery, and ordinary catalog-control accessibility/reflow findings, and parks misleading Profile support/order-help actions instead of routing them to a recommender. No support mailbox or outreach success is claimed. The committed packet reports 93/93 contained browser checks, including cart controls, Market filtered-empty recovery, ordinary unfiltered Market controls, item-specific accessible names, keyboard operation, intentional category-scroller preservation, and zero document overflow at 200% zoom; that packet was inspected in review but not independently executed. A human NVDA/VoiceOver pass remains outstanding. It remains a review-only stacked successor—not an independently deployable or production-validated release.
- **PR #233** at `b511056e394449cedfc1f65619e66baf911cfabb` is stacked directly on #232 and composes the exact 13-file #227 Chef/Catering delta without replaying #227's stale parent. The composition is exact, but the inherited request foundation remains launch-blocked by account-deletion/PII-retention, publication-consent/request-acceptance conflation, equal-sequence grant replay, revocation ordering, missing customer cancellation and provider acceptance, unbounded network operations, sensitive-draft expiry, staff-match recovery, and mobile/accessibility gaps. Vercel and Snyk succeeded; no Actions run, migration execution, local test/build, authenticated flow, browser, or assistive-technology proof exists for this head.
- **PR #227** remains the reviewed donor at `6c4a6cca6fb4ec284534878eac5fc3ca7952b050` on older ancestry. Its exact delta is now represented by #233; do not merge or re-stack #227 separately into the selected RC line.
- **PR #230** at `23fe5f9913b0e7b5595e43788e7eee6071f6d9f8` independently repairs customer order-history query/Realtime recovery from current main. The previously recorded 40px/36px recovery targets and silent retry spinner are cleared in source: **Try again** and **Browse current menu** use the local 44px minimum, and initial/retry loading exposes a polite named status with focused regressions for pending and repeated-failure transitions. GitHub Actions run #379, Vercel, and Snyk succeeded, but the workflow still does not execute Vitest; authenticated Supabase/Realtime behavior, browser reflow at 320–desktop and 200% zoom, keyboard focus, and screen-reader execution remain unproved. It is not part of #226/#232.
- **PR #231** at `1648411d023a728a73f8bfb6162eb580adea31b1` independently adds driver demand loading/error/retry presentation from current main. GitHub Actions run #366 completed install, lint, and build successfully, and Vercel/Snyk succeeded, but Vitest and authenticated driver/Supabase execution were not run. Stalled reads have no timeout, Realtime loss is not surfaced, preserved stale cards remain actionable with false-success mutation risk, and the sole retry target is 36px. It is not part of #226/#232.

Do not package or submit any Local candidate yet. The explicitly coordinated integration line is now #226 → #232 → #233. Do not merge #227 separately. Repair #233's privacy, consent, cancellation, provider-acceptance, timeout/recovery, and accessibility blockers; decide how #230 and #231 enter the selected line; then run exact combined-head tests plus authenticated non-production customer/driver/order/RLS/recovery proof. Order submission should remain parked until customer-selected scheduling and safe failure recovery are implemented and validated.

Evidence:

- https://github.com/hehaonline/heha-order-hub/pull/226
- https://github.com/hehaonline/heha-order-hub/pull/232
- https://github.com/hehaonline/heha-order-hub/pull/227
- https://github.com/hehaonline/heha-order-hub/pull/233
- https://github.com/hehaonline/heha-order-hub/pull/230

### Local Chef/Catering PR-A composition checkpoint — confirmed 2026-08-16

Local PR #233 is the explicitly coordinated composition checkpoint for issue #228. It is open, draft, mergeable, based on PR #232 exact head `3677407d6de2cbd1c8f900c31269b9a476d1bc7b`, and has exact head `b511056e394449cedfc1f65619e66baf911cfabb`.

Composition proof:

- one commit ahead and zero behind #232;
- exactly the same 13 filenames, statuses, additions, and deletions as #227's reviewed delta;
- all twelve retained file blobs match #227 exactly and the mock-chef file is absent;
- seven replaced/deleted paths were unchanged between #227's old base and #232; all six added paths were absent on #232;
- no dependency, lockfile, workflow, environment, secret, or unrelated file changed;
- Vercel and Snyk succeeded; the PR has no unresolved review thread and no GitHub Actions run.

The exact composition does not make the inherited implementation safe. Independent connector-only static review confirmed:

1. `partner_service_requests.customer_user_id` uses `ON DELETE RESTRICT`, while request address, verified contact, allergy notes, and free text have no deletion-safe retention/redaction path.
2. Local-publication consent is also used to set `accepting_requests = true`; separate provider agreement to receive requests is not evidenced.
3. Replaying the same old granted consent event refreshes the 48-hour freshness window, and malformed profile fields can block a newer revocation before revocation handling.
4. Customers cannot cancel or withdraw requests; staff matching is consequential and lacks confirmation or UI recovery; explicit provider acceptance is absent.
5. Directory, profile, targeted-link, tracking, and submission operations lack timeout/abort recovery; transient failures can label valid official links invalid.
6. Sensitive drafts can remain in `sessionStorage` beyond the stated two hours, Catering's empty-result fallback starts a private-chef request, and multiple controls miss 44px/focus/error-association requirements.
7. The SQL proof omits account deletion/erasure, customer cancellation, expired equal-sequence replay, ordinary-user privilege rejection, and separate admin/SOM role cases.

No direct anonymous/authenticated RLS bypass was confirmed statically. That is not executable proof. The migration, SQL proof, local tests/build, authenticated Supabase flows, browser/reflow, keyboard, screen-reader, and Production behavior were not run.

Release implication: #233 closes the release-stack composition question only. Keep it draft and review-only; do not mark ready, merge, apply its migration, deploy, publish partners, or package it into a native wrapper until the blockers above are repaired and the exact integrated head passes executable proof.

### Local PR #233 complete repair order — reconciled 2026-08-16

PR #233 remains the one-commit composition checkpoint at `b511056e394449cedfc1f65619e66baf911cfabb`, based directly on PR #232 head `3677407d6de2cbd1c8f900c31269b9a476d1bc7b`. It preserves the exact thirteen-file PR #227 Chef/Catering delta on the selected `#226 → #232 → #233` line. PR #227 remains the donor and must not merge separately. PR #233 is open, draft, mergeable, and unapplied; Vercel and Snyk report success, but there is no GitHub Actions run, migration execution, authenticated flow proof, browser QA, or assistive-technology evidence.

Direct exact-head review confirms that this foundation is request-only, but not yet safe to open publicly:

- one Local review RPC sets publication, request readiness, and `accepting_requests = true` together, so Local-publication consent is being treated as provider agreement to receive requests;
- exact equal-sequence bridge replay refreshes `synced_at` and the mirrored freshness timestamps, allowing an old grant receipt to renew the 48-hour availability window without a new source event;
- profile/content validation runs before the revoke branch, so malformed irrelevant profile fields can block a newer revocation from reaching the atomic delist path;
- `partner_service_requests.customer_user_id` and `partner_profile_id` use `ON DELETE RESTRICT`, while verified contact, address, allergy notes, and free text have no approved retention/redaction lifecycle;
- customers can answer a needs-information request but have no owner-scoped cancellation RPC; staff can mark a row cancelled, while providers have no authenticated acceptance/decline action;
- staff matching writes `matched` immediately, with no provider confirmation, rematch/release contract, expected-version guard, or customer recovery when the provider later cannot accept;
- every Supabase list/profile/submit/mutation call is unbounded. A timeout or connection loss can leave the client unsure whether a request or mutation committed;
- the full sensitive draft is rewritten to `sessionStorage` on edits. Expiry is checked only when restoration is attempted, so the stored address/allergy/menu data can remain after the stated two hours and the rolling `savedAt` can extend that period;
- several controls remain 40px (`h-10`/`min-h-10`) and async loading/error transitions lack complete named-status, retry, focus, and error-association evidence.

Recommended safe default: keep Chef/Catering request submission and provider-facing claims closed. Public pages may remain preview-only with truthful “not accepting requests yet” behavior until the following repairs exist on the existing #233 branch and pass exact combined-head proof.

Dependency-safe repair order:

1. **Keep one source of truth and one release line.** Repair #233 in place on its current #232 base; retain the existing request tables/RPCs and canonical Swipe ID. Do not create a parallel request model, re-merge #227, or independently merge the overlapping #145/#156/#157/#158 routing/type work.
2. **Separate three independent approvals.** Model exact-snapshot Local publication consent, HEHA internal publication review, and provider request-participation acceptance independently. `review_and_publish_partner_service_profile` may publish an eligible profile, but must not set `accepting_requests`. A separate current-owner/provider agreement—versioned, revocable, purpose-specific, and audited—must gate request readiness.
3. **Make bridge ordering fail closed.** Authenticate/authorize the bridge, lock by canonical Swipe ID, and evaluate event identity/sequence before optional public-profile fields. Process a newer revocation with the minimum required identity/status data even when content is malformed. Equal-sequence exact replay must return the original result without changing freshness. If freshness needs renewal, use a distinct monotonic heartbeat/attestation event rather than replaying consent.
4. **Define deletion and retention before storing real requests.** Replace account-blocking foreign-key behavior only through a reviewed migration. Preserve the minimum operational/audit fact while unlinking or pseudonymizing the deleted customer and clearing contact, exact address, allergy/health-adjacent notes, and free text according to approved retention periods. Revoke sessions and prove a pre-deletion JWT cannot read or mutate the request after deletion. Do not activate an automated purge until policy and rollback are approved.
5. **Complete the request state machine.** Add an owner-scoped, idempotent customer cancellation path for eligible pre-acceptance states. Treat staff selection as `provider_proposed` or `awaiting_provider`, not provider acceptance. Require an authenticated current provider/authorized representative to accept or decline; support staff release/rematch; lock the request and require an expected version so stale tabs cannot overwrite newer decisions. Keep quote, acceptance-of-quote, checkout, payment, payout, and messaging frozen.
6. **Bound every network operation and recover uncertainty.** Add explicit timeout/abort behavior for directory, targeted profile, history, queue, submit, response, match, and status operations. On submit/mutation timeout, say confirmation is unknown, preserve the same idempotency key, and reconcile from the server before enabling another action. Distinguish a confirmed absent/ineligible target from a transient lookup failure and provide retry without silently changing the requested partner/service.
7. **Minimize and expire local drafts.** Use an absolute creation expiry that edits cannot extend; remove expired content on a timer as well as restore; clear on completion, explicit cancel, logout/account change, and source-route change. Prefer not persisting address, allergy, and free-text fields unless the user explicitly chooses a short-lived “save on this device” option with clear disclosure.
8. **Repair responsive accessibility.** Raise every interactive target to at least 44×44 CSS pixels, including back links, chips, queue actions, response controls, and scope tabs. Add named polite loading/submitting statuses, associate field errors with inputs, announce unknown/failed/success states, restore focus after step/error/retry transitions, and prevent fixed CTA/BottomNav overlap.
9. **Expand executable proof.** Add clean-apply/re-apply and negative grant/RLS/BOLA tests for guest, customer A/B, provider A/B, SOM, admin, inactive/wrong role, and stale JWT. Cover equal replay without freshness extension, malformed-profile revocation, newer grant/revoke races, customer cancellation races, provider accept/decline/rematch races, deletion/redaction, exact audit minimization, and failure rollback. Run focused Vitest plus authenticated browser tests; merely committing test files is not execution evidence.
10. **Certify the integrated head only.** Test the exact pushed #233 repair atop #232 with the repository-pinned toolchain: install, lint, typecheck, focused/full tests, production build, migration/proof suite, diff/secret scan, and 320/375/390/430/768/1024/desktop plus 200% zoom, keyboard, NVDA/VoiceOver, offline, timeout, retry, duplicate-submit, and stale-action QA. Re-fetch checks, mergeability, ancestry, changed files, and review threads before any readiness decision.

Rollback/pre-activation boundary: revert the review-only commits and disposable migrations. Do not apply the migration, publish a provider, enable request intake, contact a provider/customer, activate notifications or payments, mark ready, merge, deploy, or change Production without a later exact-scope approval.

Evidence:

- https://github.com/hehaonline/heha-order-hub/pull/233
- https://github.com/hehaonline/heha-order-hub/pull/232
- https://github.com/hehaonline/heha-order-hub/pull/227
- https://github.com/hehaonline/heha-order-hub/pull/229

### Web install foundation

- Both RCs provide a manifest with `name`, `short_name`, `start_url`, standalone display, and 192/512 PNG icons.
- Both RCs reference their manifests and Apple touch icons from `index.html`.
- The Swipe RC corrected the old zoom-blocking viewport and now uses `width=device-width, initial-scale=1.0`.
- Live HTTPS installability, icon safe zones, installed launch behavior, cache/update behavior, and device-specific home-screen results were **not run** in this connector-only audit.
- Swipe includes `public/sw.js`, but the RC does not register it; Local has no worker or registration. Do not promise offline support or resilient cached operation.
- Both manifests use the same short name, `HEHA`, so installing both can be confusing.
- Local presents itself as “HEHA Order Hub” and describes real-time orders, drivers, and payouts, while the public product is HEHA Local. Approve truthful public naming before promoting installation.
- Each icon is declared as both `any maskable` using one asset. Maskable safe-zone appearance still needs visual validation.

### HTTP response-hardening evidence gate — confirmed unknown 2026-08-16

This is an **unverified web soft-launch gate**, not a finding that the deployed app is currently missing security headers.

Repository evidence at Swipe RC #113 exact head `885461f55f64ea56a9366e6573b6002769820f06` establishes only that `vercel.json` contains the SPA rewrite and no repository-owned response-header policy. Production and exact-preview response headers, Vercel project-level settings, and browser network behavior were not inspected.

A generic global policy is unsafe here:

- `index.html` contains an inline tab/deep-link script and loads Google Fonts, while the app calls Supabase. A copied strict Content Security Policy can break routing, fonts, Auth, Realtime, or Data API traffic.
- `main.jsx` intentionally exposes `/embed/partners` and `/embed/become-partner`. Global `X-Frame-Options: DENY` or `frame-ancestors 'none'` would break those Wix-facing embeds.
- Until exact responses are captured, clickjacking protection on non-embed pages, MIME-sniffing protection, referrer leakage, browser capability restrictions, transport policy, cache policy, and manifest/service-worker content types remain unknown. Vercel readiness alone does not prove them.

Safe evidence and implementation order:

1. Capture production and exact-RC-preview response headers for `/`, both embed routes, representative JS/CSS, `manifest.json`, icons, and `sw.js`. Record status, content type, caching, CSP/XFO, HSTS, `X-Content-Type-Options`, `Referrer-Policy`, and `Permissions-Policy`.
2. Inventory the approved Wix origins and every observed font/Supabase/Auth/Realtime/network destination. Do not guess an allowlist.
3. Prepare a repository-owned, route-aware policy. Start CSP in report-only mode; preserve the inline script with a reviewed hash/nonce or move it into bundled code. Keep non-embed pages fail-closed while allowing only the approved embed origins.
4. Re-run auth, partner embeds, deep links, manifest/icon/service-worker fetches, error routes, and responsive/browser QA before requesting separate approval for the exact header change.
5. Roll back by reverting the header configuration and retain before/after header receipts.

Alternative: explicitly accept the unknown for the first web pilot and leave headers unchanged. HTML meta tags are not the recommended repair because they cannot establish HSTS or a reliable route-aware framing boundary.

No header, Vercel, Wix, DNS, deployment, or Production setting was changed by this audit.

### Release toolchain and dependency-audit gate — revalidated 2026-08-11

The downloadable-app path does not yet have one supported, repository-pinned JavaScript runtime/package-manager contract.

Current exact evidence:

- Local main `e3261fc72c00ac20fc71fd07b035f16c75893917` has no root `engines`, `.nvmrc`, or `.node-version`. Its lockfile resolves `@supabase/supabase-js@2.105.4`.
- Local PR #230 exact-head Actions run `31907713458` (#379) used `actions/setup-node` with `node-version: 20`, which resolved Node `20.20.2` and npm `10.8.2` — not the npm `11.4.2` used by older release evidence. GitHub emitted repeated Node 20 deprecation warnings.
- That same successful job's `npm ci` reported 20 audit findings: 3 moderate, 16 high, and 1 critical. The workflow continued to lint/build and concluded success. Snyk also reported success, so the audit summary alone does **not** prove a production-exploitable vulnerability; the advisory identities, dependency paths, runtime reachability, and Snyk policy/ignore behavior remain unreconciled.
- Swipe main `82ec41a27150847f3d461716bc58636e24babfe6` likewise has no root `engines`, `.nvmrc`, or `.node-version`; its lockfile resolves `@supabase/supabase-js@2.106.2`. PR #116 has no GitHub Actions run, and Swipe exposes no repository lint or full-test script.
- Supabase announced that packages from its JavaScript monorepo dropped Node 20 support after 2026-06-30. The currently locked HEHA packages still declare `node >=20.0.0` and the exact Local install/build passed, but a future Supabase update cannot safely assume Node 20 support.

This is a release-reproducibility and security-evidence gate, not a request to run `npm audit fix`, upgrade dependencies, or change the production runtime from this documentation branch.

Required bounded plan:

1. Reconcile the 20 Local audit findings by advisory ID, package path, dev/production reachability, available fix, and Snyk policy/ignore state. Treat any reachable critical/high finding as a separate security repair.
2. Select one supported Node LTS baseline (Node 22 is the minimum safe candidate under Supabase's current notice), then pin the exact Node and npm versions in repository metadata, GitHub Actions, Vercel build settings, local release instructions, and eventual native-wrapper CI.
3. Validate Local and Swipe clean installs, lint where available, all relevant tests, production builds, auth/realtime/order recovery, and wrapper builds on that exact toolchain before replacing historical Node 20 evidence.
4. Keep lockfile and dependency upgrades isolated and reviewed; do not mix a runtime migration with Supabase, Vite, Capacitor, or security-package upgrades.
5. Preserve a rollback path to the last exact successful lockfile/toolchain pair while Node 22 validation is incomplete.

Evidence:

- https://github.com/hehaonline/heha-order-hub/actions/runs/31434968073
- https://github.com/hehaonline/heha-order-hub/blob/e3261fc72c00ac20fc71fd07b035f16c75893917/package.json
- https://github.com/hehaonline/heha-order-hub/blob/e3261fc72c00ac20fc71fd07b035f16c75893917/package-lock.json
- https://github.com/hehaonline/heha-swipe/blob/82ec41a27150847f3d461716bc58636e24babfe6/package.json
- https://github.com/hehaonline/heha-swipe/blob/82ec41a27150847f3d461716bc58636e24babfe6/package-lock.json
- https://supabase.com/changelog/45715-deprecation-notice-dropping-support-for-node-js-20

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

Active-lineage revalidation on 2026-08-14 confirms this blocker is still present and expanded in PR #120 at `cb15e6ab5106985b706498068b389d51d7e026d5`: its replacement anonymous view retains `owner_id` and routing fields and additionally projects `claim_status`, `partnership_status`, and `contract_status`. Review #4934056629 records the required public allowlist and executable column-contract proof. PR #120's security workflow #13 still fails before SQL/RLS/concurrency execution, so none of those database claims are validated release evidence.

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

### Supabase auth-state callback deadlock gate — revalidated 2026-08-09

Swipe RC #113 at exact head `885461f55f64ea56a9366e6573b6002769820f06` carries a shared-client auth listener that can hang launch-critical Supabase calls. The locked dependency is `@supabase/supabase-js@2.106.2`. On every non-admin, non-embed page, `main.jsx` renders `InternalDashboardShortcut` beside the app even when its Profile portal target is absent. That component registers `onAuthStateChange(() => { checkAccess(); })`; `checkAccess` immediately starts `supabase.auth.getSession()` and then queries `user_roles`.

Supabase's current troubleshooting guidance (last edited 2026-04-08 and rechecked 2026-08-09) states that an async Supabase API call made in an `onAuthStateChange` callback can deadlock the client and cause the next Supabase call anywhere on that client to hang. The RC's main app and admin-gate listeners only copy the supplied session synchronously; the shortcut listener is the unsafe exception.

This creates a launch-critical recovery risk on sign-in, sign-out, token refresh, password recovery, or other auth events:

- the shortcut's role lookup can hang instead of failing closed;
- the shared client can then strand later profile, partner, saves, swipe, onboarding, or account-action calls;
- hiding or lacking the Profile portal target does not contain the effect because the listener is already mounted;
- green build/preview checks and static auth screenshots do not exercise an auth event followed by a second database call.

Required fail-closed plan:

1. **Recommended soft-launch default:** omit/disable the internal shortcut in the RC until the listener is repaired; keep direct `/admin` authorization as the independent access path.
2. Keep the auth callback synchronous. Copy the callback's supplied session/user ID into state and return; perform the `user_roles` query in a separate effect or deferred task outside the callback.
3. Do not call `getSession()` from inside `onAuthStateChange`. Use the supplied session and guard stale results with a generation/cancellation check.
4. Default visibility to false on no session, error, cancellation, or role mismatch. Do not weaken the direct admin route's session/active-role gate.
5. Add regression coverage for initial session, sign-in, sign-out, token refresh, password recovery, rapid repeated events, Strict Mode mount/unmount, unauthorized roles, query failure, and proof that a subsequent Supabase query completes after every event.
6. Re-test against the exact locked package version. If a dependency upgrade is proposed instead, treat it as a separate reviewed dependency/lockfile change and verify the official fix/release note plus the same regression matrix.

PR #99 only moves the shortcut's portal destination and inherits this listener unchanged; preserve its placement idea, but do not use its exact head as the repair input.

No Supabase Auth setting, role, RLS policy, dependency, deployment, production session, or user account is changed or authorized by this audit.

Evidence:

- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/main.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/components/InternalDashboardShortcut.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/package-lock.json
- https://supabase.com/docs/guides/troubleshooting/why-is-my-supabase-api-call-not-returning-PGzXw0
- https://github.com/hehaonline/heha-swipe/pull/99#issuecomment-5226399388


### SECURITY DEFINER scout ACL reproducibility gate — confirmed 2026-08-12

Both current `main@82ec41a27150847f3d461716bc58636e24babfe6` and Swipe RC #113 at `885461f55f64ea56a9366e6573b6002769820f06` define `public.ensure_scout_event_artifact(uuid)` as a `SECURITY DEFINER` function. It accepts a Scout lead UUID, reads that lead without a caller predicate, can copy its contact and event details into `event_applications`, and updates the source lead with the new artifact ID.

A full exact-tree scan of all 38 SQL files found no explicit `REVOKE` for this function and no caller, role, or `auth.uid()` check in its body. PostgreSQL grants function execution to `PUBLIC` by default, so a clean repository migration replay can create a direct RPC-capable privileged mutation unless another untracked step hardens the ACL.

A metadata-only inspection of the connected **HEHA SWIPE** project on 2026-08-12 narrowed the current live risk: the function exists as `SECURITY DEFINER`, is owned by `postgres`, and has the explicit ACL `postgres=EXECUTE, service_role=EXECUTE`; `anon` and `authenticated` both report `EXECUTE=false`. The function was not invoked, and no lead or event data was queried. Therefore this audit found no evidence of a current anonymous/authenticated production exploit. The release blocker is unreconciled schema lineage: the secure live ACL is not reproduced by the committed migration that defines the function.

The adjacent `ensure_scout_pm_task(uuid)` migration demonstrates the intended source-controlled boundary by explicitly revoking execution from `PUBLIC`, `anon`, and `authenticated`. The Scout event helper lacks equivalent repository evidence.

Required fail-closed plan:

1. **Recommended immediate release default:** preserve the current live ACL, do not invoke the RPC manually, and keep the internal Scout/event lane out of launch-readiness claims until repository lineage is reconciled.
2. Prepare a dedicated migration that explicitly revokes direct execution from `PUBLIC`, `anon`, and `authenticated`. Preserve `service_role` execution only if an inventory proves a direct server caller requires it; existing trigger execution must remain independently verified.
3. Prefer moving privileged trigger-only logic into a non-exposed private schema. If direct invocation is required, use a narrowly granted wrapper and validate the target lead and caller role before mutation.
4. Add a migration proof that anonymous, ordinary authenticated, inactive-role, and wrong-role RPC calls fail; an authorized Scout insert still creates exactly one linked event artifact; retries remain idempotent; arbitrary/unknown UUIDs do not mutate state; and RLS/BOLA checks remain intact.
5. Run lineage-faithful disposable migration replay, function-ACL inspection, database advisors, and adversarial multi-session tests. Then compare the disposable ACL to the live metadata result before requesting any production migration.
6. Because live `anon`/`authenticated` execution is already denied, no emergency production ACL change is recommended from this evidence. Any later production migration or grant change remains separately approval-gated and must include an exact rollback.

No function execution, migration, role/grant change, lead record, event application, deployment, or production setting was changed. The only live inspection was function metadata/ACL.

Evidence:

- https://github.com/hehaonline/heha-swipe/blob/82ec41a27150847f3d461716bc58636e24babfe6/supabase/migrations/20260705000400_scout_event_artifacts.sql
- https://github.com/hehaonline/heha-swipe/blob/82ec41a27150847f3d461716bc58636e24babfe6/supabase/migrations/20260705000600_scout_pm_tasks.sql
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/supabase/migrations/20260705001700_sync_scout_pillar_to_partner.sql


### Public legacy pricing view exposure gate — confirmed 2026-08-12

A metadata-only inspection of the connected **HEHA SWIPE** project found that the legacy `public.heha_pricing` view remains externally exposed:

- the current Supabase security advisor reports `security_definer_view` at **ERROR** level and facing **EXTERNAL**;
- the view is owned by `postgres` and has no `security_invoker` option;
- both `anon` and `authenticated` have schema usage and `SELECT` on the view;
- the ACL grants those browser roles broad view privileges, while the definition still publishes eight internal pricing, discount, pay, and allocation constants.

Only catalog metadata, ACLs, advisor output, and the view definition were inspected. The view was not selected through a browser role, no business rows were read, and no function, migration, grant, pricing value, payment path, or production setting changed.

Draft PR #70 at exact head `0118cee76f8298f75d36fb3eed8accc7b9bcd747` recognizes the exposure and proposes `security_invoker=true` plus browser-role revocation. Its one-file intent is directionally correct, but it is not safe to merge or apply unchanged:

- it is based on stale `main@f0c9cd1b3571bafbe1038960b07a8103e04a3a66`, not current `main@82ec41a27150847f3d461716bc58636e24babfe6`;
- it recreates the entire view body and therefore republishes the old constants to trusted backends instead of limiting itself to privileges;
- it has no current consumer inventory, disposable replay, role-matrix proof, body-preservation proof, or rollback/forward-repair test;
- exact-head hosted evidence is Vercel success only; no GitHub Actions/database proof or review thread exists.

The live definition matching #70's old constants proves what is exposed today; it does not establish that those figures are approved, canonical, or safe for operational use.


A bounded read-only consumer inventory on 2026-08-12 narrowed the compatibility uncertainty:

- exact current-main searches in HEHA Swipe, HEHA Local, and HEHA Control found no references to `heha_pricing`, `driver_pay_per_portion`, or `partner_launch_suggested`;
- the live PostgreSQL catalogs report no dependent view/materialized view, function-source reference, policy reference, or trigger reference;
- `pg_cron` is not installed, so there is no in-database scheduled job consumer;
- `pg_stat_statements` has retained top-level statements since 2026-05-29, reports zero deallocations, and contains exactly one direct `select * from public.heha_pricing` fingerprint: one call as `postgres`, returning one row. It contains no matching direct-read fingerprint attributed to `anon`, `authenticated`, `authenticator`, or `service_role`.

This is evidence against an active application/Data API consumer, not proof that none exists. Statement telemetry has no per-call timestamp here, the isolated `postgres` read cannot be attributed to a person or tool, and a dormant Make, Wix, server, report, copied URL, or future job may sit outside repository/database dependency metadata. External consumer confirmation remains the smallest unresolved compatibility gate.

Required fail-closed plan:

1. **Recommended soft-launch default:** treat all public pricing, fee, discount, driver-pay, allocation, and partner-launch claims as blocked until an approved canonical source exists; keep #70 outside the RC.
2. Treat the repository and database dependency inventory as complete for this evidence packet; inventory every Make, Wix, server, report, copied URL, and other external consumer read-only. Do not assume repository non-use or quiet query telemetry proves zero dormant dependencies.
3. Prepare a fresh current-base, privilege-only successor that changes the existing view to `security_invoker=true` without redefining its body, revokes `PUBLIC`/`anon`/`authenticated`, and grants only the minimum verified server role. Any canonical pricing replacement must be a separate financial approval.
4. In a lineage-faithful disposable environment, prove the view definition is byte/semantic-equivalent before and after the privilege repair; anonymous and ordinary authenticated access fail; the approved server consumer succeeds; unrelated partner, supporter, and routing paths remain intact; and the migration re-applies safely.
5. Prepare an exact rollback and operational fallback for a missed legacy consumer. Do not default to restoring public browser access; prefer a narrowly authenticated server-owned compatibility path.
6. Apply no production migration until Geronimo approves the exact successor head, dependency inventory, validation packet, and rollback.

Alternatives:

- **Drop the view** only after proving there are no consumers; smallest permanent surface, highest compatibility risk.
- **Keep the current public view** only as an explicitly accepted temporary risk; not recommended because internal financial constants remain externally readable and the advisor remains red.
- **Merge #70 unchanged** is not recommended because it couples privilege hardening to a stale financial-body rewrite.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/70
- https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0010_security_definer_view
- https://supabase.com/docs/guides/api/securing-your-api


### Client-side partner-review webhook recovery gate — revalidated 2026-08-09

Swipe RC #113's partner registration flow has a separate client-side webhook boundary in `PartnerWizard.jsx`. After the authenticated `partners` insert succeeds, the component awaits `VITE_MAKE_PARTNER_APPROVAL_WEBHOOK` before it calls `setSubmittedListing(data)` and leaves the loading state.

The code does not set an application timeout, inspect `response.ok`, persist a delivery result, or offer notification retry/reconciliation. Its catch block only handles rejected fetches and intentionally suppresses them. Therefore:

- a slow or non-returning endpoint can strand the user in a loading state after the partner row has already been committed, creating an uncertain submission experience;
- an HTTP 4xx/5xx resolves normally and is treated the same as delivery success;
- a network rejection is hidden, so the user can see a successful registration even though the operational notification may be missing;
- when configured, the browser-visible `VITE_` endpoint receives partner identity, category, neighborhood, and owner email/phone and can be forged, replayed, or spammed by a client.

The database record—not the Make call—must be the authoritative review queue. Notification delivery must never sit between a committed submission and truthful user confirmation.

PR #78 does not repair the release path. It is an unwired, stale adapter draft that checks `response.ok` but still uses the browser-visible endpoint, still has no application timeout or durable receipt, and is not part of RC #113. Preserve it as design evidence; do not merge or finish it as a release fix. Issue #86 owns related server/database credential rotation and consumer inventory, so the eventual notification repair must coordinate with that work rather than introducing another endpoint or credential.

Required fail-closed plan:

1. **Recommended soft-launch default:** verify the variable by name only and leave `VITE_MAKE_PARTNER_APPROVAL_WEBHOOK` unset. Treat the authenticated pending partner row as the review queue and establish a manual queue/owner check before accepting live registrations.
2. Return truthful registration success immediately after the database insert. Make clear that the listing is pending review; do not imply that a notification was delivered.
3. Move optional notifications to a server-owned outbox/worker triggered from the committed record. Derive the payload server-side, minimize personal data, authenticate the destination with server-held credentials, and use an immutable event ID plus idempotent delivery.
4. Record pending/sent/failed status and bounded retry attempts without exposing endpoint values or raw personal data in logs. Provide an operational reconciliation view so failed notifications cannot hide submissions.
5. Prove database-insert failure, unset endpoint, 2xx, 4xx, 5xx, timeout, offline/rejected fetch, delayed response, replay/forgery, duplicate event, retry recovery, and manual-queue fallback in a disposable environment.
6. Inventory and coordinate the existing account and partner-approved notification consumers before rotating or replacing any Make endpoint. No live scenario, credential, Vercel variable, database trigger, or Supabase function may change without exact approval.

Evidence:

- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/components/PartnerWizard.jsx
- https://github.com/hehaonline/heha-swipe/pull/78#issuecomment-5227563825
- https://github.com/hehaonline/heha-swipe/issues/86

### Pending partner queue discoverability gate — revalidated 2026-08-09

The durable partner row is recoverable to its owner after a reload: `App.jsx` queries the latest `partners` row by `owner_id`, and `ProfileTab.jsx` independently reloads that owner-scoped row and shows its listing status. This closes the owner-side uncertainty after a successful insert even if the wizard's local `submittedListing` state is lost.

The internal recovery path is not launch-ready, however. A new registration is inserted with listing `status = 'pending'`. The canonical routing migration gives `routing_status` a default of `suggested`; its trigger promotes that field to `needs_review` only when the listing itself is already public (`approved`, `live`, or `listed`). `RoutingDashboard.jsx` loads the rows but defaults its filter to `needs_review`, so a newly submitted pending row is hidden until an operator deliberately selects **Suggested** or **All**. That screen reviews cross-platform routing, not partner-publication approval, and the exact RC contains no dedicated pending-publication queue or frontend call to `approve_partner(uuid)`.

This makes the unset-webhook fallback incomplete: the record is durable, but there is no default-visible, purpose-built queue proving that HEHA operations will discover and disposition it. The optional browser webhook must not be treated as the approval queue or the only notification path.

Required soft-launch gate:

1. **Recommended safe default:** keep live partner registration closed, or staff a documented manual query for `status = 'pending'` before accepting submissions. Continue leaving `VITE_MAKE_PARTNER_APPROVAL_WEBHOOK` unset.
2. Add a dedicated, least-privilege internal pending-publication queue ordered oldest-first. Show only the fields required to review, with explicit empty, loading, timeout, retry, and error states.
3. Keep publication approval separate from routing review. Routing status must not imply that a partner is approved, public, or HEHA Certified; final publication remains super-admin/service-owned.
4. Define owner, cadence/SLA, duplicate handling, rejection/needs-information states, escalation, and an auditable disposition receipt. A row that is merely selectable under **Suggested** is not evidence of an operated approval process.
5. Prove a successful insert with the webhook unset, reload/owner recovery, default internal discovery, oldest-first processing, unauthorized access denial, concurrent reviewers, approve/reject/needs-information paths, partial failure/retry, and public-visibility separation in a disposable environment.
6. Reconcile the live migration/RLS baseline before implementation. Do not apply schema, policy, role, RPC, webhook, or production-data changes from this documentation branch.

Evidence:

- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/App.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/components/ProfileTab.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/src/components/admin/routing/RoutingDashboard.jsx
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/supabase/migrations/20260705001100_canonical_partner_routing.sql
- https://github.com/hehaonline/heha-swipe/blob/885461f55f64ea56a9366e6573b6002769820f06/supabase/migrations/20260707045848_partner_security_foundation.sql

### Hybrid partner lifecycle successor gate — revalidated 2026-08-11

Founder decision issue #119 now requires four independent canonical concepts for every partner record: profile claim status, HEHA partnership status, contract status, and public listing status. Claiming must preserve the existing `partners.id` and must not imply Official Partner, contract completion, certification, publication, routing, pricing, or Local eligibility.

The two donor PRs remain useful but are not independently releasable:

- PR #117 exact head `5282d4ae676dbda57b196fd92f756cca839ab99d` is five commits ahead of current Swipe `main@82ec41a27150847f3d461716bc58636e24babfe6`. Its nine-file security migration/proof package has green hosted checks, but the founder disposition keeps it draft and deployment-frozen as a donor because its single relationship field combines claim, partnership, and removal concepts.
- PR #72 exact head `b76c3d47c476b81f7be1b6f2b7aafcc6e16f240d` is three commits ahead and 38 commits behind current main. Its two-file relationship migration is a stale donor for partnership-interest, review, approval, and contract concepts; it must not be rebased or merged unchanged.
- Issue #119 contains an automated implementation receipt for local commit `847101efb26c63947f71811b8d1a9837d69f7e81`, but the receipt explicitly says no draft PR was published. Live GitHub inspection found no matching remote commit, branch, or open PR. There is therefore no remote exact head to diff, test, collision-check, or independently review. The receipt also marks the SQL lifecycle proof and two-session concurrency harness as not executed.

A follow-up recovery attempt in issue #119 could not find `847101efb26c63947f71811b8d1a9837d69f7e81` in the available task checkout, local object database, refs, reflogs, unreachable objects, or filesystem artifacts, and no patch or bundle exists there. GitHub transport in that environment also remained blocked by HTTP 403. The implementation is therefore unavailable from both GitHub and the recovery environment; a PR title/body or remembered summary must not be used to reconstruct a false review target. The original task sandbox must export the exact commit/history. If that is impossible, issue #119 must explicitly lift its competing-implementation hold before one coordinated rebuild begins from the current verified base.

The successor preflight must cover more than #72 and #117. The complete 21-open-PR filename/domain sweep found two additional collisions:

- PR #118 changes 18 files and adds `20260810072829_wave1_partner_publication_consent.sql`. That migration creates a publication-consent ledger and privileged publication functions over `public.partners`, directly updates `partners.status` and `routing_status`, and replaces public partner projections. Its exact-version consent and visibility rules behaviorally overlap the new `public listing status`; the successor must map, compose, or explicitly supersede them.
- Stale PR #82 changes the original claim migrations, workflow, UI, and five exact proof/document paths also changed by #117. It must remain historical evidence, not a third implementation source.

Supabase's current platform defaults add a concrete proof requirement: new tables and functions stopped being automatically exposed by default for new projects on 2026-05-30, and the behavior is scheduled to be enforced for existing projects on 2026-10-30. Every successor table/function therefore needs explicit grants/revokes, RLS where exposed, and exact-role API tests; RLS alone does not constrain column updates or function execution.

**Safe release default:** keep #72, #82, #117, and the unpublished local implementation out of the release chain. Publish one fresh successor draft from the verified current integration base, reconcile #118 explicitly, and require a lineage-faithful disposable apply/re-apply plus state-transition, owner-guard, RLS/BOLA, deletion/reclaim, duplicate-profile, and true multi-session concurrency proofs before exact-head review. No Production migration, Auth change, claim activation, partner status transition, duplicate merge, media transfer, deployment, or cutover is authorized.

Connector-only verification completed: live PR/branch/commit searches, donor ancestry comparisons, all open Swipe PR changed-file sets, hosted donor checks, review threads, and issue #119's decision/receipt. Not run: local checkout, install/build, SQL apply/re-apply, Supabase branch, Auth/RLS execution, concurrency harness, browser QA, or Production access.

Evidence:

- https://github.com/hehaonline/heha-swipe/issues/119
- https://github.com/hehaonline/heha-swipe/pull/117
- https://github.com/hehaonline/heha-swipe/pull/72
- https://github.com/hehaonline/heha-swipe/pull/118
- https://github.com/hehaonline/heha-swipe/pull/82
- https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/postgres/column-level-security

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

The exact RC has two additional fail-open defects:

- repository-wide code search finds `account_deletion_requests` only in `ProfileTab.jsx`; no committed migration, table definition, generated type, or test establishes that the request queue exists in a reproducible database. A table that exists only in an uninspected live project would be untracked schema drift, not release evidence;
- after the request insert, the three awaited delete calls do not inspect their returned Supabase `error` values. RLS, network, or schema failure can therefore leave some or all personal data behind while the UI still reports, “Your HEHA Swipe data was cleared from the app tables.”

This is a web soft-launch blocker as well as a store blocker. A table insert is not evidence that deletion was fulfilled, and an unchecked browser-side sequence cannot provide transactionality, retry safety, or an honest completion receipt. Until the canonical schema and server-owned workflow are approved and proven, keep public account creation closed to a controlled pilot and route deletion requests through the verified support owner; do not advertise the destructive button as completed deletion.

Recommended implementation remains approval-gated: create one canonical, least-privilege deletion-request schema and one authenticated server-owned RPC or Edge Function that binds identity to `auth.uid()`, creates an idempotent request, returns a truthful pending receipt, and leaves fulfillment to an auditable admin workflow. Do not delete user data opportunistically in the browser before retention scope, reauthentication, session revocation, partial-failure recovery, and downstream obligations are defined.

Supabase also documents that deleting an Auth user does not itself invalidate already-issued JWT access tokens until they expire, so the final server-owned workflow must revoke sessions and account for token lifetime rather than treating row deletion as immediate logout.

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

### Deployed Stripe webhook fail-open drift blocker — confirmed 2026-08-12

The live HEHA Swipe Supabase project has an active `stripe-webhook` Edge Function at deployed version 10, bundle SHA-256 `d4aa5014ac0e1417e5810197ef23bdec142b868dc18bc69473638bb354694144`, last updated 2026-06-14 13:59:33 UTC. Its platform `verify_jwt=false` setting is intentional for a Stripe webhook: the deployed body requires and cryptographically verifies the `stripe-signature` header against the server-held webhook secret before processing an event. No signature-bypass defect was confirmed.

The confirmed blocker is persistence failure handling. The deployed source awaits writes to `supporter_subscriptions`, `profiles`, `supporter_payments`, and `contributions`, but does not inspect the Supabase client's returned `error` values. PostgREST permission, constraint, and other database failures normally resolve as `{ data, error }`; they do not have to throw. The handler can therefore acknowledge a paid Stripe event with HTTP 200 and `{ received: true }` even when a critical HEHA write failed. Stripe then treats delivery as successful and does not retry that event.

The failure can also be partial: for example, a subscription row can persist while the profile entitlement update fails, or a payment row can persist while the contribution write fails. That creates payment, entitlement, support, and reconciliation risk even though the Stripe charge itself succeeded.

Current repository `main@82ec41a27150847f3d461716bc58636e24babfe6` already contains a source-side repair from commit `138dd64cd8db39f9c3f7fcbe31a810e9a5165a93` (2026-07-10): `persistCritical` checks each Supabase result, throws on `error`, and routes the event to an HTTP 500 response so Stripe can retry; it also makes the contribution write an idempotent upsert. The deployed version does not match that repository source. No open Swipe PR changes either Stripe Edge Function, so this is deployment drift rather than an open-PR collision.

The last-24-hour Edge Function log response contained no `stripe-webhook` or `create-supporter-checkout` entries and no matching processing-error entry. That does not prove the flow is unused or correct, and it cannot reconstruct older missed or partial events.

The current non-production HEHA staging project is not yet a valid target for that test plan. Metadata-only inspection found `profiles` but none of the six Stripe/subscription columns used by the repaired webhook, and found no `contributions`, `supporter_payments`, or `supporter_subscriptions` tables. Its migration history is empty. Deploying the repaired function there now would therefore prove only missing-schema failure, not retry safety or convergence.

Open draft PR #69 at exact head `6d799fa323ef92b3bf2fc5211c4d12f60ca4b5fa` is the existing recovery lane for one part of that prerequisite. It adds only the recovered `20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql` source. An independent metadata-only comparison on 2026-08-12 found its three table definitions, defaults, constraints, indexes, update triggers, RLS enablement, and policies aligned with the corresponding current production objects. It is mergeable with current main, has no review threads, and is the only other open Swipe PR in this payment-schema domain.

PR #69 is necessary lineage evidence but is not sufficient to make staging webhook-ready. The repository ledger still marks live migration `20260531204554 add_stripe_fields_to_profiles` untracked, and current main contains no source for the six production profile fields the webhook writes. The staging project also lacks `contributions`; the committed entitlement-hardening migration assumes that table already exists. Production does have the webhook's three required idempotency keys: unique `supporter_subscriptions(stripe_subscription_id)`, `supporter_payments(stripe_checkout_session_id)`, and `contributions(stripe_payment_id)`.

Corrected approval-gated recovery plan:

1. **Recommended safe default:** keep the supporter purchase/entitlement path out of the soft launch. Do not deploy the repaired webhook to the current staging project yet.
2. Independently review and disposition PR #69 as source-lineage restoration only. Because production already records that migration, do not manually re-apply it there.
3. Recover and review the remaining exact payment prerequisites: the missing profile Stripe-field migration, the source that creates `contributions`, and the later entitlement ACL/unique-key hardening chain. Do not infer production DDL from application code alone.
4. Prove the complete canonical migration sequence in an approved disposable target and verify schema, defaults, constraints, grants/RLS, triggers, and the three conflict keys before deploying any function.
5. Only then deploy the exact repaired webhook in Stripe test mode; send valid signed checkout-completion, subscription-update, and subscription-deletion events.
6. Force each critical persistence operation to fail independently and prove non-2xx response, Stripe retry, eventual convergence, replay idempotency, out-of-order/concurrent delivery handling, signature denial, invalid linkage denial, and test/live separation.
7. After separate exact approval, deploy only the reviewed function version and record its version/hash. Reconcile Stripe event history against HEHA rows with a read-only report first; any replay, refund, entitlement correction, or production data mutation requires separate explicit approval.
8. If rollout verification fails, keep purchase disabled and redeploy the last known bundle while diagnosing; do not acknowledge unpersisted test events as successful.

No Edge Function was deployed, no Stripe product/webhook was changed, no event was replayed, and no production row, entitlement, charge, refund, secret, or environment setting was touched.

Evidence:

- https://github.com/hehaonline/heha-swipe/blob/82ec41a27150847f3d461716bc58636e24babfe6/supabase/functions/stripe-webhook/index.ts
- https://github.com/hehaonline/heha-swipe/commit/138dd64cd8db39f9c3f7fcbe31a810e9a5165a93
- https://github.com/hehaonline/heha-swipe/pull/69
- https://github.com/hehaonline/heha-swipe/blob/82ec41a27150847f3d461716bc58636e24babfe6/docs/migration-lineage/live-ledger-2026-07-19.csv

### Partner-claim proof and permanent-account gate — revalidated 2026-08-12

Open draft PR #117 remains the strongest current claim-security proof at pushed head `5282d4ae676dbda57b196fd92f756cca839ab99d`, but two verification boundaries remain before it can enter a release chain.

First, GitHub returned one Actions run associated with this head: Partner Claim SQL Proof run #29 (`31260802543`). It completed successfully with Supabase CLI `2.112.0`, PostgreSQL 16.14, disposable migration application, core/extended/ACL/lifecycle proofs, migration re-apply, two-session concurrency proofs, and an evidence-secret scan. Vercel and Snyk are also green. The checkout log, however, proves that the job executed GitHub's synthetic merge commit `42c849bbf91d4ef8a8b66a570def5c225a9386bb` (head `5282d4a…` merged into base `82ec41a…`), not the pushed head itself. That is useful target-integration evidence, but it does not satisfy the separate exact-pushed-head execution gate.

Second, static control-flow review found an unproved permanent-account boundary. Email-address invitations resolve to a user ID only when `auth.users.email_confirmed_at is not null`; otherwise preview and claim fail closed until verification. But the explicit `p_intended_user_id` path selects only `auth.users.email`, binds the supplied UUID without checking `email_confirmed_at` or `is_anonymous`, and both preview and claim then authorize that branch using only `auth.uid()`. Therefore an invitation deliberately or mistakenly bound to an unverified user UUID—and, if anonymous sign-ins are enabled, an anonymous user's UUID—can reach the ownership mutation with no permanent-account check. This edge was not exercised by the green proof matrix. Supabase documents that anonymous users use the `authenticated` Postgres role and must be distinguished using the `is_anonymous` JWT claim: https://supabase.com/docs/guides/auth/auth-anonymous.

Recommended fail-closed repair:

1. Require every claim recipient, including direct UUID bindings, to be a permanent verified account before issuance and again immediately before preview/claim. Read the current `auth.users` record inside the definer function; do not invent an `email_verified` JWT claim.
2. Reject `is_anonymous = true`, missing confirmation, deleted/tombstoned recipients, and a recipient that becomes ineligible after issuance.
3. Add direct-UUID negative proofs for pre-existing unverified and anonymous users; assert 42501, unchanged ownership/status/invitation, and no successful-claim audit event. Add the corresponding positive proof after the same account becomes permanent and verified.
4. Run the complete disposable proof on the exact pushed head as a distinct job/ref, then preserve the successful merge-ref run as target-integration evidence.
5. Keep #117 outside the release chain until its separate relationship-model collision with #72/#120 and the SWP-016 lineage/ADR-001 gates are resolved.

This is a review finding, not a claim that anonymous sign-ins are enabled in Production. Repository search found no `signInAnonymously` call or committed anonymous-auth setting; live Auth configuration was not inspected. No migration, Auth setting, user, invitation, Partner row, or deployment was changed.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/117
- https://github.com/hehaonline/heha-swipe/actions/runs/31260802543
- https://github.com/hehaonline/heha-swipe/blob/5282d4ae676dbda57b196fd92f756cca839ab99d/supabase/migrations/20260807160000_partner_claim_foundation_v2.sql
- https://supabase.com/docs/guides/auth/auth-anonymous

## Hybrid partner successor #120 exact-head review gate — revalidated 2026-08-12

Open draft PR #120 now stands at pushed head `cef9af2bc8785ea9732a1dca2de052b3995f1ca9`. It materially repairs the unsafe first draft: the executable chain now retains #117's `public.partner_claim_invites` source of truth and recipient/deletion guarantees, restores #72's consent-bearing `partner_interest_requests`, separates claim/partnership/contract/listing states, uses private single-use mutation capabilities, minimizes lifecycle receipts, and carries disposable SQL/RLS/concurrency/build evidence. It remains draft, unapplied, and outside the release chain.

### Verified integration evidence

Hybrid Partner Lifecycle Proof run #12 (`31644362989`) completed successfully on 2026-08-12:

- disposable Supabase startup and ordered migration application;
- 19 behavioral ACL/lifecycle assertions, including unverified/wrong/deleted-recipient denial, deletion tombstones, direct owner assignment denial, self-promotion denial, Business A/B request isolation, opt-out removal, and owner-deletion downgrade/recovery;
- convergence-safe reapplication of corrective migrations `20260811090100` through `20260811090400`, followed by a second behavioral proof;
- four scripted multi-session scenarios covering partner-lock order, replacement-vs-claim, revoke-vs-claim, and claim-wins-vs-revoke, with no `40P01`;
- `npm ci`, production build, `git diff --check`, evidence sensitivity scan, and sanitized artifact upload.

The job checked out GitHub's synthetic merge commit `9ae0a16fb2db192596ad08639b9435d9deecb06f`, whose parents are base `82ec41a27150847f3d461716bc58636e24babfe6` and pushed head `cef9af2bc8785ea9732a1dca2de052b3995f1ca9`. GitHub comparison reports zero changed files between the merge commit and the pushed head, so the tested file tree is identical. This is target-integration/merge-ref evidence, not a literal pushed-head checkout.

Vercel and Snyk are green. PR #120 is open, draft, mergeable, and owns its ten exact filenames; #72, #82, and #117 remain behavioral donors/collisions and must not enter a parallel release chain.

### Confirmed authorization blockers

Two unresolved inline review findings remain valid at `cef9af2`. Green CI does not clear them because the proof suite does not exercise either exploit path.

1. **Caller-spoofable `owner_release` bypass.** `app_private.gate_partner_lifecycle_capability` exempts the string context `owner_release` from its missing-capability rejection before returning early when no lifecycle field changes. `app_private.guard_partner_owner_self_service` also trusts that context and returns before applying its approved-field allowlist. An authenticated owner able to issue an owner-scoped UPDATE can therefore set the custom GUC and alter non-allowlisted partner data such as ratings, routing metadata, analytics, or media without a private capability.
2. **Owner-authored claim-provenance erasure.** The `auth_reference_cleanup` predicate accepts a pure `claimed_by: UUID -> NULL` or `opted_out_by: UUID -> NULL` transition without proving that an Auth FK action caused it. It then sets the trusted `owner_release` context. A normal owner UPDATE can therefore leave a listing claimed while erasing protected provenance.

These are code-level authorization defects in the draft migration, not evidence of a Production exploit. The migration remains unapplied.

### Remaining proof gaps and required repair

1. Do not treat a caller-visible GUC string as authorization. Require an inaccessible, transaction-scoped, single-use capability—or an equivalently narrow private mechanism—for owner release and Auth-reference cleanup.
2. Preserve real account deletion without relying on a condition that an ordinary owner-authored UPDATE can satisfy. Prove deletion clears the intended references and records only deletion-safe audit data.
3. Add adversarial regressions showing an ordinary authenticated owner cannot:
   - spoof `owner_release` to alter a non-allowlisted field;
   - directly null `claimed_by` or `opted_out_by`;
   - update another owner's `partner_interest_requests` row.
4. Add simultaneous redeem-vs-redeem proof: exactly one owner transition, one consumed invitation, one `claim_redeemed` event, a deterministic loser, and no `40P01`.
5. Rerun the entire disposable migration, behavioral, corrective-reapply, concurrency, build, diff, and evidence workflow on the repaired head; preserve both pushed-head/tree identity and merge-ref integration evidence.
6. Keep the branch draft and Production-frozen. Do not apply migrations, change Auth, activate claims, merge donor PRs, deploy, or mark ready without a separate exact approval.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/120
- https://github.com/hehaonline/heha-swipe/actions/runs/31644362989
- https://github.com/hehaonline/heha-swipe/pull/120#discussion_r3770655341
- https://github.com/hehaonline/heha-swipe/pull/120#discussion_r3770655342
- https://github.com/hehaonline/heha-swipe/pull/120#issuecomment-5273305629

No migration, database/Auth setting, user, Partner row, claim token, deployment, or Production system was changed by this audit update.

### Signed-contract evidence gate — confirmed 2026-08-13

Swipe draft PR #120 at exact remote head `cef9af2bc8785ea9732a1dca2de052b3995f1ca9` carries a third independent launch blocker beyond its two unresolved authorization findings. The proposed `public.approve_heha_partnership(uuid)` function accepts only a Partner UUID and verifies only that the caller is service-role/super-admin and that the Partner is claimed and under review. The function itself then writes `contract_status = 'signed'`, invents `contract_signed_at = now()`, changes the relationship to `official_partner`, and enables the legacy public partner flag.

Neither the function nor the proposed schema requires an agreement version, content hash, current owner/signer identity, acceptance/signature record, signing source, immutable evidence identifier, or completed/revoked state. The disposable proof follows the same evidence-free path—internal review followed by `approve_heha_partnership(partner_id)`—and asserts the resulting signed/official state. A privileged call can therefore manufacture a legally consequential “signed” receipt and public Official Partner badge without proving that an agreement was accepted.

This is a defect in a draft, unapplied migration; it is not evidence that a Production contract or partner status was changed. It also does not decide what legally qualifies as a signature. That definition, evidence retention/anonymization, and any real agreement activation remain Geronimo/legal approval gates.

Required fail-closed reconciliation:

1. Create an immutable, access-controlled agreement-acceptance/evidence record containing at minimum the Partner, current owner/signer identity, agreement version and content hash/reference, acceptance/signing time, status/source, and audit actor.
2. Require and lock that evidence identifier during approval; verify that it is completed, current, belongs to the exact Partner and current owner, matches the active agreement version, and is not revoked, terminated, or superseded before writing `signed` or `official_partner`.
3. Reference the evidence identifier from the lifecycle receipt without copying sensitive agreement content into general audit JSON.
4. Add negative proofs for missing evidence, wrong Partner, wrong/currently replaced owner, stale or mismatched agreement version, revoked/terminated evidence, and owner deletion/release. Add one positive exact-head proof using a valid immutable record.
5. Keep contract and Official Partner activation frozen until the authorization blockers, this evidence gate, retention policy, legal definition, and complete disposable exact-head workflow all pass review.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/120#pullrequestreview-4926596082
- https://github.com/hehaonline/heha-swipe/blob/cef9af2bc8785ea9732a1dca2de052b3995f1ca9/supabase/migrations/20260811090000_hybrid_partner_lifecycle.sql
- https://github.com/hehaonline/heha-swipe/blob/cef9af2bc8785ea9732a1dca2de052b3995f1ca9/supabase/tests/hybrid_partner_lifecycle_proof.sql

No migration, agreement, Partner row, Auth user, lifecycle receipt, deployment, or Production system was changed by this documentation update.


### Hybrid partner repair/proof reconciliation — revalidated 2026-08-13

The preceding #120 sections preserve the exact review history at `cef9af2bc8785ea9732a1dca2de052b3995f1ca9`. They are now superseded for current-head status by remote head `cb15e6ab5106985b706498068b389d51d7e026d5`, which is one commit ahead and adds the agreement-evidence and context-authenticity repair package. PR #120 remains open, draft, mergeable, unapplied, and outside the release chain.

The repair is materially present on GitHub now. The PR has twelve changed files, including:

- `20260811090500_hybrid_partner_agreement_evidence.sql`;
- `20260811090600_hybrid_partner_context_authenticity.sql`;
- expanded lifecycle and multi-session proof sources;
- the pinned disposable proof workflow and exact-head provenance gate.

This closes the earlier “local-only repair commit” provenance mismatch, but it does **not** validate the repair.

#### Exact-head workflow failure

Hybrid Partner Lifecycle Proof run #13 (`31748869580`) failed before any migration or behavioral step. The workflow checked out GitHub's synthetic merge commit `8e7b6641513609144bd966151d4f46fee0cddbd7` at the default shallow depth, then fetched PR head `cb15e6ab5106985b706498068b389d51d7e026d5` at depth one. Both commits remained shallow boundaries, so `git merge-base --is-ancestor` could not traverse the merge parent and falsely reported that the merge tree did not contain the PR head.

The job exited in “Install PostgreSQL client and pin the exact reviewed head.” Every later step was skipped:

- disposable Supabase startup and migration application;
- SQL/RLS/BOLA behavioral proof;
- corrective-migration re-apply;
- multi-session concurrency proof;
- application build and diff check;
- evidence sensitivity scan and artifact upload.

Vercel and Snyk are green, but neither substitutes for the skipped database/security workflow. None of the new repair head's executable migration, authorization, agreement, concurrency, or rollback claims is validated yet.

Required workflow repair:

1. Check out `${{ github.event.pull_request.head.sha }}` directly, preferably without persisted credentials.
2. Require literal `git rev-parse HEAD == PR_HEAD_SHA` before running the proof.
3. If merge-ref integration evidence is also desired, execute it as a separate clearly labeled job or fetch sufficient history and prove ancestry plus tree identity.
4. Add a provenance regression showing an ordinary pull-request merge ref passes and an unrelated SHA fails.
5. Rerun the entire disposable workflow on the repaired pushed head and retain the sanitized exact-head receipt.

#### Additional exact-head security findings

Automated review of `cb15e6ab` identified three further fail-closed defects that remain unresolved until a repaired head and executing proof demonstrate otherwise:

1. **Non-atomic trigger disabling.** The agreement-evidence corrective migration uses `DISABLE TRIGGER USER`, reconciliation UPDATEs, and `ENABLE TRIGGER USER` without an explicit transaction. The workflow replays the file with `psql -f` autocommit, creating a concurrent-write window and an interruption path that can leave user triggers disabled. The disable/reconcile/enable sequence must be atomic and must prove rollback restores trigger state.
2. **Forged lifecycle provenance on owner INSERT.** Owner-created partner rows have lifecycle status fields normalized but can retain caller-supplied `partnership_requested_at`, `official_partner_since`, `contract_signed_at`, `opted_out_at`, and `opted_out_by`. Reset every protected provenance field on the owner INSERT path and add cross-user attribution/forged-timestamp proofs.
3. **Caller-set JWT GUC used as privileged authority.** Agreement registration, retirement, evidence revocation, and partnership approval trust a service-role value read from caller-set `request.jwt.claims`. Under the direct-SQL authenticated-role threat model used by this proof package, an ordinary caller can set that custom GUC. Replace it with a non-forgeable database privilege/capability boundary and prove an authenticated owner cannot invoke any internal agreement/approval mutation even after setting every relevant JWT/GUC value.

Required current-head acceptance is therefore cumulative: repair the workflow provenance gate; make trigger reconciliation atomic; clear owner-insert provenance; replace caller-supplied JWT authority; retain the prior owner-release/provenance and immutable agreement-evidence protections; execute the complete disposable migration/RLS/BOLA/concurrency/build suite; and obtain independent exact-head review.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/120
- https://github.com/hehaonline/heha-swipe/actions/runs/31748869580
- https://github.com/hehaonline/heha-swipe/pull/120#pullrequestreview-4932239332
- https://github.com/hehaonline/heha-swipe/pull/120#pullrequestreview-4931739215

No migration, trigger, agreement, Partner row, Auth user, lifecycle receipt, deployment, or Production system was changed by this documentation update.


### Contract-evidence termination and replacement gate — confirmed 2026-08-16

Fresh review-thread reconciliation on Swipe PR #120 exact head `cb15e6ab5106985b706498068b389d51d7e026d5` found **10 unresolved threads**. The readiness audit already records the authorization, workflow, public-view, trigger, provenance, and contract-evidence gates. Two additional lifecycle defects must also remain explicit:

1. Terminating an Official Partner changes Partner lifecycle statuses but leaves `contract_evidence_id` attached to an `accepted` agreement record. A restarted partnership can therefore reuse old accepted evidence when the agreement version is still current; the live-acceptance uniqueness rule can also block a legitimate replacement.
2. Deleting the accepting Auth account or retiring the agreement version can leave the evidence row marked `accepted` even though its signer or agreement is no longer authorizing. The partial unique index still treats that row as live and can prevent the current owner from recording fresh evidence.

Recommended fail-closed repair:

- atomically terminalize the referenced acceptance and clear the Partner evidence link when a partnership terminates;
- terminalize invalidated acceptances on account deletion and agreement retirement without deleting the audit fact;
- define uniqueness over evidence that is both active and currently authorizing, not merely labeled `accepted`;
- prove termination → reapplication, account deletion → reclaim, agreement retirement → replacement, wrong-owner/wrong-Partner denial, and concurrent termination/resubmission on the exact integrated head.

This remains a defect in an unapplied draft, not evidence of a Production incident. PR #120 is draft, its Hybrid Partner Lifecycle Proof still fails before migration/security execution, and none of these migrations was applied by this audit.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/120
- https://github.com/hehaonline/heha-swipe/blob/cb15e6ab5106985b706498068b389d51d7e026d5/supabase/migrations/20260811090200_hybrid_partner_private_mutation_capabilities.sql
- https://github.com/hehaonline/heha-swipe/blob/cb15e6ab5106985b706498068b389d51d7e026d5/supabase/migrations/20260811090500_hybrid_partner_agreement_evidence.sql

No migration, agreement, Partner row, Auth user, deployment, or Production system was changed by this documentation update.

### PR #120 complete same-branch repair order — reconciled 2026-08-16

PR #120 remains at exact remote head `cb15e6ab5106985b706498068b389d51d7e026d5`, open, draft, mergeable, and unapplied. Its twelve changed files carry ten current unresolved review threads. Vercel and Snyk report success, but Hybrid Partner Lifecycle Proof run #13 stops in the shallow-checkout provenance gate before migrations, SQL/RLS/BOLA behavior, corrective replay, concurrency, build, or evidence scanning. The unpushed local summaries for `3f0f234…` and `8dca94f…` remain design notes only; neither is remote release evidence.

The ten findings form one security boundary and should be repaired in this dependency order on the existing #120 branch only:

1. **Lock the canonical lineage and public contract.** Retain #117's `public.partner_claim_invites` object and recipient/deletion/lock-order guarantees; retain #72's consent-bearing interest evidence; keep claim, partnership, contract, and listing state independent. Do not create a parallel claim table or merge #72, #82, #117, or #118 independently.
2. **Replace forgeable authorization before changing lifecycle behavior.** Revoke every agreement/approval mutation from `PUBLIC`, `anon`, and `authenticated`; grant only the intended non-forgeable database role. Never authorize from caller-set `request.jwt.claims` or `app.hybrid_partner_context`. Require a private, transaction-scoped, single-use capability for the narrowly approved owner-release/Auth-cleanup path, consumed under a locked Partner row.
3. **Separate Auth deletion from owner-authored updates.** A normal owner must not null `claimed_by` or `opted_out_by`, spoof `owner_release`, or alter non-allowlisted partner fields. The real deletion path must establish its private capability before FK cleanup and complete reference release, lifecycle downgrade, and sanitized receipt atomically.
4. **Sanitize every owner-created row.** Normalize both lifecycle states and all protected provenance: partnership request time, official-partner time, contract evidence/signing fields, opt-out time/actor, routing/claim administration, and any cross-user attribution. An INSERT must not be a bypass around UPDATE guards.
5. **Make agreement evidence authoritative without inventing a signature.** Keep immutable agreement/version/acceptance facts access-controlled. Approval must take and lock an evidence ID, then validate exact Partner, current owner/signer, active version/hash, accepted/current status, and absence of revocation, termination, supersession, or account deletion. The approval receipt may reference IDs and states, never agreement content or hashes. What legally qualifies as acceptance and its retention policy remain Geronimo/legal gates.
6. **Close the complete evidence lifecycle.** Partnership termination must atomically clear the Partner reference and make the old acceptance non-authorizing. Signer deletion and agreement retirement/supersession must preserve history while releasing the live-evidence slot. Fresh eligible evidence must be recordable after reclaim or a new version. Enforce this under Partner-first locking so termination, deletion, retirement, acceptance, and approval races end deterministically without stale authorization or uniqueness dead ends.
7. **Minimize the anonymous discovery surface.** Replace `public_swipe_partners` with an explicit reviewed allowlist. Exclude owner/Auth identifiers, routing notes/staff/timestamps, claim/partnership/contract states, internal analytics, and administrative fields. Exclude `contact` and `phone` by default until separate affirmative publication consent is approved. Keep owner/admin detail on protected surfaces.
8. **Make corrective application fail closed.** Any trigger suspension, reconciliation, constraint/index replacement, and re-enable sequence must be one explicit transaction with error-stop behavior. Prove rollback leaves every guard enabled. Forward migration and clean replay must converge without rewriting accepted historical evidence or reopening old privileges.
9. **Repair proof provenance before trusting results.** Check out the literal pull-request head with persisted credentials disabled and require `HEAD == PR_HEAD_SHA`. Run merge-ref integration separately if desired; do not substitute it for exact-head execution. Include a passing ordinary-merge-ref control and an unrelated-SHA negative control.
10. **Execute and independently review the pushed head.** On a disposable environment, run clean ordered migrations, corrective re-apply, SQL/RLS/BOLA tests, true simultaneous concurrency, app build, diff/secret/evidence scans, and sanitized artifact upload. Re-fetch the exact remote SHA, full diff, checks, mergeability, and every thread before resolving anything.

Minimum executable negative/transition matrix:

- caller-set JWT/GUC values cannot create administrative authority;
- owner-release spoof, direct provenance nulling, protected-field UPDATE, cross-owner interest UPDATE, and forged INSERT provenance all fail;
- missing, wrong-Partner, wrong-owner, stale-version, revoked, terminated, superseded, deleted-signer, and retired-version evidence cannot approve;
- termination → reapplication, signer deletion → reclaim, and agreement retirement → replacement all allow only fresh eligible evidence;
- two simultaneous redeems produce exactly one owner transition, one consumed invite, one `claim_redeemed` event, a deterministic loser, and no `40P01`;
- concurrent termination/deletion/retirement versus acceptance/approval never authorizes stale evidence or leaves a live-slot dead end;
- anonymous discovery returns intended public fields and rows while every excluded column is absent; owner/admin paths retain only their approved access;
- failed corrective replay rolls back completely with lifecycle/owner guards still enabled.

Release gate: keep #120 draft and Production-frozen until the repaired implementation exists at a real remote SHA, the complete exact-head suite passes, all ten findings receive fresh independent review, donor/integration ancestry is reconciled, and Geronimo separately approves any migration or activation. No Production DDL, Auth/secret change, claim activation, agreement activation, partner publication, merge, ready transition, or deployment is authorized by this repair order.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/120
- https://github.com/hehaonline/heha-swipe/actions/runs/31748869580
- https://github.com/hehaonline/heha-swipe/pull/117
- https://github.com/hehaonline/heha-swipe/pull/118

### Consent-evidence ownership handoff BOLA gate — confirmed 2026-08-12

Swipe draft PR #118 at exact head `a83e41225b6c1b75d9f0132341c3c759f01018c9` correctly keeps publication-consent evidence in a private RLS table, but its owner-read policy uses the historical event owner as continuing access authority:

- each `partner_publication_consent_events` row stores the partner's `owner_id` when the event is recorded;
- the owner policy permits `SELECT` whenever `auth.uid() = event.owner_id`;
- the policy does not also require that the caller remains the current `public.partners.owner_id`;
- no trigger or ownership-release path revokes or rewrites the historical event owner.

This collides with the approved release/reclaim direction in issue #119 and donor/successor PRs #117/#120, where a canonical Partner ID and its evidence survive owner release and verified reclaim. If the former owner's Auth account remains active, changing the Partner row to a new owner does not change old consent rows. The former owner can therefore continue reading private evidence after losing the business profile, including representative contact, name/title, evidence reference, exact profile snapshot, and recorder identifier. Conversely, the new owner is not automatically entitled to the old rows, so the current direct-table policy is neither a safe access boundary nor a complete handoff contract.

Recommended fail-closed reconciliation:

1. Keep historical actor/owner identifiers as immutable audit facts, but never use them alone as current authorization.
2. Remove the owner-facing direct table policy and expose only a reviewed, redacted current-owner status RPC; keep full evidence limited to approved internal roles. If direct owner evidence access is retained, require a current-ownership join and explicitly allowlist returned columns.
3. Prove immediate former-owner denial after release/transfer/reclaim; wrong-owner and Business A/B denial; deleted-account tombstones; current-owner status recovery; internal-role access; and evidence preservation without reassignment or destructive rewriting.
4. Run those proofs on the same exact integrated migration lineage as the hybrid claim successor. Do not patch #118 and #120 independently into competing ownership contracts.
5. Decide separately, with privacy/legal review, whether and which historical evidence a new owner may see. Default to redacted status, not full predecessor contact/evidence.

This is a confirmed policy-integration defect in the proposed SQL, not evidence that Production currently has this table or that a live former owner accessed it. PR #118 remains draft and unapplied. No database, Auth user, Partner row, consent event, deployment, or external service was queried or changed.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/118
- https://github.com/hehaonline/heha-swipe/blob/a83e41225b6c1b75d9f0132341c3c759f01018c9/supabase/migrations/20260810072829_wave1_partner_publication_consent.sql
- https://github.com/hehaonline/heha-swipe/issues/119
- https://github.com/hehaonline/heha-swipe/pull/117
- https://github.com/hehaonline/heha-swipe/pull/120


### Partner self-reauthorization bypass gate — confirmed 2026-08-13

Swipe draft PR #118 at exact head `a83e41225b6c1b75d9f0132341c3c759f01018c9` separates owner consent from the staff-only `approve_partner(uuid)` activation call, but its public-view gate does not preserve that separation after the first activation.

Exact proposed behavior:

- `authorize_partner_profile_publication(...)` is executable by `authenticated` and requires current ownership, current preparation permission, and owner approval of the current profile hash.
- `has_current_partner_publication_authorization(...)` treats the latest owner `publish_profile = granted` event as the complete exact-version visibility gate when its stored snapshot and hash match the current Partner row.
- Editing a live profile temporarily hides it because the old authorization hash becomes stale, but the edit does not clear `status = live`, `swipe_eligible`, or `local_eligible`.
- The owner can then call `authorize_partner_profile_publication(...)` for the changed hash. The public projections see matching owner authorization plus the still-live eligibility flags and expose the new content without another staff review.
- The committed proof explicitly expects that owner exact-version reapproval restores both `public_swipe_partners` and `public_local_partners`.

This means a partner can change public name, bio, media, website, offerings, or other projected content after initial approval and self-publish the changed version. The exact-version consent requirement is preserved, but the distinct HEHA content-review/activation boundary is not. This is a proposed-migration defect; PR #118 remains draft and unapplied, so it is not evidence of a live Production bypass.

Required fail-closed reconciliation:

1. Model owner publication consent and HEHA review as separate immutable events, or store a separate internally reviewed snapshot/hash.
2. Require each public projection to match both the latest current owner authorization and an allowed internal review for the exact same Partner, destination, snapshot, and hash.
3. Keep an edited profile hidden after owner reauthorization until an approved internal role reviews that exact version. Do not treat old `live` or eligibility flags as review evidence.
4. Prove: edit hides; owner reauthorization remains hidden; exact-hash staff review restores visibility; a second edit defeats the stale review; wrong-role/BOLA denial; concurrent edit/consent/review ordering; and withdrawal wins immediately over either approval.
5. Reconcile on one exact #117/#118/#120 consent and ownership lineage so a former owner, replacement owner, stale event, or competing donor migration cannot satisfy either half of the gate.

Hosted metadata at review time showed Vercel and Snyk success but no GitHub Actions run for #118's exact head. The migration, SQL proof, browser flow, and Supabase/Auth behavior were not executed by this connector-only audit.

Evidence:

- https://github.com/hehaonline/heha-swipe/pull/118#issuecomment-5275689087
- https://github.com/hehaonline/heha-swipe/blob/a83e41225b6c1b75d9f0132341c3c759f01018c9/supabase/migrations/20260810072829_wave1_partner_publication_consent.sql
- https://github.com/hehaonline/heha-swipe/blob/a83e41225b6c1b75d9f0132341c3c759f01018c9/supabase/tests/partner_publication_consent_proof.sql

No migration, Partner row, consent event, Auth user, deployment, or Production system was changed by this documentation update.

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
