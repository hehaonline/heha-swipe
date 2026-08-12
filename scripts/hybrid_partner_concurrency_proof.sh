#!/usr/bin/env bash
# Real two-session concurrency proof for PR #120. Disposable DB only.
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qtA)
ADMIN=cccccccc-cccc-4ccc-8ccc-cccccccccccc
USER_A=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
PARTNER_A=11111111-1111-4111-8111-111111111111
PARTNER_W=44444444-4444-4444-8444-444444444444
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

redact(){ sed -E 's/[0-9a-f]{64}/<redacted-token>/g'; }
jwt_sql(){ printf "select set_config('request.jwt.claims','{\"sub\":\"%s\",\"role\":\"authenticated\"}',false),set_config('request.jwt.claim.sub','%s',false),set_config('request.jwt.claim.role','authenticated',false);" "$1" "$1"; }
create_invite(){
  "${PSQL[@]}" <<SQL | tail -1
$(jwt_sql "$ADMIN")
select invite_id||'|'||raw_token from public.create_partner_claim_invite('$1'::uuid,interval '1 day','concurrency-proof','$2'::uuid,null);
SQL
}
wait_idle(){ local marker="$1"; for _ in $(seq 1 80); do [ "$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where state='idle in transaction' and query like '%$marker%'")" = 1 ] && return; sleep .25; done; echo "FAIL idle wait: $marker" >&2; exit 1; }
wait_lock(){ local marker="$1"; for _ in $(seq 1 80); do [ "$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where wait_event_type='Lock' and query like '%$marker%'")" = 1 ] && return; sleep .25; done; echo "FAIL lock wait: $marker" >&2; exit 1; }
no_deadlock(){ if grep -Eqi '40P01|deadlock detected' "$1"; then echo 'FAIL deadlock detected' >&2; redact < "$1" >&2; exit 1; fi; }

echo 'scenario 0: partner-first lock contract vs replacement'
IFS='|' read -r I0 T0 < <(create_invite "$PARTNER_A" "$USER_A")
mkfifo "$WORKDIR/s0in"
psql "$DATABASE_URL" -qtA < <({ echo 'begin;'; echo "select 's0_partner_lock' from public.partners where id='$PARTNER_A' for update;"; cat "$WORKDIR/s0in"; }) >"$WORKDIR/s0a" 2>&1 & P0A=$!
exec 5>"$WORKDIR/s0in"
wait_idle s0_partner_lock
psql "$DATABASE_URL" -qtA >"$WORKDIR/s0b" 2>&1 <<SQL &
$(jwt_sql "$ADMIN")
select 's0_replace_done' from public.create_partner_claim_invite('$PARTNER_A',interval '1 day','replacement','$USER_A',null);
SQL
P0B=$!
wait_lock replacement
{ echo "set statement_timeout='5s';"; echo "select 's0_invite_lock' from public.partner_claim_invites where id='$I0' for update;"; echo 'commit;'; } >&5
exec 5>&-
wait "$P0A"; wait "$P0B"
no_deadlock "$WORKDIR/s0a"; no_deadlock "$WORKDIR/s0b"
grep -q s0_invite_lock "$WORKDIR/s0a" || { redact <"$WORKDIR/s0a" >&2; exit 1; }
echo 'scenario 0 PASS'

echo 'scenario 1: replace vs claim'
IFS='|' read -r I1 T1 < <(create_invite "$PARTNER_A" "$USER_A")
mkfifo "$WORKDIR/s1in"
psql "$DATABASE_URL" -qtA < <({ jwt_sql "$ADMIN"; echo; echo 'begin;'; echo "select 's1_replace_done' from public.create_partner_claim_invite('$PARTNER_A',interval '1 day','replace-race','$USER_A',null);"; cat "$WORKDIR/s1in"; }) >"$WORKDIR/s1a" 2>&1 & P1A=$!
exec 6>"$WORKDIR/s1in"
wait_idle s1_replace_done
psql "$DATABASE_URL" -qtA >"$WORKDIR/s1b" 2>&1 <<SQL &
$(jwt_sql "$USER_A")
select 's1_claim_marker',* from public.claim_partner_profile('$T1');
SQL
P1B=$!
wait_lock s1_claim_marker
echo commit\; >&6; exec 6>&-
wait "$P1A"; wait "$P1B" || true
no_deadlock "$WORKDIR/s1a"; no_deadlock "$WORKDIR/s1b"
grep -q 'This claim link is not valid' "$WORKDIR/s1b" || { redact <"$WORKDIR/s1b" >&2; exit 1; }
"${PSQL[@]}" -c "do \$\$ begin
 if (select count(*) from public.partner_claim_invites where partner_id='$PARTNER_A' and consumed_at is null and revoked_at is null)<>1 then raise exception 'expected one active invite'; end if;
 if exists(select 1 from public.partners where id='$PARTNER_A' and owner_id is not null) then raise exception 'replace race changed owner'; end if;
 if exists(select 1 from public.partner_lifecycle_events where partner_id='$PARTNER_A' and event_type='claim_redeemed') then raise exception 'losing claim audited success'; end if;
end \$\$;" >/dev/null
echo 'scenario 1 PASS'

echo 'scenario 2: revoke vs claim'
IFS='|' read -r I2 T2 < <(create_invite "$PARTNER_A" "$USER_A")
mkfifo "$WORKDIR/s2in"
psql "$DATABASE_URL" -qtA < <({ jwt_sql "$ADMIN"; echo; echo 'begin;'; echo "select 's2_revoke_marker',public.revoke_partner_claim_invite('$I2');"; cat "$WORKDIR/s2in"; }) >"$WORKDIR/s2a" 2>&1 & P2A=$!
exec 7>"$WORKDIR/s2in"
wait_idle s2_revoke_marker
psql "$DATABASE_URL" -qtA >"$WORKDIR/s2b" 2>&1 <<SQL &
$(jwt_sql "$USER_A")
select 's2_claim_marker',* from public.claim_partner_profile('$T2');
SQL
P2B=$!
wait_lock s2_claim_marker
echo commit\; >&7; exec 7>&-
wait "$P2A"; wait "$P2B" || true
no_deadlock "$WORKDIR/s2a"; no_deadlock "$WORKDIR/s2b"
grep -q 'This claim link is not valid' "$WORKDIR/s2b" || { redact <"$WORKDIR/s2b" >&2; exit 1; }
"${PSQL[@]}" -c "do \$\$ begin
 if exists(select 1 from public.partner_claim_invites where partner_id='$PARTNER_A' and consumed_at is null and revoked_at is null) then raise exception 'active invite remains'; end if;
 if exists(select 1 from public.partners where id='$PARTNER_A' and owner_id is not null) then raise exception 'revoke race changed owner'; end if;
end \$\$;" >/dev/null
echo 'scenario 2 PASS'

echo 'scenario 3: genuine claim-wins vs revoke'
IFS='|' read -r I3 T3 < <(create_invite "$PARTNER_W" "$USER_A")
mkfifo "$WORKDIR/s3in"
psql "$DATABASE_URL" -qtA < <({ jwt_sql "$USER_A"; echo; echo 'begin;'; echo "select 's3_claim_winner',* from public.claim_partner_profile('$T3');"; cat "$WORKDIR/s3in"; }) >"$WORKDIR/s3a" 2>&1 & P3A=$!
exec 8>"$WORKDIR/s3in"
wait_idle s3_claim_winner
psql "$DATABASE_URL" -qtA >"$WORKDIR/s3b" 2>&1 <<SQL &
$(jwt_sql "$ADMIN")
select 's3_revoke_waiter',public.revoke_partner_claim_invite('$I3');
SQL
P3B=$!
wait_lock s3_revoke_waiter
echo commit\; >&8; exec 8>&-
wait "$P3A"; wait "$P3B"
no_deadlock "$WORKDIR/s3a"; no_deadlock "$WORKDIR/s3b"
grep -q 's3_revoke_waiter|f' "$WORKDIR/s3b" || { redact <"$WORKDIR/s3b" >&2; exit 1; }
"${PSQL[@]}" -c "do \$\$ begin
 if (select count(*) from public.partner_lifecycle_events where partner_id='$PARTNER_W' and event_type='claim_redeemed')<>1 then raise exception 'expected exactly one claim audit'; end if;
 if not exists(select 1 from public.partner_claim_invites where id='$I3' and consumed_at is not null and revoked_at is null) then raise exception 'winner invite not consumed'; end if;
 if not exists(select 1 from public.partners where id='$PARTNER_W' and owner_id='$USER_A') then raise exception 'winner owner missing'; end if;
end \$\$;" >/dev/null
echo 'scenario 3 PASS'

echo 'all hybrid concurrency scenarios PASS: no 40P01, deterministic outcomes, one claim success event'
