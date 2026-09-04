# External consumer certification ledger

Status: **review-only inventory; no consumer is presumed certified**.

This ledger is scoped only to Healthy Habit LLC's HEHA systems. Do not import
accounts, owners, evidence, or approvals from a separate legal entity. It is not
approval to contact a consumer, apply SQL, deploy a client, change a credential,
or publish data.

## Certification rules and access matrix

- `Unassigned` is intentional until a person accepts responsibility; a product
  or provider name is not an accountable owner.
- `Unknown` and repository-search absence are not evidence of non-use.
- Phase A is additive and applies only to identified callers of the 13-field
  `list_public_swipe_partner_cards` or 17-field
  `list_public_partner_directory` RPC. `N/A` elsewhere does not relax Phase B.
- Phase B removes `public`, `anon`, and `authenticated` access to all three
  legacy views. It removes `public` and `anon` base-table access, then gives
  `authenticated` only SELECT/INSERT/UPDATE on `partners`, constrained by
  owner/internal RLS. The relation owner and `service_role` remain untouched.
- Pricing is independent: Phase-B partner certification is never evidence for
  the separate `heha_pricing` hardening packet, or vice versa.
- A certification needs a named owner, exact caller/environment/credential
  class, dated last-use evidence, and reproducible smoke or non-use proof.
- Every Phase-B and pricing field remains **NOT CERTIFIED** until its own
  evidence is complete.

## Approval sequence

1. Complete the read-only inventory and review one exact packet.
2. Obtain explicit approval for that packet's staging apply before any SQL runs.
3. In the separately authorized staging context, apply only that packet and
   capture its denial, preservation, replacement, and consumer smoke evidence.
4. Certify only the rows and packet supported by that evidence.
5. Obtain a separate production approval. Staging approval, another packet's
   evidence, or a completed row never authorizes production.

## Inventory

| Consumer / surface | Operating entity / account | Environment | Credential class | Accountable owner | Current status | Evidence | Last-use evidence | Phase A certification | Phase B certification | Pricing certification | Pricing smoke evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HEHA Swipe store-card reader | Healthy Habit LLC / GitHub `hehaonline/heha-swipe`; Supabase project ID unrecorded | Native store candidate; hosted target unverified | Supabase public anon key; optional authenticated user JWT | Unassigned | Code cut over; live RPC unavailable/unverified | `src/lib/publicPartner.js` calls `list_public_swipe_partner_cards`; contract tests cover 13 fields | Unknown; no dated hosted smoke receipt | NOT CERTIFIED — prove exact fields and eligible IDs as anon/auth in approved staging | NOT CERTIFIED — prove card loading after legacy closure without fallback | NOT CERTIFIED — no pricing disposition approved | No `heha_pricing` call found in this source path; no dated non-use proof |
| HEHA website directory data caller | Healthy Habit LLC / GitHub `hehaonline/heha-swipe`; Supabase project ID unrecorded | HEHA Swipe `/embed/partners`; hosted route unverified | Supabase public anon key | Unassigned | Code cut over; live RPC unavailable/unverified | `src/components/embed/PartnerDirectoryEmbed.jsx` calls `list_public_partner_directory`; contract tests cover 17 fields | Unknown; no dated hosted route receipt | NOT CERTIFIED — prove exact fields and eligible IDs as anon/auth in approved staging | NOT CERTIFIED — prove the hosted data caller after legacy closure | NOT CERTIFIED — no pricing disposition approved | No `heha_pricing` call found in this source path; no dated non-use proof |
| HEHA Swipe owner self-service | Healthy Habit LLC / GitHub `hehaonline/heha-swipe`; Supabase project ID unrecorded | HEHA Swipe web owner UI; hosted revision unverified | Supabase authenticated owner JWT with RLS | Unassigned | Discovered direct `partners` SELECT/INSERT/UPDATE caller; store channel hides it | `src/App.jsx`, `src/components/ProfileTab.jsx`, `src/components/CommunityPassTab.jsx`, `src/components/PartnerWizard.jsx`, and `src/components/PartnerProfileEditor.jsx` | Unknown; no current owner-flow smoke receipt | N/A — not an identified caller of either Phase-A RPC | NOT CERTIFIED — prove own-row read/write and foreign-row denial after regrant | NOT CERTIFIED — no pricing disposition approved | No dated owner-flow pricing smoke or reviewed non-use proof |
| HEHA Swipe internal routing UI | Healthy Habit LLC / GitHub `hehaonline/heha-swipe`; Supabase project ID unrecorded | HEHA Swipe internal web UI; hosted revision unverified | Supabase authenticated internal-role JWT with RLS | Unassigned | Discovered direct `partners` SELECT/UPDATE caller | `src/components/admin/routing/RoutingDashboard.jsx` | Unknown; no current internal-role smoke receipt | N/A — not an identified caller of either Phase-A RPC | NOT CERTIFIED — prove exact internal-role read/write boundary after regrant | NOT CERTIFIED — no pricing disposition approved | No dated internal-role pricing smoke or reviewed non-use proof |
| HEHA HubSpot sync edge function | Healthy Habit LLC / Supabase project and HEHA HubSpot connection IDs unrecorded | Supabase Edge Function; deployed revision unverified | Server-side `service_role` and HubSpot private-app credential | Unassigned | Discovered service-role `partners` reader; Phase B intends no service-role change | `supabase/functions/hubspot-sync/index.ts` | Unknown; no current invocation receipt | N/A — not an identified caller of either Phase-A RPC | NOT CERTIFIED — prove service read unchanged and browser access closed | NOT CERTIFIED — no pricing disposition approved | No `heha_pricing` call found in the function; no dated non-use proof |
| HEHA Local | Healthy Habit LLC intended / HEHA Local account identifier unverified | Application and environment unknown | Credential and database role unknown | Unassigned | External use not disproved; partner/pricing dependency unknown | No connected/default-branch code hit on 2026-09-04; this is not non-use proof | Unknown | N/A — not an identified caller of either Phase-A RPC | NOT CERTIFIED — exact caller and bounded replacement or non-use required | NOT CERTIFIED — exact caller and disposition unknown | No configuration, query inventory, run receipt, or owner attestation |
| Wix site shell and direct integrations | Healthy Habit LLC intended / Wix account identifier unverified | Wix site revision and environment unknown | Iframe/public browser or integration credential unknown | Unassigned | Source-controlled embed is separately rowed; direct data/pricing use uninspected | No Wix configuration export, request log, or owner attestation | Unknown | N/A — outer shell is not an identified direct Phase-A RPC caller | NOT CERTIFIED — hosted shell smoke and direct legacy non-use required | NOT CERTIFIED — direct pricing dependency unknown | No Wix export, dated smoke, or owner-attested non-use |
| Make scenarios | Healthy Habit LLC intended / Make organization identifier unverified | Scenario names and environments unknown | Connection and database role unknown | Unassigned | External scenarios/connections uninspected | No scenario export, connection inventory, run receipt, or owner attestation | Unknown | N/A — not an identified caller of either Phase-A RPC | NOT CERTIFIED — exact caller and bounded replacement or non-use required | NOT CERTIFIED — direct pricing dependency unknown | No scenario export, dated run receipt, or owner-attested non-use |
| Other external or non-code consumers | Healthy Habit LLC intended / account inventory incomplete | Environment unknown | Credential class unknown | Unassigned | Discovery open | No complete API-log, credential, webhook, automation, or integration inventory | Unknown | N/A — Phase A is additive and no direct caller is identified | NOT CERTIFIED — hard blocker until discovery closes | NOT CERTIFIED — hard blocker until discovery closes | No complete pricing caller inventory or dated proof |

## Evidence checklist per consumer

- [ ] A named owner accepts the exact caller/account row.
- [ ] Record exact object/RPC, fields, environment, origin, and credential class
      without storing secrets here.
- [ ] Attach dated last-use or owner-attested non-use evidence with search scope.
- [ ] Obtain packet-specific staging-apply approval before any SQL or smoke run.
- [ ] Preserve Phase-A, Phase-B, and pricing evidence independently.
- [ ] Obtain separate production approval only after the relevant packet and
      consumer rows are certified.

## Current discovery boundary

A read-only GitHub organization search on 2026-09-04 found legacy partner-view
references only in `heha-swipe`. It cannot see Wix configuration, Make
scenarios, Supabase API clients, local scripts, third-party credentials, or HEHA
Local code outside the connected/default-branch scope. All external rows remain
**NOT CERTIFIED**.
