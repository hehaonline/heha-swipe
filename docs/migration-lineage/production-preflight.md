# Production Preflight and Future Proof Plan

No branch or environment was created.

1. **[I]** Obtain explicit cost confirmation and Geronimo authorization.
2. **[I]** Pin the approved Supabase CLI and PostgreSQL 17-compatible runtime.
3. **[I]** Start from an empty local/disposable Supabase project.
4. **[I]** Place only the canonical migration chain in the proof project.
5. Run:

```bash
supabase start
supabase db reset
supabase migration list --local
supabase db lint --local
```

6. **[I]** Compare generated schema against the approved sanitized object manifest.
7. **[I]** Prove tables, constraints, functions, triggers, views, RLS, grants, extensions and storage configuration separately.
8. **[I]** Run only synthetic fixtures and rollback-contained SQL proofs.
9. **[I]** Repeat the process in a disposable cloud branch after cost approval.
10. **[I]** Retain logs/diffs/checksums, then destroy the branch.

A rebuild is successful only if `db reset` completes from zero and produces no unexplained schema diff. Supabase confirms that reset applies all migration scripts in order. [Supabase deployment migrations](https://supabase.com/docs/guides/deployment/database-migrations).

## Procedure proving PR #82 compatibility

After the canonical baseline succeeds:

1. Add the two PR #82 migrations after the canonical chain without editing their reviewed SQL.
2. Reset again from zero.
3. Confirm the baseline supplies:

```text
public.partners
public.admin_audit_logs
public.user_roles
app_private.has_internal_role(text[])
extensions.pgcrypto
auth.users / auth.uid()
```

4. Run:

```text
partner_claim_foundation_proof.sql
partner_claim_extended_proof.sql
```

5. **[I]** Require 9/9 core and 33/33 extended cases, including all three approved roles and unverified-recipient denial.
6. **[I]** Diff pre/post schema and verify the only intended additions are claim fields, invitation objects, claim RPCs, policies, grants and audit behavior.
7. **[I]** Run the documented rollback-only proof and then rebuild forward from zero again.
8. **[U]** This procedure has not yet been run against the repaired baseline.

## Production preflight, no-go conditions and evidence retention

No-go until all are satisfied:

- **[LP]** Nova/ChatGPT architecture approval for PR A is recorded; executable implementation remains separately gated.
- **[U]** ADR-001 confirms the canonical project and identity boundary.
- **[U]** SQL bodies for ledger-only migrations are recovered or explicitly superseded.
- **[U]** Live functions, triggers, policies, grants, views and constraints are captured and reviewed.
- **[U]** Every duplicate receives a written compatibility decision.
- **[U]** Local zero-build and approved disposable-cloud rebuild both pass.
- **[U]** PR #82 applies after the baseline with all claim proofs green.
- **[U]** Schema drift is explained and approved.
- **[U]** Production backup/recovery and forward-repair procedures are approved.
- **[U]** Geronimo authorizes any environment cost and later production action.

Evidence retention must include:

- **[I]** ordered ledger export;
- **[I]** repository and historical-file checksums;
- **[I]** sanitized schema/object manifest;
- **[I]** duplicate-resolution record;
- **[I]** CLI/runtime versions;
- **[I]** reset, lint, schema-diff and SQL-proof logs;
- **[I]** disposable environment creation/destruction evidence;
- **[I]** approvals and explicit production no-go decision.

## Current stop state

Authorized now:

- documentation-only PR A.

Still prohibited:

- PR B implementation;
- changes to `supabase/migrations`;
- paid Supabase branching;
- migration-ledger edits;
- production migration or deployment;
- PR #82 merge/apply;
- SWP-017 cloud QA before lineage and ADR gates.
