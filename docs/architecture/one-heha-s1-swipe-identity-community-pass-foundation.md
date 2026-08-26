# ONE HEHA S1 — Swipe identity and Community Pass foundation

**Status:** Draft, review-only, unapplied

**Base:** `heha-swipe/main@a8abb46c4908c9f216c589dd35ab7369a8f6cba9`

**Canonical consumer identity:** HEHA Local Auth user ID

**Canonical business identity:** HEHA Swipe `partners.id`

**Production authorization:** None

## Purpose

S1 is the first bounded implementation package under the merged ONE HEHA identity plan. It prepares the private HEHA Swipe database foundation needed to bind one current Swipe Auth subject to the canonical HEHA Local user ID and to recompose Community Pass Package A around that canonical identity.

The package is review-only. All SQL lives under `supabase/review_only/one_heha_s1/`; standard Supabase migration runners do not read that directory. Nothing has been applied to HEHA Swipe, HEHA Local, staging, Production, Stripe, Auth, Vercel configuration, or a real account.

## Current authority

The current rules are:

1. HEHA Local Auth issues the permanent consumer identity.
2. HEHA Swipe `partners.id` remains the permanent business identity.
3. Business ownership is a separately reviewed relationship, not a user role.
4. Local operational roles remain server-controlled and do not prove business ownership.
5. Community Pass remains one server-owned Swipe ledger.
6. Swipe may store the Local Auth UUID only as an opaque cross-project identifier with no cross-project foreign key.
7. Email may help explain a link journey but never completes or persists a link.
8. HEHA Local later receives only a minimized, signed, short-lived member decision; it never copies the Community Pass ledger.

## Collision and donor decision

PR #128 remains donor-only and must not merge unchanged.

S1 preserves its useful business and accounting semantics:

- recurring support from $2 to $100 per month in $1 increments;
- six months for $15 once;
- twelve months for $25 once;
- one-time founding trial;
- active, recovery, cancellation, refund, dispute, and reconciliation states;
- immutable policy acceptance;
- append-only lifecycle events;
- retry-safe Stripe event inbox;
- one server-owned test/live environment boundary;
- provider and refund liabilities surviving account deletion.

S1 replaces the donor identity model:

- `community_pass_accounts.canonical_user_id` represents the Local Auth UUID;
- it has no foreign key to Swipe `auth.users`;
- subscription, purchase, entitlement, acceptance, and event rows bind through `account_id`;
- no Community Pass child table stores a permanent Swipe `user_id`;
- no browser request may supply a canonical user ID as authority.

PR #126 remains architecture and financial-policy reference material. Existing supporter tables and Stripe IDs remain historical; S1 does not rename, copy, convert, or delete them.

## File scope

| File | Purpose |
| --- | --- |
| `000_minimal_baseline.sql` | Synthetic PostgreSQL/Auth/role fixture for CI only |
| `001_private_identity.sql` | Private link, handshake, event, uniqueness, RLS, and ACL foundation |
| `002_community_pass_foundation.sql` | Canonical-user Community Pass tables, constraints, RLS, immutable evidence, and runtime config |
| `003_transition_functions.sql` | Server-only link, account, trial, active-state, and deletion transitions |
| `proof/001_s1.proof.sql` | Structural, BOLA, replay, trial, deletion, liability, and recreation proof |
| `proof/concurrency_two_client.sh` | Genuine two-client idempotency and conflict races |
| `rollback/001_s1.rollback.sql` | Synthetic disposable rollback and clean-teardown contract |
| `contracts/one-heha-s1-swipe-foundation-v1.json` | Machine-readable authority, amount, security, and proof contract |
| `scripts/verify-one-heha-s1-review.mjs` | Deterministic source and scope verifier |
| `.github/workflows/one-heha-s1-review-proof.yml` | PostgreSQL 15/17 apply, proof, concurrency, rollback, reapply, and scope gate |

No `src/`, executable migration, Edge Function, dependency, lockfile, environment, provider, or deployment file is part of S1.

## Private identity registry

### `one_heha_private.identity_links`

The active record binds:

```text
Swipe auth.users.id
  -> canonical Local Auth UUID
```

The Local UUID has no foreign key. The Swipe UUID may reference only Swipe Auth. Partial unique indexes enforce at most one active link per canonical account/environment and at most one active link per Swipe account/environment.

Browser roles and even direct service-role SQL receive no table access. Only narrow `SECURITY DEFINER` transitions may read or change the registry.

### `one_heha_private.link_handshakes`

A handshake stores:

- one request ID;
- the exact current Swipe Auth UUID;
- a hashed one-time nonce;
- verified identity classification;
- recent Swipe reauthentication time;
- later Local reauthentication time;
- a hashed one-time Local assertion JTI;
- a maximum five-minute expiry;
- pending, consumed, expired, cancelled, manual-review, or exception state.

Raw nonces, JWS assertions, passwords, OTPs, provider tokens, sessions, and email addresses are not stored.

Only `verified_non_sso` may enter the automated path. SSO, unverified, missing, ambiguous, conflicting, and deleted classifications fail closed for the later human-review workflow.

### `one_heha_private.identity_events`

Events are append-only and idempotent. The package records link request, Local verification, activation, revocation, deletion, rejection, and exception facts without retaining raw credentials or provider tokens.

## Server-only transitions

### Start handshake

`one_heha_private.begin_link_handshake` requires:

- a known Swipe Auth UUID;
- verified non-SSO classification;
- Swipe reauthentication no older than ten minutes;
- a lowercase 64-character nonce hash;
- no active link or current pending handshake;
- a server-owned test/live environment.

It returns an opaque handshake ID. S1 does not expose a browser endpoint.

### Activate link

`one_heha_private.activate_identity_link` is callable only through the trusted server boundary. It requires:

- the exact pending request and Swipe UUID;
- the canonical Local UUID from a verified Local assertion;
- Local reauthentication no older than ten minutes;
- a one-time hashed JTI;
- a valid five-minute handshake;
- no active conflicting link.

Canonical and Swipe advisory locks are always acquired in the same order. Repeating the identical request and JTI returns the same link. A different JTI, expired request, wrong account, or conflicting link fails closed.

S1 does not create a public or authenticated RPC. S2 must bind the Swipe UUID to the current verified server-side session before calling these functions.

### Community Pass account

`community_pass_private.create_or_get_account_for_swipe_user` resolves:

```text
trusted Swipe user ID
  -> active private identity link
  -> canonical Local user ID
  -> one Community Pass account
```

The function never accepts the canonical ID from a browser and cannot create an account without an active link.

### Trial activation

`community_pass_private.start_trial_for_swipe_user` preserves the donor one-time trial rule, current environment, one-open-contract boundary, invitation window, 30-day term, and append-only event. It remains service-only. The later customer endpoint belongs to S2 and must infer the Swipe user from the authenticated session.

### Canonical deletion

`one_heha_private.revoke_identity_for_canonical_user` is the S1 downstream deletion transition. It is idempotent and designed for a later signed Local request.

It performs the fail-closed order:

1. take the canonical account lock;
2. cancel pending handshakes;
3. revoke and minimize the identity link;
4. revoke active/recovery Community Pass entitlement;
5. block active member decisions;
6. move open provider subscriptions to `reconciliation_exception` rather than claiming they were canceled;
7. preserve purchase, acceptance, payment, refund, dispute, and audit liabilities;
8. replace the canonical UUID with an opaque tombstone hash;
9. write one minimized idempotent deletion receipt.

A later account using the same email receives a new canonical Local UUID and inherits nothing.

## Community Pass constraints retained

- Monthly amount: 200–10,000 cents, exact 100-cent increments.
- Quantity mirrors the whole-dollar monthly amount.
- Six-month prepaid: exactly 1,500 cents.
- Twelve-month prepaid: exactly 2,500 cents.
- Trial use becomes immutable after first activation.
- Active/open entitlement states are unique per account/environment.
- Direct browser table access is closed.
- All seven public Community Pass tables use ENABLE + FORCE RLS.
- Acceptances and lifecycle events are append-only.
- Stripe inbox events are unique by environment and event ID.

Only these entitlement states may later produce an active member decision:

- `trial_active`
- `monthly_subscription_active`
- `prepaid_term_active`

Payment recovery, cancellation, support review, suspension, expiry, deletion, refund, dispute, and reconciliation exception remain inactive for new member-only rewards or delivery waivers.

## Proof contract

The exact-head CI package must pass on PostgreSQL 15 and 17:

1. create synthetic roles and Auth users;
2. apply identity, Community Pass, and transition SQL;
3. apply the same files again;
4. verify private schemas, forced RLS, browser ACL denial, service-only function grants, and empty search paths;
5. prove the Local UUID has no cross-project foreign key;
6. prove no Community Pass child table stores `user_id`;
7. reject SSO and unverified classifications;
8. activate one dual-reauthentication link;
9. return one stable result for an identical replay;
10. reject a different JTI replay and an expired handshake;
11. derive one Community Pass account through the active link;
12. activate one trial and reject a second activation or reset;
13. prove another account cannot inherit the entitlement;
14. prove identity and Community Pass events are append-only;
15. revoke identity and entitlement before canonical deletion completes;
16. preserve an open Stripe subscription as a reconciliation liability;
17. prove deletion retries are idempotent;
18. prove a recreated account inherits nothing;
19. run genuine two-client same-request and conflicting-link races;
20. roll back every S1 object, prove clean teardown, reapply, and rerun proof.

The hosted Supabase current-schema rehearsal, generated types, security/performance advisors, and provider-compatible key handling remain R1 gates. Passing this repository CI is not a substitute for them.

## Known limitations and next packages

S1 deliberately does not include:

- Local JWS issuance or deletion orchestration — L1;
- Swipe link HTTP endpoints or signed Local member-decision endpoint — S2;
- Local linking UX, Local Deals client, or benefit integration — L2;
- real OAuth/provider reauthentication;
- key generation, secret storage, key rotation, environment variables, or network calls;
- current-schema Supabase apply or data migration;
- Stripe test or live events;
- legal/privacy/retention approval;
- real user or partner reconciliation.

R1 remains a separate approval. No paid or hosted environment may be created from S1 alone.

## Safety boundary

No Production authorization.

This package authorizes only reviewable source, synthetic PostgreSQL proof, and exact-head CI. It does not authorize merge, standard migration placement, Supabase apply, Auth export/import/link/delete, real account linking, real data access, environment secrets, Edge Function deployment, Stripe product/Price/Checkout/subscription/invoice/charge/refund changes, billing, entitlement activation, HEHA Credit, delivery waivers, customer communication, app publication, DNS, or launch claims.
