# Store release database review packet

These files are deliberately outside `supabase/migrations`. They are evidence and
review material only; repository CI, Capacitor sync, and store builds must never
apply them.

## Live reconciliation — 2026-09-04

The HEHA Swipe project was inspected read-only.

- `account_deletion_requests` has the required columns, RLS is enabled, its
  existing own-row policies use `auth.uid() = user_id`, and there is no duplicate
  `user_id` group. Browser roles currently have table privileges broader than
  the request flow needs.
- Anonymous access can read 101 rows from the 56-column `public.partners` table.
  Some rows expose owner/contact/phone/routing/economic fields, and two rows fall
  outside the intended store eligibility gate.
- The three legacy public partner views are also broad. The in-repo directory
  embed used `public_partner_directory`; it is cut over in this PR. Use of
  `public_local_partners` by HEHA Local, Wix, Make, or another external consumer
  is not yet disproved.

These findings are evidence for review, not approval to apply SQL.

## Deletion request packet

`001_request_my_account_deletion.sql` narrows direct access to:

- SELECT only on `id, user_id, status, created_at` for `authenticated`;
- INSERT only on `user_id, email, reason` for `authenticated`;
- no table privilege for `public` or `anon`;
- the two existing own-row policies restricted to `authenticated`.

It also adds the idempotent no-argument receipt RPC and one-request-per-user
index. Before any authorized database change:

1. Reconfirm columns, defaults, policy names, grants, constraints, and duplicate
   count still match the documented preconditions.
2. Review the SQL with the Supabase owner. Do not discard historical requests.
3. Apply manually only after explicit production approval, then call the RPC
   twice as a non-admin authenticated test user. Preserve evidence that both
   calls return the same receipt without adding a duplicate row.

## Partner data packet

This is intentionally split:

- Phase A — `002_public_partner_card_projection.sql`: add two zero-argument,
  fixed-schema RPCs. Swipe gets exactly 13 store-card fields; the public directory
  gets exactly 17 website fields. The PR clients now call these RPCs and fail
  closed because the RPCs do not exist live.
- Phase B — `003_close_legacy_partner_browser_paths.sql`: revoke the three wide
  views for every browser role, remove public/anonymous base-table access and
  broad public/saver policies, then preserve authenticated owner/internal
  SELECT/INSERT/UPDATE only through the reviewed RLS boundary.

Do not preview-deploy or production-deploy the current client head until Phase A
has received separate database approval, been applied, and passed anon/auth smoke
proof. Do not apply Phase B until HEHA Local, Wix, Make, website, and every other
consumer has a certified bounded replacement or verified non-use.
Track owners and evidence in
`docs/store-release/EXTERNAL_CONSUMER_CERTIFICATION.md`. Every Phase-B and
pricing cell remains **NOT CERTIFIED** until its own evidence is complete;
absence from a repository search never proves non-use. Phase A is limited to
the two additive RPC callers and is `N/A` for unrelated consumers.
Any staging apply requires explicit approval for that exact packet first.
Staging proof never authorizes production or another packet.

Required Phase B proof:

1. Anonymous reads of `partners` and every legacy view are denied;
   authenticated reads of every legacy view are denied.
2. Each RPC returns only its exact typed fields and exactly the eligible ID set.
3. Browser roles cannot DELETE, TRUNCATE, REFERENCES, or TRIGGER `partners`.
4. Ordinary authenticated users cannot read another owner's private row.
5. Authenticated owner and internal-role SELECT/INSERT/UPDATE flows still pass
   only within their RLS boundaries.
6. HEHA Local, Wix, Make, and website smoke tests pass on their replacements.

The SECURITY DEFINER RPCs are intentional and bounded by zero arguments, fixed
typed outputs and predicates, an empty search path, fully-qualified sources, and
no dynamic SQL.


## Legacy pricing view

`004_harden_heha_pricing_access.sql` changes only the existing view's security
mode and privilege matrix; it never recreates the view or repeats pricing
constants. It remains blocked on Wix, Make, HEHA Local, and other external
consumer inventory. Before any separately approved staging apply, snapshot the
view definition hash, owner, relation type/options, and exact ACL. Prove those
structural values remain unchanged apart from `security_invoker=true`, browser
roles have no privilege, `service_role` has SELECT only, external consumers
pass, and the database advisor error clears.

Account deletion remains a request workflow until an authorized administrator
removes the Supabase Auth identity and associated personal records. The client
must not clear roles, delete partial rows, or state that deletion is complete.
