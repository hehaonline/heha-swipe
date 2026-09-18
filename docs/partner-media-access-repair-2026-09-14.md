# PAR-023/PAR-028 media access repair — September 14, 2026

Based on PR #140 at 108c668a3cbea393c0d8427740c74848c95c929e.
This is a review branch. No hosted migration, real account, claim, photo upload,
publication, payment, partner email or Production deployment is authorized by it.

## Changes

- Carry the existing owner-path v2 repair into a forward migration, byte-for-byte
  SHA-256 1d71a7b25cb35833064a2a26d297e0efe8d4fe9fe33c03b791229ddd8e4f0d26.
  Its three policies now bind the storage object path instead of partners.name.
  Unexpected existing policy definitions abort; reapplication is supported.
- Add a separate internal assisted-intake RPC. Only a permanent, verified account
  with an existing super_admin, developer_admin or pm_admin role can submit.
  It requires a real private storage object at actor/partner/file, exact metadata,
  source and rights-reference evidence. The queue remains submitted; no partner
  ownership, public media, consent or Local state changes. In this legacy queue
  owner_id identifies the submitting actor, not a grant of business ownership.
- Add private intake receipts and idempotent request IDs. An exact retry returns
  one request; conflicting retry input, duplicate photo, absent file, missing
  rights evidence, foreign uploader path and unauthorized actors are denied.
- Extend the existing isolated integration proof with the real retained media
  foundation and both forward repairs. No new scheduler or outreach worker.

## Verification

Node 22.22.0: existing claim-flow suite 35/35; application build passed.
Native PostgreSQL 17.6: 26/26 new behavioral checks passed against the existing
current-main integration fixture plus real media foundation and real verified
recipient helper. Native pgcrypto is unavailable, so that local check does not
include the full lifecycle/claim chain. Existing isolated Supabase CI is the
full-chain verification gate. The native fixture models Auth/Storage metadata;
it is not proof of Auth email delivery or Storage API photo bytes.

## Remaining release evidence

Exact-code independent review, full-chain isolated Supabase result, actual
Auth-email -> same-card claim -> edit/save -> Storage API upload/review ->
logout/login with wrong-recipient/cross-business/retry negative cases, and the
existing separate human release decision remain required. No live success is
claimed. Staff-submitted files remain internal review material; this patch does
not publish them or grant a future claimant access to a staff-owned path.
The account holder must not be told to resend already approved Sweetwater media.

## Rollback

Before apply: do not merge/release this review branch.
After any separately approved apply: prefer a reviewed forward correction.
Owner-policy reversion reintroduces the known valid-upload failure and is not
an acceptable silent fallback. Staff intake can be disabled by revoking EXECUTE
on its exact RPC signature; retain evidence/requests. Do not delete submitted
data, make the bucket public or assign HEHA ownership as rollback.

## Combined proof findings and follow-on

First full-chain run 34854286840 reached the media proof after the complete
claim migrations, then rejected its direct SQL DELETE via storage.protect_delete.
The test now respects that real safeguard; actual byte read/delete is exercised
through Storage API instead. No storage safeguard was removed.

The existing profile editor also retained raw authenticated partners UPDATE for
preapproval records, which final #140 permissions prohibit. All ordinary edits
now use the already-supported private review queue; no fields or grants were
expanded. The existing latest-request check avoids a second active submission.
The synthetic integration baseline includes the real profile queue and exact
current multi-category request guard.

The new localhost-only API proof uses actual GoTrue verified synthetic fixtures,
PostgREST claim/review submission, Storage byte upload/private signed read/delete,
wrong-recipient/cross-business/duplicate denials and logout/login persistence.
It does not prove email delivery, browser rendering, recovery or Production.

## Verified results

- Full isolated Supabase workflow 34856440940 succeeded at runtime/test commit
  2cbfe3368f08e754392f933a20c9bac85f9d3e3b, including the complete lifecycle and
  publication chain, its concurrency/negative controls, and 24 media SQL checks.
- Actual localhost Auth/PostgREST/Storage API proof: 14/14. Correct same-card claim,
  wrong recipient and reused claim denied, profile changes persisted, byte upload,
  exact private signed read, cross-business/duplicate denials, logout/login,
  real Storage API deletion, and unchanged public images.
- Desktop 1440x1000 and mobile 390x844: actual editor rendered with production CSS;
  changing a pending profile created exactly one mocked review request and
  prevented a second submission. No horizontal overflow. Screenshots and the
  clearly scoped UI/API receipts are under review-evidence/partner-media-20260914.
- Node 22.22.0 focused claim tests: 35/35; application build passed.
- Added the two forward migration entries and byte hashes to the existing
  repository compatibility packet; preserved historical ledger rows and all
  negative-control checks. They are review candidates, not live equivalence or
  independently approved migrations. Map/evidence/semantic-negative checks pass
  locally; Linux descriptor-containment verification requires the existing CI.

The two unsuccessful earlier CI attempts are retained as test-development
evidence. Both respected the provider's direct-delete protection; final deletion
checks use Storage API, without disabling the protection.
