# HEHA Swipe Deep Sanitized Metadata Capture Plan — 2026-08-24

Status: **SOURCE-CONTROLLED PREPARATION / LIVE CAPTURE NOT YET AUTHORIZED BY THIS FILE**  
Task: `SWP-016`

## Objective

Capture enough current structural metadata to design a reproducible, data-less HEHA Swipe baseline while keeping customer data, secrets, provider payloads, and Production behavior untouched.

This plan follows the verified top-level inventory on `main` and the repository↔live-ledger compatibility map. It does not authorize executable baseline SQL.

The unavailable historical 381,741-byte capture is governed by `historical-deep-capture-custody-2026-08-24.md`. Its reported digest and zero-match scan are unverified operator reports. Those bytes are permanently excluded from publication, baseline work, CI, and AI/chat/connector reuse; if retained, they remain in encrypted private quarantine only.

## Tranche 1 — deep structure

Prepared query:

`docs/migration-lineage/queries/deep-structure-manifest-capture.sql`

Target schemas:

- `public`
- `app_private`

Captured record classes in the first, pre-egress-safe pass:

1. table columns, ordinal position, formatted type, nullability, identity/generated state, collation, and presence flags for withheld defaults and column comments;
2. table-comment presence, with comment text withheld;
3. table constraints and structural flags, with definition text withheld;
4. indexes and structural flags, with definition text withheld;
5. enum type identity and label order, with raw labels withheld;
6. domains, base types, nullability, and presence flags for withheld defaults and constraints;
7. sequences and structural parameters, with owner role names withheld.

The query reads catalog metadata only. It does not select from application tables. Raw defaults, constraints, index expressions, domain expressions, table/column comment text, enum labels, and sequence-owner role names are withheld inside PostgreSQL before result rows are returned. The public artifact contains no unsalted fingerprint of those values. This pass proves bounded inventory and allowlisted structural flags only; it does not claim semantic definition parity.

### Mandatory execution containment — still not authorized

Before any live metadata read, an independent reviewer must approve all of the following for the named canonical environment:

1. a least-privilege, read-only database role and a transaction forced to `READ ONLY`;
2. the committed query's server-side allowlist/redaction boundary and pinned `pg_catalog` search path;
3. a private workstation/session that does not echo result rows to a connector, CI, chat, observability stream, or shared terminal transcript;
4. a restricted destination directory and files readable only by the operator;
5. a separate, reviewed rule for any later raw-definition allowlist. No raw expression or comment may leave the database until that rule exists.

The exact client byte contract, to be run only after that approval with a separately configured `PGSERVICE` entry, is:

```bash
set -euo pipefail
umask 077
capture_parent_input="${TMPDIR:?Set TMPDIR to a canonical operator-owned mode-700 directory}"
operator_uid="$(id -u)"
for required_command in realpath stat sha256sum mktemp psql; do
  if ! command -v "$required_command" >/dev/null; then
    echo "Required capture command is unavailable: $required_command" >&2
    exit 1
  fi
done
if [[ ! -d /proc/self/fd ]]; then
  echo "Descriptor verification requires Linux /proc/self/fd." >&2
  exit 1
fi
validate_capture_chain() {
  local current="$1" ancestor_uid ancestor_mode ancestor_mode_value
  while :; do
    if [[ ! -d "$current" || -L "$current" ]]; then
      echo "Every capture-path component must be a real directory: $current" >&2
      return 1
    fi
    IFS=: read -r ancestor_uid ancestor_mode < <(stat -c '%u:%a' -- "$current")
    if [[ "$ancestor_uid" != "$operator_uid" && "$ancestor_uid" != "0" ]]; then
      echo "Every capture-path component must be owned by the operator or root: $current" >&2
      return 1
    fi
    ancestor_mode_value=$((8#$ancestor_mode))
    if (( ancestor_mode_value & 0022 )); then
      if [[ "$ancestor_uid" != "0" ]] || (( !(ancestor_mode_value & 01000) )); then
        echo "Writable capture-path components must be root-owned sticky directories: $current" >&2
        return 1
      fi
    fi
    [[ "$current" == "/" ]] && break
    current="${current%/*}"
    [[ -n "$current" ]] || current="/"
  done
}
if [[ "$capture_parent_input" != /* ]]; then
  echo "TMPDIR must be an absolute path." >&2
  exit 1
fi
if ! capture_parent="$(realpath -e -- "$capture_parent_input")"; then
  echo "TMPDIR must resolve to an existing directory." >&2
  exit 1
fi
if [[ "$capture_parent" != "$capture_parent_input" ]]; then
  echo "TMPDIR must already be canonical and contain no symlink path component." >&2
  exit 1
fi
if [[ ! -d "$capture_parent" || -L "$capture_parent" || "$(stat -c '%u:%a' "$capture_parent")" != "$operator_uid:700" ]]; then
  echo "TMPDIR must be an existing non-symlink directory owned by the operator with mode 700." >&2
  exit 1
fi
validate_capture_chain "$capture_parent"
capture_dir="$(mktemp -d -- "$capture_parent/swp-016-private-capture.XXXXXXXX")"
capture_file="$capture_dir/deep-structure-manifest.jsonl"
error_file="$capture_dir/deep-structure-manifest.stderr"
receipt_file="$capture_dir/deep-structure-manifest.receipt"
if [[ -L "$capture_dir" || "$(stat -c '%u:%a' "$capture_dir")" != "$operator_uid:700" ]]; then
  echo "Fresh capture directory must be operator-owned mode 700." >&2
  exit 1
fi
validate_capture_chain "$capture_dir"
for destination in "$capture_file" "$error_file" "$receipt_file"; do
  if [[ -e "$destination" || -L "$destination" ]]; then
    echo "Refusing pre-existing or symlink destination: $destination" >&2
    exit 1
  fi
done
set -o noclobber
: >"$capture_file"
: >"$error_file"
: >"$receipt_file"
set +o noclobber
chmod 600 -- "$capture_file" "$error_file" "$receipt_file"
for destination in "$capture_file" "$error_file" "$receipt_file"; do
  if [[ ! -f "$destination" || -L "$destination" || "$(stat -c '%u:%a' "$destination")" != "$operator_uid:600" ]]; then
    echo "Capture destination must be a regular operator-owned mode-600 file." >&2
    exit 1
  fi
done
exec 3<>"$capture_file" 4<>"$error_file" 5<>"$receipt_file"
capture_dir_identity="$(stat -Lc '%d:%i' "$capture_dir")"
capture_file_identity="$(stat -Lc '%d:%i' /proc/self/fd/3)"
error_file_identity="$(stat -Lc '%d:%i' /proc/self/fd/4)"
receipt_file_identity="$(stat -Lc '%d:%i' /proc/self/fd/5)"
if [[ "$(stat -Lc '%u:%a:%s' /proc/self/fd/3)" != "$operator_uid:600:0" || \
      "$(stat -Lc '%u:%a:%s' /proc/self/fd/4)" != "$operator_uid:600:0" || \
      "$(stat -Lc '%u:%a:%s' /proc/self/fd/5)" != "$operator_uid:600:0" ]]; then
  echo "Opened capture descriptors must reference operator-owned mode-600 regular empty files." >&2
  exit 1
fi
set +e
PGCLIENTENCODING=UTF8 PGSERVICE=heha-swipe-approved-readonly \
  psql -XAtq -P footer=off -v ON_ERROR_STOP=1 \
  -f docs/migration-lineage/queries/deep-structure-manifest-capture.sql \
  >&3 2>&4
psql_status=$?
set -e
path_integrity=true
if ! validate_capture_chain "$capture_parent" || ! validate_capture_chain "$capture_dir"; then
  path_integrity=false
fi
if [[ ! -d "$capture_dir" || -L "$capture_dir" ]] || \
   [[ "$(stat -Lc '%d:%i' "$capture_dir" 2>/dev/null || true)" != "$capture_dir_identity" ]]; then
  path_integrity=false
fi
verify_pinned_destination() {
  local destination="$1" expected_identity="$2" descriptor="$3"
  if [[ ! -f "$destination" || -L "$destination" ]] || \
     [[ "$(stat -Lc '%u:%a:%d:%i' "$destination" 2>/dev/null || true)" != "$operator_uid:600:$expected_identity" ]] || \
     [[ "$(stat -Lc '%d:%i' "/proc/self/fd/$descriptor")" != "$expected_identity" ]]; then
    path_integrity=false
  fi
}
verify_pinned_destination "$capture_file" "$capture_file_identity" 3
verify_pinned_destination "$error_file" "$error_file_identity" 4
verify_pinned_destination "$receipt_file" "$receipt_file_identity" 5
capture_bytes="$(stat -Lc '%s' /proc/self/fd/3)"
capture_sha256="$(sha256sum /proc/self/fd/3 | cut -d ' ' -f1)"
error_bytes="$(stat -Lc '%s' /proc/self/fd/4)"
error_sha256="$(sha256sum /proc/self/fd/4 | cut -d ' ' -f1)"
eligible=true
if (( psql_status != 0 )) || [[ "$path_integrity" != "true" ]]; then
  eligible=false
fi
printf 'SWP016_PSQL_STATUS=%s\nSWP016_PATH_INTEGRITY=%s\nSWP016_CAPTURE_BYTES=%s\nSWP016_CAPTURE_SHA256=%s\nSWP016_ERROR_BYTES=%s\nSWP016_ERROR_SHA256=%s\nSWP016_ELIGIBLE=%s\n' \
  "$psql_status" "$path_integrity" "$capture_bytes" "$capture_sha256" "$error_bytes" "$error_sha256" "$eligible" >&5
exec 3>&- 4>&- 5>&-
if [[ "$eligible" != "true" ]]; then
  echo "Capture is ineligible; discard it and repair the containment or psql failure before retrying." >&2
  exit 1
fi
```

The connection profile must remain outside source control and command history. The resulting bytes remain private until a reviewer confirms that every row matches the server-side sanitized contract. Before any later path-based review or commit, recompute the capture SHA-256 and byte count from the same canonical directory and compare them with the private descriptor-derived receipt; a mismatch or an ineligible receipt is a hard stop. This Bash contract trusts the operator's UID and root; a hostile same-UID process or privileged root is outside its threat model and requires a dedicated OS account/container plus an `openat2`/`O_NOFOLLOW` helper. This file does not authorize creating that profile or running the command.

If future parity work requires a stable comparison token for withheld text, the only proposed option is a keyed HMAC-SHA-256 computed in a separately approved private path with a non-exported, purpose-specific key. That option is not implemented or authorized here; no key, HMAC, raw value, or public fingerprint may be added to this query or artifact without separate review.

### Stop before capture or commit if

- the query can return raw default, constraint, index, domain, or comment text;
- the database role, private/no-log path, output permissions, or server-side redaction rule is unverified;
- an unexpected schema appears;
- the result cannot be deterministically sorted;
- the output is too large for bounded review;
- current object counts conflict with the verified top-level manifest.

If a stop condition occurs, do not run the capture. If execution has already started, keep any result confined to the approved private destination, record the stop, and recapture only after the query and containment path are independently reviewed. Never silently edit evidence bytes.

## Tranche 2 — views, functions, and triggers

Prepare only after Tranche 1 passes.

Capture:

- view definitions, `security_invoker` / `security_barrier` options, owner, dependencies, and grants;
- function identity, language, volatility, parallel safety, security mode, owner, pinned search path, EXECUTE ACL, normalized body hash, and dependencies;
- trigger timing, event mask, update-column set, enabled state, function identity, and deterministic ordering.

Do not commit raw function bodies until a secret scan and independent review confirm that the bodies contain no credentials, tokens, private endpoints, or customer data.

## Tranche 3 — RLS and effective access

Prepare only after Tranche 2 passes.

Capture:

- schema/table/function grants;
- RLS `USING` and `WITH CHECK` expressions;
- permissive/restrictive mode and roles;
- effective access matrices for `anon`, `authenticated`, owner, internal roles, service role, Auth admin, and database owner;
- SECURITY DEFINER caller binding and search-path behavior.

This tranche is security-sensitive. A count of policies or the presence of RLS is not a BOLA proof.

## Tranche 4 — provider-managed behavior

Capture sanitized configuration receipts for:

- application-required extensions;
- Storage buckets and policies, without objects or signed URLs;
- cron schedules and function names, without secret arguments;
- Edge Function names/configuration boundaries, without environment values;
- Auth settings required for the app contract;
- provider versions and branch behavior.

Provider-managed schemas must not be recreated blindly by baseline SQL.

## Tranche 5 — authority and identity

Document and prove:

- canonical ONE HEHA account identity;
- legacy `supporter_*` records and profile cache boundaries;
- new Community Pass account/subscription/purchase/entitlement/event authority;
- HEHA Swipe → HEHA Local server-to-server benefit verification;
- deletion, redaction, retention, and email-reuse behavior.

No legacy supporter row becomes Community Pass authority without a separately approved customer-protection mapping.

## Review and build sequence

1. source-control the exact read-only, server-side-sanitized query;
2. independently review the private/no-log containment path and pre-egress redaction;
3. receive one explicit authorization for the bounded live metadata read;
4. execute against the named canonical environment with the exact JSONL command;
5. preserve exact UTF-8/LF bytes in the restricted destination;
6. verify that no raw expression or comment crossed the redaction boundary;
7. commit only the reviewed sanitized artifact, capture receipt, and SHA-256;
8. run a fail-closed verifier;
9. perform database dependency, privacy, and security review;
10. draft—but do not run—the executable canonical baseline;
11. estimate runtime and cost for a data-less disposable branch;
12. obtain separate founder approval;
13. prove zero-to-current rebuild, generated types, advisors, behavior, concurrency, rollback/forward-fix, and complete cleanup;
14. delete the branch and record actual cost.

## No-go conditions

Do not:

- read or copy customer, partner, payment, order, profile, Auth, or storage rows;
- commit secrets or provider credentials;
- alter Production or its migration ledger;
- fold Community Pass PR #128 into the baseline silently;
- treat same-name migration candidates as SQL equivalence;
- create a paid branch without exact cost approval;
- activate Stripe, billing, entitlements, credits, benefits, delivery waivers, or public launch.

Production impact: **NONE**.
