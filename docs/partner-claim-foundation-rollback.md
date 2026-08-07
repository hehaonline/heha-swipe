# Partner claim foundation: review, test, and rollback

Migration: `20260807160000_partner_claim_foundation_v2.sql`

This corrective migration supersedes the never-merged draft PR #82 migrations (`20260716090000_partner_claim_foundation.sql` and `20260718194500_fix_partner_claim_profile_ambiguity.sql`) and remains review-only. Do not apply it until migration lineage is reconciled and the rollback-only proofs pass in a non-production Supabase environment.

## Deterministic ACL boundary (v2)

`public.partner_claim_invites` starts from `REVOKE ALL` for `PUBLIC`, `anon`, `authenticated`, and `service_role`, then grants back only:

- `authenticated`: `SELECT` (filtered by the internal-role RLS policy)
- `service_role`: `SELECT`, `INSERT`, `UPDATE`, `DELETE`

`TRUNCATE`, `REFERENCES`, and `TRIGGER` are denied to every client role and are covered by behavioral denial proofs, because RLS does not govern those three privileges. The four claim RPCs use the same revoke-then-grant pattern (`EXECUTE` for `authenticated` and `service_role` only).

## Claim-administration and recipient boundary

Claim invitation administration is limited to `super_admin`, `developer_admin`, and `pm_admin`. `som_admin` is intentionally unsupported by this claim flow; any future SOM permissions require a separate role-model review.

Every invitation is bound to exactly one intended recipient in addition to its hashed one-time token:

- an existing Auth account is stored as `intended_user_id`; or
- a not-yet-created account is stored as `intended_email_normalized` using only `lower(trim(email))`.

The separate `recipient_hint` is server-generated and masked. Claim and preview RPCs compare the binding with `auth.uid()` or the confirmed Auth email before ownership or invitation state can change. Recipient mismatch fails closed and does not consume or revoke the invitation.

## Required proof run

Choose two disposable, unclaimed partner rows, two ordinary Auth users, and one Auth user with an allowed active internal role. Run:

```sh
psql "$NON_PRODUCTION_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -v partner_a_id=... \
  -v partner_b_id=... \
  -v user_a_id=... \
  -v user_b_id=... \
  -v internal_admin_user_id=... \
  -f supabase/tests/partner_claim_foundation_proof.sql
```

The proof runs inside `BEGIN` / `ROLLBACK`. It checks grants, invalid/expired/revoked/reused tokens, canonical Partner ID preservation, the ownership-only mutation boundary, and Business A versus Business B isolation.

Two additional self-contained rollback proofs run against the synthetic baseline fixture (`supabase/tests/fixtures/partner_claim_minimal_baseline.sql`):

```sh
psql "$NON_PRODUCTION_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/partner_claim_extended_proof.sql
psql "$NON_PRODUCTION_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/partner_claim_acl_matrix_proof.sql
```

`partner_claim_acl_matrix_proof.sql` asserts the full seven-privilege table matrix (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER) for `PUBLIC`, `anon`, `authenticated`, `service_role`, and the object owner, plus behavioral 42501 denials for TRUNCATE, REFERENCES-dependency creation, TRIGGER creation, and direct DML. `.github/workflows/partner-claim-proof.yml` runs all three proofs in a disposable Supabase stack in CI.

## Pre-apply snapshot

Before any approved apply, record counts and export the affected rows from:

- `public.partners` for rows with an existing `owner_id`
- `public.partner_claim_invites` if the table already exists in the target
- `public.admin_audit_logs` for `partner_claim_%` actions

Also record the current definitions and grants for the four claim RPCs and `app_private.set_partner_listing_origin()`.

## Rollback decision

Prefer a forward corrective migration after any claim has been issued or consumed. Dropping the table after real use destroys security/audit evidence and is not an acceptable routine rollback.

The destructive rollback skeleton at the end of the migration may be used only when all of these are true:

1. No invitation has been distributed.
2. No invitation has been consumed.
3. The pre-apply snapshot is retained.
4. The designated independent technical reviewer for the current phase (currently Nova, per the phase ownership recorded on the successor PR) approves the exact target and statements, and Geronimo authorizes any execution against a shared or production environment. Destructive rollback must never be self-approved by the implementer.

If a claim has occurred, disable new invite creation by revoking authenticated execution on `create_partner_claim_invite`, preserve invite/audit rows, and ship a reviewed forward migration. Do not clear `owner_id`, delete partners, or rewrite canonical Partner IDs as an emergency rollback.

## Explicit non-effects

Applying or rolling back this foundation must not change listing publication, HEHA Partner status, HEHA Certified status, routing, Local eligibility, product approval, payment, dispatch, or outbound messaging.
