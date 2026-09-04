# External consumer certification ledger

Status: **review-only inventory; no consumer is presumed certified**.

This ledger controls whether the Phase-A bounded RPCs and the Phase-B legacy
browser-path closure in `supabase/review_only/store_release` may progress. It is
not approval to contact a consumer, apply SQL, deploy a client, change a
credential, or publish data.

## Certification rules

- `Unassigned` is intentional until a person accepts responsibility; product or
  company names are not accountable owners.
- `Unknown` and repository-search absence are not evidence of non-use.
- A certification needs a named owner, the exact endpoint/object and credential
  class, dated last-use evidence, and a reproducible replacement or non-use
  proof.
- Phase A means the consumer's bounded replacement is proven against the exact
  13-field Swipe or 17-field directory RPC contract, when applicable.
- Phase B means closing `partners`, `public_swipe_partners`,
  `public_partner_directory`, and `public_local_partners` to browser roles has a
  passing consumer smoke test or verified non-use. Pricing access is tracked
  alongside this gate because the separate `heha_pricing` hardening packet has
  the same external-consumer dependency.
- Every row remains **NOT CERTIFIED** until its evidence fields are completed.

## Inventory

| Consumer / surface | Accountable owner | Current status | Evidence | Last-use evidence | Phase A certification | Phase B certification |
| --- | --- | --- | --- | --- | --- | --- |
| HEHA Swipe store-card reader | Unassigned | Code cut over; live RPC unavailable/unverified | `src/lib/publicPartner.js` calls `list_public_swipe_partner_cards`; contract tests cover 13 fields | Unknown; no dated hosted smoke receipt | NOT CERTIFIED — code-ready only | NOT CERTIFIED — requires Phase-A hosted anon/auth smoke before any client deployment |
| HEHA website partner-directory embed | Unassigned | Code cut over; hosted embed unverified | `src/components/embed/PartnerDirectoryEmbed.jsx` calls `list_public_partner_directory`; contract tests cover 17 fields | Unknown; no dated hosted/Wix page smoke receipt | NOT CERTIFIED — code-ready only | NOT CERTIFIED — replacement and Wix-hosted embed must pass after Phase A |
| HEHA Swipe authenticated owner/internal UI | Unassigned | Discovered direct `partners` SELECT/INSERT/UPDATE consumer; hidden from the store channel where policy requires | `src/App.jsx`, `ProfileTab.jsx`, `CommunityPassTab.jsx`, `PartnerWizard.jsx`, `PartnerProfileEditor.jsx`, and `admin/routing/RoutingDashboard.jsx` | Unknown; no current owner/internal role smoke receipt | N/A — not a public-reader replacement | NOT CERTIFIED — owner and internal-role RLS flows must pass after the proposed regrant |
| HEHA HubSpot sync edge function | Unassigned | Discovered service-role `partners` reader; Phase B intends to leave service-role access untouched | `supabase/functions/hubspot-sync/index.ts` | Unknown; no current function invocation receipt | N/A — service integration | NOT CERTIFIED — prove the service path is unchanged without exposing browser access |
| HEHA Local | Unassigned | External/non-code use not disproved; possible `public_local_partners` and/or `heha_pricing` dependency | No connected repository code hit found on 2026-09-04; this is not non-use proof | Unknown | NOT CERTIFIED — replacement interface and credential class unknown | NOT CERTIFIED — hard blocker |
| Wix | Unassigned | External configuration not inspected; website embed is documented, but direct data/pricing use is unknown | In-repo embed replacement exists; no Wix configuration/export or owner attestation | Unknown | NOT CERTIFIED — hosted embed/replacement not proven | NOT CERTIFIED — hard blocker |
| Make | Unassigned | External scenarios/connections not inspected; partner/pricing use is unknown | No scenario export, connection inventory, run receipt, or owner attestation | Unknown | NOT CERTIFIED — replacement interface and credential class unknown | NOT CERTIFIED — hard blocker |
| Other external or non-code consumers | Unassigned | Discovery open | No complete Supabase API-log, credential, webhook, automation, or integration inventory | Unknown | NOT CERTIFIED | NOT CERTIFIED — hard blocker until discovery closes |

## Evidence checklist per consumer

- [ ] A named owner accepts the row.
- [ ] Record the exact object/RPC, fields used, authentication role, environment,
      and caller origin without storing secrets here.
- [ ] Attach a dated last-successful-use receipt or an owner-attested non-use
      record with the search scope and date.
- [ ] Map the consumer to a bounded Phase-A replacement, or mark Phase A `N/A`
      with a reviewed reason.
- [ ] Run a provider-safe replacement smoke test and preserve the result.
- [ ] Run the Phase-B denial/preservation smoke in a separately authorized
      staging context.
- [ ] Obtain explicit database approval only after every Phase-B row is
      certified; production remains a separate decision.

## Current discovery boundary

A read-only GitHub organization search on 2026-09-04 found legacy partner-view
references only in the `heha-swipe` repository. That search cannot see Wix
configuration, Make scenarios, Supabase API clients, locally stored scripts,
third-party credentials, or HEHA Local code outside the connected/default-branch
search scope. It therefore leaves all external rows **NOT CERTIFIED**.
