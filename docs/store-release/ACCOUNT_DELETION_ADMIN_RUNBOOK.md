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
4. Inventory every local foreign-key reference and external processor record,
   including incomplete Stripe Checkout Sessions, before destructive work.
5. Use a reviewed design that blocks writes from already-issued access tokens,
   serializes retained-record creation with the deletion decision, and preserves
   de-identified completion evidence after the live request row cascades.
6. Rehearse the complete design against a disposable account, including stale
   sessions, delayed webhooks, concurrent writes, retries, and retained history.
7. Obtain explicit action-time approval for the exact production procedure and
   request before deleting anything. Never expose a service-role key to a client.
8. Confirm sign-in and stale-session writes fail, no unintended business records
   were removed, the de-identified completion receipt exists, and then notify
   the user. Do not attempt to update the cascaded request row.

No fulfillment procedure is approved or included in the release candidate.
The app message remains “requested” until the full process is complete. Partial
client-side deletes, role clearing, and unverified completion claims are
prohibited.
