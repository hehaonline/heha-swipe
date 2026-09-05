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
  expected_hubspot_columns constant text[] := array[
    'name','category','contact','instagram','website','bio','phone',
    'partner_type','neighborhood','hours'
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
  assert not pg_catalog.has_table_privilege('anon', 'public.partners', 'TRUNCATE');
  assert not pg_catalog.has_table_privilege('anon', 'public.partners', 'REFERENCES');
  assert not pg_catalog.has_table_privilege('anon', 'public.partners', 'TRIGGER');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'SELECT');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'INSERT');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'DELETE');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'TRUNCATE');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'REFERENCES');
  assert not pg_catalog.has_table_privilege('service_role', 'public.partners', 'TRIGGER');
  assert pg_catalog.has_table_privilege('authenticated', 'public.partners', 'SELECT');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'INSERT');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'DELETE');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'TRUNCATE');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'REFERENCES');
  assert not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'TRIGGER');
  assert not exists (
    select 1
    from pg_catalog.pg_class relation_row
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation_row.relacl,
        pg_catalog.acldefault('r',relation_row.relowner)
      )
    ) privilege_row
    where relation_row.oid='public.partners'::regclass
      and privilege_row.grantee=0
  ), 'PUBLIC must not retain a raw public.partners table ACL';
  assert not pg_catalog.has_any_column_privilege('anon', 'public.partners', 'SELECT');
  assert not pg_catalog.has_any_column_privilege('anon', 'public.partners', 'INSERT');
  assert not pg_catalog.has_any_column_privilege('anon', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_any_column_privilege('anon', 'public.partners', 'REFERENCES');
  assert not pg_catalog.has_any_column_privilege('service_role', 'public.partners', 'SELECT');
  assert not pg_catalog.has_any_column_privilege('service_role', 'public.partners', 'INSERT');
  assert not pg_catalog.has_any_column_privilege('service_role', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_any_column_privilege('service_role', 'public.partners', 'REFERENCES');
  assert pg_catalog.has_any_column_privilege('authenticated', 'public.partners', 'SELECT');
  assert not pg_catalog.has_any_column_privilege('authenticated', 'public.partners', 'INSERT');
  assert not pg_catalog.has_any_column_privilege('authenticated', 'public.partners', 'UPDATE');
  assert not pg_catalog.has_any_column_privilege('authenticated', 'public.partners', 'REFERENCES');
  assert not exists (
    select 1
    from pg_catalog.pg_attribute attribute_row
    cross join lateral pg_catalog.aclexplode(attribute_row.attacl) privilege_row
    left join pg_catalog.pg_roles role_row
      on role_row.oid=privilege_row.grantee
    where attribute_row.attrelid='public.partners'::regclass
      and attribute_row.attnum>0
      and not attribute_row.attisdropped
      and attribute_row.attacl is not null
      and (
        privilege_row.grantee=0
        or role_row.rolname=any(array['anon','authenticated','service_role']::text[])
      )
  ), 'raw roles must not retain explicit public.partners column ACL entries';
  assert (
    select pg_catalog.array_agg(polname::text order by polname)
    from pg_catalog.pg_policy
    where polrelid='public.partners'::regclass
  ) = array['Owners can view own partner','partners_internal_read']::text[],
    'public.partners must retain SELECT policies only';
  assert pg_catalog.to_regprocedure(
    'public.update_my_partner_profile(uuid,text,text,text[],text,text,text,text[],text,text,text[],text,text,text,text[])'
  ) is not null;
  assert pg_catalog.has_function_privilege(
    'authenticated',
    'public.update_my_partner_profile(uuid,text,text,text[],text,text,text,text[],text,text,text[],text,text,text,text[])',
    'EXECUTE'
  );
  assert not pg_catalog.has_function_privilege(
    'anon',
    'public.update_my_partner_profile(uuid,text,text,text[],text,text,text,text[],text,text,text[],text,text,text,text[])',
    'EXECUTE'
  );
  assert not pg_catalog.has_function_privilege(
    'service_role',
    'public.update_my_partner_profile(uuid,text,text,text[],text,text,text,text[],text,text,text[],text,text,text,text[])',
    'EXECUTE'
  );

  assert pg_catalog.to_regclass('public.partner_publication_consent_events') is not null;
  assert pg_catalog.to_regclass('public.partner_publication_review_events') is not null;
  assert (
    select pg_catalog.bool_and(attnotnull)
    from pg_catalog.pg_attribute
    where attrelid = 'public.partner_publication_consent_events'::regclass
      and attname = any(array[
        'representative_authority_confirmed',
        'profile_preparation_confirmed'
      ]::text[])
      and not attisdropped
  ), 'authority/profile attestations must be durable non-null ledger fields';
  assert (
    select count(*) = 2
    from pg_catalog.pg_attribute
    where attrelid = 'public.partner_publication_consent_events'::regclass
      and attname = any(array[
        'representative_authority_confirmed',
        'profile_preparation_confirmed'
      ]::text[])
      and not attisdropped
  ), 'both authority/profile attestation fields must exist';
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
  assert pg_catalog.to_regprocedure(
    'public.submit_partner_registration_with_consent(uuid,text,text[],text,text,text,text,text[],text,text,text,text,text,text,text[],jsonb,text,text,text[],text,text,boolean,boolean,boolean,boolean,text)'
  ) is not null;
  assert pg_catalog.to_regprocedure(
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,boolean,boolean,uuid,text)'
  ) is not null;
  assert pg_catalog.to_regprocedure(
    'public.record_verified_partner_publication_consent(uuid,text,text,text,text,text,text,text,uuid,text,text,boolean,boolean,boolean,boolean,text[])'
  ) is not null;
  assert pg_catalog.to_regprocedure(
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,uuid,text)'
  ) is null, 'obsolete preparation overload must be retired';
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
  assert pg_catalog.to_regprocedure(
    'public.get_partner_hubspot_sync_source(uuid)'
  ) is not null;
  assert not pg_catalog.has_function_privilege(
    'anon',
    'public.get_partner_hubspot_sync_source(uuid)',
    'EXECUTE'
  );
  assert not pg_catalog.has_function_privilege(
    'authenticated',
    'public.get_partner_hubspot_sync_source(uuid)',
    'EXECUTE'
  );
  assert pg_catalog.has_function_privilege(
    'service_role',
    'public.get_partner_hubspot_sync_source(uuid)',
    'EXECUTE'
  );
  assert (
    select function_row.prosecdef
      and function_row.provolatile='s'
      and 'search_path=""'=any(coalesce(function_row.proconfig,array[]::text[]))
      and function_row.proargnames[2:11]=expected_hubspot_columns
      and function_row.proallargtypes[2:11]=
        pg_catalog.array_fill('pg_catalog.text'::regtype::oid,array[10])
      and function_row.proowner=(
        select relation_row.relowner
        from pg_catalog.pg_class relation_row
        where relation_row.oid='public.partners'::regclass
      )
    from pg_catalog.pg_proc function_row
    where function_row.oid=
      'public.get_partner_hubspot_sync_source(uuid)'::regprocedure
  ), 'HubSpot sync RPC must be same-owner, stable, security-definer and exactly ten text columns';
  assert not exists (
    select 1
    from pg_catalog.pg_proc function_row
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_row.proacl,
        pg_catalog.acldefault('f',function_row.proowner)
      )
    ) privilege_row
    left join pg_catalog.pg_roles role_row
      on role_row.oid=privilege_row.grantee
    where function_row.oid=
      'public.get_partner_hubspot_sync_source(uuid)'::regprocedure
      and privilege_row.privilege_type='EXECUTE'
      and privilege_row.grantee<>function_row.proowner
      and (
        privilege_row.grantee=0
        or role_row.rolname is distinct from 'service_role'
        or privilege_row.is_grantable
      )
  ), 'HubSpot sync RPC must have no PUBLIC, browser, grant-option, or unexpected execute ACL';
  assert pg_catalog.to_regprocedure(
    'public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean)'
  ) is not null;
  assert (
    select function_row.prosecdef
    from pg_catalog.pg_proc function_row
    where function_row.oid=
      'public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean)'::regprocedure
  );
  assert (
    select 'search_path=""'=any(coalesce(function_row.proconfig,array[]::text[]))
    from pg_catalog.pg_proc function_row
    where function_row.oid=
      'public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean)'::regprocedure
  );
  assert not pg_catalog.has_function_privilege(
    'anon',
    'public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean)',
    'EXECUTE'
  );
  assert pg_catalog.has_function_privilege(
    'authenticated',
    'public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean)',
    'EXECUTE'
  );
  assert not pg_catalog.has_function_privilege(
    'service_role',
    'public.review_partner_routing(uuid,text,boolean,boolean,boolean,text,text,text,text,text,boolean)',
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

  assert pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_viewdef('public.public_partner_directory'::regclass, true)
    ),
    'where false'
  ) > 0, 'public partner directory must remain fail-closed';

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
    'raw table and column ACLs denied; private ledgers closed; review and HubSpot RPCs service-only; all public views exactly 33 allowlisted columns'
  );
end;
$proof$;

set local role anon;
select pg_temp.expect_state(
  'anon HubSpot partner sync source denied',
  '42501',
  $$select * from public.get_partner_hubspot_sync_source(
    '78787878-7878-4787-8787-787878787878'
  )$$
);
reset role;

set local role authenticated;
select pg_temp.expect_state(
  'authenticated HubSpot partner sync source denied',
  '42501',
  $$select * from public.get_partner_hubspot_sync_source(
    '78787878-7878-4787-8787-787878787878'
  )$$
);
reset role;

set local role service_role;
do $proof$
declare
  hubspot_source record;
begin
  select * into hubspot_source
  from public.get_partner_hubspot_sync_source(
    '78787878-7878-4787-8787-787878787878'
  );

  assert found, 'service HubSpot partner sync source returned no row';
  assert hubspot_source.name='Tampa Test Kitchen';
  assert hubspot_source.category='Catering';
  assert hubspot_source.contact='PRIVATE contact';
  assert hubspot_source.instagram='@tampatestkitchen';
  assert hubspot_source.website='https://example.invalid';
  assert hubspot_source.bio='Profile version one';
  assert hubspot_source.phone='555-0177';
  assert hubspot_source.neighborhood='Tampa Bay';

  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'service HubSpot partner sync source succeeds', true,
    'service_role reads only the exact ten-field sync projection while raw public.partners remains denied'
  );
end;
$proof$;
reset role;

-- ---------------------------------------------------------------------------
-- Supported new-registration path. No privileged raw partner UPDATE is used:
-- owner submission/consent, exact-hash staff review, routing finalization and
-- listing activation remain separate RPC decisions. Temporarily give this
-- synthetic owner an internal role to prove registration defaults do not depend
-- on the ordinary-owner trigger branch.
-- ---------------------------------------------------------------------------
insert into public.user_roles(user_id,role,active)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'super_admin',
  true
);

select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
set local role authenticated;
select
  submitted.result->>'id' as submitted_partner_id,
  submitted.result->>'public_profile_snapshot_hash' as submitted_profile_hash
from (
  select public.submit_partner_registration_with_consent(
    '72000000-0000-4000-8000-000000000001',
    'Supported Registration Proof',
    array['Restaurant']::text[],
    'Tampa Bay',
    'Fresh food from a supported registration',
    'A complete synthetic public profile for the supported registration proof.',
    'Mon-Fri 9-5',
    array[repeat('é',160)]::text[],
    'Restaurant',
    null,
    'registration-proof@example.invalid',
    'https://registration-proof.example.invalid',
    '@registrationproof',
    'PRIVATE registration location',
    array[repeat('é',160)]::text[],
    '[]'::jsonb,
    '🍽️',
    '#ff8a24',
    array['heha_swipe']::text[],
    'Bailey Owner',
    'Founder',
    true,
    true,
    true,
    false,
    'wave1-profile-consent-2026-08-10'
  ) as result
) submitted \gset
select pg_catalog.set_config(
  'heha.submitted_partner_id',
  :'submitted_partner_id',
  true
) as _submitted_partner_id_context \gset

select (
  public.authorize_partner_profile_publication(
    :'submitted_partner_id'::uuid,
    array['heha_swipe']::text[],
    'Bailey Owner',
    'Founder',
    '72000000-0000-4000-8000-000000000002',
    'wave1-profile-consent-2026-08-10',
    :'submitted_profile_hash'
  )->>'state'
) as submitted_publication_consent_state \gset
reset role;

do $proof$
begin
  assert (
    select status='pending'
      and claim_status='claimed'
      and owner_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
      and claimed_by='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
      and claimed_at is not null
      and partnership_status='not_requested'
      and contract_status='not_required'
      and contract_evidence_id is null
      and listing_status='hidden'
      and routing_status='suggested'
      and routing_notes is null
      and routing_updated_by is null
      and routing_updated_at is null
      and website_eligible is null
      and swipe_eligible is null
      and local_eligible is null
      and local_lane is null
      and heha_pillar='nourish'
      and primary_cta_destination is null
      and primary_cta_label is null
      and primary_cta_path is null
      and reviewed_at is null
      and reviewed_by is null
      and review_note is null
      and approved_by is null
    from public.partners
    where id=current_setting('heha.submitted_partner_id')::uuid
  );
  insert into partner_publication_integration_results(label,ok,detail)
  values (
    'new registration starts pending',
    true,
    'supported owner RPC created claimed, pending, hidden, no-approved-routing, no-staff-evidence defaults while retaining the current-main nourish suggestion'
  );
end;
$proof$;

delete from public.user_roles
where user_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
  and role='super_admin';

set local role anon;
select pg_temp.assert_public_state(
  'new registration initially hidden',
  :'submitted_partner_id'::uuid,
  false,
  false
);
reset role;

select pg_temp.clear_auth();
set local role service_role;
select public.record_partner_publication_review(
  '72000000-0000-4000-8000-000000000003',
  :'submitted_partner_id'::uuid,
  'heha_swipe',
  :'submitted_profile_hash',
  'rejected',
  '12121212-1212-4212-8212-121212121212',
  'Synthetic profile needs a corrected staff review.'
) as submitted_rejection_review_id \gset
reset role;

do $proof$
begin
  assert (
    select status='pending'
    from public.partners
    where id=current_setting('heha.submitted_partner_id')::uuid
  );
  assert not exists (
    select 1
    from public.partner_lifecycle_events
    where partner_id=current_setting('heha.submitted_partner_id')::uuid
      and event_type='publication_review_status_approved'
  );
  insert into partner_publication_integration_results(label,ok,detail)
  values (
    'rejection preserves pending status',
    true,
    'a valid exact-hash rejection records evidence but cannot advance legacy status'
  );
end;
$proof$;

select pg_temp.clear_auth();
set local role service_role;
select public.record_partner_publication_review(
  '72000000-0000-4000-8000-000000000004',
  :'submitted_partner_id'::uuid,
  'heha_swipe',
  :'submitted_profile_hash',
  'approved',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  null
) as submitted_approval_review_id \gset
select public.record_partner_publication_review(
  '72000000-0000-4000-8000-000000000004',
  :'submitted_partner_id'::uuid,
  'heha_swipe',
  :'submitted_profile_hash',
  'approved',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  null
) as submitted_approval_replay_id \gset
reset role;

select pg_temp.assert_true(
  'new registration approval replay',
  :'submitted_approval_replay_id'::uuid=:'submitted_approval_review_id'::uuid,
  'exact review replay returned the original evidence identity'
);

do $proof$
begin
  assert (
    select status='approved'
      and listing_status='hidden'
      and routing_status<>'approved'
    from public.partners
    where id=current_setting('heha.submitted_partner_id')::uuid
  );
  assert (
    select count(*)=1
    from public.partner_lifecycle_events
    where partner_id=current_setting('heha.submitted_partner_id')::uuid
      and event_type='publication_review_status_approved'
      and actor_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
      and before_state->>'status'='pending'
      and after_state->>'status'='approved'
  );
  insert into partner_publication_integration_results(label,ok,detail)
  values (
    'exact review advances status once',
    true,
    'approved exact-hash evidence advanced pending to approved once without routing or listing activation'
  );
end;
$proof$;

set local role anon;
select pg_temp.assert_public_state(
  'status approval without routing hidden',
  :'submitted_partner_id'::uuid,
  false,
  false
);
reset role;

select pg_temp.set_auth('34343434-3434-4434-8434-343434343434');
set local role authenticated;
select pg_temp.expect_state(
  'outsider routing review denied',
  '42501',
  $$select public.review_partner_routing(
    current_setting('heha.submitted_partner_id')::uuid,
    'nourish',true,true,false,null,'swipe','Discover Partner',
    '/?partner='||current_setting('heha.submitted_partner_id'),
    'Unauthorized routing proof',true
  )$$
);
reset role;

select pg_temp.set_auth('12121212-1212-4212-8212-121212121212');
set local role authenticated;
select pg_temp.expect_state(
  'pm routing finalization denied',
  '42501',
  $$select public.review_partner_routing(
    current_setting('heha.submitted_partner_id')::uuid,
    'nourish',true,true,false,null,'swipe','Discover Partner',
    '/?partner='||current_setting('heha.submitted_partner_id'),
    'PM routing finalization proof',true
  )$$
);
reset role;

select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
set local role authenticated;
select public.review_partner_routing(
  :'submitted_partner_id'::uuid,
  'nourish',
  true,
  true,
  false,
  null,
  'swipe',
  'Discover Partner',
  '/?partner='||:'submitted_partner_id',
  'Supported registration routing proof',
  true
);
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'routing without listing activation hidden',
  :'submitted_partner_id'::uuid,
  false,
  false
);
reset role;

select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
set local role authenticated;
select public.set_partner_listing_status(
  :'submitted_partner_id'::uuid,
  'listed'
);
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'supported registration RPC path remains under terms/privacy hold',
  :'submitted_partner_id'::uuid,
  false,
  false
);
reset role;

do $proof$
begin
  assert (
    select status='approved'
      and listing_status='listed'
      and routing_status='approved'
      and coalesce(swipe_eligible,false)
    from public.partners
    where id=current_setting('heha.submitted_partner_id')::uuid
  );
  insert into partner_publication_integration_results(label,ok,detail)
  values (
    'supported registration to gated Swipe path',
    true,
    'supported RPCs reached approved status, routing, and listing while the terms/privacy and website-directory holds remained closed'
  );
end;
$proof$;

-- Raw authenticated mutation stays closed even if the caller forges the
-- internal context value. The registration RPC remains the only owner row
-- creation path and overwrites lifecycle/audit defaults server-side.
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
set local role authenticated;
select pg_catalog.set_config('app.hybrid_partner_context','owner_profile_edit',true);
select pg_temp.expect_state(
  'forged raw owner update denied',
  '42501',
  format(
    'update public.partners set tagline=%L where id=%L::uuid',
    'forged direct update',
    :'submitted_partner_id'
  )
);
select pg_temp.expect_state(
  'forged raw owner insert denied',
  '42501',
  $$insert into public.partners(
      id,created_at,updated_at,owner_id,name,category,categories,
      status,distance_text,reviewed_at,reviewed_by,review_note,approved_by
    ) values (
      '73000000-0000-4000-8000-000000000001',
      '2000-01-01 00:00:00+00',
      '2000-01-01 00:00:00+00',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'Forged direct insert',
      'Restaurant',
      array['Restaurant']::text[],
      'approved',
      'forged',
      pg_catalog.now(),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'forged staff evidence',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    )$$
);
select pg_catalog.set_config('app.hybrid_partner_context','',true);
reset role;

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select pg_temp.expect_state(
  'owner profile RPC cross-business BOLA denied',
  '42501',
  format(
    $$select public.update_my_partner_profile(
      %L::uuid,%L,'Supported Registration Proof',
      array['Restaurant']::text[],'Tampa Bay','cross-business edit',
      'A complete synthetic public profile for the supported registration proof.',
      array[]::text[],'Mon-Fri 9-5','Restaurant',
      array['Prepared meals']::text[],
      'https://registration-proof.example.invalid','@registrationproof',
      null,array[]::text[]
    )$$,
    :'submitted_partner_id',
    :'submitted_profile_hash'
  )
);
reset role;

select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
set local role authenticated;
select pg_temp.expect_state(
  'oversized multibyte partner tag denied',
  '23514',
  format(
    $$select public.update_my_partner_profile(
      %L::uuid,%L,'Supported Registration Proof',
      array['Restaurant']::text[],'Tampa Bay','bounded tag proof',
      'A complete synthetic public profile for the supported registration proof.',
      array[repeat('é',161)]::text[],'Mon-Fri 9-5','Restaurant',
      array['Prepared meals']::text[],
      'https://registration-proof.example.invalid','@registrationproof',
      null,array[]::text[]
    )$$,
    :'submitted_partner_id',
    :'submitted_profile_hash'
  )
);
select pg_temp.expect_state(
  'oversized multibyte partner offering denied',
  '23514',
  format(
    $$select public.update_my_partner_profile(
      %L::uuid,%L,'Supported Registration Proof',
      array['Restaurant']::text[],'Tampa Bay','bounded offering proof',
      'A complete synthetic public profile for the supported registration proof.',
      array[]::text[],'Mon-Fri 9-5','Restaurant',
      array[repeat('é',161)]::text[],
      'https://registration-proof.example.invalid','@registrationproof',
      null,array[]::text[]
    )$$,
    :'submitted_partner_id',
    :'submitted_profile_hash'
  )
);
select pg_temp.expect_state(
  'oversized multibyte delivery day denied',
  '23514',
  format(
    $$select public.update_my_partner_profile(
      %L::uuid,%L,'Supported Registration Proof',
      array['Restaurant']::text[],'Tampa Bay','bounded delivery-day proof',
      'A complete synthetic public profile for the supported registration proof.',
      array[]::text[],'Mon-Fri 9-5','Restaurant',
      array['Prepared meals']::text[],
      'https://registration-proof.example.invalid','@registrationproof',
      null,array[repeat('é',17)]::text[]
    )$$,
    :'submitted_partner_id',
    :'submitted_profile_hash'
  )
);
select
  edit_result.result->>'profile_snapshot_hash' as edited_profile_hash,
  edit_result.result->>'prior_evidence_invalidated' as prior_evidence_invalidated
from (
  select public.update_my_partner_profile(
    :'submitted_partner_id'::uuid,
    :'submitted_profile_hash',
    'Supported Registration Proof',
    array['Restaurant']::text[],
    'Tampa Bay',
    'Fresh food from a reviewed owner edit',
    'A complete synthetic public profile for the supported registration proof.',
    array[]::text[],
    'Mon-Fri 9-5',
    'Restaurant',
    array['Prepared meals']::text[],
    'https://registration-proof.example.invalid',
    '@registrationproof',
    null,
    array[repeat('é',16)]::text[]
  ) as result
) edit_result \gset

select pg_temp.expect_state(
  'stale owner profile hash denied',
  '40001',
  format(
    $$select public.update_my_partner_profile(
      %L::uuid,%L,'Supported Registration Proof',
      array['Restaurant']::text[],'Tampa Bay','stale replay',
      'A complete synthetic public profile for the supported registration proof.',
      array[]::text[],'Mon-Fri 9-5','Restaurant',
      array['Prepared meals']::text[],
      'https://registration-proof.example.invalid','@registrationproof',
      null,array[]::text[]
    )$$,
    :'submitted_partner_id',
    :'submitted_profile_hash'
  )
);
reset role;

select pg_catalog.set_config(
  'heha.edited_profile_hash',
  :'edited_profile_hash',
  true
) as _edited_profile_hash_context \gset
select pg_catalog.set_config(
  'heha.prior_evidence_invalidated',
  :'prior_evidence_invalidated',
  true
) as _prior_evidence_invalidated_context \gset
select pg_catalog.set_config(
  'heha.submitted_profile_hash',
  :'submitted_profile_hash',
  true
) as _submitted_profile_hash_context \gset

do $proof$
declare
  status_payload jsonb;
begin
  assert current_setting('heha.edited_profile_hash')
    <>current_setting('heha.submitted_profile_hash');
  assert current_setting('heha.prior_evidence_invalidated')='true';
  status_payload := public.get_my_partner_publication_status(
    current_setting('heha.submitted_partner_id')::uuid
  );
  assert status_payload->>'profile_snapshot_hash'
    =current_setting('heha.edited_profile_hash');
  assert status_payload->'publication_destinations'='[]'::jsonb;
  assert status_payload->'staff_review_destinations'='[]'::jsonb;
  assert (
    select status='approved'
      and listing_status='listed'
      and reviewed_by is null
      and routing_status='needs_review'
      and routing_notes is null
      and routing_updated_by is null
      and routing_updated_at is not null
      and website_eligible is true
      and swipe_eligible is true
      and local_eligible is true
      and local_lane='meals'
      and heha_pillar='nourish'
      and primary_cta_destination='local'
      and primary_cta_label='Order Meals'
      and primary_cta_path='/restaurants'
      and complete_pct=app_private.partner_completion_pct(partners)
    from public.partners
    where id=current_setting('heha.submitted_partner_id')::uuid
  );
  assert not exists (
    select 1
    from app_private.partner_lifecycle_mutation_capabilities capability_row
    where capability_row.backend_pid=pg_catalog.pg_backend_pid()
      and capability_row.transaction_id=pg_catalog.txid_current()
      and capability_row.partner_id=current_setting('heha.submitted_partner_id')::uuid
  );
  assert exists (
    select 1
    from public.partner_publication_consent_events
    where partner_id=current_setting('heha.submitted_partner_id')::uuid
      and profile_snapshot_hash=current_setting('heha.submitted_profile_hash')
  );
  assert exists (
    select 1
    from public.partner_publication_review_events
    where partner_id=current_setting('heha.submitted_partner_id')::uuid
      and profile_snapshot_hash=current_setting('heha.submitted_profile_hash')
  );
  insert into partner_publication_integration_results(label,ok,detail)
  values (
    'owner profile RPC invalidates prior evidence and routing',
    true,
    'typed current-owner edit changed the exact snapshot hash, recomputed completion, consumed its private capability, preserved append-only evidence, and forced current-main routing suggestions back through needs_review'
  );
end;
$proof$;
reset role;

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

-- Continue on the pre-existing approved fixture without mutating raw lifecycle
-- status. Failed attestations, forged authority, unauthorized reviewers and
-- stale hashes must leave the lifecycle untouched; the supported pending ->
-- approved path is proved above through the owner-registration RPC.
select pg_temp.assert_true(
  'review fixture remains approved',
  (select status = 'approved' from public.partners
   where id = '78787878-7878-4787-8787-787878787878'),
  'the pre-existing fixture remains approved before consent and staff review'
);

-- Owner grants both destination permissions for the exact current profile.
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;
select pg_temp.expect_state(
  'representative authority attestation required',
  '23514',
  $$select public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe','heha_local']::text[],
    'Avery Owner', 'Founder',
    false, true, true, true,
    '70000000-0000-4000-8000-000000000021',
    'wave1-profile-consent-2026-08-10'
  )$$
);
select pg_temp.expect_state(
  'profile preparation attestation required',
  '23514',
  $$select public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe','heha_local']::text[],
    'Avery Owner', 'Founder',
    true, false, true, true,
    '70000000-0000-4000-8000-000000000022',
    'wave1-profile-consent-2026-08-10'
  )$$
);
select (
  public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_swipe','heha_local']::text[],
    'Avery Owner',
    'Founder',
    true,
    true,
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

do $proof$
begin
  assert not exists (
    select 1
    from public.partner_publication_consent_events
    where request_key = any(array[
      '70000000-0000-4000-8000-000000000021'::uuid,
      '70000000-0000-4000-8000-000000000022'::uuid
    ])
  ), 'failed authority/profile attestation requests must not append evidence';
  assert (
    select count(*) = 4
    from public.partner_publication_consent_events
    where request_key = any(array[
      '70000000-0000-4000-8000-000000000001'::uuid,
      '70000000-0000-4000-8000-000000000002'::uuid
    ])
      and state = 'granted'
      and representative_authority_confirmed
      and profile_preparation_confirmed
      and media_permission_confirmed
  ), 'both destination grants must persist authority/profile/media attestations';
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'durable owner attestations', true,
    'false authority/profile confirmations append nothing; all four current destination grant events persist true attestations'
  );
end;
$proof$;

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

reset role;
select pg_temp.assert_true(
  'failed review attempts preserve status',
  (select status = 'approved' from public.partners
   where id = '78787878-7878-4787-8787-787878787878'),
  'forged authority, unauthorized reviewers and a stale hash do not mutate lifecycle state'
);
set local role service_role;

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
reset role;
select pg_temp.assert_true(
  'exact approved review preserves approved fixture',
  (select status = 'approved' from public.partners
   where id = '78787878-7878-4787-8787-787878787878'),
  'the exact current-hash approved review and replay leave the already-approved fixture unchanged'
);

-- Exact-hash profile approval does not finalize routing. The supported routing
-- review remains an independent super-admin decision.
reset role;
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
set local role authenticated;
select public.review_partner_routing(
  '78787878-7878-4787-8787-787878787878',
  'nourish',
  true,
  true,
  false,
  null,
  'swipe',
  'Discover Partner',
  '/?partner=78787878-7878-4787-8787-787878787878',
  'Exact-hash publication proof routing review',
  true
);
reset role;

-- Exact replay is historical evidence and remains stable after the reviewer is
-- deactivated. A new decision may not be attributed to that inactive reviewer.
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
  assert status_payload -> 'public_destinations' = '[]'::jsonb,
    pg_catalog.format(
      'public_destinations must stay empty under legal hold; got %s',
      status_payload -> 'public_destinations'
    );
  assert status_payload -> 'staff_review_destinations' = '["heha_swipe"]'::jsonb,
    pg_catalog.format(
      'staff_review_destinations must retain exact Swipe review; got %s',
      status_payload -> 'staff_review_destinations'
    );
  assert not (status_payload ?| array[
    'authorized_account_contact','evidence_reference','reviewed_by','reviewer_id',
    'recorded_by','request_key','request_payload_hash'
  ]::text[]), 'owner status leaked a private evidence identity field';
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'redacted authoritative owner status under legal hold', true,
    'owner status reports exact Swipe staff review but no public destination or private evidence identities while the legal hold is active'
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
  assert status_payload -> 'public_destinations' = '[]'::jsonb,
    pg_catalog.format(
      'public_destinations must stay empty under Swipe/Local legal holds; got %s',
      status_payload -> 'public_destinations'
    );
  assert status_payload -> 'staff_review_destinations'
    = '["heha_swipe", "heha_local"]'::jsonb,
    pg_catalog.format(
      'staff_review_destinations must retain exact Swipe and Local reviews; got %s',
      status_payload -> 'staff_review_destinations'
    );
  assert not (status_payload ?| array[
    'authorized_account_contact','evidence_reference','reviewed_by','reviewer_id',
    'recorded_by','request_key','request_payload_hash'
  ]::text[]), 'owner status leaked a private evidence identity field';
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'legal hold absent from authoritative public status', true,
    'Swipe and Local may be exact-review approved, but neither is reported public while their independent release gates remain disabled'
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

-- Grant plus exact-hash staff review records current evidence, but the legal
-- hold keeps both public Swipe and website-directory projections empty until
-- approved versioned terms/privacy evidence is implemented.
set local role anon;
select pg_temp.assert_public_state(
  'grant and staff review remain under legal hold',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
do $proof$
begin
  assert not exists (select 1 from public.public_partner_directory),
    'website directory must remain empty even after Swipe review';
  assert not exists (select 1 from public.public_swipe_partners),
    'Swipe must remain empty until approved terms/privacy evidence is bound';
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'public projections legal hold', true,
    'current owner consent and exact-hash staff review do not bypass the empty Swipe and website-directory legal hold'
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
  'local withdrawal preserves private Swipe evidence under legal hold',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
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

-- Leave the withdrawal's pending status and routing reset intact. Owner
-- re-consent still cannot publish; the next exact-hash approval must perform
-- the supported pending-to-approved transition, followed by routing review.
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
    true,
    false,
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
select pg_temp.assert_true(
  'unchanged reconsent remains pending',
  (select status = 'pending' from public.partners
   where id = '78787878-7878-4787-8787-787878787878'),
  'owner reconsent does not bypass the staff-owned pending-to-approved transition'
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
select pg_temp.assert_true(
  'fresh exact review re-approves pending profile',
  (select status = 'approved' from public.partners
   where id = '78787878-7878-4787-8787-787878787878'),
  'fresh exact-hash review advances the withdrawn pending profile back to approved'
);

do $proof$
begin
  assert (
    select status='approved'
      and routing_status='needs_review'
      and coalesce(swipe_eligible,false)=false
    from public.partners
    where id='78787878-7878-4787-8787-787878787878'
  );
  assert (
    select count(*)=1
    from public.partner_lifecycle_events
    where partner_id='78787878-7878-4787-8787-787878787878'
      and event_type='publication_review_status_approved'
      and actor_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
      and after_state->>'publication_review_event_id'
        = (
          select review_row.id::text
          from public.partner_publication_review_events review_row
          where review_row.request_key='70000000-0000-4000-8000-000000000013'
        )
  );
  insert into partner_publication_integration_results(label,ok,detail)
  values (
    'supported pending status transition',
    true,
    'fresh exact-hash approval advanced pending to approved once while routing remained unapproved'
  );
end;
$proof$;

set local role anon;
select pg_temp.assert_public_state(
  'status approval alone remains hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
set local role authenticated;
select public.review_partner_routing(
  '78787878-7878-4787-8787-787878787878',
  'nourish',
  true,
  true,
  false,
  null,
  'swipe',
  'Discover Partner',
  '/?partner=78787878-7878-4787-8787-787878787878',
  'Fresh exact-hash reapproval routing review',
  true
);
reset role;

set local role anon;
select pg_temp.assert_public_state(
  'fresh review after unchanged reconsent remains under legal hold',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
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
    true,
    false,
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
  'profile drift fresh exact review remains under legal hold',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
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
    true,
    false,
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
  'category mutation fresh exact review remains under legal hold',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
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
  'independent listing relist remains under legal hold',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
);
reset role;

-- Swipe accepts every explicitly supported category, while the not-yet-enabled
-- Local destination remains limited to Catering/PrivateChef. Restaurant is a
-- supported Swipe category but deliberately outside that Wave 1 Local subset.
select pg_temp.clear_auth();
update public.partners
set category = 'Restaurant',
    categories = array['Restaurant']::text[],
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
    true,
    false,
    '70000000-0000-4000-8000-000000000023',
    'wave1-profile-consent-2026-08-10'
  ) ->> 'profile_snapshot_hash'
) as restaurant_swipe_hash \gset
select pg_temp.expect_state(
  'non-wave1 Local preparation denied',
  '23514',
  $$select public.authorize_existing_partner_profile_preparation(
    '78787878-7878-4787-8787-787878787878',
    array['heha_local']::text[],
    'Avery Owner', 'Founder',
    true, true, true, true,
    '70000000-0000-4000-8000-000000000024',
    'wave1-profile-consent-2026-08-10'
  )$$
);
reset role;

select pg_temp.assert_true(
  'supported non-wave1 Swipe preparation',
  :'restaurant_swipe_hash' ~ '^[0-9a-f]{64}$',
  'Restaurant returned an exact Swipe preparation snapshot hash'
);
do $proof$
begin
  assert exists (
    select 1
    from public.partner_publication_consent_events
    where request_key = '70000000-0000-4000-8000-000000000023'
      and destination = 'heha_swipe'
      and action = 'prepare_profile'
      and state = 'granted'
      and representative_authority_confirmed
      and profile_preparation_confirmed
      and media_permission_confirmed
      and service_area_attested is false
      and service_areas = array[]::text[]
  );
  assert not exists (
    select 1
    from public.partner_publication_consent_events
    where request_key = '70000000-0000-4000-8000-000000000024'
  );
  insert into partner_publication_integration_results(label, ok, detail)
  values (
    'supported non-wave1 Swipe boundary', true,
    'Restaurant preparation succeeds for Swipe with durable attestations and no service area; Local rejects it without recording evidence'
  );
end;
$proof$;

set local role anon;
select pg_temp.assert_public_state(
  'non-wave1 preparation alone hidden',
  '78787878-7878-4787-8787-787878787878',
  false,
  false
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
