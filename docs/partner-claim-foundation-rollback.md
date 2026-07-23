# Partner claim foundation: review, test, and rollback

Migration: `20260716090000_partner_claim_foundation.sql`

This migration remains review-only. Do not apply it until migration lineage is reconciled and the rollback-only proof passes in a non-production Supabase environment.

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
4. Shahid approves the exact target and statements.

If a claim has occurred, disable new invite creation by revoking authenticated execution on `create_partner_claim_invite`, preserve invite/audit rows, and ship a reviewed forward migration. Do not clear `owner_id`, delete partners, or rewrite canonical Partner IDs as an emergency rollback.

## Explicit non-effects

Applying or rolling back this foundation must not change listing publication, HEHA Partner status, HEHA Certified status, routing, Local eligibility, product approval, payment, dispatch, or outbound messaging.
