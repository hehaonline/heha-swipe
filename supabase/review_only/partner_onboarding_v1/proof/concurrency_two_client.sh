#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must point to the disposable CI database}"

# PGOPTIONS=-c heha.review_only=on is supplied by the disposable CI job and is
# intentionally inherited by every child psql process.
PSQL=(psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -qAt)

PREFLIGHT="$("${PSQL[@]}" -c "
  select coalesce(pg_catalog.inet_server_addr()::text, 'missing')
    || ':' || pg_catalog.current_database()
    || ':' || coalesce(pg_catalog.current_setting('heha.review_only', true), '');
")"
case "$PREFLIGHT" in
  127.0.0.1:partner_onboarding_review:on|::1:partner_onboarding_review:on)
    ;;
  *)
    echo "HEHA_REVIEW_ONLY_GUARD: concurrency proof requires loopback partner_onboarding_review and external heha.review_only=on (got $PREFLIGHT)" >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OPERATOR='00000000-0000-4000-8000-0000000000a1'
SIGNER='00000000-0000-4000-8000-0000000000b2'
APPLICANT='00000000-0000-4000-8000-0000000000c3'
OTHER_APPLICANT='00000000-0000-4000-8000-0000000000d4'
REVIEWER='00000000-0000-4000-8000-0000000000e5'
LEGAL_ADMIN='00000000-0000-4000-8000-000000000104'
EVIDENCE_REVIEWER='00000000-0000-4000-8000-000000000105'
RELEASE_REVIEWER='00000000-0000-4000-8000-000000000106'
SWIPE_ATTESTOR='00000000-0000-4000-8000-000000000101'
WEBSITE_ATTESTOR='00000000-0000-4000-8000-000000000102'
LOCAL_ATTESTOR='00000000-0000-4000-8000-000000000103'
PARTNER_ONE='91000000-0000-4000-8000-000000000001'
PARTNER_TWO='91000000-0000-4000-8000-000000000002'
PARTNER_BUSINESS_RACE='91000000-0000-4000-8000-000000000003'
SHARED_LOCAL_TARGET='93000000-0000-4000-8000-000000000001'
TOKEN_ONE='concurrency_invite_token_abcdefghijklmnopqrstuvwxyz_001'
TOKEN_TWO='concurrency_invite_token_abcdefghijklmnopqrstuvwxyz_002'
TOKEN_BUSINESS_RACE='concurrency_business_invite_token_abcdefghijklmnop_003'
ASSERTIONS='{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic concurrency terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}'

run_authenticated() {
  local actor="$1"
  local statement="$2"
  "${PSQL[@]}" -c "
    begin;
    set local role authenticated;
    select pg_catalog.set_config('request.jwt.claim.sub', '$actor', true);
    $statement
    commit;
  "
}

run_service() {
  local statement="$1"
  "${PSQL[@]}" -c "
    begin;
    set local role service_role;
    $statement
    commit;
  "
}

run_admin() {
  local statement="$1"
  "${PSQL[@]}" -c "
    begin;
    $statement
    commit;
  "
}

last_uuid() {
  grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' | tail -n 1
}

expect_generic_loser() {
  local file="$1"
  if ! grep -q 'HEHA_PARTNER_REQUEST_DENIED' "$file"; then
    echo "losing client failed for an unexpected reason" >&2
    cat "$file" >&2 || true
    exit 1
  fi
}

"${PSQL[@]}" <<SQL
begin;
insert into public.partners (
  id, name, legal_name, postal_code, category, categories, location, bio,
  image_url, gallery_urls, status, complete_pct, heha_partner,
  website_eligible, swipe_eligible, local_eligible, local_lane,
  primary_cta_destination, primary_cta_label, primary_cta_path, is_test_record
) values
  (
    '$PARTNER_ONE', 'Synthetic Concurrency One',
    'Synthetic Concurrency One LLC', '33611', 'Restaurant', array['Restaurant'],
    'Tampa, FL', 'Synthetic concurrency partner one',
    'https://example.invalid/concurrency-one.jpg', '[]'::jsonb,
    'pending', 100, false, false, false, false, 'meals',
    'local', 'Order locally', '/restaurants/$SHARED_LOCAL_TARGET', false
  ),
  (
    '$PARTNER_TWO', 'Synthetic Concurrency Two',
    'Synthetic Concurrency Two LLC', '33612', 'Restaurant', array['Restaurant'],
    'Tampa, FL', 'Synthetic concurrency partner two',
    'https://example.invalid/concurrency-two.jpg', '[]'::jsonb,
    'pending', 100, false, false, false, false, 'meals',
    'local', 'Order locally', '/restaurants/$SHARED_LOCAL_TARGET', false
  );

insert into partner_onboarding_private.staff_bootstrap_authorizations (
  id, user_id, authority_type, authorization_reference,
  authorized_by_database_role, authorized_at
) values (
  '94000000-0000-4000-8000-000000000001', '$REVIEWER',
  'security_admin', 'SYNTHETIC-CONCURRENCY-BOOTSTRAP-AUTHORIZATION',
  current_user, '2026-08-31 12:00:00+00'::timestamptz
);

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', '$REVIEWER', true);
select partner_onboarding_private.bootstrap_staff_authority_v1('$REVIEWER', 'security_admin');
select partner_onboarding_private.grant_staff_authority_v1('$LEGAL_ADMIN', 'legal_admin', '$REVIEWER');
select partner_onboarding_private.grant_staff_authority_v1('$EVIDENCE_REVIEWER', 'evidence_reviewer', '$REVIEWER');
select partner_onboarding_private.grant_staff_authority_v1('$RELEASE_REVIEWER', 'release_reviewer', '$REVIEWER');
select partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000101', 'swipe_attestor', '$REVIEWER'
);
select partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000102', 'website_attestor', '$REVIEWER'
);
select partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000103', 'local_attestor', '$REVIEWER'
);
select partner_onboarding_private.reconcile_partner_business_registry_v1('$REVIEWER');
select partner_onboarding_private.set_runtime_config_v1(
  true, true, false, false, false, false,
  'partner-onboarding-concurrency-claim-application', '$REVIEWER'
);
select partner_onboarding_private.issue_partner_invitation_v1(
  '$PARTNER_ONE', '$OPERATOR', 'restaurant', 'operator_only', '$TOKEN_ONE',
  pg_catalog.clock_timestamp() + interval '2 days', '$REVIEWER'
);
select partner_onboarding_private.issue_partner_invitation_v1(
  '$PARTNER_TWO', '$OPERATOR', 'restaurant', 'operator_only', '$TOKEN_TWO',
  pg_catalog.clock_timestamp() + interval '2 days', '$REVIEWER'
);
reset role;
commit;
SQL

# DUPLICATE_SELF_APPLICATION_BUSINESS_KEY_RACE: two distinct applicants and
# request keys race the same normalized business identity. Exactly one app,
# registry root, and raw partner may win; the other client is generic-denied.
business_application_one_sql="select public.create_or_resume_partner_application_v1(
  '92000000-0000-4000-8000-000000000000',
  '{\"name\":\"Synthetic Concurrency Business Race\",\"legal_name\":\"Synthetic Concurrency Business Race LLC\",\"postal_code\":\"33613\",\"location\":\"Tampa, FL\",\"category\":\"Restaurant\",\"categories\":[\"Restaurant\"]}'::jsonb
);"
business_application_two_sql="select public.create_or_resume_partner_application_v1(
  '92000000-0000-4000-8000-000000000100',
  '{\"name\":\"  Synthetic   Concurrency Business Race  \",\"legal_name\":\"Synthetic Concurrency Business Race LLC\",\"postal_code\":\"33613\",\"location\":\" tampa, fl \",\"category\":\"Restaurant\",\"categories\":[\"Restaurant\"]}'::jsonb
);"

set +e
run_authenticated "$APPLICANT" "$business_application_one_sql" >"$TMP_DIR/business-app-1.out" 2>"$TMP_DIR/business-app-1.err" &
PID_ONE=$!
run_authenticated "$OTHER_APPLICANT" "$business_application_two_sql" >"$TMP_DIR/business-app-2.out" 2>"$TMP_DIR/business-app-2.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e

if ! { [[ "$STATUS_ONE" -eq 0 && "$STATUS_TWO" -ne 0 ]] || [[ "$STATUS_ONE" -ne 0 && "$STATUS_TWO" -eq 0 ]]; }; then
  echo "duplicate self-application business-key race did not produce exactly one canonical winner" >&2
  echo "applicant-one=$STATUS_ONE applicant-two=$STATUS_TWO" >&2
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/business-app-1.err"
else
  expect_generic_loser "$TMP_DIR/business-app-2.err"
fi

BUSINESS_CANONICAL_COUNTS="$("${PSQL[@]}" -c "
  with canonical as (
    select state.partner_id
    from partner_onboarding_private.partner_state state
    where state.business_key_sha256 = partner_onboarding_private.normalized_business_key(
      'Synthetic Concurrency Business Race', 'Tampa, FL'
    )
    union all
    select application.partner_id
    from partner_onboarding_private.partner_applications application
    where application.business_key_sha256 = partner_onboarding_private.normalized_business_key(
      'Synthetic Concurrency Business Race', 'Tampa, FL'
    )
  )
  select count(*)::text || ':' || count(distinct partner_id)::text from canonical;
")"
if [[ "$BUSINESS_CANONICAL_COUNTS" != '1:1' ]]; then
  echo "business-key race created non-canonical relationship rows: $BUSINESS_CANONICAL_COUNTS" >&2
  exit 1
fi

BUSINESS_RAW_ROOT_COUNTS="$("${PSQL[@]}" -c "
  select
    (select count(*)
     from public.partners partner
     where partner_onboarding_private.normalized_business_key(
       partner.name,
       coalesce(partner.location, partner.neighborhood, partner.postal_code)
     ) = partner_onboarding_private.normalized_business_key(
       'Synthetic Concurrency Business Race', 'Tampa, FL'
     ))::text
    || ':' ||
    (select count(*)
     from partner_onboarding_private.partner_business_registry registry
     where registry.business_key_sha256 =
       partner_onboarding_private.normalized_business_key(
         'Synthetic Concurrency Business Race', 'Tampa, FL'
       ))::text;
")"
if [[ "$BUSINESS_RAW_ROOT_COUNTS" != '1:1' ]]; then
  echo "DUPLICATE_SELF_APPLICATION_RAW_PROFILE_COUNT violated one raw/root reservation: $BUSINESS_RAW_ROOT_COUNTS" >&2
  exit 1
fi

# EXISTING_PROFILE_INVITATION_PRECEDENCE: a fixed existing profile is first
# reconciled and invited through the protected admin path. A later application
# for the same normalized identity is deterministically denied; this is a
# boundary proof, not mislabeled as a symmetric race.
run_admin "
  insert into public.partners (
    id, name, legal_name, postal_code, category, categories, location, bio,
    image_url, gallery_urls, status, complete_pct, heha_partner,
    website_eligible, swipe_eligible, local_eligible, local_lane,
    primary_cta_destination, primary_cta_label, primary_cta_path, is_test_record
  ) values (
    '$PARTNER_BUSINESS_RACE', 'Synthetic Concurrency Existing Invite',
    'Synthetic Concurrency Existing Invite LLC', '33614', 'Restaurant', array['Restaurant'],
    'Tampa, FL', 'Synthetic deterministic invitation precedence', null, '[]'::jsonb,
    'pending', 20, false, false, false, false, 'meals',
    'local', 'Order locally', '/restaurants/$PARTNER_BUSINESS_RACE', false
  );
" >/dev/null

run_authenticated "$REVIEWER" "
  select partner_onboarding_private.reconcile_partner_business_registry_v1('$REVIEWER');
  select partner_onboarding_private.issue_partner_invitation_v1(
    '$PARTNER_BUSINESS_RACE', '$OPERATOR', 'restaurant', 'operator_only',
    '$TOKEN_BUSINESS_RACE', pg_catalog.clock_timestamp() + interval '2 days',
    '$REVIEWER'
  );
" >/dev/null

existing_profile_application_sql="select public.create_or_resume_partner_application_v1(
  '92000000-0000-4000-8000-000000000101',
  '{\"name\":\"Synthetic Concurrency Existing Invite\",\"legal_name\":\"Synthetic Concurrency Existing Invite LLC\",\"postal_code\":\"33614\",\"location\":\"Tampa, FL\",\"category\":\"Restaurant\",\"categories\":[\"Restaurant\"]}'::jsonb
);"
set +e
run_authenticated "$APPLICANT" "$existing_profile_application_sql" >"$TMP_DIR/existing-profile-app.out" 2>"$TMP_DIR/existing-profile-app.err"
EXISTING_PROFILE_STATUS=$?
set -e
if [[ "$EXISTING_PROFILE_STATUS" -eq 0 ]]; then
  echo 'existing-profile invitation precedence allowed a duplicate application' >&2
  exit 1
fi
expect_generic_loser "$TMP_DIR/existing-profile-app.err"

EXISTING_PROFILE_COUNTS="$("${PSQL[@]}" -c "
  select
    (select count(*) from public.partners partner
     where partner_onboarding_private.normalized_business_key(
       partner.name, coalesce(partner.location, partner.neighborhood, partner.postal_code)
     ) = partner_onboarding_private.normalized_business_key(
       'Synthetic Concurrency Existing Invite', 'Tampa, FL'
     ))::text || ':' ||
    (select count(*) from partner_onboarding_private.partner_business_registry registry
     where registry.business_key_sha256 = partner_onboarding_private.normalized_business_key(
       'Synthetic Concurrency Existing Invite', 'Tampa, FL'
     ))::text || ':' ||
    (select count(*) from partner_onboarding_private.partner_state state
     where state.partner_id = '$PARTNER_BUSINESS_RACE')::text;
")"
if [[ "$EXISTING_PROFILE_COUNTS" != '1:1:1' ]]; then
  echo "existing-profile invitation precedence lost canonical identity: $EXISTING_PROFILE_COUNTS" >&2
  exit 1
fi

# Identical claim requests serialize and return one stable claim receipt.
same_claim_sql="select (
  public.claim_partner_invitation_v1(
    '$TOKEN_ONE', '92000000-0000-4000-8000-000000000001'
  ) ->> 'claim_evidence_id'
)::uuid;"

run_authenticated "$OPERATOR" "$same_claim_sql" >"$TMP_DIR/claim-same-1.out" 2>"$TMP_DIR/claim-same-1.err" &
PID_ONE=$!
run_authenticated "$OPERATOR" "$same_claim_sql" >"$TMP_DIR/claim-same-2.out" 2>"$TMP_DIR/claim-same-2.err" &
PID_TWO=$!
wait "$PID_ONE"
wait "$PID_TWO"

CLAIM_ONE="$(last_uuid <"$TMP_DIR/claim-same-1.out")"
CLAIM_TWO="$(last_uuid <"$TMP_DIR/claim-same-2.out")"
if [[ -z "$CLAIM_ONE" || "$CLAIM_ONE" != "$CLAIM_TWO" ]]; then
  echo "same-request claim race did not return one stable receipt" >&2
  cat "$TMP_DIR/claim-same-1.err" "$TMP_DIR/claim-same-2.err" >&2 || true
  exit 1
fi

CLAIM_COUNT="$("${PSQL[@]}" -c "
  select count(*) from partner_onboarding_private.partner_claims
  where partner_id = '$PARTNER_ONE';
")"
if [[ "$CLAIM_COUNT" != '1' ]]; then
  echo "same-request claim race created $CLAIM_COUNT receipts" >&2
  exit 1
fi

# Two different request keys racing for one invitation produce exactly one
# winner and one privacy-preserving loser.
conflict_claim_one="select (
  public.claim_partner_invitation_v1(
    '$TOKEN_TWO', '92000000-0000-4000-8000-000000000002'
  ) ->> 'claim_evidence_id'
)::uuid;"
conflict_claim_two="select (
  public.claim_partner_invitation_v1(
    '$TOKEN_TWO', '92000000-0000-4000-8000-000000000003'
  ) ->> 'claim_evidence_id'
)::uuid;"

set +e
run_authenticated "$OPERATOR" "$conflict_claim_one" >"$TMP_DIR/claim-conflict-1.out" 2>"$TMP_DIR/claim-conflict-1.err" &
PID_ONE=$!
run_authenticated "$OPERATOR" "$conflict_claim_two" >"$TMP_DIR/claim-conflict-2.out" 2>"$TMP_DIR/claim-conflict-2.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e

if ! { [[ "$STATUS_ONE" -eq 0 && "$STATUS_TWO" -ne 0 ]] || [[ "$STATUS_ONE" -ne 0 && "$STATUS_TWO" -eq 0 ]]; }; then
  echo "conflicting claim race did not produce exactly one winner" >&2
  echo "status one=$STATUS_ONE status two=$STATUS_TWO" >&2
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/claim-conflict-1.err"
else
  expect_generic_loser "$TMP_DIR/claim-conflict-2.err"
fi

AGREEMENT_ID="$(run_authenticated "$LEGAL_ADMIN" "
  select partner_onboarding_private.register_partner_agreement_version_v1(
    'restaurant', 'restaurant-concurrency-v1',
    'Synthetic Concurrency Restaurant Agreement',
    pg_catalog.clock_timestamp() - interval '1 day',
    'SYNTHETIC CONCURRENCY DOCUMENT -- NO LEGAL EFFECT',
    partner_onboarding_private.sha256_text(
      'SYNTHETIC CONCURRENCY DOCUMENT -- NO LEGAL EFFECT'
    ),
    'I agree to the synthetic concurrency terms.',
    '{\"privacy\":\"synthetic-concurrency-v1\"}'::jsonb,
    'SYNTHETIC-CONCURRENCY-LEGAL-REVIEW', '$LEGAL_ADMIN',
    pg_catalog.clock_timestamp() - interval '2 days'
  );
" | last_uuid)"

run_authenticated "$LEGAL_ADMIN" "
  select partner_onboarding_private.select_partner_agreement_version_v1(
    '$AGREEMENT_ID', '$LEGAL_ADMIN'
  );
  select partner_onboarding_private.grant_partner_signer_authority_v1(
    '$PARTNER_ONE', '$SIGNER', 'Signer B', 'Authorized Representative', '$LEGAL_ADMIN'
  );
  select partner_onboarding_private.grant_partner_signer_authority_v1(
    '$PARTNER_TWO', '$SIGNER', 'Signer B', 'Authorized Representative', '$LEGAL_ADMIN'
  );
" >/dev/null

run_authenticated "$REVIEWER" "
  select partner_onboarding_private.set_runtime_config_v1(
    true, false, true, false, false, false,
    'partner-onboarding-concurrency-acceptance', '$REVIEWER'
  );
" >/dev/null

DOCUMENT_SHA="$("${PSQL[@]}" -c "
  select partner_onboarding_private.sha256_text(
    'SYNTHETIC CONCURRENCY DOCUMENT -- NO LEGAL EFFECT'
  );
")"

# Identical acceptance requests return one immutable receipt.
same_acceptance_sql="select (
  public.record_category_partner_agreement_acceptance_v1(
    '$PARTNER_ONE', '$AGREEMENT_ID', '$DOCUMENT_SHA',
    '92000000-0000-4000-8000-000000000010', '$ASSERTIONS'::jsonb
  ) ->> 'acceptance_id'
)::uuid;"

run_authenticated "$SIGNER" "$same_acceptance_sql" >"$TMP_DIR/accept-same-1.out" 2>"$TMP_DIR/accept-same-1.err" &
PID_ONE=$!
run_authenticated "$SIGNER" "$same_acceptance_sql" >"$TMP_DIR/accept-same-2.out" 2>"$TMP_DIR/accept-same-2.err" &
PID_TWO=$!
wait "$PID_ONE"
wait "$PID_TWO"

ACCEPT_ONE="$(last_uuid <"$TMP_DIR/accept-same-1.out")"
ACCEPT_TWO="$(last_uuid <"$TMP_DIR/accept-same-2.out")"
if [[ -z "$ACCEPT_ONE" || "$ACCEPT_ONE" != "$ACCEPT_TWO" ]]; then
  echo "same-request acceptance race did not return one stable receipt" >&2
  cat "$TMP_DIR/accept-same-1.err" "$TMP_DIR/accept-same-2.err" >&2 || true
  exit 1
fi

# Different request keys for one partner/version have one winner because the
# immutable acceptance is unique for that relationship epoch.
conflict_accept_one="select (
  public.record_category_partner_agreement_acceptance_v1(
    '$PARTNER_TWO', '$AGREEMENT_ID', '$DOCUMENT_SHA',
    '92000000-0000-4000-8000-000000000011', '$ASSERTIONS'::jsonb
  ) ->> 'acceptance_id'
)::uuid;"
conflict_accept_two="select (
  public.record_category_partner_agreement_acceptance_v1(
    '$PARTNER_TWO', '$AGREEMENT_ID', '$DOCUMENT_SHA',
    '92000000-0000-4000-8000-000000000012', '$ASSERTIONS'::jsonb
  ) ->> 'acceptance_id'
)::uuid;"

set +e
run_authenticated "$SIGNER" "$conflict_accept_one" >"$TMP_DIR/accept-conflict-1.out" 2>"$TMP_DIR/accept-conflict-1.err" &
PID_ONE=$!
run_authenticated "$SIGNER" "$conflict_accept_two" >"$TMP_DIR/accept-conflict-2.out" 2>"$TMP_DIR/accept-conflict-2.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e
if ! { [[ "$STATUS_ONE" -eq 0 && "$STATUS_TWO" -ne 0 ]] || [[ "$STATUS_ONE" -ne 0 && "$STATUS_TWO" -eq 0 ]]; }; then
  echo "conflicting acceptance race did not produce exactly one winner" >&2
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/accept-conflict-1.err"
else
  expect_generic_loser "$TMP_DIR/accept-conflict-2.err"
fi

# Register the complete synthetic release evidence for both partners, with
# distinct Swipe and Local identities.
for partner_pair in "$PARTNER_ONE:$SHARED_LOCAL_TARGET" "$PARTNER_TWO:$SHARED_LOCAL_TARGET"; do
  IFS=: read -r partner_id local_partner_id <<<"$partner_pair"
  run_authenticated "$EVIDENCE_REVIEWER" "
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'profile',
      partner_onboarding_private.partner_profile_sha256('$partner_id'),
      '{\"status\":\"verified\",\"source\":\"concurrency\"}'::jsonb,
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'media',
      partner_onboarding_private.partner_media_sha256('$partner_id'),
      '{\"status\":\"verified\",\"source\":\"concurrency\"}'::jsonb,
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'compliance', repeat('c', 64),
      '{\"status\":\"verified\",\"source\":\"concurrency\"}'::jsonb,
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'local_identity', repeat('d', 64),
      pg_catalog.jsonb_build_object(
        'status', 'verified', 'local_lane', 'meals',
        'swipe_partner_id', '$partner_id',
        'local_partner_id', '$local_partner_id', 'primary_cta_destination', 'local',
        'primary_cta_path', '/restaurants/$local_partner_id'
      ),
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'smoke_test', repeat('e', 64),
      pg_catalog.jsonb_build_object(
        'status', 'passed', 'passed', true, 'order_path_passed', true,
        'local_partner_id', '$local_partner_id',
        'customer_order_receipt_id', 'synthetic-customer-order',
        'partner_acceptance_receipt_id', 'synthetic-partner-acceptance',
        'driver_receipt_id', 'synthetic-driver',
        'delivery_receipt_id', 'synthetic-delivery'
      ),
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'partner_consent',
      partner_onboarding_private.partner_preview_sha256('$partner_id'),
      '{\"status\":\"approved\",\"approved\":true}'::jsonb,
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
    select partner_onboarding_private.issue_partner_evidence_v1(
      '$partner_id', 'heha_review',
      partner_onboarding_private.partner_preview_sha256('$partner_id'),
      '{\"status\":\"approved\",\"approved\":true}'::jsonb,
      pg_catalog.gen_random_uuid(), '$EVIDENCE_REVIEWER'
    );
  " >/dev/null
done

run_authenticated "$REVIEWER" "
  select partner_onboarding_private.set_runtime_config_v1(
    true, false, true, true, false, false,
    'partner-onboarding-concurrency-release', '$REVIEWER'
  );
" >/dev/null

# Identical release finalizations return one stable release receipt.
same_release_sql="select (
  partner_onboarding_private.finalize_partner_release_v1(
    '$PARTNER_ONE',
    partner_onboarding_private.partner_preview_sha256('$PARTNER_ONE'),
    '92000000-0000-4000-8000-000000000020', '$RELEASE_REVIEWER'
  ) ->> 'release_receipt_id'
)::uuid;"

run_authenticated "$RELEASE_REVIEWER" "$same_release_sql" >"$TMP_DIR/release-same-1.out" 2>"$TMP_DIR/release-same-1.err" &
PID_ONE=$!
run_authenticated "$RELEASE_REVIEWER" "$same_release_sql" >"$TMP_DIR/release-same-2.out" 2>"$TMP_DIR/release-same-2.err" &
PID_TWO=$!
wait "$PID_ONE"
wait "$PID_TWO"

RELEASE_ONE="$(last_uuid <"$TMP_DIR/release-same-1.out")"
RELEASE_TWO="$(last_uuid <"$TMP_DIR/release-same-2.out")"
if [[ -z "$RELEASE_ONE" || "$RELEASE_ONE" != "$RELEASE_TWO" ]]; then
  echo "same-request release race did not return one stable receipt" >&2
  cat "$TMP_DIR/release-same-1.err" "$TMP_DIR/release-same-2.err" >&2 || true
  exit 1
fi

# Conflicting release request keys for one release epoch produce one winner.
conflict_release_one="select (
  partner_onboarding_private.finalize_partner_release_v1(
    '$PARTNER_TWO',
    partner_onboarding_private.partner_preview_sha256('$PARTNER_TWO'),
    '92000000-0000-4000-8000-000000000021', '$RELEASE_REVIEWER'
  ) ->> 'release_receipt_id'
)::uuid;"
conflict_release_two="select (
  partner_onboarding_private.finalize_partner_release_v1(
    '$PARTNER_TWO',
    partner_onboarding_private.partner_preview_sha256('$PARTNER_TWO'),
    '92000000-0000-4000-8000-000000000022', '$RELEASE_REVIEWER'
  ) ->> 'release_receipt_id'
)::uuid;"

set +e
run_authenticated "$RELEASE_REVIEWER" "$conflict_release_one" >"$TMP_DIR/release-conflict-1.out" 2>"$TMP_DIR/release-conflict-1.err" &
PID_ONE=$!
run_authenticated "$RELEASE_REVIEWER" "$conflict_release_two" >"$TMP_DIR/release-conflict-2.out" 2>"$TMP_DIR/release-conflict-2.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e
if ! { [[ "$STATUS_ONE" -eq 0 && "$STATUS_TWO" -ne 0 ]] || [[ "$STATUS_ONE" -ne 0 && "$STATUS_TWO" -eq 0 ]]; }; then
  echo "conflicting release race did not produce exactly one winner" >&2
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/release-conflict-1.err"
else
  expect_generic_loser "$TMP_DIR/release-conflict-2.err"
fi

RELEASE_TWO="$("${PSQL[@]}" -c "
  select partner_onboarding_private.current_release_receipt_id_v1('$PARTNER_TWO');
" | last_uuid)"
if [[ -z "$RELEASE_TWO" ]]; then
  echo 'conflicting release race did not leave one current release' >&2
  exit 1
fi

run_authenticated "$REVIEWER" "
  select partner_onboarding_private.set_runtime_config_v1(
    true, false, true, true, true, true,
    'partner-onboarding-concurrency-activation', '$REVIEWER'
  );
" >/dev/null

# Identical activation requests serialize and return one immutable target
# acknowledgement. The snapshot binds every required target field.
same_activation_sql="select (
  partner_onboarding_private.record_partner_surface_activation_v1(
    '$PARTNER_ONE', '$RELEASE_ONE', 'swipe', '$PARTNER_ONE',
    'concurrency-swipe-ack-same-001',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', '$RELEASE_ONE'::uuid,
      'target_partner_id', '$PARTNER_ONE'::uuid,
      'target_receipt_id', 'concurrency-swipe-ack-same-001',
      'surface', 'swipe',
      'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-swipe',
      'attested_by', '$SWIPE_ATTESTOR'::uuid
    ),
    '92000000-0000-4000-8000-000000000023', '$SWIPE_ATTESTOR'
  ) ->> 'activation_receipt_id'
)::uuid;"

run_authenticated "$SWIPE_ATTESTOR" "$same_activation_sql" >"$TMP_DIR/activation-same-1.out" 2>"$TMP_DIR/activation-same-1.err" &
PID_ONE=$!
run_authenticated "$SWIPE_ATTESTOR" "$same_activation_sql" >"$TMP_DIR/activation-same-2.out" 2>"$TMP_DIR/activation-same-2.err" &
PID_TWO=$!
wait "$PID_ONE"
wait "$PID_TWO"

ACTIVATION_ONE="$(last_uuid <"$TMP_DIR/activation-same-1.out")"
ACTIVATION_TWO="$(last_uuid <"$TMP_DIR/activation-same-2.out")"
if [[ -z "$ACTIVATION_ONE" || "$ACTIVATION_ONE" != "$ACTIVATION_TWO" ]]; then
  echo 'same-request activation race did not return one stable receipt' >&2
  cat "$TMP_DIR/activation-same-1.err" "$TMP_DIR/activation-same-2.err" >&2 || true
  exit 1
fi

ACTIVATION_ONE_COUNT="$("${PSQL[@]}" -c "
  select count(*)
  from partner_onboarding_private.partner_surface_activation_receipts
  where release_receipt_id = '$RELEASE_ONE' and surface = 'swipe';
")"
if [[ "$ACTIVATION_ONE_COUNT" != '1' ]]; then
  echo "same-request activation race created $ACTIVATION_ONE_COUNT receipts" >&2
  exit 1
fi

# CROSS_SOURCE_LOCAL_TARGET_COLLISION: two different Swipe source partners,
# each with a current release bound to the same Local identity, race one Local
# target. Exactly one source may own the target; the loser is generic-denied.
conflict_activation_one="select (
  partner_onboarding_private.record_partner_surface_activation_v1(
    '$PARTNER_ONE', '$RELEASE_ONE', 'local_orderability', '$SHARED_LOCAL_TARGET',
    'concurrency-local-ack-source-one',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', '$RELEASE_ONE'::uuid,
      'target_partner_id', '$SHARED_LOCAL_TARGET'::uuid,
      'target_receipt_id', 'concurrency-local-ack-source-one',
      'surface', 'local_orderability', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-local',
      'attested_by', '$LOCAL_ATTESTOR'::uuid
    ),
    '92000000-0000-4000-8000-000000000024', '$LOCAL_ATTESTOR'
  ) ->> 'activation_receipt_id'
)::uuid;"
conflict_activation_two="select (
  partner_onboarding_private.record_partner_surface_activation_v1(
    '$PARTNER_TWO', '$RELEASE_TWO', 'local_orderability', '$SHARED_LOCAL_TARGET',
    'concurrency-local-ack-source-two',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', '$RELEASE_TWO'::uuid,
      'target_partner_id', '$SHARED_LOCAL_TARGET'::uuid,
      'target_receipt_id', 'concurrency-local-ack-source-two',
      'surface', 'local_orderability', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-local',
      'attested_by', '$LOCAL_ATTESTOR'::uuid
    ),
    '92000000-0000-4000-8000-000000000025', '$LOCAL_ATTESTOR'
  ) ->> 'activation_receipt_id'
)::uuid;"

set +e
run_authenticated "$LOCAL_ATTESTOR" "$conflict_activation_one" >"$TMP_DIR/activation-conflict-1.out" 2>"$TMP_DIR/activation-conflict-1.err" &
PID_ONE=$!
run_authenticated "$LOCAL_ATTESTOR" "$conflict_activation_two" >"$TMP_DIR/activation-conflict-2.out" 2>"$TMP_DIR/activation-conflict-2.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e
if ! { [[ "$STATUS_ONE" -eq 0 && "$STATUS_TWO" -ne 0 ]] || [[ "$STATUS_ONE" -ne 0 && "$STATUS_TWO" -eq 0 ]]; }; then
  echo 'conflicting activation race did not produce exactly one target winner' >&2
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/activation-conflict-1.err"
else
  expect_generic_loser "$TMP_DIR/activation-conflict-2.err"
fi

CROSS_SOURCE_LOCAL_TARGET_STATE="$("${PSQL[@]}" -c "
  with current_target_owner as (
    select activation.partner_id
    from partner_onboarding_private.partner_surface_activation_receipts activation
    where activation.surface = 'local_orderability'
      and activation.target_partner_id = '$SHARED_LOCAL_TARGET'
      and activation.partner_id in ('$PARTNER_ONE', '$PARTNER_TWO')
      and activation.id = partner_onboarding_private.surface_activation_receipt_id_v1(
        activation.partner_id, activation.surface
      )
  )
  select count(*)::text || ':' || count(distinct partner_id)::text
  from current_target_owner;
")"
if [[ "$CROSS_SOURCE_LOCAL_TARGET_STATE" != '1:1' ]]; then
  echo "CROSS_SOURCE_LOCAL_TARGET_COLLISION left an invalid current target owner set: $CROSS_SOURCE_LOCAL_TARGET_STATE" >&2
  exit 1
fi

# Staff-authority revocation and an action requiring that authority share the
# registry lock. The website attestation may commit immediately before the
# revocation, or it loses generically after the revocation; a stale replay is
# always denied once the authority is gone.
WEBSITE_GRANT="$("${PSQL[@]}" -c "
  select grant_row.id
  from partner_onboarding_private.staff_authority_grants grant_row
  where grant_row.user_id = '$WEBSITE_ATTESTOR'
    and grant_row.authority_type = 'website_attestor'
    and not exists (
      select 1 from partner_onboarding_private.staff_authority_revocations revocation
      where revocation.authority_grant_id = grant_row.id
    )
  order by grant_row.granted_at desc, grant_row.id desc
  limit 1;
" | last_uuid)"
if [[ -z "$WEBSITE_GRANT" ]]; then
  echo 'website attestor grant missing before staff-revocation race' >&2
  exit 1
fi

website_activation_sql="select (
  partner_onboarding_private.record_partner_surface_activation_v1(
    '$PARTNER_TWO', '$RELEASE_TWO', 'website', '$PARTNER_TWO',
    'concurrency-website-ack-authority-race',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', '$RELEASE_TWO'::uuid,
      'target_partner_id', '$PARTNER_TWO'::uuid,
      'target_receipt_id', 'concurrency-website-ack-authority-race',
      'surface', 'website', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-website',
      'attested_by', '$WEBSITE_ATTESTOR'::uuid
    ),
    '92000000-0000-4000-8000-000000000027', '$WEBSITE_ATTESTOR'
  ) ->> 'activation_receipt_id'
)::uuid;"
website_revoke_sql="select partner_onboarding_private.revoke_staff_authority_v1(
  '$WEBSITE_GRANT', '$REVIEWER', 'concurrency_staff_authority_revocation'
);"

# STAFF_AUTHORITY_REPLAY_VS_REVOKE: first create the immutable action receipt,
# then race its exact replay against revocation of the authority that attested
# it. The replay can linearize before revocation, but can never work afterward.
run_authenticated "$WEBSITE_ATTESTOR" "$website_activation_sql" >"$TMP_DIR/staff-race-seed.out" 2>"$TMP_DIR/staff-race-seed.err"
if [[ -z "$(last_uuid <"$TMP_DIR/staff-race-seed.out")" ]]; then
  echo 'staff-authority replay race could not seed its immutable action receipt' >&2
  cat "$TMP_DIR/staff-race-seed.err" >&2 || true
  exit 1
fi

set +e
run_authenticated "$WEBSITE_ATTESTOR" "$website_activation_sql" >"$TMP_DIR/staff-race-action.out" 2>"$TMP_DIR/staff-race-action.err" &
PID_ONE=$!
run_authenticated "$REVIEWER" "$website_revoke_sql" >"$TMP_DIR/staff-race-revoke.out" 2>"$TMP_DIR/staff-race-revoke.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e
if [[ "$STATUS_TWO" -ne 0 ]]; then
  echo 'staff-authority revocation lost its serialized race unexpectedly' >&2
  cat "$TMP_DIR/staff-race-revoke.err" >&2 || true
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/staff-race-action.err"
fi

set +e
run_authenticated "$WEBSITE_ATTESTOR" "$website_activation_sql" >"$TMP_DIR/staff-race-replay.out" 2>"$TMP_DIR/staff-race-replay.err"
STALE_STAFF_REPLAY_STATUS=$?
set -e
if [[ "$STALE_STAFF_REPLAY_STATUS" -eq 0 ]]; then
  echo 'revoked website attestor replayed a privileged action' >&2
  exit 1
fi
expect_generic_loser "$TMP_DIR/staff-race-replay.err"

STAFF_REVOCATION_COUNT="$("${PSQL[@]}" -c "
  select count(*) from partner_onboarding_private.staff_authority_revocations
  where authority_grant_id = '$WEBSITE_GRANT';
")"
if [[ "$STAFF_REVOCATION_COUNT" != '1' ]]; then
  echo "staff-revocation race produced $STAFF_REVOCATION_COUNT revocation rows" >&2
  exit 1
fi

# Concurrent identical surface revocations are idempotent: one immutable
# surface-revocation row, one release revocation, and one epoch advance.
same_surface_revoke_sql="select partner_onboarding_private.revoke_partner_surface_activation_v1(
  '$ACTIVATION_ONE', '$SWIPE_ATTESTOR', 'concurrency_surface_revocation'
);"
run_authenticated "$SWIPE_ATTESTOR" "$same_surface_revoke_sql" >"$TMP_DIR/surface-revoke-1.out" 2>"$TMP_DIR/surface-revoke-1.err" &
PID_ONE=$!
run_authenticated "$SWIPE_ATTESTOR" "$same_surface_revoke_sql" >"$TMP_DIR/surface-revoke-2.out" 2>"$TMP_DIR/surface-revoke-2.err" &
PID_TWO=$!
wait "$PID_ONE"
wait "$PID_TWO"

REVOCATION_COUNTS="$("${PSQL[@]}" -c "
  select
    (select count(*) from partner_onboarding_private.partner_surface_activation_revocations
     where activation_receipt_id = '$ACTIVATION_ONE')::text
    || ':' ||
    (select count(*) from partner_onboarding_private.partner_release_revocations
     where release_receipt_id = '$RELEASE_ONE')::text;
")"
if [[ "$REVOCATION_COUNTS" != '1:1' ]]; then
  echo "same surface revocation race produced unexpected rows: $REVOCATION_COUNTS" >&2
  exit 1
fi

# Race a new release finalization against a watched source-profile edit. If
# finalization wins, the trigger immediately invalidates it; if the edit wins,
# stale profile/preview evidence denies finalization. Either ordering ends with
# no current release or public card and never deadlocks.
profile_race_release_sql="select (
  partner_onboarding_private.finalize_partner_release_v1(
    '$PARTNER_ONE',
    partner_onboarding_private.partner_preview_sha256('$PARTNER_ONE'),
    '92000000-0000-4000-8000-000000000026', '$RELEASE_REVIEWER'
  ) ->> 'release_receipt_id'
)::uuid;"
profile_race_edit_sql="update public.partners
  set name = 'Synthetic Concurrency One Reviewed'
  where id = '$PARTNER_ONE'
  returning id;"

set +e
run_authenticated "$RELEASE_REVIEWER" "$profile_race_release_sql" >"$TMP_DIR/profile-race-release.out" 2>"$TMP_DIR/profile-race-release.err" &
PID_ONE=$!
run_admin "$profile_race_edit_sql" >"$TMP_DIR/profile-race-edit.out" 2>"$TMP_DIR/profile-race-edit.err" &
PID_TWO=$!
wait "$PID_ONE"
STATUS_ONE=$?
wait "$PID_TWO"
STATUS_TWO=$?
set -e
if [[ "$STATUS_TWO" -ne 0 ]]; then
  echo 'watched profile edit failed during release race' >&2
  cat "$TMP_DIR/profile-race-edit.err" >&2 || true
  exit 1
fi
if [[ "$STATUS_ONE" -ne 0 ]]; then
  expect_generic_loser "$TMP_DIR/profile-race-release.err"
fi

PROFILE_RACE_STATE="$("${PSQL[@]}" -c "
  select
    (partner_onboarding_private.current_release_receipt_id_v1('$PARTNER_ONE') is null)::text
    || ':' ||
    (not exists (
      select 1 from public.partner_public_cards_v1 where partner_id = '$PARTNER_ONE'
    ))::text
    || ':' ||
    (select (name = 'Synthetic Concurrency One Reviewed')::text
     from public.partners where id = '$PARTNER_ONE');
")"
if [[ "$PROFILE_RACE_STATE" != 'true:true:true' ]]; then
  echo "profile-edit/finalize race did not fail closed: $PROFILE_RACE_STATE" >&2
  exit 1
fi

FINAL_COUNTS="$("${PSQL[@]}" -c "
  select
    (select count(*) from partner_onboarding_private.partner_claims
      where partner_id in ('$PARTNER_ONE', '$PARTNER_TWO'))::text
    || ':' ||
    (select count(*) from partner_onboarding_private.partner_agreement_acceptances
      where partner_id in ('$PARTNER_ONE', '$PARTNER_TWO'))::text
    || ':' ||
    (select count(*) from partner_onboarding_private.partner_release_receipts
      where partner_id in ('$PARTNER_ONE', '$PARTNER_TWO'))::text
    || ':' ||
    (select count(*) from partner_onboarding_private.partner_surface_activation_receipts
      where partner_id in ('$PARTNER_ONE', '$PARTNER_TWO'))::text
    || ':' ||
    (select count(*) from partner_onboarding_private.partner_surface_activation_revocations
      where activation_receipt_id = '$ACTIVATION_ONE')::text
    || ':' ||
    (select count(*) from partner_onboarding_private.partner_release_revocations
      where release_receipt_id = '$RELEASE_ONE')::text;
")"
if [[ ! "$FINAL_COUNTS" =~ ^2:2:(2|3):(2|3):1:1$ ]]; then
  echo "unexpected final claim:acceptance:release:activation:surface-revocation:release-revocation counts: $FINAL_COUNTS" >&2
  exit 1
fi

echo 'PASS: two-client application/invitation, claim, acceptance, release, activation, revocation, and profile-edit races are idempotent and fail closed.'
