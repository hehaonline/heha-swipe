\set ON_ERROR_STOP on
begin;

create temporary table partner_publication_integration_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;
grant select, insert on table partner_publication_integration_results
  to anon, authenticated, service_role;

create or replace function pg_temp.set_auth(
  p_user uuid,
  p_role text default 'authenticated',
  p_is_anonymous boolean default false
) returns void language plpgsql as $$
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object(
      'sub', p_user::text,
      'role', p_role,
      'is_anonymous', p_is_anonymous
    )::text,
    true
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', p_role, true);
  perform pg_catalog.set_config('app.hybrid_partner_context', '', true);
end;
$$;

create or replace function pg_temp.clear_auth()
returns void language plpgsql as $$
begin
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  perform pg_catalog.set_config('request.jwt.claim.role', '', true);
  perform pg_catalog.set_config('app.hybrid_partner_context', '', true);
end;
$$;

create or replace function pg_temp.expect_state(
  p_label text,
  p_expected text,
  p_sql text
) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception '% expected SQLSTATE %, statement succeeded', p_label, p_expected;
exception when others then
  if sqlstate = p_expected then
    insert into partner_publication_integration_results(label, ok, detail)
    values (p_label, true, 'denied with SQLSTATE ' || p_expected);
  else
    raise exception '% expected SQLSTATE %, got %: %',
      p_label, p_expected, sqlstate, sqlerrm;
  end if;
end;
$$;

create or replace function pg_temp.assert_true(
  p_label text,
  p_ok boolean,
  p_detail text
) returns void language plpgsql as $$
begin
  if p_ok is not true then
    raise exception '%', p_label;
  end if;
  insert into partner_publication_integration_results(label, ok, detail)
  values (p_label, true, p_detail);
end;
$$;

create or replace function pg_temp.assert_public_state(
  p_label text,
  p_partner_id uuid,
  p_swipe_visible boolean,
  p_directory_visible boolean
) returns void language plpgsql as $$
declare
  swipe_visible boolean;
  directory_visible boolean;
begin
  select exists (
    select 1 from public.public_swipe_partners where id = p_partner_id
  ) into swipe_visible;
  select exists (
    select 1 from public.public_partner_directory where id = p_partner_id
  ) into directory_visible;

  if swipe_visible is distinct from p_swipe_visible
     or directory_visible is distinct from p_directory_visible then
    raise exception '% expected Swipe/Directory visibility %/%, got %/%',
      p_label, p_swipe_visible, p_directory_visible,
      swipe_visible, directory_visible;
  end if;

  if exists (
    select 1 from public.public_local_partners where id = p_partner_id
  ) then
    raise exception '% unexpectedly reached the disabled Local bridge', p_label;
  end if;

  insert into partner_publication_integration_results(label, ok, detail)
  values (
    p_label,
    true,
    pg_catalog.format(
      'Swipe/Directory=%s/%s and Local=false',
      swipe_visible,
      directory_visible
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Exact structural boundary.
-- ---------------------------------------------------------------------------
do $proof$
declare
  expected_columns constant text[] := array[
    'id','created_at','name','category','categories','instagram','website','bio',
    'tags','rating','review_count','distance_text','color','photo_emoji',
    'heha_partner','status','hours','business_type','offerings','neighborhood',
    'tagline','items','image_url','price_range','gallery_urls','partner_type',
    'delivery_days','heha_pillar','local_eligible','local_lane',
    'primary_cta_destination','primary_cta_label','primary_cta_path'
  ]::text[];
  actual_columns text[];
  view_name text;
  private_column text;
  review_consent_id_attnum smallint;
  review_consent_sequence_attnum smallint;
  consent_id_attnum smallint;
  consent_sequence_attnum smallint;
begin
  if pg_catalog.has_table_privilege('anon', 'public.partners', 'SELECT') then
    raise exception 'anon must not have raw SELECT on public.partners';
  end if;
  assert not pg_catalog.has_table_privilege('anon', 'public.partners', 'INSERT');
  assert not pg_catalog.has_table_privilege('anon', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_table_privilege('anon', 'public.partners', 'DELETE');
  assert pg_catalog.has_table_privilege('authenticated', 'public.partners', 'SELECT');
  assert pg_catalog.has_table_privilege('authenticated', 'public.partners', 'INSERT');
  assert pg_catalog.has_table_privilege('authenticated', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'DELETE');

  assert pg_catalog.to_regclass('public.partner_publication_consent_events') is not null;
  assert pg_catalog.to_regclass('public.partner_publication_review_events') is not null;
  assert (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.partner_publication_consent_events'::regclass
  );
  assert (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.partner_publication_review_events'::regclass
  );

  assert not pg_catalog.has_table_privilege(
    'anon', 'public.partner_publication_consent_events', 'SELECT'
  );
  assert not pg_catalog.has_table_privilege(
    'authenticated', 'public.partner_publication_consent_events', 'SELECT'
  );
  assert not pg_catalog.has_table_privilege(
    'anon', 'public.partner_publication_review_events', 'SELECT'
  );
  assert not pg_catalog.has_table_privilege(
    'authenticated', 'public.partner_publication_review_events', 'SELECT'
  );
  assert pg_catalog.has_table_privilege(
    'service_role', 'public.partner_publication_consent_events', 'SELECT'
  );
  assert pg_catalog.has_table_privilege(
    'service_role', 'public.partner_publication_review_events', 'SELECT'
  );
  assert not pg_catalog.has_table_privilege(
    'service_role', 'public.partner_publication_consent_events', 'INSERT'
  );
  assert not pg_catalog.has_table_privilege(
    'service_role', 'public.partner_publication_review_events', 'INSERT'
  );
  assert not pg_catalog.has_table_privilege(
    'service_role', 'public.partner_publication_review_events', 'UPDATE'
  );
  assert not pg_catalog.has_table_privilege(
    'service_role', 'public.partner_publication_review_events', 'DELETE'
  );

  assert pg_catalog.to_regprocedure(
    'public.record_partner_publication_review(uuid,uuid,text,text,text,uuid,text)'
  ) is not null;
  assert not pg_catalog.has_function_privilege(
    'anon',
    'public.record_partner_publication_review(uuid,uuid,text,text,text,uuid,text)',
    'EXECUTE'
  );
  assert not pg_catalog.has_function_privilege(
    'authenticated',
    'public.record_partner_publication_review(uuid,uuid,text,text,text,uuid,text)',
    'EXECUTE'
  );
  assert pg_catalog.has_function_privilege(
    'service_role',
    'public.record_partner_publication_review(uuid,uuid,text,text,text,uuid,text)',
    'EXECUTE'
  );
  assert pg_catalog.to_regprocedure('public.approve_partner(uuid)') is null;
  assert pg_catalog.to_regprocedure(
    'public.approve_heha_partnership(uuid,uuid)'
  ) is not null;

  foreach view_name in array array[
    'public_partner_directory', 'public_swipe_partners', 'public_local_partners'
  ]::text[] loop
    select pg_catalog.array_agg(column_name order by ordinal_position)
    into actual_columns
    from information_schema.columns
    where table_schema = 'public' and table_name = view_name;
    assert actual_columns = expected_columns,
      pg_catalog.format('%s must expose the exact 33-column contract', view_name);

    foreach private_column in array array[
      'updated_at','owner_id','location','contact','complete_pct','contribution',
      'total_swipes','total_saves','total_profile_views','google_place_id','phone',
      'product_price_policy','service_fee_type','service_fee_amount','pricing_notes',
      'routing_status','routing_notes','routing_updated_by','routing_updated_at',
      'reviewed_by','review_note','claim_status','partnership_status',
      'contract_status','listing_status'
    ]::text[] loop
      assert not (private_column = any(actual_columns)),
        pg_catalog.format('public.%s exposed private column %s', view_name, private_column);
    end loop;

    assert pg_catalog.has_table_privilege(
      'anon', pg_catalog.format('public.%I', view_name), 'SELECT'
    );
    assert pg_catalog.has_table_privilege(
      'authenticated', pg_catalog.format('public.%I', view_name), 'SELECT'
    );
    assert not pg_catalog.has_table_privilege(
      'anon', pg_catalog.format('public.%I', view_name), 'INSERT'
    );
    assert not pg_catalog.has_table_privilege(
      'authenticated', pg_catalog.format('public.%I', view_name), 'UPDATE'
    );
  end loop;

  assert exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.partner_publication_review_events'::regclass
      and tgname = 'partner_publication_review_events_immutable'
      and not tgisinternal
      and tgenabled <> 'D'
  );
  assert exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.partner_publication_consent_events'::regclass
      and tgname = 'partner_publication_consent_events_immutable'
      and not tgisinternal
      and tgenabled <> 'D'
  );
  select attnum into review_consent_id_attnum
  from pg_catalog.pg_attribute
  where attrelid = 'public.partner_publication_review_events'::regclass
    and attname = 'consent_event_id' and not attisdropped;
  select attnum into review_consent_sequence_attnum
  from pg_catalog.pg_attribute
  where attrelid = 'public.partner_publication_review_events'::regclass
    and attname = 'consent_event_sequence' and not attisdropped;
  select attnum into consent_id_attnum
  from pg_catalog.pg_attribute
  where attrelid = 'public.partner_publication_consent_events'::regclass
    and attname = 'id' and not attisdropped;
  select attnum into consent_sequence_attnum
  from pg_catalog.pg_attribute
  where attrelid = 'public.partner_publication_consent_events'::regclass
    and attname = 'event_sequence' and not attisdropped;

  assert exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.partner_publication_review_events'::regclass
      and confrelid = 'public.partner_publication_consent_events'::regclass
      and conname = 'partner_publication_review_consent_event_fkey'
      and contype = 'f'
      and conkey = array[
        review_consent_id_attnum, review_consent_sequence_attnum
      ]::smallint[]
      and confkey = array[consent_id_attnum, consent_sequence_attnum]::smallint[]
      and confdeltype = 'r'
  ), 'review evidence must have one exact two-column consent-event FK';

  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'exact structural boundary', true,
    'raw anon denied; private ledgers closed; review RPC service-only; all public views exactly 33 allowlisted columns'
  );
end;
$proof$;

-- No consent or review means no public row.
set local role anon;
select pg_temp.assert_public_state(
  'initial fail closed',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

-- Cross-business status lookup and private evidence are denied before any
-- publication state is recorded.
select pg_temp.set_auth('34343434-3434-4434-8434-343434343434');
set local role authenticated;
select pg_temp.expect_state(
  'cross-business publication status BOLA',
  '42501',
  $$select public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  )$$
);
select pg_temp.expect_state(
  'outsider consent ledger denied',
  '42501',
  $$select 1 from public.partner_publication_consent_events limit 1$$
);
select pg_temp.expect_state(
  'outsider review ledger denied',
  '42501',
  $$select 1 from public.partner_publication_review_events limit 1$$
);
reset role;

-- Owner grants both destination permissions for the exact current profile.
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select (
  public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe','heha_local']::text[],
    'Avery Owner',
    'Founder',
    true,
    true,
    '70000000-0000-4000-8000-000000000001',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'profile_snapshot_hash'
) as profile_hash_v1 \gset

select (
  public.authorize_partner_profile_publication(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe','heha_local']::text[],
    'Avery Owner',
    'Founder',
    '70000000-0000-4000-8000-000000000002',
    'wave1-profile-consent-2026-08-10',
    :'profile_hash_v1'
  ) ->> 'state'
) as owner_publish_state \gset

do $proof$
declare status_payload jsonb;
begin
  status_payload := public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  );
  assert (status_payload -> 'publication_destinations')
    in ('["heha_local", "heha_swipe"]'::jsonb, '["heha_swipe", "heha_local"]'::jsonb);
  assert status_payload -> 'public_destinations' = '[]'::jsonb;
  assert status_payload -> 'staff_review_destinations' = '[]'::jsonb;
  assert not (status_payload ? 'authorized_account_contact');
  assert not (status_payload ? 'evidence_reference');
  assert not (status_payload ?| array[
    'reviewed_by','reviewer_id','recorded_by','request_key','request_payload_hash'
  ]::text[]);
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'owner redacted status', true,
    'current owner receives destination state without private evidence identity/contact fields'
  );
end;
$proof$;
reset role;

-- Owner consent is necessary but is not a HEHA staff publication decision.
set local role anon;
select pg_temp.assert_public_state(
  'owner grant without staff review hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

-- Caller-controlled JWT/GUC service claims cannot cross the review boundary.
select pg_temp.set_auth(
  '34343434-3434-4434-8434-343434343434',
  'service_role',
  false
);
set local role authenticated;
select pg_temp.expect_state(
  'forged service GUC review denied',
  '42501',
  format(
    $$select public.record_partner_publication_review(
      '70000000-0000-4000-8000-000000000003',
      '78787878-7878-4787-8787-787878787878',
      'heha_swipe', %L, 'approved',
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd', null
    )$$,
    :'profile_hash_v1'
  )
);
reset role;

-- The real service database role may record evidence only for an active
-- super_admin or pm_admin reviewer. Developer and SOM roles are insufficient.
select pg_temp.clear_auth();
set local role service_role;
select pg_temp.expect_state(
  'developer reviewer rejected',
  '42501',
  format(
    $$select public.record_partner_publication_review(
      '70000000-0000-4000-8000-000000000004',
      '78787878-7878-4787-8787-787878787878',
      'heha_swipe', %L, 'approved',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc', null
    )$$,
    :'profile_hash_v1'
  )
);
select pg_temp.expect_state(
  'som reviewer rejected',
  '42501',
  format(
    $$select public.record_partner_publication_review(
      '70000000-0000-4000-8000-000000000005',
      '78787878-7878-4787-8787-787878787878',
      'heha_swipe', %L, 'approved',
      '23232323-2323-4232-8232-232323232323', null
    )$$,
    :'profile_hash_v1'
  )
);
select pg_temp.expect_state(
  'stale staff review hash rejected',
  '23514',
  $$select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000006',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    '0000000000000000000000000000000000000000000000000000000000000000',
    'approved',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    null
  )$$
);

select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000007',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    :'profile_hash_v1',
    'approved',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    null
) as first_review_id \gset
select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000007',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    :'profile_hash_v1',
    'approved',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    null
) as replay_review_id \gset
select pg_temp.assert_true(
  'review idempotency',
  :'replay_review_id'::uuid = :'first_review_id'::uuid,
  'same request and evidence return the original append-only review identity'
);

-- Exact replay is historical evidence and remains stable after the reviewer is
-- deactivated. A new decision may not be attributed to that inactive reviewer.
reset role;
update public.user_roles
set active = false
where user_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  and role = 'super_admin';
select pg_temp.clear_auth();
set local role service_role;
select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000007',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    :'profile_hash_v1',
    'approved',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    null
) as inactive_replay_review_id \gset
select pg_temp.assert_true(
  'inactive reviewer exact replay',
  :'inactive_replay_review_id'::uuid = :'first_review_id'::uuid,
  'exact historical request replay returns its original identity after reviewer deactivation'
);
select pg_temp.expect_state(
  'inactive reviewer new decision denied',
  '42501',
  format(
    $$select public.record_partner_publication_review(
      '70000000-0000-4000-8000-000000000017',
      '78787878-7878-4787-8787-787878787878',
      'heha_swipe', %L, 'approved',
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd', null
    )$$,
    :'profile_hash_v1'
  )
);
reset role;
update public.user_roles
set active = true
where user_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  and role = 'super_admin';

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
do $proof$
declare status_payload jsonb;
begin
  status_payload := public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  );
  assert status_payload -> 'public_destinations' = '["heha_swipe"]'::jsonb;
  assert status_payload -> 'staff_review_destinations' = '["heha_swipe"]'::jsonb;
  assert not (status_payload ?| array[
    'authorized_account_contact','evidence_reference','reviewed_by','reviewer_id',
    'recorded_by','request_key','request_payload_hash'
  ]::text[]);
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'redacted authoritative owner status after Swipe review', true,
    'owner status reports only the exact reviewed public Swipe destination and no evidence identities'
  );
end;
$proof$;
reset role;
select pg_temp.clear_auth();
set local role service_role;

select pg_temp.expect_state(
  'review idempotency divergence rejected',
  '23505',
  format(
    $$select public.record_partner_publication_review(
      '70000000-0000-4000-8000-000000000007',
      '78787878-7878-4787-8787-787878787878',
      'heha_swipe', %L, 'rejected',
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'Changed decision'
    )$$,
    :'profile_hash_v1'
  )
);

select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000008',
    '78787878-7878-4787-8787-787878787878',
    'heha_local',
    :'profile_hash_v1',
    'approved',
    '12121212-1212-4212-8212-121212121212',
    null
) as local_review_id \gset
do $proof$
begin
  assert (
    select count(*) = 2
    from public.partner_publication_review_events
    where partner_id = '78787878-7878-4787-8787-787878787878'
  );
  assert not exists (
    select 1
    from public.partner_publication_review_events review_row
    join public.partner_publication_consent_events consent_row
      on consent_row.id = review_row.consent_event_id
     and consent_row.event_sequence = review_row.consent_event_sequence
    where review_row.partner_id = '78787878-7878-4787-8787-787878787878'
      and (
        consent_row.partner_id is distinct from review_row.partner_id
        or consent_row.owner_id is distinct from review_row.owner_id
        or consent_row.destination is distinct from review_row.destination
        or consent_row.action <> 'publish_profile'
        or consent_row.state <> 'granted'
      )
  );
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'exact consent-review binding', true,
    'Swipe and Local reviews bind to exact current granted publication-consent event identities'
  );
end;
$proof$;
reset role;

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
do $proof$
declare status_payload jsonb;
begin
  status_payload := public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  );
  assert status_payload -> 'public_destinations' = '["heha_swipe"]'::jsonb;
  assert status_payload -> 'staff_review_destinations'
    = '["heha_swipe", "heha_local"]'::jsonb;
  assert not (status_payload ?| array[
    'authorized_account_contact','evidence_reference','reviewed_by','reviewer_id',
    'recorded_by','request_key','request_payload_hash'
  ]::text[]);
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'disabled Local absent from authoritative public status', true,
    'Local may be exact-review approved but is absent from public destinations while the bridge is disabled'
  );
end;
$proof$;
reset role;

-- ACL revocation is not the only append-only defense: even the migration owner
-- cannot mutate or delete existing consent/review evidence through direct SQL.
select pg_temp.expect_state(
  'review evidence direct update immutable',
  '42501',
  $$update public.partner_publication_review_events
    set reason = 'tampered review evidence'
    where request_key = '70000000-0000-4000-8000-000000000007'$$
);
select pg_temp.expect_state(
  'review evidence direct delete immutable',
  '42501',
  $$delete from public.partner_publication_review_events
    where request_key = '70000000-0000-4000-8000-000000000007'$$
);
select pg_temp.expect_state(
  'consent evidence direct update immutable',
  '42501',
  $$update public.partner_publication_consent_events
    set state = 'revoked'
    where partner_id = '78787878-7878-4787-8787-787878787878'
      and destination = 'heha_swipe'
      and action = 'publish_profile'$$
);
select pg_temp.expect_state(
  'consent evidence direct delete immutable',
  '42501',
  $$delete from public.partner_publication_consent_events
    where partner_id = '78787878-7878-4787-8787-787878787878'
      and destination = 'heha_swipe'
      and action = 'publish_profile'$$
);
do $proof$
begin
  assert (
    select decision = 'approved' and reason is null
    from public.partner_publication_review_events
    where request_key = '70000000-0000-4000-8000-000000000007'
  );
  assert (
    select state = 'granted'
    from public.partner_publication_consent_events
    where partner_id = '78787878-7878-4787-8787-787878787878'
      and destination = 'heha_swipe'
      and action = 'publish_profile'
    order by event_sequence desc
    limit 1
  );
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'append-only evidence behavior', true,
    'migration-owner UPDATE/DELETE attacks fail 42501 and both evidence rows remain unchanged'
  );
end;
$proof$;

-- Grant plus exact-hash staff review makes the safe Swipe/Directory card public.
set local role anon;
select pg_temp.assert_public_state(
  'grant and staff review visible',
  '78787878-7878-4787-8787-787878787878',
  true,
  true
);
do $proof$
declare card record;
begin
  select * into card
  from public.public_swipe_partners
  where id = '78787878-7878-4787-8787-787878787878';
  assert card.local_eligible is false;
  assert card.local_lane is null;
  assert card.primary_cta_destination = 'swipe';
  assert card.primary_cta_label = 'Discover Partner';
  assert card.primary_cta_path = '/?partner=78787878-7878-4787-8787-787878787878';
  assert card.items = '[]'::jsonb;
  assert card.price_range is null;
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'public card fail-closed routing', true,
    'reviewed Wave 1 card suppresses items/pricing and exposes only the Swipe fallback CTA'
  );
end;
$proof$;
reset role;

-- Destination-scoped Local withdrawal cannot silently withdraw Swipe.
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select (
  public.withdraw_partner_publication_authorization(
    '78787878-7878-4787-8787-787878787878',
    array['heha_local']::text[],
    'Avery Owner',
    'Founder',
    '70000000-0000-4000-8000-000000000009',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'state'
) as local_withdrawal_state \gset
reset role;

do $proof$
begin
  assert (
    select state = 'granted'
    from public.partner_publication_consent_events
    where partner_id = '78787878-7878-4787-8787-787878787878'
      and destination = 'heha_swipe'
      and action = 'publish_profile'
    order by event_sequence desc
    limit 1
  );
  assert (
    select state = 'revoked'
    from public.partner_publication_consent_events
    where partner_id = '78787878-7878-4787-8787-787878787878'
      and destination = 'heha_local'
      and action = 'publish_profile'
    order by event_sequence desc
    limit 1
  );
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'per-destination withdrawal ledger', true,
    'Local publication is revoked while Swipe publication remains granted'
  );
end;
$proof$;

set local role anon;
select pg_temp.assert_public_state(
  'local withdrawal preserves swipe',
  '78787878-7878-4787-8787-787878787878',
  true,
  true
);
reset role;

-- Critical unchanged-profile regression: a Swipe withdrawal hides immediately.
-- Re-granting the exact same hash is still hidden because the prior review is
-- bound to the prior consent event. Only a new staff review restores visibility.
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select (
  public.withdraw_partner_publication_authorization(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    '70000000-0000-4000-8000-000000000010',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'state'
) as swipe_withdrawal_state \gset

do $proof$
declare status_payload jsonb;
begin
  status_payload := public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  );
  assert status_payload -> 'public_destinations' = '[]'::jsonb;
  assert status_payload -> 'staff_review_destinations' = '[]'::jsonb;
  assert not (status_payload ?| array[
    'authorized_account_contact','evidence_reference','reviewed_by','reviewer_id',
    'recorded_by','request_key','request_payload_hash'
  ]::text[]);
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'withdrawal clears authoritative owner status', true,
    'destination withdrawal immediately clears both public and current staff-review destination status'
  );
end;
$proof$;
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'swipe withdrawal hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

-- Restore only the non-consent listing inputs in this synthetic proof. The
-- latest owner authorization remains revoked, so this alone cannot publish.
select pg_temp.clear_auth();
update public.partners
set status = 'approved',
    swipe_eligible = true,
    updated_at = pg_catalog.now()
where id = '78787878-7878-4787-8787-787878787878';

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select (
  public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    true,
    true,
    '70000000-0000-4000-8000-000000000011',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'profile_snapshot_hash'
) as unchanged_profile_hash \gset
select (
  public.authorize_partner_profile_publication(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    '70000000-0000-4000-8000-000000000012',
    'wave1-profile-consent-2026-08-10',
    :'unchanged_profile_hash'
  ) ->> 'state'
) as unchanged_reconsent_state \gset
reset role;

select pg_temp.assert_true(
  'unchanged owner reconsent hash',
  :'unchanged_profile_hash' = :'profile_hash_v1',
  'owner re-consented to the byte-identical public profile hash'
);

set local role anon;
select pg_temp.assert_public_state(
  'unchanged reconsent still needs fresh review',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.clear_auth();
set local role service_role;
select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000013',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    :'unchanged_profile_hash',
    'approved',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    null
) as unchanged_reconsent_review_id \gset
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'fresh review after unchanged reconsent visible',
  '78787878-7878-4787-8787-787878787878',
  true,
  true
);
reset role;

-- Public profile drift invalidates both owner and staff exact-version evidence.
select pg_temp.clear_auth();
update public.partners
set bio = 'Profile version two', updated_at = pg_catalog.now()
where id = '78787878-7878-4787-8787-787878787878';

set local role anon;
select pg_temp.assert_public_state(
  'profile drift hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select (
  public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    true,
    true,
    '70000000-0000-4000-8000-000000000014',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'profile_snapshot_hash'
) as profile_hash_v2 \gset
select (
  public.authorize_partner_profile_publication(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    '70000000-0000-4000-8000-000000000015',
    'wave1-profile-consent-2026-08-10',
    :'profile_hash_v2'
  ) ->> 'state'
) as drift_reconsent_state \gset
reset role;

select pg_temp.assert_true(
  'profile drift changed exact hash',
  :'profile_hash_v2' is distinct from :'profile_hash_v1',
  'public profile drift produced a new server snapshot hash'
);

set local role anon;
select pg_temp.assert_public_state(
  'profile drift owner reconsent alone hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.clear_auth();
set local role service_role;
select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000016',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    :'profile_hash_v2',
    'approved',
    '12121212-1212-4212-8212-121212121212',
    null
) as drift_review_id \gset
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'profile drift fresh exact review visible',
  '78787878-7878-4787-8787-787878787878',
  true,
  true
);
reset role;

-- Category/categories are snapshot-bearing publication fields too. A category
-- mutation cannot escape the gate by retaining the same owner/listing state.
select pg_temp.clear_auth();
update public.partners
set category = 'PrivateChef',
    categories = array['PrivateChef']::text[],
    updated_at = pg_catalog.now()
where id = '78787878-7878-4787-8787-787878787878';

set local role anon;
select pg_temp.assert_public_state(
  'category mutation hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select (
  public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    true,
    true,
    '70000000-0000-4000-8000-000000000018',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'profile_snapshot_hash'
) as profile_hash_v3 \gset
select (
  public.authorize_partner_profile_publication(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe']::text[],
    'Avery Owner',
    'Founder',
    '70000000-0000-4000-8000-000000000019',
    'wave1-profile-consent-2026-08-10',
    :'profile_hash_v3'
  ) ->> 'state'
) as category_reconsent_state \gset
reset role;

select pg_temp.assert_true(
  'category mutation changed exact hash',
  :'profile_hash_v3' is distinct from :'profile_hash_v2',
  'category/categories mutation produced a new server snapshot hash'
);

set local role anon;
select pg_temp.assert_public_state(
  'category mutation owner reconsent alone hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.clear_auth();
set local role service_role;
select public.record_partner_publication_review(
    '70000000-0000-4000-8000-000000000020',
    '78787878-7878-4787-8787-787878787878',
    'heha_swipe',
    :'profile_hash_v3',
    'approved',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    null
) as category_review_id \gset
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'category mutation fresh exact review visible',
  '78787878-7878-4787-8787-787878787878',
  true,
  true
);
reset role;

-- Claimed-owner listing opt-out is an independent immediate public kill switch.
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select public.opt_out_partner_listing(
  '78787878-7878-4787-8787-787878787878'
);
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'listing opt out hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

-- Internal listing review can restore the independent listing gate without
-- changing the already exact owner/staff evidence.
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
set local role authenticated;
select public.set_partner_listing_status(
  '78787878-7878-4787-8787-787878787878',
  'listed'
);
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'independent listing relist visible',
  '78787878-7878-4787-8787-787878787878',
  true,
  true
);
reset role;

-- Auth deletion releases ownership through #120, invalidates current-owner
-- consent/review, and never exposes the private evidence to the former owner.
select pg_temp.clear_auth();
delete from auth.users
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

do $proof$
begin
  assert (
    select owner_id is null
      and claim_status = 'unclaimed'
      and claimed_at is null
      and claimed_by is null
      and heha_partner is false
    from public.partners
    where id = '78787878-7878-4787-8787-787878787878'
  );
  assert exists (
    select 1 from public.partner_lifecycle_events
    where partner_id = '78787878-7878-4787-8787-787878787878'
      and event_type = 'owner_released'
  );
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'owner release lifecycle', true,
    'account deletion released owner/claim provenance and emitted the #120 lifecycle receipt'
  );
end;
$proof$;

set local role anon;
select pg_temp.assert_public_state(
  'owner release hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select pg_temp.expect_state(
  'former owner status denied',
  '42501',
  $$select public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  )$$
);
select pg_temp.expect_state(
  'former owner consent evidence denied',
  '42501',
  $$select 1 from public.partner_publication_consent_events limit 1$$
);
select pg_temp.expect_state(
  'former owner review evidence denied',
  '42501',
  $$select 1 from public.partner_publication_review_events limit 1$$
);
reset role;

select pg_temp.set_auth('34343434-3434-4434-8434-343434343434');
set local role authenticated;
select pg_temp.expect_state(
  'post-release cross-business BOLA denied',
  '42501',
  $$select public.get_my_partner_publication_status(
    '78787878-7878-4787-8787-787878787878'
  )$$
);
reset role;

do $proof$
begin
  assert not exists (
    select 1
    from public.public_swipe_partners public_row
    join public.partners partner_row on partner_row.id = public_row.id
    where public_row.heha_partner is true
      and (
        partner_row.partnership_status <> 'official_partner'
        or partner_row.contract_status <> 'signed'
        or partner_row.contract_evidence_id is null
      )
  );
  assert not exists (
    select 1 from public.partners
    where partnership_status = 'official_partner'
      and contract_evidence_id is null
  );
  assert not exists (
    select 1 from public.partners
    where contract_status = 'signed'
      and contract_evidence_id is null
  );
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'post-final lifecycle compatibility', true,
    'public Official Partner remains evidence-derived and signed/official state retains #120 evidence invariants'
  );
end;
$proof$;

select label, ok, detail
from partner_publication_integration_results
order by label;

rollback;
