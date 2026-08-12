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

### Release toolchain and dependency-audit gate — revalidated 2026-08-11

The downloadable-app path does not yet have one supported, repository-pinned JavaScript runtime/package-manager contract.

Current exact evidence:

- Local main `e3261fc72c00ac20fc71fd07b035f16c75893917` has no root `engines`, `.nvmrc`, or `.node-version`. Its lockfile resolves `@supabase/supabase-js@2.105.4`.
- Local PR #230 exact-head Actions run `31434968073` used `actions/setup-node` with `node-version: 20`, which resolved Node `20.20.2` and npm `10.8.2` — not the npm `11.4.2` used by older release evidence. GitHub emitted repeated Node 20 deprecation warnings.
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

## Hybrid partner successor #120 exact-head review gate

Open draft PR #120 at exact head `17f80c241ac11ef27d5896523511ee19210f9ac9` proposes the right high-level separation of claim, partnership, contract, and listing status, but its executable migration is not a safe successor to #72/#117 and must remain outside the release chain.

Confirmed blockers at that exact head:

1. `redeem_partner_claim` requires `auth.jwt()->>'email_verified'`. Supabase's current JWT claims reference does not define that claim; the standard authenticated-token claims include `email`, `is_anonymous`, `aal`, and `amr`, but not `email_verified`. With an ordinary Supabase JWT, `coalesce(..., false)` therefore rejects every claim before recipient matching. Evidence: https://supabase.com/docs/guides/auth/jwt-fields.
2. Lock order is inverted across the two competing operations: `issue_partner_claim` locks Partner → invitation, while `redeem_partner_claim` locks invitation → Partner. That recreates the replace-vs-claim deadlock interleave that #117's current partner-first implementation and negative control were designed to catch. #120's shell script runs only claim-vs-claim, supplies no authenticated JWT context, and was syntax-checked but not executed.
3. The SQL "invalid official state" proof uses `where false`, changes no row, and accepts both success and `check_violation`; it therefore cannot prove the constraint. It also omits callable RPC behavior, all seven table privileges, role/identity denials, token lifecycle, deletion behavior, audit invariants, and replacement/revocation races.
4. Claim issuance and automatic replacement do not write lifecycle events or a revoking actor. The invitation table stores the full recipient email with no retention/anonymization contract. Its Partner FK cascades deletion while the lifecycle-event FK restricts it, leaving deletion behavior dependent on whether an event happens to exist rather than one explicit policy.
5. #120's preflight says the exact remote donor heads and open-PR collision inventory were unavailable. They are now known: #120 and #117 both start at current `main@82ec41a27150847f3d461716bc58636e24babfe6`; #117 has the more complete current security/ACL/deletion/concurrency evidence; #72 and #82 remain stale historical donors. All four behaviorally overlap despite different filenames.

Recommended successor design: preserve #120's independent status dimensions, but rebuild the migration on current main using #117's recipient binding, deterministic ACL matrix, partner-first lock order, deletion/tombstone contract, adversarial lifecycle proofs, and evidence controls. Do not merge #117 unchanged either: its single `relationship_status` model must first be replaced with the approved independent dimensions. A new exact-head disposable replay must include baseline lineage, state mapping, Business A/B RLS, standard Supabase JWT fixtures, issue/replace/redeem/revoke races, deletion/reclaim, audit privacy, and negative controls.

No migration was applied, no Auth user or Partner row was queried or changed, and no claim token, production database, deployment, or external system was touched.

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
