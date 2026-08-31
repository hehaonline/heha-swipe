# Store release database review packet

These files are deliberately outside `supabase/migrations`. They are evidence and
review material only; repository CI, Capacitor sync, and store builds must never
apply them.

Before any authorized database change:

1. Confirm the live `account_deletion_requests` columns, defaults, grants, RLS
   policies, and constraints match the preconditions documented in the SQL.
   Reconcile any duplicate `user_id` rows before reviewing the required unique
   index; do not discard historical requests automatically.
2. Review `001_request_my_account_deletion.sql` with the Supabase owner.
3. Apply it manually only after explicit production approval, then test as a
   non-admin authenticated account. Call it twice and preserve evidence that
   both calls return the same receipt without adding a duplicate row.
4. Review the dedicated public projection in
   `002_public_partner_card_projection.sql`; compare its 13 fields with
   `src/lib/publicPartner.js` before considering a client view-name switch.
5. Verify grants, RLS behavior, and that internal fields cannot be selected.

Account deletion remains a request workflow until an authorized administrator
removes the Supabase Auth identity and associated personal records. The client
must not clear roles, delete partial rows, or state that deletion is complete.

Release activation remains blocked until both the dedicated 13-field public
projection and deletion RPC have been reviewed, applied with separate approval,
and verified against the live project. The client-side field allowlist is not a
substitute for the backend projection.
