# Partner publication legal-review input

Status: **DRAFT FOR FOUNDER/LEGAL REVIEW — NOT APPROVED COPY**

This profile-publication gate is separate from the Official Partner/commercial
agreement. Until exact final copy, URLs, and version identifiers are approved,
all public partner projections must remain fail-closed.

## Proposed UI acknowledgements

Both controls must start unchecked.

1. **Partner publication terms:** “I have read and agree to the HEHA Partner
   Profile Publication Terms identified below.”
2. **Privacy notice:** “I acknowledge the HEHA Privacy Notice identified below,
   including HEHA’s processing of the representative and business information
   used to prepare, review, publish, update, and withdraw this profile.”

The exact profile-version approval remains a separate confirmation:
“I approve this exact profile version for publication to the destinations
selected above. A later public-profile change requires new approval.”

## Legal inputs still required

- final Partner Profile Publication Terms URL and immutable version identifier;
- final Privacy Notice URL and immutable version identifier;
- exact legal entity/contact, effective date, retention/deletion language, and
  any destination-specific disclosures;
- approval of the existing media-permission and destination-withdrawal copy;
- a digest or other immutable evidence reference for each approved document.

`partner-publication-terms-2026-08-19-draft1` and
`privacy-notice-2026-08-19-draft1` are review labels only. They must never be
accepted by the server or treated as approved versions.

## Required engineering behavior after approval

- store both approved version identifiers and both explicit booleans in the
  private append-only publication-consent evidence;
- bind them to the idempotency/request hash and exact profile snapshot hash;
- reject false, blank, draft, stale, or unsupported versions at the RPC;
- invalidate public eligibility when either current version changes;
- preserve withdrawal and prior evidence without rewriting history;
- never infer Official Partner, HEHA Certified, commercial-contract, claim, or
  listing-activation status from these acknowledgements.
