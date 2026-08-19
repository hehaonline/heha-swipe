#!/usr/bin/env bash
# Genuine two-session approve/withdraw serialization proof for the composed RC.
# Disposable database only.
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

PSQL=(psql -X "${DATABASE_URL}" -v ON_ERROR_STOP=1 -qtA)
OWNER=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
REVIEWER=dddddddd-dddd-4ddd-8ddd-dddddddddddd
PARTNER=78787878-7878-4787-8787-787878787878
PROOF_TMP="$(mktemp -d)"
trap 'rm -rf "${PROOF_TMP}"' EXIT

redact() {
  sed -E 's/[0-9a-f]{64}/<redacted-snapshot-hash>/g'
}

auth_sql() {
  printf "select set_config('request.jwt.claims','{\"sub\":\"%s\",\"role\":\"authenticated\",\"is_anonymous\":false}',true),set_config('request.jwt.claim.sub','%s',true),set_config('request.jwt.claim.role','authenticated',true);" "${1}" "${1}"
}

wait_idle() {
  local marker="$1"
  for _ in $(seq 1 80); do
    if [ "$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where state='idle in transaction' and query like '%${marker}%'")" = 1 ]; then
      return
    fi
    sleep .25
  done
  echo "FAIL idle wait: ${marker}" >&2
  exit 1
}

wait_lock() {
  local marker="$1"
  for _ in $(seq 1 80); do
    if [ "$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where wait_event_type='Lock' and query like '%${marker}%'")" = 1 ]; then
      return
    fi
    sleep .25
  done
  echo "FAIL lock wait: ${marker}" >&2
  exit 1
}

no_deadlock() {
  if grep -Eqi '40P01|deadlock detected' "$1"; then
    echo 'FAIL deadlock detected' >&2
    redact < "$1" >&2
    exit 1
  fi
}

owner_prepare_publish() {
  local prepare_key="$1"
  local publish_key="$2"
  "${PSQL[@]}" <<SQL | tail -1
begin;
set local role authenticated;
$(auth_sql "${OWNER}")
select (
  public.authorize_existing_partner_profile_preparation(
    '${PARTNER}', array['heha_swipe']::text[],
    'Concurrency Owner', 'Founder', true, true, true, false,
    '${prepare_key}', 'wave1-profile-consent-2026-08-10'
  ) ->> 'profile_snapshot_hash'
) as profile_hash \gset
select public.authorize_partner_profile_publication(
  '${PARTNER}', array['heha_swipe']::text[],
  'Concurrency Owner', 'Founder', '${publish_key}',
  'wave1-profile-consent-2026-08-10', :'profile_hash'
);
select :'profile_hash';
commit;
SQL
}

assert_hidden() {
  "${PSQL[@]}" >/dev/null <<SQL
do \$proof\$
begin
  if exists (
    select 1 from public.public_swipe_partners where id='${PARTNER}'
  ) or exists (
    select 1 from public.public_partner_directory where id='${PARTNER}'
  ) then
    raise exception 'approve/withdraw race left a public partner row';
  end if;
end;
\$proof\$;
SQL
}

echo 'scenario 1: withdrawal commits before waiting staff approval'
HASH_ONE="$(owner_prepare_publish \
  71000000-0000-4000-8000-000000000001 \
  71000000-0000-4000-8000-000000000002)"

mkfifo "${PROOF_TMP}/withdraw_first_in"
psql -X "${DATABASE_URL}" -v ON_ERROR_STOP=1 -qtA \
  < <({
    echo 'begin;'
    echo 'set local role authenticated;'
    auth_sql "${OWNER}"
    echo
    echo "select 'integration_withdraw_winner',public.withdraw_partner_publication_authorization('${PARTNER}',array['heha_swipe']::text[],'Concurrency Owner','Founder','71000000-0000-4000-8000-000000000003','wave1-profile-consent-2026-08-10');"
    cat "${PROOF_TMP}/withdraw_first_in"
  }) > "${PROOF_TMP}/withdraw_first.out" 2>&1 &
WITHDRAW_FIRST_PID=$!
exec 5> "${PROOF_TMP}/withdraw_first_in"
wait_idle integration_withdraw_winner

psql -X "${DATABASE_URL}" -v ON_ERROR_STOP=1 -qtA \
  > "${PROOF_TMP}/review_waiter.out" 2>&1 <<SQL &
begin;
set local role service_role;
select 'integration_review_waiter',public.record_partner_publication_review(
  '71000000-0000-4000-8000-000000000004','${PARTNER}','heha_swipe',
  '${HASH_ONE}','approved','${REVIEWER}',null
);
commit;
SQL
REVIEW_WAITER_PID=$!
wait_lock integration_review_waiter
echo 'commit;' >&5
exec 5>&-
wait "${WITHDRAW_FIRST_PID}"
wait "${REVIEW_WAITER_PID}" || true
no_deadlock "${PROOF_TMP}/withdraw_first.out"
no_deadlock "${PROOF_TMP}/review_waiter.out"
grep -q 'Current owner preparation and publication consent are required before HEHA staff review' \
  "${PROOF_TMP}/review_waiter.out" || {
    redact < "${PROOF_TMP}/review_waiter.out" >&2
    exit 1
  }
"${PSQL[@]}" >/dev/null <<SQL
do \$proof\$
begin
  if (
    select state
    from public.partner_publication_consent_events
    where partner_id='${PARTNER}' and destination='heha_swipe'
      and action='publish_profile'
    order by event_sequence desc
    limit 1
  ) is distinct from 'revoked' then
    raise exception 'withdraw-first race did not leave latest revoke';
  end if;
  if exists (
    select 1 from public.partner_publication_review_events
    where request_key='71000000-0000-4000-8000-000000000004'
  ) then
    raise exception 'losing staff review wrote evidence';
  end if;
  if (
    select status from public.partners where id='${PARTNER}'
  ) is distinct from 'pending' then
    raise exception 'withdraw-first race did not preserve pending lifecycle state';
  end if;
end;
\$proof\$;
SQL
assert_hidden
echo 'scenario 1 PASS: waiting approval rechecked consent and failed closed'

echo 'scenario 2: staff approval commits before waiting withdrawal'
HASH_TWO="$(owner_prepare_publish \
  71000000-0000-4000-8000-000000000005 \
  71000000-0000-4000-8000-000000000006)"

mkfifo "${PROOF_TMP}/review_first_in"
psql -X "${DATABASE_URL}" -v ON_ERROR_STOP=1 -qtA \
  < <({
    echo 'begin;'
    echo 'set local role service_role;'
    echo "select 'integration_review_winner',public.record_partner_publication_review('71000000-0000-4000-8000-000000000007','${PARTNER}','heha_swipe','${HASH_TWO}','approved','${REVIEWER}',null);"
    echo 'reset role;'
    echo "do \$proof\$ begin /* integration_review_winner */ if (select status from public.partners where id='${PARTNER}') is distinct from 'approved' then raise exception 'exact review did not atomically advance pending to approved'; end if; end; \$proof\$;"
    cat "${PROOF_TMP}/review_first_in"
  }) > "${PROOF_TMP}/review_first.out" 2>&1 &
REVIEW_FIRST_PID=$!
exec 6> "${PROOF_TMP}/review_first_in"
wait_idle integration_review_winner

psql -X "${DATABASE_URL}" -v ON_ERROR_STOP=1 -qtA \
  > "${PROOF_TMP}/withdraw_waiter.out" 2>&1 <<SQL &
begin;
set local role authenticated;
$(auth_sql "${OWNER}")
select 'integration_withdraw_waiter',public.withdraw_partner_publication_authorization(
  '${PARTNER}',array['heha_swipe']::text[],
  'Concurrency Owner','Founder','71000000-0000-4000-8000-000000000008',
  'wave1-profile-consent-2026-08-10'
);
commit;
SQL
WITHDRAW_WAITER_PID=$!
wait_lock integration_withdraw_waiter
echo 'commit;' >&6
exec 6>&-
wait "${REVIEW_FIRST_PID}"
wait "${WITHDRAW_WAITER_PID}"
no_deadlock "${PROOF_TMP}/review_first.out"
no_deadlock "${PROOF_TMP}/withdraw_waiter.out"
grep -q 'integration_review_winner' "${PROOF_TMP}/review_first.out" || {
  redact < "${PROOF_TMP}/review_first.out" >&2
  exit 1
}
grep -q 'integration_withdraw_waiter' "${PROOF_TMP}/withdraw_waiter.out" || {
  redact < "${PROOF_TMP}/withdraw_waiter.out" >&2
  exit 1
}
"${PSQL[@]}" >/dev/null <<SQL
do \$proof\$
begin
  if not exists (
    select 1 from public.partner_publication_review_events
    where request_key='71000000-0000-4000-8000-000000000007'
  ) then
    raise exception 'winning staff review evidence is missing';
  end if;
  if (
    select state
    from public.partner_publication_consent_events
    where partner_id='${PARTNER}' and destination='heha_swipe'
      and action='publish_profile'
    order by event_sequence desc
    limit 1
  ) is distinct from 'revoked' then
    raise exception 'approve-first race did not leave latest revoke';
  end if;
  if (
    select status from public.partners where id='${PARTNER}'
  ) is distinct from 'pending' then
    raise exception 'later withdrawal did not return approved legacy status to pending';
  end if;
  if (
    select count(*)
    from public.partner_lifecycle_events
    where partner_id='${PARTNER}'
      and event_type='publication_review_status_approved'
      and actor_id='${REVIEWER}'
  ) <> 1 then
    raise exception 'approve-first race did not record exactly one supported status transition';
  end if;
end;
\$proof\$;
SQL
assert_hidden
echo 'scenario 2 PASS: later withdrawal invalidated committed approval'
echo 'all publication approve/withdraw concurrency scenarios PASS: no deadlock and final state hidden'
