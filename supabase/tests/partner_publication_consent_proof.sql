-- Wave 1 partner publication consent proof.
--
-- Run only after applying 20260810072829_wave1_partner_publication_consent.sql
-- to a disposable database, a confirmed Supabase development branch, or a
-- transactionally isolated live-schema clone. Never run this against Production.
--
-- Required psql variables:
--   wave1_partner_id    - an owned Catering or PrivateChef row safe to mutate
--   super_admin_user_id - an active HEHA super_admin user
--
-- Exact invocation:
--   psql -X -v ON_ERROR_STOP=1 -v wave1_partner_id=<uuid> -v super_admin_user_id=<uuid> -f supabase/tests/partner_publication_consent_proof.sql <connection-uri>

\set ON_ERROR_STOP on

begin;

create temporary table partner_publication_consent_proof_inputs (
  partner_id uuid primary key,
  super_admin_id uuid not null,
  owner_id uuid not null
) on commit drop;

-- psql substitutes variables here because this statement is not inside a
-- dollar-quoted PL/pgSQL body.
insert into partner_publication_consent_proof_inputs(partner_id, super_admin_id, owner_id)
select
  :'wave1_partner_id'::uuid,
  :'super_admin_user_id'::uuid,
  p.owner_id
from public.partners p
where p.id = :'wave1_partner_id'::uuid
  and p.owner_id is not null
  and app_private.is_wave1_food_partner(p);

do $$
begin
  if (select count(*) from pg_temp.partner_publication_consent_proof_inputs) <> 1 then
    raise exception 'proof partner must be an owned Catering or PrivateChef row';
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
  p_email text default null
)
returns void
language plpgsql
as $$
declare
  v_sub text := coalesce(p_sub::text, '00000000-0000-0000-0000-000000000000');
begin
  perform set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object(
      'sub', v_sub,
      'role', p_role,
      'email', coalesce(p_email, 'proof@heha.example')
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

do $$
declare
  v_forbidden text[] := array[
    'owner_id', 'contact', 'phone', 'location', 'complete_pct', 'contribution',
    'total_swipes', 'total_saves', 'total_profile_views', 'google_place_id',
    'product_price_policy', 'service_fee_type', 'service_fee_amount',
    'pricing_notes', 'routing_status', 'routing_notes', 'routing_updated_by',
    'routing_updated_at', 'is_test_record'
  ];
  v_view text;
  v_column text;
  v_options text[];
  v_view_owner oid;
  v_partner_owner oid;
begin
  if not (
    select c.relrowsecurity
    from pg_catalog.pg_class c
    where c.oid = 'public.partner_publication_consent_events'::regclass
  ) then
    raise exception 'partner_publication_consent_events must have RLS enabled';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.partner_publication_consent_events', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.partner_publication_consent_events', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_publication_consent_events', 'DELETE')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'INSERT')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'UPDATE')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_publication_consent_events', 'DELETE') then
    raise exception 'append-only consent evidence has broader direct privileges than intended';
  end if;
  if pg_catalog.has_sequence_privilege(
       'service_role',
       'public.partner_publication_consent_events_event_sequence_seq',
       'USAGE'
     )
     or pg_catalog.has_sequence_privilege(
       'authenticated',
       'public.partner_publication_consent_events_event_sequence_seq',
       'USAGE'
     ) then
    raise exception 'browser/service roles must not directly advance the consent event sequence';
  end if;
  if pg_catalog.has_table_privilege(
    'anon',
    'app_private.partner_publication_projection',
    'SELECT'
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.partner_publication_projection',
    'SELECT'
  ) then
    raise exception 'private consent projection must not be browser-readable';
  end if;

  if not pg_catalog.has_table_privilege(
    'authenticated',
    'public.partner_publication_consent_events',
    'SELECT'
  ) then
    raise exception 'authenticated owners/internal users need RLS-scoped ledger SELECT';
  end if;
  if pg_catalog.has_table_privilege('anon', 'public.partners', 'SELECT') then
    raise exception 'anon must not read raw partner rows';
  end if;

  select c.relowner into v_partner_owner
  from pg_catalog.pg_class c
  where c.oid = 'public.partners'::regclass;

  foreach v_view in array array[
    'public_partner_directory', 'public_swipe_partners', 'public_local_partners'
  ] loop
    select c.reloptions, c.relowner into v_options, v_view_owner
    from pg_catalog.pg_class c
    where c.oid = format('public.%I', v_view)::regclass;

    if not ('security_barrier=true' = any (coalesce(v_options, array[]::text[])))
       or 'security_invoker=true' = any (coalesce(v_options, array[]::text[]))
       or v_view_owner is distinct from v_partner_owner then
      raise exception '% must be a same-owner security-barrier definer projection', v_view;
    end if;
    if not pg_catalog.has_table_privilege('anon', format('public.%I', v_view), 'SELECT') then
      raise exception 'anon needs SELECT on safe public view %', v_view;
    end if;

    foreach v_column in array v_forbidden loop
      if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = v_view
          and column_name = v_column
      ) then
        raise exception '% exposes forbidden column %', v_view, v_column;
      end if;
    end loop;
  end loop;

  insert into pg_temp.partner_publication_consent_results(label, ok, detail)
  values (
    'private/public boundary',
    true,
    'RLS, append-only ACLs, raw-table denial, safe view ownership/mode/grants, and forbidden columns verified'
  );
end;
$$;

do $$
declare
  v_function regprocedure;
  v_config text[];
begin
  foreach v_function in array array[
    'public.submit_partner_registration_with_consent(uuid,text,text[],text,text,text,text,text[],text,text,text,text,text,text,text[],jsonb,text,text,text[],text,text,boolean,boolean,text)'::regprocedure,
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,uuid,text)'::regprocedure,
    'public.authorize_partner_profile_publication(uuid,text[],text,text,uuid,text,text)'::regprocedure,
    'public.get_my_partner_publication_status(uuid)'::regprocedure,
    'public.record_verified_partner_publication_consent(uuid,text,text,text,text,text,text,text,uuid,text,text,boolean,boolean,text[])'::regprocedure,
    'public.approve_partner(uuid)'::regprocedure
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
    'public.submit_partner_registration_with_consent(uuid,text,text[],text,text,text,text,text[],text,text,text,text,text,text,text[],jsonb,text,text,text[],text,text,boolean,boolean,text)'::regprocedure,
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,uuid,text)'::regprocedure,
    'public.authorize_partner_profile_publication(uuid,text[],text,text,uuid,text,text)'::regprocedure,
    'public.get_my_partner_publication_status(uuid)'::regprocedure
  ] loop
    if pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE') then
      raise exception 'owner-only RPC unexpectedly grants service_role execution: %', v_function;
    end if;
  end loop;

  if not pg_catalog.has_function_privilege(
    'authenticated',
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,uuid,text)',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'service_role',
    'public.authorize_existing_partner_profile_preparation(uuid,text[],text,text,boolean,boolean,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'existing-profile preparation RPC has the wrong role grants';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated',
    'public.record_verified_partner_publication_consent(uuid,text,text,text,text,text,text,text,uuid,text,text,boolean,boolean,text[])',
    'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'service_role',
    'public.record_verified_partner_publication_consent(uuid,text,text,text,text,text,text,text,uuid,text,text,boolean,boolean,text[])',
    'EXECUTE'
  ) then
    raise exception 'verified-consent RPC needs authenticated role-gated and service-role execution';
  end if;

  insert into pg_temp.partner_publication_consent_results(label, ok, detail)
  values (
    'rpc grants and search paths',
    true,
    'PUBLIC/anon revoked; owner/admin RPC role grants and empty search paths verified'
  );
end;
$$;

do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_other_partner_id uuid := gen_random_uuid();
  v_partner public.partners;
begin
  if public.suggest_partner_local_lane('PrivateChef', null, null, null, array[]::text[]) <> 'chef' then
    raise exception 'PrivateChef must route to the chef lane';
  end if;
  if public.suggest_partner_local_lane('Catering', null, null, null, array[]::text[]) <> 'group_orders' then
    raise exception 'Catering must route to the group_orders lane';
  end if;
  select p into v_partner from public.partners p where p.id = v_partner_id;
  v_partner.category := 'Restaurant';
  v_partner.categories := array['Restaurant', 'Catering', 'PrivateChef']::text[];
  if app_private.wave1_local_lane(v_partner) <> 'group_orders' then
    raise exception 'ordered multi-category routing must use the first applicable category';
  end if;
  v_partner.categories := array['Restaurant', 'PrivateChef', 'Catering']::text[];
  if app_private.wave1_local_lane(v_partner) <> 'chef' then
    raise exception 'ordered multi-category routing must remain deterministic';
  end if;
  if app_private.is_specific_local_partner_path('/chef') then
    raise exception 'generic /chef must not be treated as partner-specific';
  end if;
  if not app_private.is_specific_wave1_local_partner_path(
    '/chef/match?swipePartnerId=' || v_partner_id::text || '&service=private_chef',
    v_partner_id,
    'chef'
  ) then
    raise exception 'exact chef request route must match its Swipe partner';
  end if;
  if app_private.is_specific_wave1_local_partner_path(
    '/chef/' || v_other_partner_id::text,
    v_partner_id,
    'chef'
  ) then
    raise exception 'a chef route must not point at a different partner';
  end if;
  if app_private.is_specific_wave1_local_partner_path(
    '/group-orders/' || v_partner_id::text,
    v_partner_id,
    'chef'
  ) then
    raise exception 'a chef consent must not activate a catering route';
  end if;

  insert into pg_temp.partner_publication_consent_results(label, ok, detail)
  values (
    'wave1 routing',
    true,
    'PrivateChef -> chef, Catering -> group_orders, and generic/wrong-partner/wrong-lane Local routes fail closed'
  );
end;
$$;

-- Exercise actual anonymous privileges, not just JWT-shaped session settings.
set local role anon;
do $$
begin
  begin
    perform 1 from public.partners limit 1;
    raise exception 'anon unexpectedly read raw partners';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.partner_publication_consent_events limit 1;
    raise exception 'anon unexpectedly read private consent evidence';
  exception when insufficient_privilege then null;
  end;
  perform 1 from public.public_swipe_partners limit 1;
  perform 1 from public.public_local_partners limit 1;
  begin
    perform public.get_my_partner_publication_status(
      current_setting('heha.proof_partner_id')::uuid
    );
    raise exception 'anon unexpectedly executed owner status RPC';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

insert into partner_publication_consent_results(label, ok, detail)
values ('anon persona', true, 'anon can read only safe views; raw rows, ledger, and owner RPC are denied');

do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_super_admin uuid := current_setting('heha.proof_super_admin_id')::uuid;
  v_lane text;
  v_service text;
  v_specific_path text;
  v_prepare_swipe uuid := gen_random_uuid();
  v_prepare_local uuid := gen_random_uuid();
  v_publish_swipe uuid := gen_random_uuid();
  v_publish_local uuid := gen_random_uuid();
  v_publish_local_event uuid;
  v_retry_event uuid;
  v_profile_hash text;
  v_changed_profile_hash text;
  v_original_category text;
  v_original_categories text[];
  v_wrong_lane text;
  v_wrong_service text;
begin
  perform pg_temp.set_auth_context('authenticated', v_super_admin, 'proof@heha.example');

  select app_private.wave1_local_lane(p), p.category, p.categories
  into v_lane, v_original_category, v_original_categories
  from public.partners p where p.id = v_partner_id;
  v_service := case v_lane when 'chef' then 'private_chef' else 'catering' end;
  v_wrong_lane := case v_lane when 'chef' then 'group_orders' else 'chef' end;
  v_wrong_service := case v_wrong_lane when 'chef' then 'private_chef' else 'catering' end;
  v_specific_path := '/chef/match?swipePartnerId=' || v_partner_id::text || '&service=' || v_service;

  -- A Wave 1 category is consent-managed even before its first evidence event.
  -- This proof is transactionally isolated and rolls the temporary deletion back.
  delete from public.partner_publication_consent_events where partner_id = v_partner_id;
  update public.partners
  set status = 'live',
      website_eligible = true,
      swipe_eligible = true,
      local_eligible = true,
      local_lane = v_lane,
      primary_cta_destination = 'local',
      primary_cta_path = v_specific_path,
      is_test_record = false
  where id = v_partner_id;
  if exists (select 1 from public.public_partner_directory where id = v_partner_id)
     or exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'zero-history Wave 1 profile bypassed the consent gate';
  end if;
  begin
    perform public.approve_partner(v_partner_id);
    raise exception 'zero-history Wave 1 profile was approved without permission';
  exception when check_violation then null;
  end;

  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'heha_swipe', 'prepare_profile', 'granted',
      'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-prepare-without-media-rights',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, false, false, array['Tampa Bay']::text[]
    );
    raise exception 'prepare grant unexpectedly succeeded without current media permission';
  exception when check_violation then null;
  end;

  -- Latest revoke events establish a deterministic no-consent starting point.
  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_swipe', 'prepare_profile', 'revoked',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-start-revoke-prepare-swipe',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, false, array['Tampa Bay']::text[]
  );
  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_swipe', 'publish_profile', 'revoked',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-start-revoke-publish-swipe',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, false, array['Tampa Bay']::text[]
  );
  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'prepare_profile', 'revoked',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-start-revoke-prepare-local',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, true, array['Tampa Bay']::text[]
  );
  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'publish_profile', 'revoked',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-start-revoke-publish-local',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, true, array['Tampa Bay']::text[]
  );

  -- Even direct routing-field tampering cannot bypass the view-level gate.
  update public.partners
  set status = 'live',
      swipe_eligible = true,
      local_eligible = true,
      local_lane = v_lane,
      primary_cta_destination = 'local',
      primary_cta_path = v_specific_path,
      routing_status = 'approved',
      is_test_record = false
  where id = v_partner_id;
  select app_private.partner_public_profile_hash(p) into v_profile_hash
  from public.partners p where p.id = v_partner_id;
  if exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or exists (select 1 from public.public_local_partners where id = v_partner_id)
     or exists (select 1 from public.public_partner_directory where id = v_partner_id) then
    raise exception 'Wave 1 partner became public without current destination consent';
  end if;

  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'heha_local', 'publish_profile', 'granted',
      'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-publish-before-prepare',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', v_profile_hash, true, true, array['Tampa Bay']::text[]
    );
    raise exception 'publish grant unexpectedly succeeded without current prepare grant';
  exception when check_violation then null;
  end;

  -- Consent-managed profiles cannot escape into a legacy public surface by
  -- mutating from a Wave 1 food category to an unconsented category.
  update public.partners
  set category = 'Wellness',
      categories = array['Wellness']::text[],
      status = 'live',
      website_eligible = true,
      swipe_eligible = true,
      local_eligible = true
  where id = v_partner_id;
  if exists (select 1 from public.public_partner_directory where id = v_partner_id)
     or exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'category mutation escaped the consent-managed publication gate';
  end if;
  update public.partners
  set category = v_original_category,
      categories = v_original_categories
  where id = v_partner_id;

  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_swipe', 'prepare_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-prepare-swipe',
    v_prepare_swipe, 'wave1-profile-consent-2026-08-10', null, true, false, array['Tampa Bay']::text[]
  );
  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'prepare_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-prepare-local',
    v_prepare_local, 'wave1-profile-consent-2026-08-10', null, true, true, array['Tampa Bay']::text[]
  );

  update public.partners
  set category = case v_lane when 'chef' then 'Catering' else 'PrivateChef' end,
      categories = array[case v_lane when 'chef' then 'Catering' else 'PrivateChef' end]::text[]
  where id = v_partner_id;
  select app_private.partner_public_profile_hash(p) into v_changed_profile_hash
  from public.partners p where p.id = v_partner_id;
  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'heha_local', 'publish_profile', 'granted',
      'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-publish-after-lane-change',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', v_changed_profile_hash, true, true, array['Tampa Bay']::text[]
    );
    raise exception 'publication unexpectedly reused preparation permission from a different Local lane';
  exception when check_violation then null;
  end;
  update public.partners
  set category = v_original_category,
      categories = v_original_categories,
      local_lane = v_lane,
      primary_cta_path = v_specific_path
  where id = v_partner_id;

  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_swipe', 'publish_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-publish-swipe',
    v_publish_swipe, 'wave1-profile-consent-2026-08-10', v_profile_hash, true, false, array['Tampa Bay']::text[]
  );
  v_publish_local_event := public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'publish_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-publish-local',
    v_publish_local, 'wave1-profile-consent-2026-08-10', v_profile_hash, true, true, array['Tampa Bay']::text[]
  );

  -- Same key + same client payload remains idempotent.
  v_retry_event := public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'publish_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-publish-local',
    v_publish_local, 'wave1-profile-consent-2026-08-10', v_profile_hash, true, true, array['Tampa Bay']::text[]
  );
  if v_retry_event is distinct from v_publish_local_event then
    raise exception 'idempotent publish retry returned a different event';
  end if;

  update public.partners set primary_cta_path = v_specific_path where id = v_partner_id;
  perform public.approve_partner(v_partner_id);
  if not exists (
    select 1 from public.partners
    where id = v_partner_id
      and status = 'live'
      and swipe_eligible is true
      and local_eligible is true
      and website_eligible is false
      and primary_cta_path = v_specific_path
  ) then
    raise exception 'approval did not honor current consent and partner-specific Local route';
  end if;
  if not exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or not exists (select 1 from public.public_local_partners where id = v_partner_id)
     or exists (select 1 from public.public_partner_directory where id = v_partner_id) then
    raise exception 'destination-specific public projections do not match granted consent';
  end if;
  if exists (
    select 1 from public.public_swipe_partners
    where id = v_partner_id and (items <> '[]'::jsonb or price_range is not null)
  ) then
    raise exception 'Wave 1 public profile exposed deferred menu/per-portion pricing';
  end if;

  update public.partners
  set local_lane = v_wrong_lane,
      primary_cta_path = '/chef/match?swipePartnerId=' || v_partner_id::text || '&service=' || v_wrong_service
  where id = v_partner_id;
  if exists (select 1 from public.public_local_partners where id = v_partner_id)
     or not exists (select 1 from public.public_swipe_partners where id = v_partner_id) then
    raise exception 'wrong-lane route tampering did not fail closed only on HEHA Local';
  end if;
  if exists (
    select 1
    from public.public_swipe_partners
    where id = v_partner_id
      and (
        local_eligible is true
        or local_lane is not null
        or primary_cta_destination is distinct from 'swipe'
        or primary_cta_label is distinct from 'Discover Partner'
        or primary_cta_path is distinct from '/?partner=' || v_partner_id::text
      )
  ) then
    raise exception 'Swipe projection exposed a tampered or unconsented HEHA Local CTA';
  end if;
  update public.partners
  set local_lane = v_lane,
      primary_cta_path = v_specific_path
  where id = v_partner_id;
  if not exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'restoring the consent-derived lane and exact route did not restore HEHA Local';
  end if;

  -- Revoking preparation fails closed at Local even if routing flags remain true.
  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'prepare_profile', 'revoked',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-revoke-prepare-local',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, true, array['Tampa Bay']::text[]
  );
  if exists (select 1 from public.public_local_partners where id = v_partner_id)
     or not exists (select 1 from public.public_swipe_partners where id = v_partner_id) then
    raise exception 'prepare revocation did not remove only the affected destination';
  end if;

  -- A retry of the original publish request still returns its original event.
  v_retry_event := public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'publish_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-publish-local',
    v_publish_local, 'wave1-profile-consent-2026-08-10', v_profile_hash, true, true, array['Tampa Bay']::text[]
  );
  if v_retry_event is distinct from v_publish_local_event then
    raise exception 'idempotent retry became state-dependent after prepare revocation';
  end if;

  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'prepare_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-regrant-prepare-local',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, true, array['Tampa Bay']::text[]
  );
  if not exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'current prepare regrant did not restore still-current publication consent';
  end if;

  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'publish_profile', 'revoked',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-revoke-publish-local',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, true, array['Tampa Bay']::text[]
  );
  if exists (select 1 from public.public_local_partners where id = v_partner_id)
     or exists (select 1 from public.partners where id = v_partner_id and local_eligible) then
    raise exception 'publish revocation did not delist and disable Local';
  end if;

  perform public.record_verified_partner_publication_consent(
    v_partner_id, 'heha_local', 'publish_profile', 'granted',
    'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-regrant-publish-local',
    gen_random_uuid(), 'wave1-profile-consent-2026-08-10', v_profile_hash, true, true, array['Tampa Bay']::text[]
  );
  update public.partners set primary_cta_path = v_specific_path where id = v_partner_id;
  perform public.approve_partner(v_partner_id);

  -- Profile drift immediately removes both destinations, even after flag tampering.
  update public.partners
  set tagline = coalesce(tagline, '') || ' stale-proof',
      swipe_eligible = true,
      local_eligible = true
  where id = v_partner_id;
  if exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'stale exact-version consent remained public';
  end if;
  begin
    perform public.approve_partner(v_partner_id);
    raise exception 'stale profile approval unexpectedly succeeded';
  exception when check_violation then null;
  end;
  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'heha_local', 'publish_profile', 'granted',
      'Wave One Proof', 'Owner', 'proof@heha.example', 'proof-stale-profile-hash',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', v_profile_hash, true, true, array['Tampa Bay']::text[]
    );
    raise exception 'verified evidence authorized a profile version the representative did not review';
  exception when check_violation then null;
  end;

  insert into pg_temp.partner_publication_consent_results(label, ok, detail)
  values (
    'consent lifecycle',
    true,
    'zero-history/no-consent tamper, prepare-before-publish, media permission, lane-change rejection, exact reviewed hash, grants, exact route/lane, idempotency, revocations, regrants, category mutation, pricing suppression, and profile drift verified'
  );
end;
$$;

-- Exercise an unrelated authenticated user with actual Postgres role + RLS.
select pg_temp.set_auth_context('authenticated', gen_random_uuid(), 'unrelated@heha.example');
set local role authenticated;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
begin
  if exists (
    select 1 from public.partner_publication_consent_events
    where partner_id = v_partner_id
  ) then
    raise exception 'unrelated authenticated user read private consent evidence';
  end if;
  if exists (select 1 from public.partners where id = v_partner_id) then
    raise exception 'unrelated authenticated user read raw partner row';
  end if;
  begin
    perform public.approve_partner(v_partner_id);
    raise exception 'ordinary authenticated user unexpectedly approved partner';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.record_verified_partner_publication_consent(
      v_partner_id, 'heha_swipe', 'prepare_profile', 'granted',
      'Wrong User', 'Viewer', 'wrong@heha.example', 'unauthorized-proof',
      gen_random_uuid(), 'wave1-profile-consent-2026-08-10', null, true, false, array['Tampa Bay']::text[]
    );
    raise exception 'ordinary authenticated user unexpectedly recorded verified consent';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

insert into partner_publication_consent_results(label, ok, detail)
values ('unrelated authenticated persona', true, 'RLS hides owner data and role-gated admin RPCs deny ordinary users');

-- Exercise the actual owner role against raw-row and consent-ledger RLS.
select pg_temp.set_auth_context(
  'authenticated',
  current_setting('heha.proof_owner_id')::uuid,
  'owner@heha.example'
);
set local role authenticated;
do $$
declare
  v_partner_id uuid := current_setting('heha.proof_partner_id')::uuid;
  v_status jsonb;
begin
  if not exists (select 1 from public.partners where id = v_partner_id) then
    raise exception 'partner owner cannot read own raw profile';
  end if;
  if not exists (
    select 1 from public.partner_publication_consent_events
    where partner_id = v_partner_id
  ) then
    raise exception 'partner owner cannot read own consent evidence';
  end if;
  v_status := public.get_my_partner_publication_status(v_partner_id);
  if v_status ->> 'partner_id' is distinct from v_partner_id::text then
    raise exception 'owner status RPC returned the wrong partner';
  end if;

  perform public.authorize_existing_partner_profile_preparation(
    v_partner_id,
    array['heha_swipe', 'heha_local']::text[],
    'Wave One Owner',
    'Owner',
    true,
    true,
    gen_random_uuid(),
    'wave1-profile-consent-2026-08-10'
  );
  perform public.authorize_partner_profile_publication(
    v_partner_id,
    array['heha_swipe', 'heha_local']::text[],
    'Wave One Owner',
    'Owner',
    gen_random_uuid(),
    'wave1-profile-consent-2026-08-10',
    v_status ->> 'profile_snapshot_hash'
  );
  v_status := public.get_my_partner_publication_status(v_partner_id);
  if v_status -> 'publication_destinations' <> '["heha_swipe", "heha_local"]'::jsonb
     and v_status -> 'publication_destinations' <> '["heha_local", "heha_swipe"]'::jsonb then
    raise exception 'signed-in owner flow did not approve the exact current version for both destinations';
  end if;
  if not exists (select 1 from public.public_swipe_partners where id = v_partner_id)
     or not exists (select 1 from public.public_local_partners where id = v_partner_id) then
    raise exception 'owner exact-version reapproval did not restore current authorized projections';
  end if;
end;
$$;
reset role;

insert into partner_publication_consent_results(label, ok, detail)
values (
  'owner persona',
  true,
  'owner RLS plus existing-profile preparation, exact-version approval, status, and visibility restoration succeed'
);

select label, ok, detail
from partner_publication_consent_results
order by label;

rollback;
