# Partner identity reconciliation — review-only plan

**Issue:** #121  
**Reviewed base:** `main@82ec41a27150847f3d461716bc58636e24babfe6`  
**Status:** documentation and synthetic proof only; deployment frozen  
**Decision owner:** a named human reviewer; never this tool or PR

## Boundary

This lane helps reviewers identify possible duplicate or split partner profiles. It does **not** query Production, select a canonical partner, merge or delete rows, repoint references, issue a claim, infer ownership, publish a profile, enforce uniqueness, or modify PR #120. Every output is a private review candidate with `mutation_allowed=false` and `canonical_partner_id=null`.

Evidence labels used below:

- **[RP] repository-proven:** present in the reviewed repository base.
- **[S] synthetic proof:** exercised only by the fixtures and offline tests in this PR.
- **[U] unresolved:** requires a separately authorized catalog/metadata review or named-human evidence.

No real partner or customer identifiers belong in GitHub. Running the catalog inventory against a live system is outside this PR.

## Repository identity and reference inventory

| Family | Repository evidence | Reconciliation requirement |
|---|---|---|
| Canonical profile | **[RP]** `public.partners.id` is the permanent Swipe identifier. | Never replace it by inference; a named human must identify the surviving ID. |
| Owner/account | **[RP]** `partners.owner_id` links an authenticated owner. Owner-scoped policies and change requests depend on it. | Two different non-null owners are a conflict and override matching business signals. Never move ownership in this lane. |
| Strong signals | **[RP]** `google_place_id`, `website`, `phone`/`contact`, and `instagram` exist in current partner flows. | Normalize only for comparison. An exact Place ID or at least two independent exact normalized signals forms a strong candidate, still manual-only. |
| Email provenance | **[RP]** Scout ingestion maps `scout_leads.email` into `partners.contact`; current repository evidence does not prove that every `contact` is an email or an owner-controlled address. | Treat normalized email as strong only with provenance; otherwise mark **[U]**. |
| Name and location | **[RP]** `name`, `location`, `neighborhood`; Scout also holds address/city/state/postal code. | Name + location alone is only a likely match. Similar names with conflicting locations stay separate. |
| Scout link | **[RP]** `scout_leads.partner_id` and Scout-triggered readiness/HubSpot artifacts. | Preserve the lead link and provenance; never create a partner automatically during reconciliation. |
| Customer interest | **[RP]** the app uses `saves`; **[U]** the complete live event lineage is not proven here. Current app/donor vocabulary includes `swipe_events` and `swipes`, which must not be silently treated as the same table. | Inventory and preserve saves, swipe history, and analytics/event rows by their actual catalog names before any approved action. |
| Profile changes | **[RP]** `partner_profile_change_requests.partner_id` and `owner_id`. | Preserve immutable request history, reviewer state, and owner provenance. |
| Media | **[RP]** `partner_media_requests.partner_id`, owner, storage path and replacement lineage; partner profile media fields also exist. | Inventory both row references and storage-object ownership. No media move or rights inference in this lane. |
| Offers/requests | **[RP]** partner-originated community/deal requests reference partner and owner. Other request families remain **[U]** until catalog inventory. | Preserve every request, state transition and audit record. |
| Routing and visibility | **[RP]** Local lane, CTA destination/path, routing status/notes, platform visibility and readiness/HubSpot artifacts key to a partner ID. | Preserve the approved/suggested state and reviewer provenance; never infer orderability or public eligibility. |
| Categories/profile fields | **[RP]** partner category and multi-category logic, bio, hours, offerings, delivery and pricing-related fields are profile state. | Treat as payload to preserve, not identity proof unless a named reviewer explicitly authorizes it. |
| Claim/agreement evidence | **[U]** related donor lanes contain claim/relationship concepts but are not merged into this base. | Inventory later; unresolved claim evidence blocks reconciliation and publication. |
| Local bridge | **[U]** Order Hub #161 proposes storing the Swipe UUID value as `swipe_partner_id`; cross-project FK enforcement is neither present nor authorized here. | Never invent a cross-project FK. Inventory Local references separately and require a named cross-project decision. |

The catalog-only SQL reports metadata that can refine this inventory in a disposable clone. Any family absent from repository migrations remains unresolved rather than assumed absent.

## Deterministic classification precedence

Classification stops at the first applicable row:

1. `non_partner_source` — either record is a shopping/source-only record. It cannot become claimable or Official Partner by inference.
2. `ownership_conflict` — the candidates have different non-null owners and at least one matching identifier. Freeze claims and escalate.
3. `strong_identifier_match` — exact Google Place ID, or at least two independent exact normalized signals from domain, phone, email-with-provenance, or Instagram plus similar name or exact address.
4. `likely_match` — one normalized signal, or exact normalized name + address, without conflicting ownership.
5. `separate_businesses` — same/similar name but conflicting place, domain, phone, email, Instagram, owner, or location evidence.
6. `insufficient_evidence` — no deterministic relationship can be supported.

All six classes are fail-closed. Even `strong_identifier_match` means only “prepare a private dry run.” It never authorizes a canonical ID, mutation, claim, Official Partner status, routing, or publication.

## Normalization contract

The offline reporter uses deterministic standard-library normalization:

- Unicode compatibility decomposition, lowercase, punctuation collapse and whitespace collapse for names/addresses;
- lowercase host only, with `www.` and trailing dot removed, for domains;
- digits only, with a leading U.S. country code removed, for phones;
- lowercase trim for email;
- URL/`@` removal and lowercase for Instagram;
- exact trimmed comparison for Google Place ID and owner ID.

Normalization never changes source data. The report includes only record IDs and matched/conflicting field names, not raw identifier values.

## Private reconciliation queue contract

This is a design contract, not a migration. A future private queue must be admin-only and contain:

- immutable `reconciliation_case_id`, schema version and created time;
- candidate permanent IDs or non-sensitive fingerprints, never copied PII;
- classification, evidence types, provenance and evidence timestamps;
- `decision_status` beginning at `pending_named_human_review`;
- `canonical_partner_id` nullable and always null before approval;
- `mutation_allowed` default false;
- named reviewer ID, decision time, reason and approval scope;
- dry-run receipt hash, before-count manifest and affected reference families;
- execution receipt hash, exact code/migration SHA and per-family after counts if a later separately approved operation occurs;
- forward compensating-restore receipt linked to the original receipt;
- append-only audit events. Corrections add a new event; they never rewrite a prior decision.

The queue must be private by default, deny anonymous/authenticated partner access, and provide no public view or claim endpoint.

## Synthetic preservation manifest

Fixtures carry counts for every currently required family:

`saves`, `swipes`, `analytics`, `requests`, `media`, `routing`, `local_bridge`, `profile_changes`, `offers`, `readiness`, `platform_visibility`, and `crm_links`.

The reporter copies those counts unchanged into each candidate pair. **[S]** Tests prove no count or family disappears and no canonical ID is emitted. This is not evidence that the live schema uses these exact table names; that remains **[U]**.

## Initial named-business checklists

These checklists intentionally contain no IDs, contacts, values, or conclusions.

### Pure Kitchen — **[U]**

- [ ] Gather separately authorized strong identifiers and their provenance.
- [ ] Verify each owner/account link with the named business owner or delegate.
- [ ] Inventory every child-reference family and Local `swipe_partner_id` value.
- [ ] Confirm which public/unclaimed profiles are the same business, if any.
- [ ] Produce a dry-run receipt; stop for the named-human canonical decision.

### The Mediterranean Chickpea — **[U]**

- [ ] Distinguish owner, operational delegate, Scout/Square/messenger records and profile identities.
- [ ] Gather authorized strong identifiers without copying them into GitHub.
- [ ] Inventory child references and public/routing state.
- [ ] Produce a dry-run receipt; stop for the named-human decision.

### Orawganic / All Raw Organic — **[U]**

- [ ] Determine whether the names are aliases, a rename, or separate identities using authorized evidence.
- [ ] Verify owner/account authority and preferred canonical public wording separately.
- [ ] Inventory child references, media rights and Local linkage.
- [ ] Produce a dry-run receipt; stop for the named-human decision.

### Trader Joe’s shopping-source boundary — **[U]**

- [ ] Classify shopping-source records as `non_partner_source`.
- [ ] Do not infer consent, ownership, claimability, Official Partner status or publication rights.
- [ ] Keep source/order provenance separate from partner identity.
- [ ] Escalate any proposed partner relationship through its own authorized consent flow.

## Review-only dry-run sequence

1. Run unit tests and the reporter only against the committed synthetic fixture.
2. In a disposable clone, and only under a separate authorization, run the catalog-only SQL. It reads metadata, never application rows, and rolls back.
3. A named reviewer may later provide explicitly authorized sanitized metadata to a private environment; never commit it.
4. Generate candidate classifications and a preservation manifest.
5. Stop. A named human either rejects, keeps separate, requests more evidence, or authorizes preparation of a distinct mutation plan.

No output from this PR is executable approval.

## Future forward-only plan (not authorized here)

Only after an individual named-human decision and a separate Production change approval:

1. Pin exact source and target IDs, environment, schema SHA and code SHA in an approval receipt.
2. Acquire a concurrency guard; revalidate owners, claims, status, identifiers and per-family counts.
3. Snapshot both profiles and every child family to a private immutable receipt.
4. Preserve both permanent IDs. Add an explicit private redirect/alias ledger only if separately designed and approved; do not delete the losing profile.
5. Repoint one audited family at a time with idempotency keys and before/after counts. Cross-project Local updates are a separate named operation.
6. Reconcile owner and claim evidence before any profile can become claimable or Official Partner.
7. Verify saves, swipe/event history, analytics, requests, media/storage, routing, Local linkage, profile changes, offers, readiness, visibility and CRM links.
8. Keep publication and routing disabled until an independent review verifies the receipt.

### Compensating restore

Rollback is forward-only: append a restore receipt, replay each family to the captured source ID, verify counts and visibility, and retain both the original and compensating receipts. Never erase audit history, delete the redirect ledger, or rely on reversing a migration file.

## No-go conditions

Stop when any of the following is true:

- owner or claim evidence conflicts or is missing;
- fewer than the required strong signals are proven;
- a child-reference family, storage object, Local reference or audit lineage is unknown;
- a concurrent profile/claim/media/request change occurred after the dry run;
- the dry-run environment, schema SHA or code SHA differs from the approved execution target;
- counts do not reconcile exactly;
- publication, routing, payment, orderability or compensation could change;
- the named reviewer, approval scope, restore plan or independent review is absent.

## Verification

```bash
python3 -m unittest discover -s tests -p 'test_partner_reconciliation.py'
python3 scripts/partner_reconciliation_report.py \
  --input fixtures/partner-reconciliation/synthetic_partners.json \
  --output /tmp/partner-reconciliation-report.json
python3 -m json.tool /tmp/partner-reconciliation-report.json >/dev/null
npm run build
git diff --check
```

Passing these checks proves only deterministic synthetic reporting and documentation integrity. Exact-head ChatGPT/Nova architecture/security review is required before any authorized metadata exercise or real reconciliation decision.
