#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must point to the disposable CI database}"

PSQL=(psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -qAt)
TMP_DIR="$(mktemp -d)"
ACTIVE_PIDS=()

cleanup() {
  for pid in "${ACTIVE_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

NOW="2026-08-25 14:00:00+00"

start_canonical_barrier() {
  local phase="$1"
  local canonical_user_id="$2"
  BARRIER_FIFO="$TMP_DIR/${phase}.release"
  BARRIER_READY="$TMP_DIR/${phase}.ready"
  BARRIER_ERROR="$TMP_DIR/${phase}.holder.err"
  BARRIER_HOLDER_APP="heha-s1-${phase}-holder"
  mkfifo "$BARRIER_FIFO"

  PGAPPNAME="$BARRIER_HOLDER_APP" "${PSQL[@]}" \
    >"$TMP_DIR/${phase}.holder.out" 2>"$BARRIER_ERROR" <<SQL &
select pg_catalog.pg_advisory_lock(
  pg_catalog.hashtextextended(
    'one-heha:canonical:test:${canonical_user_id}',
    0
  )
);
\! printf '%s\n' ready > "$BARRIER_READY"
\! read -r barrier_release < "$BARRIER_FIFO"
select pg_catalog.pg_advisory_unlock(
  pg_catalog.hashtextextended(
    'one-heha:canonical:test:${canonical_user_id}',
    0
  )
);
SQL
  BARRIER_HOLDER_PID=$!
  ACTIVE_PIDS+=("$BARRIER_HOLDER_PID")

  for _ in $(seq 1 200); do
    if [[ -s "$BARRIER_READY" ]]; then
      return 0
    fi
    if ! kill -0 "$BARRIER_HOLDER_PID" 2>/dev/null; then
      echo "${phase} barrier holder exited before acquiring the canonical lock" >&2
      cat "$BARRIER_ERROR" >&2 || true
      return 1
    fi
    sleep 0.05
  done

  echo "${phase} barrier holder did not acquire the canonical lock" >&2
  cat "$BARRIER_ERROR" >&2 || true
  return 1
}

prove_two_clients_waiting() {
  local phase="$1"
  local app_one="$2"
  local app_two="$3"
  local waiting

  for _ in $(seq 1 200); do
    waiting="$("${PSQL[@]}" -c "
      with holder as (
        select
          a.pid as holder_pid,
          l.database,
          l.classid,
          l.objid,
          l.objsubid
        from pg_catalog.pg_stat_activity a
        join pg_catalog.pg_locks l on l.pid = a.pid
        where a.application_name = '${BARRIER_HOLDER_APP}'
          and l.locktype = 'advisory'
          and l.granted
      ), exact_waiters as (
        select a.pid, a.application_name
        from holder h
        join pg_catalog.pg_locks l
          on l.locktype = 'advisory'
         and not l.granted
         and l.database is not distinct from h.database
         and l.classid is not distinct from h.classid
         and l.objid is not distinct from h.objid
         and l.objsubid is not distinct from h.objsubid
        join pg_catalog.pg_stat_activity a on a.pid = l.pid
        where a.application_name in ('${app_one}', '${app_two}')
          and h.holder_pid = any (pg_catalog.pg_blocking_pids(a.pid))
      )
      select count(distinct pid)::text || ':' ||
             count(distinct application_name)::text || ':' ||
             count(*)::text
      from exact_waiters;
    ")"
    if [[ "$waiting" = "2:2:2" ]]; then
      printf 'PASS: %s barrier observed both clients waiting on the canonical advisory lock.\n' "$phase"
      return 0
    fi
    if ! kill -0 "$PID_ONE" 2>/dev/null || ! kill -0 "$PID_TWO" 2>/dev/null; then
      echo "${phase} client exited before both sessions reached the advisory-lock barrier" >&2
      return 1
    fi
    sleep 0.05
  done

  echo "${phase} barrier observed ${waiting:-0}, not two, waiting clients" >&2
  return 1
}

release_canonical_barrier() {
  local phase="$1"
  printf 'release\n' >"$BARRIER_FIFO"
  if ! wait "$BARRIER_HOLDER_PID"; then
    echo "${phase} barrier holder failed while releasing the canonical lock" >&2
    cat "$BARRIER_ERROR" >&2 || true
    return 1
  fi
}

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

SAME_APP_ONE="heha-s1-same-client-1"
SAME_APP_TWO="heha-s1-same-client-2"
start_canonical_barrier "same-request" "50000000-0000-0000-0000-0000000000a1"

PGAPPNAME="$SAME_APP_ONE" PGOPTIONS="-c statement_timeout=20s -c lock_timeout=15s" \
  "${PSQL[@]}" -c "$same_request_sql" >"$TMP_DIR/same-1.out" 2>"$TMP_DIR/same-1.err" &
PID_ONE=$!
ACTIVE_PIDS+=("$PID_ONE")
PGAPPNAME="$SAME_APP_TWO" PGOPTIONS="-c statement_timeout=20s -c lock_timeout=15s" \
  "${PSQL[@]}" -c "$same_request_sql" >"$TMP_DIR/same-2.out" 2>"$TMP_DIR/same-2.err" &
PID_TWO=$!
ACTIVE_PIDS+=("$PID_TWO")

prove_two_clients_waiting "same-request" "$SAME_APP_ONE" "$SAME_APP_TWO"
release_canonical_barrier "same-request"

wait "$PID_ONE"
wait "$PID_TWO"
ACTIVE_PIDS=()

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

CONFLICT_APP_ONE="heha-s1-conflict-client-1"
CONFLICT_APP_TWO="heha-s1-conflict-client-2"
start_canonical_barrier "conflict" "50000000-0000-0000-0000-0000000000ff"

PGAPPNAME="$CONFLICT_APP_ONE" PGOPTIONS="-c statement_timeout=20s -c lock_timeout=15s" \
  "${PSQL[@]}" -c "$conflict_one_sql" >"$TMP_DIR/conflict-1.out" 2>"$TMP_DIR/conflict-1.err" &
PID_ONE=$!
ACTIVE_PIDS+=("$PID_ONE")
PGAPPNAME="$CONFLICT_APP_TWO" PGOPTIONS="-c statement_timeout=20s -c lock_timeout=15s" \
  "${PSQL[@]}" -c "$conflict_two_sql" >"$TMP_DIR/conflict-2.out" 2>"$TMP_DIR/conflict-2.err" &
PID_TWO=$!
ACTIVE_PIDS+=("$PID_TWO")

prove_two_clients_waiting "conflict" "$CONFLICT_APP_ONE" "$CONFLICT_APP_TWO"
release_canonical_barrier "conflict"

set +e
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e
ACTIVE_PIDS=()

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
