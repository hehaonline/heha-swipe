#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must point to the disposable CI database}"

PSQL=(psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -qAt)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

NOW="2026-08-25 14:00:00+00"

"${PSQL[@]}" <<SQL
insert into community_pass_private.runtime_config (
  singleton,
  environment,
  config_version
) values (
  true,
  'test',
  's1-concurrency-v1'
)
on conflict (singleton) do nothing;

select one_heha_private.begin_link_handshake(
  '40000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-0000000000a1',
  'verified_non_sso',
  timestamptz '$NOW' - interval '2 minutes',
  repeat('4', 64),
  timestamptz '$NOW'
);
SQL

same_request_sql="select one_heha_private.activate_identity_link(
  '40000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-0000000000a1',
  '50000000-0000-0000-0000-0000000000a1',
  timestamptz '$NOW' - interval '1 minute',
  repeat('5', 64),
  timestamptz '$NOW'
);"

"${PSQL[@]}" -c "$same_request_sql" >"$TMP_DIR/same-1.out" 2>"$TMP_DIR/same-1.err" &
PID_ONE=$!
"${PSQL[@]}" -c "$same_request_sql" >"$TMP_DIR/same-2.out" 2>"$TMP_DIR/same-2.err" &
PID_TWO=$!

wait "$PID_ONE"
wait "$PID_TWO"

LINK_ONE="$(tail -n 1 "$TMP_DIR/same-1.out" | tr -d '[:space:]')"
LINK_TWO="$(tail -n 1 "$TMP_DIR/same-2.out" | tr -d '[:space:]')"

if [[ -z "$LINK_ONE" || "$LINK_ONE" != "$LINK_TWO" ]]; then
  echo "same-request race did not return one stable link ID" >&2
  cat "$TMP_DIR/same-1.err" >&2 || true
  cat "$TMP_DIR/same-2.err" >&2 || true
  exit 1
fi

SAME_COUNTS="$("${PSQL[@]}" -c "
  select
    (select count(*) from one_heha_private.identity_links
      where environment = 'test'
        and canonical_user_id = '50000000-0000-0000-0000-0000000000a1'
        and status = 'active')::text
    || ':' ||
    (select count(*) from one_heha_private.identity_events
      where environment = 'test'
        and idempotency_key = 'link-activated:40000000-0000-0000-0000-000000000001')::text
    || ':' ||
    (select count(*) from one_heha_private.link_handshakes
      where environment = 'test'
        and request_id = '40000000-0000-0000-0000-000000000001'
        and state = 'consumed')::text;
")"

if [[ "$SAME_COUNTS" != "1:1:1" ]]; then
  echo "same-request race produced unexpected counts: $SAME_COUNTS" >&2
  exit 1
fi

"${PSQL[@]}" <<SQL
select one_heha_private.begin_link_handshake(
  '40000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-0000000000b2',
  'verified_non_sso',
  timestamptz '$NOW' - interval '2 minutes',
  repeat('6', 64),
  timestamptz '$NOW'
);

select one_heha_private.begin_link_handshake(
  '40000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-0000000000c3',
  'verified_non_sso',
  timestamptz '$NOW' - interval '2 minutes',
  repeat('7', 64),
  timestamptz '$NOW'
);
SQL

conflict_one_sql="select one_heha_private.activate_identity_link(
  '40000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-0000000000b2',
  '50000000-0000-0000-0000-0000000000ff',
  timestamptz '$NOW' - interval '1 minute',
  repeat('8', 64),
  timestamptz '$NOW'
);"

conflict_two_sql="select one_heha_private.activate_identity_link(
  '40000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-0000000000c3',
  '50000000-0000-0000-0000-0000000000ff',
  timestamptz '$NOW' - interval '1 minute',
  repeat('a', 64),
  timestamptz '$NOW'
);"

set +e
"${PSQL[@]}" -c "$conflict_one_sql" >"$TMP_DIR/conflict-1.out" 2>"$TMP_DIR/conflict-1.err" &
PID_ONE=$!
"${PSQL[@]}" -c "$conflict_two_sql" >"$TMP_DIR/conflict-2.out" 2>"$TMP_DIR/conflict-2.err" &
PID_TWO=$!

wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e

if ! { [[ "$STATUS_ONE" -eq 0 && "$STATUS_TWO" -ne 0 ]] || [[ "$STATUS_ONE" -ne 0 && "$STATUS_TWO" -eq 0 ]]; }; then
  echo "conflicting canonical-link race did not produce exactly one winner" >&2
  echo "status one=$STATUS_ONE status two=$STATUS_TWO" >&2
  cat "$TMP_DIR/conflict-1.err" >&2 || true
  cat "$TMP_DIR/conflict-2.err" >&2 || true
  exit 1
fi

CONFLICT_COUNT="$("${PSQL[@]}" -c "
  select count(*)
  from one_heha_private.identity_links
  where environment = 'test'
    and canonical_user_id = '50000000-0000-0000-0000-0000000000ff'
    and status = 'active';
")"

if [[ "$CONFLICT_COUNT" != "1" ]]; then
  echo "conflicting canonical-link race produced $CONFLICT_COUNT active links" >&2
  exit 1
fi

if [[ "$STATUS_ONE" -ne 0 ]] && ! grep -Eq 'HEHA_ONE_IDENTITY_LINK_CONFLICT|duplicate key' "$TMP_DIR/conflict-1.err"; then
  echo "losing client one failed for an unexpected reason" >&2
  cat "$TMP_DIR/conflict-1.err" >&2
  exit 1
fi

if [[ "$STATUS_TWO" -ne 0 ]] && ! grep -Eq 'HEHA_ONE_IDENTITY_LINK_CONFLICT|duplicate key' "$TMP_DIR/conflict-2.err"; then
  echo "losing client two failed for an unexpected reason" >&2
  cat "$TMP_DIR/conflict-2.err" >&2
  exit 1
fi

echo "PASS: ONE HEHA S1 two-client races returned one idempotent link and one conflict-safe winner."
