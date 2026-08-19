-- Partner publication consent security proof for the composed integration RC.
-- Apply the complete RC migration set to a disposable database first. Never
-- run this proof against Production. All fixture changes are rolled back.
--
-- Required psql variables:
--   wave1_partner_id    - an owned Catering or PrivateChef row safe to mutate
--   super_admin_user_id - an active super_admin distinct from the owner

\set ON_ERROR_STOP on

begin;

create temporary table partner_publication_consent_proof_inputs (
  partner_id uuid primary key,
  super_admin_id uuid not null,
  owner_id uuid not null
) on commit drop;

insert into partner_publication_consent_proof_inputs(partner_id, super_admin_id, owner_id)
select :'wave1_partner_id'::uuid, :'super_admin_user_id'::uuid, p.owner_id
from public.partners p
where p.id = :'wave1_partner_id'::uuid
  and p.owner_id is not null
  and app_private.is_wave1_food_partner(p);

do $$
begin
  if (select count(*) from pg_temp.partner_publication_consent_proof_inputs) <> 1 then
    raise exception 'proof partner must be an owned Catering or PrivateChef row';
  end if;
  if exists (
    select 1 from pg_temp.partner_publication_consent_proof_inputs
    where owner_id = super_admin_id
  ) then
    raise exception 'super_admin_user_id must differ from the proof owner';
  end if;
end;
$$;

select set_config('heha.proof_partner_id', partner_id::text, true),
       set_config('heha.proof_super_admin_id', super_admin_id::text, true),
       set_config('heha.proof_owner_id', owner_id::text, true)
from partner_publication_consent_proof_inputs;

create temporary table partner_publication_consent_results (
  label text primary key,
  ok boolean not null,
  detail text not null
) on commit drop;

create or replace function pg_temp.set_auth_context(
  p_role text,
  p_sub uuid default null,
  p_email text default null,
  p_is_anonymous boolean default false
)
returns void
language plpgsql
as $$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_sub,
      'role', p_role,
      'email', coalesce(p_email, 'proof@heha.example'),
      'is_anonymous', p_is_anonymous
    )::text,
    true
  );
  perform set_config('request.jwt.claim.sub', v_sub, true);
  perform set_config('request.jwt.claim.role', p_role, true);
end;
$$;

create or replace function pg_temp.public_has_function_execute(p_function regprocedure)
returns boolean
language sql
as $$
  select exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where p.oid = p_function
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  );
$$;

-- Static private-ledger, grants, search-path, and authority contract.
do $$
declare
  v_function regprocedure;
  v_config text[];
  v_definition text;
begin
  if not (
    select c.relrowsecurity
    from pg_catalog.pg_class c
    where c.oid = 'public.partner_publication_consent_events'::regclass
  ) then
    raise exception 'consent ledger must have RLS enabled';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid = 'public.partner_publication_consent_events'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.confrelid = 'auth.users'::regclass
  ) then
    raise exception 'immutable owner/recorder identity snapshots must not be Auth deletion FKs';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.partner_publication_consent_events'::regclass
      and trigger_row.tgname = 'partner_publication_consent_events_immutable'
      and not trigger_row.tgisinternal
      and trigger_row.tgenabled <> 'D'
  ) then
    raise exception 'consent ledger needs an enabled structural UPDATE/DELETE deny trigger';
  end if;
  if pg_catalog.has_table_privilege('anon', 'public.partner_publication_consent_events', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.partner_publication_consent_events', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'TRUNCATE')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'INSERT')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'UPDATE')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'DELETE')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'TRUNCATE') then
    raise exception 'private append-only ledger has broader direct privileges than intended';
  end if;
  if pg_catalog.has_sequence_privilege(
       'authenticated',
       'public.partner_publication_consent_events_event_sequence_seq',
       'USAGE'
     ) or pg_catalog.has_sequence_privilege(
       'service_role',
       'public.partner_publication_consent_events_event_sequence_seq',
       'USAGE'
     ) then
    raise exception 'browser/service roles must not directly advance the event sequence';
  end if;
  if pg_catalog.has_function_privilege(
       'authenticated', 'app_private.is_service_role_request()', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'service_role', 'app_private.is_service_role_request()', 'EXECUTE'
     ) then
    raise exception 'private service-role authority helper must not be client-executable';
  end if;
  if pg_catalog.has_function_privilege(
       'authenticated', 'app_private.guard_partner_publication_consent_immutability()', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'service_role', 'app_private.guard_partner_publication_consent_immutability()', 'EXECUTE'
     ) then
    raise exception 'consent immutability trigger helper must not be client-executable';
  end if;

  foreach v_function in array array[
    'public.submit_partner_registration_with_consent(uuid,text,text[],text,text,text,text,text[],text,text,text,text,text,text,text[],jsonb,text,text,text[],text,text,boolean,boolean,boolean,boolean,text)'::regprocedure,
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,boolean,boolean,uuid,text)'::regprocedure,
    'public.authorize_partner_profile_publication(uuid,text[],text,text,uuid,text,text)'::regprocedure,
    'public.withdraw_partner_publication_authorization(uuid,text[],text,text,uuid,text)'::regprocedure,
    'public.get_my_partner_publication_status(uuid)'::regprocedure,
    'public.record_verified_partner_publication_consent(uuid,text,text,text,text,text,text,text,uuid,text,text,boolean,boolean,boolean,boolean,text[])'::regprocedure
  ] loop
    select p.proconfig into v_config from pg_catalog.pg_proc p where p.oid = v_function;
    if not ('search_path=""' = any (coalesce(v_config, array[]::text[]))) then
      raise exception '% must pin search_path to empty', v_function;
    end if;
    if pg_temp.public_has_function_execute(v_function)
       or pg_catalog.has_function_privilege('anon', v_function, 'EXECUTE') then
      raise exception 'PUBLIC/anon must not execute %', v_function;
    end if;
  end loop;

  foreach v_function in array array[
    'public.submit_partner_registration_with_consent(uuid,text,text[],text,text,text,text,text[],text,text,text,text,text,text,text[],jsonb,text,text,text[],text,text,boolean,boolean,boolean,boolean,text)'::regprocedure,
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,boolean,boolean,uuid,text)'::regprocedure,
    'public.authorize_partner_profile_publication(uuid,text[],text,text,uuid,text,text)'::regprocedure,
    'public.withdraw_partner_publication_authorization(uuid,text[],text,text,uuid,text)'::regprocedure,
    'public.get_my_partner_publication_status(uuid)'::regprocedure
  ] loop
    if not pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE') then
      raise exception 'owner-only RPC has wrong grants: %', v_function;
    end if;
  end loop;

  v_function := 'public.withdraw_partner_publication_authorization(uuid,text[],text,text,uuid,text)'::regprocedure;
  select lower(pg_get_functiondef(v_function)) into v_definition;
  if position('app_private.authorize_partner_lifecycle_mutation' in v_definition) = 0 then
    raise exception 'owner withdrawal must mint the private listing-change capability before updating the partner';
  end if;

  v_function := 'public.record_verified_partner_publication_consent(uuid,text,text,text,text,text,text,text,uuid,text,text,boolean,boolean,boolean,boolean,text[])'::regprocedure;
  if not pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE') then
    raise exception 'verified-consent RPC needs authenticated + service_role execution';
  end if;
  select lower(pg_get_functiondef(v_function)) into v_definition;
  if position('app_private.is_service_role_request()' in v_definition) = 0
     or position('request.jwt' in v_definition) > 0
     or position('app_private.authorize_partner_lifecycle_mutation' in v_definition) = 0 then
    raise exception 'verified-consent RPC must use non-forgeable service authority and a private capability for routing withdrawal';
  end if;
  v_function := pg_catalog.to_regprocedure('public.approve_partner(uuid)');
  if v_function is not null and (
       pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE')
     ) then
    raise exception 'legacy one-step approve_partner must remain retired';
  end if;

  insert into pg_temp.partner_publication_consent_results values (
    'private ledger and RPC authority', true,
    'structural append-only ledger with durable identity snapshots; browser access denied; owner RPCs scoped; service helper non-forgeable; legacy approval retired'
  );
end;
$$;

-- Unsupported group-order URL is denied; only the exact future exporter shape
-- is recognized internally. The final public projection still disables Local.
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
begin
  if app_private.is_specific_local_partner_path('/group-orders/' || v_partner_id::text)
     or app_private.is_specific_wave1_local_partner_path(
       '/group-orders/' || v_partner_id::text, v_partner_id, 'group_orders'
     ) then
    raise exception 'unsupported /group-orders route was accepted';
  end if;
  if not app_private.is_specific_wave1_local_partner_path(
    '/chef/match?swipePartnerId=' || v_partner_id::text || '&service=catering',
    v_partner_id,
    'group_orders'
  ) then
    raise exception 'exact future catering exporter contract was not recognized';
  end if;
  if app_private.is_specific_local_partner_path('/chef') then
    raise exception 'generic /chef path was accepted';
  end if;
  insert into pg_temp.partner_publication_consent_results values (
    'Local route boundary', true,
    'unsupported group-order/generic paths denied; exact future catering match shape recognized only internally'
  );
end;
$$;

-- Evidence is append-only. Do not delete any pre-existing consent or staff
-- review row: the new owner consent events below receive later sequences, so an
-- earlier review stays bound to its earlier consent event and cannot authorize
-- the new exact owner consent.
update public.partners
set status = 'live',
    website_eligible = false,
    swipe_eligible = true,
    local_eligible = true,
    local_lane = app_private.wave1_local_lane(partners),
    primary_cta_destination = 'local',
    primary_cta_label = 'Request a quote',
    primary_cta_path = '/group-orders/' || id::text,
    routing_status = 'approved',
    is_test_record = false
where id = current_setting('heha.proof_partner_id')::uuid;

-- JWT/GUC service-role forgery under the authenticated database role fails.
select pg_temp.set_auth_context('service_role', gen_random_uuid(), 'forged@heha.example');
set local role authenticated;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
begin
  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'heha_swipe', 'prepare_profile', 'revoked',
      'Forged Service', 'Attacker', 'attacker@heha.example', 'forged-service-role',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null,
      false, false, false, false,
      array['Tampa Bay']::text[]
    );
    raise exception 'forged service JWT recorded consent';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.partner_publication_consent_events where partner_id = v_partner_id;
    raise exception 'authenticated caller read private consent ledger';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
insert into partner_publication_consent_results values (
  'forged service authority', true,
  'service_role JWT/GUC forgery denied under authenticated database role'
);

-- Positive authority uses actual database service_role with an ordinary JWT.
select pg_temp.set_auth_context(
  'authenticated',
  current_setting('heha.proof_super_admin_id')::uuid,
  'service-proof@heha.example'
);
set local role service_role;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_key uuid := gen_random_uuid();
  v_event uuid;
begin
  v_event := public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_swipe', 'publish_profile', 'revoked',
    'Wave One Proof', 'Operations', 'proof@heha.example', 'real-service-revocation',
    v_key, 'wave1-profile-consent-2026-08-10', null,
    false, false, false, false,
    array['Tampa Bay']::text[]
  );
  if v_event is null or public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_swipe', 'publish_profile', 'revoked',
    'Wave One Proof', 'Operations', 'proof@heha.example', 'real-service-revocation',
    v_key, 'wave1-profile-consent-2026-08-10', null,
    false, false, false, false,
    array['Tampa Bay']::text[]
  ) is distinct from v_event then
    raise exception 'real service role failed idempotent evidence recording';
  end if;
  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'invalid_destination', 'publish_profile', 'revoked',
      'Wave One Proof', 'Operations', 'proof@heha.example', 'invalid-destination',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null,
      false, false, false, false,
      array['Tampa Bay']::text[]
    );
    raise exception 'invalid destination was accepted';
  exception when check_violation then null;
  end;
  -- Satisfy the separate listing-review gate so the later owner-consent-only
  -- invisibility assertion isolates the missing staff publication review.
  perform public.set_partner_listing_status(v_partner_id, 'listed');
end;
$$;
reset role;
insert into partner_publication_consent_results values (
  'real service authority', true,
  'actual service_role succeeds and stays idempotent; invalid destination fails closed'
);

-- Owner grants remain consent only, never staff review. Then withdraw just the
-- Local destination and prove Swipe consent remains current.
select pg_temp.set_auth_context(
  'authenticated',
  current_setting('heha.proof_owner_id')::uuid,
  'owner@heha.example'
);
set local role authenticated;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_prepare_key uuid := gen_random_uuid();
  v_publish_key uuid := gen_random_uuid();
  v_withdraw_key uuid := gen_random_uuid();
  v_status jsonb;
  v_first jsonb;
begin
  begin
    perform 1 from public.partner_publication_consent_events where partner_id = v_partner_id;
    raise exception 'current owner read private consent history directly';
  exception when insufficient_privilege then null;
  end;

  perform public.authorize_existing_partner_profile_preparation(
    v_partner_id, array['heha_swipe', 'heha_local']::text[],
    'Wave One Owner', 'Owner', true, true, true, true, v_prepare_key,
    'wave1-profile-consent-2026-08-10'
  );
  perform public.authorize_existing_partner_profile_preparation(
    v_partner_id, array['heha_swipe', 'heha_local']::text[],
    'Wave One Owner', 'Owner', true, true, true, true, v_prepare_key,
    'wave1-profile-consent-2026-08-10'
  );
  v_status := public.get_my_partner_publication_status(v_partner_id);
  perform public.authorize_partner_profile_publication(
    v_partner_id, array['heha_swipe', 'heha_local']::text[],
    'Wave One Owner', 'Owner', v_publish_key,
    'wave1-profile-consent-2026-08-10', v_status ->> 'profile_snapshot_hash'
  );
  perform public.authorize_partner_profile_publication(
    v_partner_id, array['heha_swipe', 'heha_local']::text[],
    'Wave One Owner', 'Owner', v_publish_key,
    'wave1-profile-consent-2026-08-10', v_status ->> 'profile_snapshot_hash'
  );
  v_status := public.get_my_partner_publication_status(v_partner_id);
  if v_status -> 'publication_destinations' <> '["heha_swipe", "heha_local"]'::jsonb
     and v_status -> 'publication_destinations' <> '["heha_local", "heha_swipe"]'::jsonb then
    raise exception 'owner exact-hash consent did not cover both destinations';
  end if;
  if exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'owner consent alone became staff review or enabled Local export';
  end if;

  v_first := public.withdraw_partner_publication_authorization(
    v_partner_id, array['heha_local']::text[],
    'Wave One Owner', 'Owner', v_withdraw_key,
    'wave1-profile-consent-2026-08-10'
  );
  if public.withdraw_partner_publication_authorization(
    v_partner_id, array['heha_local']::text[],
    'Wave One Owner', 'Owner', v_withdraw_key,
    'wave1-profile-consent-2026-08-10'
  ) is distinct from v_first then
    raise exception 'withdrawal retry returned a different response';
  end if;
  begin
    perform public.withdraw_partner_publication_authorization(
      v_partner_id, array['heha_swipe']::text[],
      'Wave One Owner', 'Owner', v_withdraw_key,
      'wave1-profile-consent-2026-08-10'
    );
    raise exception 'withdrawal key was reused for a different destination';
  exception when unique_violation then null;
  end;
  begin
    perform public.withdraw_partner_publication_authorization(
      v_partner_id, array['not_a_destination']::text[],
      'Wave One Owner', 'Owner', gen_random_uuid(),
      'wave1-profile-consent-2026-08-10'
    );
    raise exception 'invalid withdrawal destination was accepted';
  exception when check_violation then null;
  end;
  v_status := public.get_my_partner_publication_status(v_partner_id);
  if v_status -> 'publication_destinations' <> '["heha_swipe"]'::jsonb then
    raise exception 'Local-only withdrawal did not preserve Swipe consent';
  end if;
  if exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'Local export or CTA became public';
  end if;

  perform set_config('heha.proof_prepare_key', v_prepare_key::text, true);
  perform set_config('heha.proof_publish_key', v_publish_key::text, true);
  perform set_config('heha.proof_withdraw_key', v_withdraw_key::text, true);
end;
$$;
reset role;

do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_owner_id uuid := current_setting('heha.proof_owner_id')::uuid;
begin
  begin
    update public.partner_publication_consent_events
    set owner_id = gen_random_uuid()
    where request_key = current_setting('heha.proof_withdraw_key')::uuid;
    raise exception 'consent evidence UPDATE bypassed the structural append-only trigger';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.partner_publication_consent_events
    where request_key = current_setting('heha.proof_withdraw_key')::uuid;
    raise exception 'consent evidence DELETE bypassed the structural append-only trigger';
  exception when insufficient_privilege then null;
  end;
  if (select count(*) from public.partner_publication_consent_events
      where request_key = current_setting('heha.proof_prepare_key')::uuid) <> 2
     or (select count(*) from public.partner_publication_consent_events
      where request_key = current_setting('heha.proof_publish_key')::uuid) <> 2 then
    raise exception 'owner grant idempotency created duplicate destination events';
  end if;
  if (select count(*) from public.partner_publication_consent_events
      where request_key = current_setting('heha.proof_withdraw_key')::uuid
        and partner_id = v_partner_id
        and owner_id = v_owner_id
        and destination = 'heha_local'
        and action = 'publish_profile'
        and state = 'revoked') <> 1 then
    raise exception 'owner withdrawal did not append one owner-scoped Local revocation';
  end if;
  if not app_private.has_current_partner_publication_authorization(
       (select p from public.partners p where p.id = v_partner_id), 'heha_swipe'
     ) or app_private.has_current_partner_publication_authorization(
       (select p from public.partners p where p.id = v_partner_id), 'heha_local'
     ) then
    raise exception 'withdrawal did not preserve only current Swipe consent';
  end if;
  if exists (select 1 from public.partners
             where id = v_partner_id and (local_eligible or local_lane is not null)) then
    raise exception 'Local withdrawal did not clear raw Local eligibility';
  end if;
  insert into pg_temp.partner_publication_consent_results values (
    'owner consent and withdrawal', true,
    'redacted status only; consent alone non-public; Local withdrawal append-only/idempotent and Swipe-preserving'
  );
end;
$$;

-- Deleting an Auth account must not rewrite immutable owner/recorder evidence.
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_deleted_user_id uuid := gen_random_uuid();
  v_evidence_key uuid := gen_random_uuid();
  v_partner public.partners;
begin
  insert into auth.users (
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
  ) values (
    v_deleted_user_id,
    'authenticated',
    'authenticated',
    'deleted-consent-' || v_deleted_user_id::text || '@example.invalid',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    false,
    false,
    now(),
    now()
  );

  select p.* into v_partner from public.partners p where p.id = v_partner_id;
  insert into public.partner_publication_consent_events (
    partner_id, owner_id, destination, action, state,
    authorized_representative_name, authorized_representative_title,
    authorized_account_contact, consent_statement_version, evidence_channel,
    evidence_reference, service_areas, local_lane, media_permission_confirmed,
    service_area_attested, profile_snapshot, profile_snapshot_hash, request_key,
    request_payload_hash, recorded_by
  ) values (
    v_partner_id, v_deleted_user_id, 'heha_local', 'prepare_profile', 'revoked',
    'Deleted Account Proof', 'Former Owner',
    'deleted-consent@example.invalid', 'wave1-profile-consent-2026-08-10',
    'admin_record', 'account-deletion-durability', array['Tampa Bay']::text[],
    app_private.wave1_local_lane(v_partner), false, false,
    app_private.partner_public_profile_snapshot(v_partner),
    app_private.partner_public_profile_hash(v_partner), v_evidence_key,
    repeat('b', 64), v_deleted_user_id
  );

  delete from auth.users where id = v_deleted_user_id;
  if exists (select 1 from auth.users where id = v_deleted_user_id)
     or not exists (
       select 1
       from public.partner_publication_consent_events
       where request_key = v_evidence_key
         and owner_id = v_deleted_user_id
         and recorded_by = v_deleted_user_id
     ) then
    raise exception 'Auth deletion erased or rewrote immutable consent identity snapshots';
  end if;

  insert into pg_temp.partner_publication_consent_results values (
    'account deletion durability', true,
    'deleting an Auth user preserves immutable owner_id and recorded_by UUID evidence snapshots'
  );
end;
$$;

-- BOLA: unrelated authenticated user cannot inspect or narrow this partner.
select pg_temp.set_auth_context('authenticated', gen_random_uuid(), 'unrelated@heha.example');
set local role authenticated;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
begin
  begin
    perform public.get_my_partner_publication_status(v_partner_id);
    raise exception 'unrelated user read owner status';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.withdraw_partner_publication_authorization(
      v_partner_id, array['heha_swipe']::text[],
      'Wrong User', 'Viewer', gen_random_uuid(),
      'wave1-profile-consent-2026-08-10'
    );
    raise exception 'unrelated user withdrew owner consent';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
insert into partner_publication_consent_results values (
  'owner BOLA denial', true,
  'unrelated authenticated users cannot inspect status or withdraw another owner destination'
);

-- A historical event owner_id must not grant a former owner any access after
-- the partner has a different current owner.
insert into public.partner_publication_consent_events (
  partner_id, owner_id, destination, action, state,
  authorized_representative_name, authorized_representative_title,
  authorized_account_contact, consent_statement_version, evidence_channel,
  evidence_reference, service_areas, local_lane, media_permission_confirmed,
  service_area_attested, profile_snapshot, profile_snapshot_hash, request_key,
  request_payload_hash, recorded_by
)
select
  p.id, current_setting('heha.proof_super_admin_id')::uuid,
  'heha_swipe', 'prepare_profile', 'revoked',
  'Former Owner Proof', 'Former Owner', 'former-owner@heha.example',
  'wave1-profile-consent-2026-08-10', 'admin_record',
  'historical-former-owner-evidence', array['Tampa Bay']::text[], null,
  false, false, app_private.partner_public_profile_snapshot(p),
  app_private.partner_public_profile_hash(p), gen_random_uuid(), repeat('a', 64),
  current_setting('heha.proof_super_admin_id')::uuid
from public.partners p
where p.id = current_setting('heha.proof_partner_id')::uuid;

select pg_temp.set_auth_context(
  'authenticated',
  current_setting('heha.proof_super_admin_id')::uuid,
  'former-owner@heha.example'
);
set local role authenticated;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
begin
  begin
    perform 1 from public.partner_publication_consent_events
    where partner_id = v_partner_id and owner_id = auth.uid();
    raise exception 'historical owner_id granted ledger access';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.get_my_partner_publication_status(v_partner_id);
    raise exception 'former owner read current status';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.withdraw_partner_publication_authorization(
      v_partner_id, array['heha_swipe']::text[],
      'Former Owner Proof', 'Former Owner', gen_random_uuid(),
      'wave1-profile-consent-2026-08-10'
    );
    raise exception 'former owner withdrew current authorization';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
insert into partner_publication_consent_results values (
  'former owner denial', true,
  'historical owner_id grants neither ledger, current status, nor withdrawal access'
);

select label, ok, detail
from partner_publication_consent_results
order by label;

rollback;
