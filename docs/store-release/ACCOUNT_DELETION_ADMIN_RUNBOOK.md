# Account deletion administrator runbook

This is a review-only operating packet. It does not authorize database changes
and it is not executed by CI.

## Request receipt

The native client calls `request_my_account_deletion()` with no arguments. The
function derives the user from `auth.uid()` and returns:

- `request_id`
- `status` (`requested` or `already_requested`)
- `requested_at`

The review-only function serializes calls per authenticated user. A repeat or
concurrent call must return the same non-null `request_id` and `requested_at`
without creating another row. Its documented live-table columns, grants, and
RLS policies are preconditions—not assumptions to apply blindly.

The function draft is under `supabase/review_only/store_release`. Until an
authorized owner reviews and applies it, in-app deletion correctly surfaces an
unavailable/support message instead of claiming success.

## Authorized processing checklist

1. Open the deletion request using its receipt ID in the trusted admin context.
2. Verify account ownership using the authenticated request and, if necessary,
   a reply from the account email. Never request a password or verification code.
3. Record legal or operational retention requirements before deletion.
4. Rehearse the review-only `005_fulfill_account_deletion.sql` procedure
   against a disposable account. It must refuse any partner, order, payment,
   subscription, or contribution record requiring case-specific retention.
5. With explicit action-time production approval for the exact request receipt,
   run the trusted service-role procedure once. It deletes bounded personal
   records and the Supabase Auth identity in one transaction while preserving
   only a de-identified completion receipt. Never expose a service-role key to
   the client.
6. Confirm the account can no longer sign in and no unintended partner/business
   records were removed.
7. Mark the request complete in the trusted admin record and notify the user.

The live request row currently cascades with the Auth identity, so completion
must not rely on that row. The separate receipt stores only request/timing and
per-table counts—never email, user ID, reason, or profile content. The app
message remains “requested” until the process is complete. Partial client-side
deletes, role clearing, and unverified completion claims are prohibited.
