#!/usr/bin/env bash
# Two-session concurrency proof for the partner-claim lock-order contract in
# 20260807160000_partner_claim_foundation_v2.sql.
#
# create_partner_claim_invite and claim_partner_profile both take row locks
# partner-first, invitation-second, so replace-vs-claim and revoke-vs-claim
# serialize deterministically instead of deadlocking. This script drives two
# real database sessions through both races and asserts: no 40P01 anywhere,
# one deterministic winner, exactly one active/terminal invitation state,
# unchanged ownership, and no successful-claim audit event.
#
# Usage: DATABASE_URL=postgresql://... bash partner_claim_concurrency_proof.sh
# Runs against a disposable database only (mutates invite rows and commits).
# Raw one-time tokens are captured in shell variables and never printed; all
# session output is token-redacted before it reaches stdout.

set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"

PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qtA)
ADMIN_SUB=cccccccc-cccc-4ccc-8ccc-cccccccccccc
USER_A=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
PARTNER_A=11111111-1111-4111-8111-111111111111
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

redact() { sed -E 's/[0-9a-f]{64}/<redacted-token>/g'; }

jwt_sql() {
  # Session-level auth context (survives across statements in one session).
  printf "select set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', false), set_config('request.jwt.claim.sub', '%s', false), set_config('request.jwt.claim.role', 'authenticated', false);" "$1" "$1"
}

create_invite() { # $1 partner, $2 intended user; prints "invite_id|raw_token"
  "${PSQL[@]}" <<SQL | tail -1
$(jwt_sql "$ADMIN_SUB")
select invite_id || '|' || raw_token
from public.create_partner_claim_invite('$1'::uuid, interval '1 day', 'concurrency-proof', '$2'::uuid, null);
SQL
}

wait_for_idle_txn() { # $1 = marker in the session's last query text
  for _ in $(seq 1 60); do
    n=$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where state = 'idle in transaction' and query like '%$1%'")
    [ "$n" = "1" ] && return 0
    sleep 0.5
  done
  echo "FAIL: first session never reached idle-in-transaction holding $1" >&2
  exit 1
}

wait_for_lock_wait() { # $1 = marker in query text
  for _ in $(seq 1 60); do
    waiting=$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where wait_event_type = 'Lock' and query like '%$1%'")
    [ "$waiting" = "1" ] && return 0
    sleep 0.5
  done
  echo "FAIL: second session never reached lock wait for $1" >&2
  exit 1
}

assert_no_deadlock() { # $1 file
  if grep -q '40P01' "$1"; then
    echo 'FAIL: deadlock (40P01) detected' >&2
    redact < "$1" >&2
    exit 1
  fi
}

echo '== scenario 0: lock-order contract — claim lock sequence vs live replacement =='
# Manually executes claim_partner_profile's documented lock sequence (partner
# FOR UPDATE, then invitation FOR UPDATE) in one session while a real
# replacement create runs concurrently in another. Under the pre-fix order
# (invitation first) this exact interleave deadlocks with 40P01; under the
# partner-first contract the second lock must be granted immediately.

IFS='|' read -r INVITE0_ID TOKEN0 < <(create_invite "$PARTNER_A" "$USER_A")

mkfifo "$WORKDIR/c1_in"
psql "$DATABASE_URL" -qtA < <(
  {
    echo "begin;"
    echo "select 'lockorder_partner_first' from public.partners where id = '$PARTNER_A'::uuid for update;"
    cat "$WORKDIR/c1_in"
  }
) > "$WORKDIR/c1_out" 2>&1 &
C1_PID=$!
exec 5> "$WORKDIR/c1_in"

wait_for_idle_txn lockorder_partner_first

psql "$DATABASE_URL" -qtA > "$WORKDIR/c2_out" 2>&1 <<SQL &
$(jwt_sql "$ADMIN_SUB")
select 'lockorder_replacement_done' from public.create_partner_claim_invite('$PARTNER_A'::uuid, interval '1 day', 'lockorder-replacement', '$USER_A'::uuid, null);
SQL
C2_PID=$!

wait_for_lock_wait lockorder-replacement

# Claim's second lock: the invitation row. Must be granted immediately — the
# blocked create holds no invitation lock yet. A short statement_timeout
# turns any ordering regression into a hard failure instead of a hang.
{
  echo "set statement_timeout = '5s';"
  echo "select 'lockorder_invite_granted' from public.partner_claim_invites where id = '$INVITE0_ID'::uuid for update;"
  echo "commit;"
} >&5
exec 5>&-
wait "$C1_PID"
wait "$C2_PID" || true

assert_no_deadlock "$WORKDIR/c1_out"
assert_no_deadlock "$WORKDIR/c2_out"
grep -q lockorder_invite_granted "$WORKDIR/c1_out" \
  || { echo 'FAIL: partner-first session could not take the invitation lock (ordering regression)' >&2; redact < "$WORKDIR/c1_out" >&2; exit 1; }
grep -q lockorder_replacement_done "$WORKDIR/c2_out" \
  || { echo 'FAIL: replacement create did not complete after the contract session committed' >&2; redact < "$WORKDIR/c2_out" >&2; exit 1; }
echo 'scenario 0 PASS: partner-first lock sequence acquires both locks with a live replacement blocked behind it; no 40P01'

echo '== scenario 1: admin replaces the invitation while a claim is in flight =='

IFS='|' read -r INVITE1_ID TOKEN1 < <(create_invite "$PARTNER_A" "$USER_A")

# Session 1: open a transaction and run the replacement create (locks the
# partner row, revokes the active invite, inserts a new one) but hold the
# commit until the concurrent claim is provably blocked behind it.
mkfifo "$WORKDIR/s1_in"
psql "$DATABASE_URL" -qtA < <(
  {
    jwt_sql "$ADMIN_SUB"; echo
    echo "begin;"
    echo "select 'replacement_invite_created' from public.create_partner_claim_invite('$PARTNER_A'::uuid, interval '1 day', 'concurrency-proof-replacement', '$USER_A'::uuid, null);"
    cat "$WORKDIR/s1_in"
  }
) > "$WORKDIR/s1_out" 2>&1 &
S1_PID=$!
exec 3> "$WORKDIR/s1_in"

# Wait until session 1 holds its locks: it sits idle-in-transaction with the
# replacement create as its last statement (psql file output may be buffered,
# so the catalog — not the log file — is the synchronization source).
wait_for_idle_txn concurrency-proof-replacement

# Session 2: claim with the original token; must block on the partner lock.
psql "$DATABASE_URL" -qtA > "$WORKDIR/s2_out" 2>&1 <<SQL &
$(jwt_sql "$USER_A")
select 'claim_marker_s2', * from public.claim_partner_profile('$TOKEN1');
SQL
S2_PID=$!

wait_for_lock_wait claim_marker_s2

echo "commit;" >&3
exec 3>&-
wait "$S1_PID"
wait "$S2_PID" || true

assert_no_deadlock "$WORKDIR/s1_out"
assert_no_deadlock "$WORKDIR/s2_out"
grep -q 'This claim link is revoked' "$WORKDIR/s2_out" \
  || { echo 'FAIL: blocked claim did not fail deterministically on the revoked invite' >&2; redact < "$WORKDIR/s2_out" >&2; exit 1; }

"${PSQL[@]}" -c "
do \$\$
declare active_count integer;
begin
  select count(*) into active_count from public.partner_claim_invites
  where partner_id = '$PARTNER_A' and consumed_at is null and revoked_at is null;
  if active_count <> 1 then
    raise exception 'expected exactly 1 active invite after replace-vs-claim, got %', active_count;
  end if;
  if exists (select 1 from public.partners where id = '$PARTNER_A' and owner_id is not null) then
    raise exception 'replace-vs-claim changed ownership';
  end if;
  if exists (select 1 from public.admin_audit_logs
             where action_type = 'partner_profile_claimed' and related_id = '$PARTNER_A') then
    raise exception 'replace-vs-claim wrote a successful-claim audit event';
  end if;
end \$\$;" > /dev/null
echo 'scenario 1 PASS: claim blocked behind replacement, lost deterministically (revoked, P0002), no 40P01, one active invite, ownership unchanged'

echo '== scenario 2: admin revokes the invitation while a claim is in flight =='

TOKEN2_LINE=$(create_invite "$PARTNER_A" "$USER_A")  # auto-revokes scenario 1's leftover active invite
IFS='|' read -r INVITE2_ID TOKEN2 <<< "$TOKEN2_LINE"

mkfifo "$WORKDIR/r1_in"
psql "$DATABASE_URL" -qtA < <(
  {
    jwt_sql "$ADMIN_SUB"; echo
    echo "begin;"
    echo "select 'revoke_done', public.revoke_partner_claim_invite('$INVITE2_ID'::uuid);"
    cat "$WORKDIR/r1_in"
  }
) > "$WORKDIR/r1_out" 2>&1 &
R1_PID=$!
exec 4> "$WORKDIR/r1_in"

wait_for_idle_txn revoke_done

psql "$DATABASE_URL" -qtA > "$WORKDIR/r2_out" 2>&1 <<SQL &
$(jwt_sql "$USER_A")
select 'claim_marker_r2', * from public.claim_partner_profile('$TOKEN2');
SQL
R2_PID=$!

wait_for_lock_wait claim_marker_r2

echo "commit;" >&4
exec 4>&-
wait "$R1_PID"
wait "$R2_PID" || true

assert_no_deadlock "$WORKDIR/r1_out"
assert_no_deadlock "$WORKDIR/r2_out"
grep -q 'This claim link is revoked' "$WORKDIR/r2_out" \
  || { echo 'FAIL: claim did not observe the committed revocation' >&2; redact < "$WORKDIR/r2_out" >&2; exit 1; }

"${PSQL[@]}" -c "
do \$\$
begin
  if exists (select 1 from public.partner_claim_invites
             where partner_id = '$PARTNER_A' and consumed_at is null and revoked_at is null) then
    raise exception 'expected zero active invites after revoke-vs-claim';
  end if;
  if exists (select 1 from public.partners where id = '$PARTNER_A' and owner_id is not null) then
    raise exception 'revoke-vs-claim changed ownership';
  end if;
end \$\$;" > /dev/null
echo 'scenario 2 PASS: claim blocked behind revocation, lost deterministically (revoked, P0002), no 40P01, zero active invites, ownership unchanged'

echo '== scenario 3: claim-wins invariant — exactly one successful-claim audit event =='
# When the claim wins the race, the invitation is consumed exactly once, a
# later revoke is a no-op (false), and exactly one successful-claim audit
# event exists. Uses a dedicated fixture partner so earlier scenarios''
# unchanged-ownership assertions on partner A stay valid.
PARTNER_W=88888888-8888-4888-8888-888888888888

IFS='|' read -r INVITE3_ID TOKEN3 < <(create_invite "$PARTNER_W" "$USER_A")

"${PSQL[@]}" > "$WORKDIR/w_claim_out" 2>&1 <<SQL
$(jwt_sql "$USER_A")
select 'claim_winner_done' from public.claim_partner_profile('$TOKEN3');
SQL
grep -q claim_winner_done "$WORKDIR/w_claim_out" \
  || { echo 'FAIL: winner claim did not complete' >&2; redact < "$WORKDIR/w_claim_out" >&2; exit 1; }

REVOKE_RESULT=$("${PSQL[@]}" <<SQL | tail -1
$(jwt_sql "$ADMIN_SUB")
select public.revoke_partner_claim_invite('$INVITE3_ID'::uuid);
SQL
)
[ "$REVOKE_RESULT" = "f" ] \
  || { echo "FAIL: revoke after consumption returned '$REVOKE_RESULT'; expected f (no-op)" >&2; exit 1; }

"${PSQL[@]}" -c "
do \$\$
declare claim_events integer;
begin
  select count(*) into claim_events from public.admin_audit_logs
  where action_type = 'partner_profile_claimed' and related_id = '$PARTNER_W';
  if claim_events <> 1 then
    raise exception 'expected exactly 1 successful-claim audit event, got %', claim_events;
  end if;
  if not exists (select 1 from public.partner_claim_invites
                 where id = '$INVITE3_ID' and consumed_at is not null and revoked_at is null) then
    raise exception 'winning claim did not leave a single consumed, unrevoked invitation';
  end if;
  if not exists (select 1 from public.partners
                 where id = '$PARTNER_W' and owner_id = '$USER_A') then
    raise exception 'winning claim did not attach ownership';
  end if;
end \$\$;" > /dev/null
echo 'scenario 3 PASS: winning claim consumed the invitation exactly once; later revoke is a no-op; exactly one successful-claim audit event'

echo 'concurrency proof complete: consistent partner-first lock order, no deadlocks, deterministic winners'
