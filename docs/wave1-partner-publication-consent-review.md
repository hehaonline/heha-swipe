# Wave 1 chef and caterer publication-permission review

Status: review candidate only. Do not apply, merge, deploy, activate a partner, or call this an official partnership from this branch.

Base: `hehaonline/heha-swipe` `main@82ec41a27150847f3d461716bc58636e24babfe6`

Scope: Tampa Bay Catering and PrivateChef partners, with HEHA Swipe as the canonical partner identity/profile source and HEHA Local as a separately activated destination.

## What this slice establishes

- A signed-in partner can submit one profile and explicitly choose HEHA Swipe, HEHA Local, or both; nothing is preselected.
- Existing owned chef/caterer profiles can enter the same permission flow without creating a duplicate listing.
- Private profile preparation and exact-version publication approval are separate actions.
- The server records an append-only, private evidence event with representative, destination, Tampa Bay service-area attestation, media permission, statement version, server snapshot/hash, timestamp, actor, source, and idempotency data.
- Verified outreach replies can be recorded through a role-gated RPC. A prepare grant must exist before a publish grant.
- Every Wave 1 profile is consent-managed from its first draft, even before an evidence event exists. Any other profile with consent history also stays consent-managed; changing categories cannot fall back into a legacy public route.
- Consent-managed public visibility continuously requires the latest destination-specific prepare and publish grants plus the exact current snapshot. Revocation or profile drift fails closed at the public views even if a routing flag is changed directly.
- Full address, phone, contact, account owner, consent evidence, analytics, routing notes, and internal pricing fields stay private.
- Wave 1 item/per-portion prices and price ranges are suppressed. The public profile says “To be quoted”; the chef/caterer owns the food/service price in the later quote flow.
- `PrivateChef` routes to `chef`; `Catering` routes to `group_orders`.
- Generic `/chef` and `/group-orders` paths are not partner-specific. HEHA Local activation requires an attributable direct profile path or `/chef/match?swipePartnerId=<uuid>&service=private_chef|catering`; the stored partner UUID, consent-derived lane, and service must all match.
- A submitted `partners` row remains the durable review-queue record. The optional browser notification is only an alert; a notification failure is disclosed and does not erase or duplicate the submission.

Profile permission is not partner-terms acceptance, a commercial contract, HEHA Certified status, or HEHA’s decision to activate the listing.

## Required gates before any database apply or UI deployment

1. Founder/legal approval of versioned partner terms, privacy language, profile/media permission copy, and a withdrawal path. This branch deliberately does not manufacture a terms acceptance.
2. Reconcile Swipe’s migration ledger and foundational schema. The repository has duplicate versions and does not reproduce the current production schema cleanly.
3. Obtain a disposable Supabase branch or a current live-schema clone. There is no confirmed Swipe staging project today.
4. Apply the migration only to that disposable target and run `supabase/tests/partner_publication_consent_proof.sql` with an owned test chef/caterer and a super-admin test user.
5. Run Supabase security/performance advisors and review every RLS policy, table/function grant, function owner/search path, and definer-view allowlist.
6. Add component/browser tests for new registration, existing profile preparation, exact preview unavailable, duplicate clicks, RPC failures, retries, revocation, and keyboard/focus behavior.
7. Browser QA at 320, 390, 430, 768, 1024, and desktop widths; keyboard-only and screen-reader checks included.
8. Complete the separate HEHA Local successor: approved Swipe-to-Local profile bridge, mock-profile removal, persisted service request RPC/queue/status, and partner identity preservation through login and submission.

Deploy database/RPCs to staging first, then point a preview frontend at staging. Never deploy the frontend before compatible RPCs exist. Production apply, merge, deployment, partner publication, and public launch each require a separate approval.

## Outreach evidence sequence

For a verified email reply, HEHA operations must preserve the source thread/message reference and record two distinct statements:

1. `prepare_profile/granted`: permission to create a private draft for the named destinations, representative authority, Tampa Bay coverage for Local, and supplied-media rights.
2. `publish_profile/granted`: approval of the exact server-captured partner-authored profile version after the representative has reviewed it. Verified-email evidence must identify the 64-character server snapshot hash shown to the representative; the recording RPC rejects a stale or missing hash.

A vague “sounds good” or an invitation response that does not identify the destination/profile version is not publication approval. Record opt-outs and withdrawals as new revoked events; never edit prior evidence.

## Rollback

Before any consent/request data exists: revoke RPC execution, restore the prior reviewed public-view definitions/grants, and remove only the unused new objects in a transaction on the disposable target.

After evidence exists: use a soft rollback. Revoke write RPCs, set Wave 1 destination eligibility false, restore safe public views that exclude Wave 1, and preserve the consent ledger. Do not drop or rewrite evidence. If a destination is withdrawn, delist only that destination and keep any separately authorized destination unchanged.

## HEHA Local successor contract

- Upsert Local `partner_profiles` by unique `swipe_partner_id`; transfer public-safe fields and current profile hash only, never private contact or consent evidence.
- New/changed Local projections remain `needs_review` until Local approval.
- Remove Pittsburgh mock chefs and fail closed for unknown/unpublished partner IDs.
- Resolve `swipePartnerId` to an approved Local profile and preserve it through request submission.
- Persist a real, authenticated, idempotent chef/catering service request with a human-readable reference and customer/admin status views, separate from the catalog cart.
- No checkout or payment until the frozen quote/payment gate is separately approved.
