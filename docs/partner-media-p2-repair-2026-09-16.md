# PR #141: bounded P2 repair candidate

Starting head: `5e5dd0137c76e91cb1e6042da753dabaa21c77c7`.
Exact dependency: PR #140 at `108c668a3cbea393c0d8427740c74848c95c929e`.
Scope: the three findings in issue comment `5688831047`; no feature or publication change.

## Behavior

- App's exact selected card is carried into Profile and Community Pass. Each child lookup filters both owner and exact card ID. A missing selection, failed lookup, mismatched response, or old owner/card snapshot cannot fall back to a newer owned card. Selection keys reset child/editor state across account/card changes.
- Community Pass loads full `categories`. Executable tests use the actual editor initialization/change-building functions to prove a one-field edit preserves Restaurant + Vendor and adding Events proposes all three categories.
- The new forward migration rejects unexpected donor definitions, bucket/trigger drift, and existing active conflicts before installing anything. Partial unique indexes protect active paths and logo/cover slots; all writers share parent-row locking and a private row-version serialization record for gallery max-six. The latter also rejects stale Repeatable Read snapshots. Public partner rows are never updated for locking.
- Active upload means add/replace with submitted, needs_info, or approved status. Removal requests and applied/rejected/cancelled history do not reserve upload slots. This deliberately aligns the previously inconsistent owner/staff prechecks. Internal review timestamps, owner-only submission defaults, backend terminal-history writes, and verified staff source/rights evidence remain. Backend active writes and internal reactivation now obey the same integrity constraints.

## Evidence scope

Executed locally on Node 24.19.0: all 70 focused JavaScript tests, including five new exact-card/category regressions; proof-script syntax; repository ledger/evidence verification and ten semantic negative controls; packet hashes. Materialized relevant source was verified against connected GitHub blob SHAs before editing. No mounted React harness/dependencies, PostgreSQL, Docker, or Supabase CLI was available locally, so this is helper plus exact-source contract evidence, not a mounted browser or database execution claim. The migration was authored as a forward source file without invoking an unavailable CLI; no SQL was applied locally or hosted.

The existing literal-head CI workflow now also runs for PR #141's exact dependency branch. It retains the full historical lifecycle/publication/API proof and adds four atomic preflight negatives, sequential/bulk/review/backend SQL assertions, and eleven true two-session races (owner/owner, both owner/staff orderings, and Repeatable Read). CI results must be read for the eventual exact commit; this document does not preclaim success.

Historical September 14 evidence is retained and is not evidence that this changed candidate passed. Independent exact-head security/database review, real verification-email/recovery and complete hosted-browser behavior, live schema/ACL/Storage and conflict preflight, approved ordering/rollback, and explicit human merge/migration/deployment decisions remain required. No formal APPROVED verdict is claimed.

No hosted SQL/data, account, email, ownership, publication, permission, deployment, merge, or spend action was performed. Proposed migration rollback must be independently reviewed; do not drop shared integrity safeguards or restore old asymmetric limits casually.
