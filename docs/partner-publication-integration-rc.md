# Partner publication integration release candidate

## Exact source refs

| Source | SHA | Role |
|---|---|---|
| `main` | `82ec41a27150847f3d461716bc58636e24babfe6` | RC base |
| PR #118 | `a83e41225b6c1b75d9f0132341c3c759f01018c9` | publication-consent donor |
| PR #120 | `8a5ebee906fdf3b146974bb7e6031d214e888fa5` | claim, partnership, agreement, and listing lifecycle donor |
| PR #124 | `5c57e7766c4586e0bc479058e80be7dff7de5d08` | public-projection privacy contract and proof donor |

The donor PRs remain draft and must not be merged or applied independently. This
RC is the only combined release lane. It does not authorize a Production
migration, deployment, claim invitation, partner publication, or outreach send.

## Required migration order

1. `20260810072829_wave1_partner_publication_consent.sql`
2. `20260811090000` through `20260811090600` hybrid lifecycle migrations
3. `20260817154529_hybrid_partner_security_reconciliation.sql`
4. `20260817154927_hybrid_partner_claim_recipient_contract.sql`
5. `20260817171238_partner_publication_integration_rc.sql`

The RC copy of `20260811090000` must not replace the consent-aware public view
created by the earlier migration. PostgreSQL cannot use `CREATE OR REPLACE VIEW`
to turn that established 33-column contract into the donor's reordered 59-column
view. The final integration migration is the sole final owner of the private
publication projection and all three public partner views.

## Public boundary

- Anonymous users cannot select the raw `partners` table.
- Public views expose exactly the reviewed 33-column allowlist.
- Owner IDs, contact details, phone numbers, routing notes, review actors,
  analytics, lifecycle fields, and internal pricing remain private.
- Visibility requires an approved/live non-test row, `listing_status='listed'`,
  destination eligibility, current owner consent, an exact current content
  snapshot, and a separate exact-hash HEHA staff publication review.
- A pending partner cannot move to approved/live through owner consent alone.
  The supported transition requires a HEHA staff review of the exact current
  profile hash; any drift or missing review remains fail-closed.
- Website-directory publication is a separate destination and remains disabled
  until its own explicit, versioned directory consent is implemented. HEHA
  Swipe consent must never be reused as website-directory consent.
- Owner consent never grants Official Partner status. Public `heha_partner` is
  derived only from `partnership_status='official_partner'`.
- Withdrawal, profile drift, listing opt-out/removal, owner release, or stale
  staff review hides the row without deleting the canonical partner ID.
- Targeted HEHA Local routing stays disabled until a least-privilege exporter or
  outbox is implemented and independently proven.

## Release evidence gates

- Combined lexical migration proof on the literal PR head.
- Consent, withdrawal, staff-review separation, former-owner isolation, BOLA,
  non-forgeable internal authority, exact columns, and negative controls.
- Existing claim, agreement, deletion, wall-clock expiry, and multi-session
  concurrency proofs.
- Corrective migration reapplication and application tests/build.
- A current-schema Supabase branch or clone. The synthetic fixtures are necessary
  CI evidence but are not sufficient Production release evidence because the
  repository's historical migration chain is not a reliable fresh-reset lineage.
- Fresh security review after every exact-head repair.
- Founder/legal approval of the exact versioned partner terms and privacy copy,
  plus the matching acceptance predicate and evidence contract. This is a hard
  release blocker; draft placeholders or generic profile permission do not
  satisfy it.
