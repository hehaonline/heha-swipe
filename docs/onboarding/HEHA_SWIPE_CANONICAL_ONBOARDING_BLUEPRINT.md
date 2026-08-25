# HEHA Swipe Canonical Partner Onboarding Blueprint

**Status:** Product and integration specification only  
**Implementation:** Blocked until HEHA-ARCH-000 P0 remediation and ADR-001 approval  
**Primary user-facing home:** HEHA Swipe  
**Operational continuation:** HEHA Local / Order Hub  
**Canonical future source of truth:** Approved HEHA canonical Supabase project

## 1. Product decision

Partner onboarding remains inside HEHA Swipe.

HEHA Swipe owns the partner-facing discovery, registration, business claim, profile, media, review status, and correction experience. HEHA Local / Order Hub owns menu operations, orders, fulfillment, payouts, Restaurant Assurance Balance, reconciliation, and other financial or operational functions after a business chooses to receive HEHA orders.

The user should experience one continuous journey:

1. Join HEHA in Swipe.
2. Find, claim, or create the business.
3. Complete the public profile.
4. Select desired HEHA capabilities.
5. Submit and resolve review tasks.
6. Continue into order setup when applicable.
7. Manage the business through one Partner Hub, even when some modules are powered by HEHA Local.

The business must not register separately in Swipe, Local, and HEHA.ONLINE.

## 2. Existing HEHA Swipe foundation to preserve

### `src/components/PartnerWizard.jsx`

Current strengths:

- Six-step business registration flow.
- Business basics, details, contact, offerings, style, and review.
- Creates a partner record with `owner_id`, contact information, category, offerings, simple featured items, status, and completion percentage.
- Sends a nonblocking Make.com notification after submission.
- Displays submission status.

Current limitations:

- Form state is local to the component and is not a resumable server-side draft.
- Directly inserts into the Swipe `partners` table.
- No find-or-claim flow before creating a business.
- No duplicate-business prevention.
- No location model.
- No goal/capability selection.
- Featured items are unstructured name/price/emoji values.
- No canonical ID or migration link.

### `src/components/PartnerProfileEditor.jsx`

Current strengths:

- Allows direct edits during early review states.
- Uses version-like change requests after approval.
- Keeps the current public profile unchanged while reviewed edits are pending.
- Limits editable fields through an allowlist.

Current limitations:

- Writes directly to Swipe partner tables and Swipe-specific change-request tables.
- Only one pending profile change request appears to be permitted.
- Does not yet use risk-based field classification.
- Does not provide one combined Needs Your Attention queue.

### `src/components/PartnerMediaManager.jsx`

Current strengths:

- Private pending bucket.
- Signed previews.
- Logo, cover, and gallery support.
- Review-gated additions, replacements, and removals.
- Existing public media remains live during review.

Current limitations:

- Business-level media only.
- No menu-item media linkage.
- No semantic classification metadata.
- No rights-confirmation flow.
- No canonical media ID or canonical business ID.

These components should be incrementally adapted, not discarded.

## 3. One journey, two capability layers

### Layer A — Discoverability in HEHA Swipe

Minimum requirements:

- Verified account.
- Business name.
- Category.
- Location or service area.
- Public contact method.
- Short description.
- Ownership or authorization statement.
- Listing terms.

Result:

- Draft or submitted HEHA partner profile.
- Public discovery profile after approval.
- No order or banking requirement.

### Layer B — Receive HEHA orders

Requested from the Swipe Partner Hub through a capability card:

> Receive orders through HEHA

Additional setup:

- Operating location.
- Hours.
- Fulfillment method.
- Pickup instructions.
- Menu or product catalog.
- Ingredients and allergens where applicable.
- Order-notification channel.
- Partner operating agreement.
- Payment or payout setup.
- Optional Restaurant Assurance Balance authorization.

The operational pages may be rendered by or linked to HEHA Local, but the user should remain inside one coherent Partner Hub and one identity session.

### Layer C — HEHA Certified

Separate optional review path. Certification must not block basic listing or ordinary order setup unless a business or item violates safety, legal, ownership, or fraud standards.

## 4. Target onboarding flow

### Step 0 — Authentication

- Use canonical HEHA ID after ADR-001/ADR-002 approval.
- Existing Swipe users enter an account-linking flow rather than recreating accounts.
- Basic onboarding may begin without MFA.
- Sensitive setup later requires step-up MFA.

### Step 1 — Find your business

Search using:

- Business name.
- Address.
- Phone.
- Website domain.
- Existing Swipe record.

Outcomes:

- Claim existing business.
- Request manager access.
- Continue an existing draft.
- Register a new business.

Never silently merge uncertain matches.

### Step 2 — Your relationship

Options:

- I own this business.
- I manage this business.
- I am authorized to register it.
- I was invited.

Collect the least burdensome verification method that works.

### Step 3 — Business essentials

- Public business name.
- Legal name only when needed.
- Category.
- Public contact.
- Website/social link.
- Location or service area.
- Short description.

Auto-save after each meaningful change.

### Step 4 — Choose HEHA goals

- Get discovered.
- Receive orders.
- Create a Community Offer.
- Join HEHA marketing opportunities.
- Start HEHA Certified review.

No optional goal is preselected.

### Step 5 — Public profile

- Tagline.
- Full description.
- Offerings.
- Price range.
- Hours summary.
- Languages.
- Business attributes the partner chooses to disclose.

Grammar assistance must preserve original text and require partner acceptance.

### Step 6 — Media

- Logo.
- Cover.
- Gallery.
- Rights confirmation.
- AI classification suggestion with user confirmation.

### Step 7 — Preview and submit

Show:

- Swipe profile preview.
- Information that becomes public.
- Information that stays private.
- Missing required fields.
- Selected capabilities.
- Legal acknowledgements.
- One recommended next action.

### Step 8 — Post-submission Partner Hub

Four partner-facing states only:

- Draft.
- Needs You.
- HEHA Is Reviewing.
- Ready / Live.

The Partner Hub contains one Needs Your Attention queue for profile, ownership, media, order setup, payout setup, and marketing approvals.

## 5. Canonical-data transition strategy

Do not immediately replace the working Swipe UI.

### Transition stage 1 — Adapter layer

Create a repository service boundary so UI components do not call `supabase.from("partners")` directly.

Recommended modules:

- `src/services/partnerOnboardingRepository.js`
- `src/services/partnerProfileRepository.js`
- `src/services/partnerMediaRepository.js`
- `src/services/partnerCapabilityRepository.js`

Initially these adapters may call the current Swipe tables. Later they can call the canonical backend without rewriting the screens.

### Transition stage 2 — Stable external identifiers

Every current Swipe record receives or maps to:

- `canonical_business_id`
- `source_system = heha_swipe`
- `source_partner_id`
- `migration_status`

Do not treat `owner_id` as complete ownership proof. The audit found that most Swipe partner records do not currently have an owner-linked account.

### Transition stage 3 — Dual-read verification, not dual-write target state

During migration only:

- Read current Swipe profile.
- Read proposed canonical profile.
- Compare.
- Resolve differences.
- Validate public output.

Avoid long-term bidirectional synchronization.

### Transition stage 4 — Canonical writes

After migration validation:

- Swipe onboarding writes canonical business drafts.
- Swipe discovery reads approved public projections.
- Current Swipe `partners` becomes read-only legacy or is retired after rollback criteria pass.

## 6. Resumable draft requirements

Drafts must survive:

- Refresh.
- Logout.
- Device change.
- Poor connection.
- Interrupted uploads.

Each draft stores:

- Current step.
- Completed fields.
- Selected capabilities.
- Validation results.
- Last saved time.
- User and business relationship.
- Draft version.

UX requirements:

- Visible “Saved” indicator.
- Retry state when offline/save fails.
- Optional fields marked clearly.
- “Do this later” where safe.
- No false 100% completion.

## 7. Risk-based edit behavior

### Instant update

Examples:

- Hours.
- Temporary closure.
- Website/social links.
- Pickup instructions.
- Sold-out status.

### Automated check

Examples:

- Basic descriptions.
- Ordinary spelling corrections.
- Gallery images.
- Price changes within policy.

### Human review

Examples:

- Ownership.
- Allergens.
- Verified nutrition.
- Health claims.
- Certification.
- Payout destination.
- Public rights dispute.

Approved content remains live until the replacement version is approved.

## 8. Partner Hub modules

The Swipe Partner Hub should expose:

- Overview.
- Business Profile.
- Photos & Media.
- Locations & Hours.
- Capabilities.
- Offers.
- Reviews & Corrections.
- Team & Access.
- Security.
- Publication Status.
- Receive Orders setup.
- Help & Support.

Order, menu, payout, and assurance-balance modules may route into HEHA Local while preserving HEHA ID and visual continuity.

## 9. Capability-state model

Each business has independent states:

- `listing_status`
- `ordering_status`
- `offer_status`
- `marketing_status`
- `certification_status`

A failure in one capability should not pause unrelated capabilities unless there is a critical ownership, fraud, legal, security, or safety issue.

## 10. Notifications

The Partner Hub inbox is authoritative.

Notify only when:

- The user must act.
- HEHA completes a meaningful review.
- A security-sensitive event occurs.
- A live order requires action.
- A financial action changes state.

Do not notify the partner for internal workflow noise.

Operational consent and marketing consent remain separate.

## 11. Existing Swipe migration rules

Preserve:

- Business profile content.
- Approval history.
- Category.
- Offers.
- Existing public URL where practical.
- Media references pending rights confirmation.

Require reconfirmation for:

- Ownership.
- Current contact information.
- Terms and Privacy acceptance.
- Communication preferences.
- Marketing rights.
- Media usage rights.
- Allergens and safety-sensitive information.
- Banking and payouts.

Do not force trusted partners to rebuild complete profiles.

## 12. Implementation gates

No canonical write-path implementation until:

- HEHA-ARCH-000 audit wording is accepted.
- Candidate P0 security remediation is complete.
- Migration baseline is reproducible.
- ADR-001 is signed.
- Account-linking and ownership strategy is approved.

Documentation, adapter design, UI inventory, test planning, and ticket preparation may proceed now.

## 13. Definition of done

A new partner can:

1. Sign in once.
2. Find, claim, or create a business.
3. Leave and resume later.
4. Complete a public listing.
5. Upload reviewed media.
6. Choose HEHA capabilities.
7. Submit and understand the status.
8. Resolve one clear correction task.
9. Publish to HEHA Swipe.
10. Select Receive Orders.
11. Continue into Local menu/order/payout setup without a second account or business registration.
12. Return to one Partner Hub and see all outstanding tasks.

An existing partner can activate or link an account, confirm ownership and current consent, and preserve the existing business profile.

## 14. First safe implementation slice

After ADR-001, the first Swipe onboarding code ticket should not change the database target. It should introduce the repository/service adapter boundary around current partner onboarding calls, with characterization tests proving no user-visible behavior changes.

This allows later canonical migration without rewriting `PartnerWizard`, `PartnerProfileEditor`, and `PartnerMediaManager` at the same time.
