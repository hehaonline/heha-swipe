-- Exact behavioral proof for the HEHA partner-onboarding V1 review packet.
--
-- Apply 000, 001, 002, and 003 first on a disposable PostgreSQL 15/17
-- database. Every lifecycle row below is synthetic and the transaction rolls
-- back. This file is not a hosted-Supabase or Production migration.

begin;

do $review_only_guard$
begin
  if coalesce(pg_catalog.current_setting('heha.review_only', true), '') <> 'on'
     or pg_catalog.current_database() <> 'partner_onboarding_review'
     or coalesce(pg_catalog.host(pg_catalog.inet_server_addr()), '') not in ('127.0.0.1', '::1') then
    raise exception 'HEHA_REVIEW_ONLY_GUARD'
      using errcode = '42501',
            hint = 'Requires loopback database partner_onboarding_review and externally supplied heha.review_only=on.';
  end if;
end;
$review_only_guard$;

create temporary table partner_onboarding_proof_state (
  key text primary key,
  value text not null
) on commit drop;

grant select, insert, update, delete on table pg_temp.partner_onboarding_proof_state
  to anon, authenticated, service_role;

create or replace function pg_temp.expect_partner_denied(
  p_label text,
  p_sql text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  execute p_sql;
  raise exception '%: expected HEHA_PARTNER_REQUEST_DENIED, but statement succeeded', p_label;
exception
  when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'HEHA_PARTNER_REQUEST_DENIED' then
      raise exception '%: expected generic P0001 denial, got %: %', p_label, sqlstate, sqlerrm;
    end if;
end;
$function$;

create or replace function pg_temp.expect_sqlstate(
  p_label text,
  p_expected_state text,
  p_sql text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  execute p_sql;
  raise exception '%: expected SQLSTATE %, but statement succeeded', p_label, p_expected_state;
exception
  when others then
    if sqlstate <> p_expected_state then
      raise exception '%: expected SQLSTATE %, got %: %', p_label, p_expected_state, sqlstate, sqlerrm;
    end if;
end;
$function$;

create or replace function pg_temp.expect_boolean(
  p_label text,
  p_expected boolean,
  p_sql text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_actual boolean;
begin
  execute p_sql into v_actual;
  if v_actual is distinct from p_expected then
    raise exception '%: expected %, got %', p_label, p_expected, v_actual;
  end if;
end;
$function$;

grant execute on function pg_temp.expect_partner_denied(text, text)
  to anon, authenticated, service_role;
grant execute on function pg_temp.expect_sqlstate(text, text, text)
  to anon, authenticated, service_role;
grant execute on function pg_temp.expect_boolean(text, boolean, text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Structure, exact ACLs, forced RLS, private isolation, and default-off gates.
-- ---------------------------------------------------------------------------

do $structure$
declare
  v_table text;
  v_signature text;
  v_config text[];
begin
  if not exists (
    select 1
    from partner_onboarding_private.runtime_config rc
    where rc.singleton
      and rc.environment = 'test'
      and rc.claim_enabled is false
      and rc.application_enabled is false
      and rc.acceptance_enabled is false
      and rc.release_enabled is false
      and rc.swipe_publication_enabled is false
      and rc.local_ordering_enabled is false
  ) then
    raise exception 'All six server switches must default off';
  end if;

  foreach v_table in array array[
    'runtime_config',
    'partner_business_registry',
    'partner_state',
    'partner_invites',
    'partner_invite_revocations',
    'partner_reclassification_resets',
    'partner_claims',
    'partner_claim_revocations',
    'partner_claim_profile_corrections',
    'partner_applications',
    'partner_application_requests',
    'partner_application_corrections',
    'partner_business_key_corrections',
    'partner_profile_correction_requests',
    'partner_actor_authority_grants',
    'partner_actor_authority_revocations',
    'staff_bootstrap_authorizations',
    'staff_authority_grants',
    'staff_authority_revocations',
    'partner_agreement_versions',
    'current_agreement_versions',
    'partner_agreement_acceptances',
    'partner_agreement_acceptance_revocations',
    'partner_evidence_receipts',
    'partner_evidence_revocations',
    'partner_release_receipts',
    'partner_release_revocations',
    'partner_surface_activation_receipts',
    'partner_surface_activation_revocations',
    'audit_events'
  ] loop
    if pg_catalog.to_regclass('partner_onboarding_private.' || v_table) is null then
      raise exception 'Missing private table %', v_table;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_class c
      where c.oid = pg_catalog.to_regclass('partner_onboarding_private.' || v_table)
        and c.relrowsecurity
        and c.relforcerowsecurity
    ) then
      raise exception 'Private table % must have ENABLE + FORCE RLS', v_table;
    end if;

    if pg_catalog.has_table_privilege('anon', 'partner_onboarding_private.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'partner_onboarding_private.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('service_role', 'partner_onboarding_private.' || v_table, 'SELECT')
       or pg_catalog.has_table_privilege('anon', 'partner_onboarding_private.' || v_table, 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', 'partner_onboarding_private.' || v_table, 'INSERT')
       or pg_catalog.has_table_privilege('service_role', 'partner_onboarding_private.' || v_table, 'INSERT')
       or pg_catalog.has_table_privilege('anon', 'partner_onboarding_private.' || v_table, 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', 'partner_onboarding_private.' || v_table, 'UPDATE')
       or pg_catalog.has_table_privilege('service_role', 'partner_onboarding_private.' || v_table, 'UPDATE')
       or pg_catalog.has_table_privilege('anon', 'partner_onboarding_private.' || v_table, 'DELETE')
       or pg_catalog.has_table_privilege('authenticated', 'partner_onboarding_private.' || v_table, 'DELETE')
       or pg_catalog.has_table_privilege('service_role', 'partner_onboarding_private.' || v_table, 'DELETE') then
      raise exception 'Private table % has a direct role grant', v_table;
    end if;
  end loop;

  if pg_catalog.has_schema_privilege('anon', 'partner_onboarding_private', 'USAGE')
     or not pg_catalog.has_schema_privilege('authenticated', 'partner_onboarding_private', 'USAGE')
     or not pg_catalog.has_schema_privilege('service_role', 'partner_onboarding_private', 'USAGE') then
    raise exception 'Private schema USAGE ACL mismatch';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class c
    where c.oid = 'public.partner_public_cards_v1'::pg_catalog.regclass
      and c.relrowsecurity
      and c.relforcerowsecurity
  ) then
    raise exception 'partner_public_cards_v1 must have ENABLE + FORCE RLS';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.partner_public_cards_v1', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_public_cards_v1', 'SELECT')
     or not pg_catalog.has_column_privilege('anon', 'public.partner_public_cards_v1', 'name', 'SELECT')
     or not pg_catalog.has_column_privilege('authenticated', 'public.partner_public_cards_v1', 'name', 'SELECT')
     or pg_catalog.has_column_privilege('anon', 'public.partner_public_cards_v1', 'release_receipt_id', 'SELECT')
     or pg_catalog.has_column_privilege('authenticated', 'public.partner_public_cards_v1', 'activation_receipt_id', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.partner_public_cards_v1', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partner_public_cards_v1', 'INSERT')
     or pg_catalog.has_table_privilege('service_role', 'public.partner_public_cards_v1', 'SELECT') then
    raise exception 'Public-card allowlisted column ACL mismatch';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.partners', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'DELETE') then
    raise exception 'Raw partners ACL is not owner-read-only';
  end if;

  foreach v_signature in array array[
    'public.claim_partner_invitation_v1(text,uuid)',
    'public.create_or_resume_partner_application_v1(uuid,jsonb)',
    'public.revise_partner_profile_v1(uuid,uuid,jsonb)',
    'public.get_partner_agreement_for_acceptance_v1(uuid)',
    'public.record_category_partner_agreement_acceptance_v1(uuid,uuid,text,uuid,jsonb)',
    'public.list_my_partner_onboarding_assignments_v1()',
    'public.get_partner_onboarding_capabilities_v1(uuid)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Client RPC ACL mismatch for %', v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'partner_onboarding_private.epoch_release_receipt_id_v1(uuid)',
    'partner_onboarding_private.current_release_receipt_id_v1(uuid)',
    'partner_onboarding_private.surface_activation_receipt_id_v1(uuid,text)',
    'partner_onboarding_private.invalidate_release_after_partner_change_v1()',
    'partner_onboarding_private.current_partner_business_key_v1(uuid)',
    'partner_onboarding_private.partner_business_identity_is_current_v1(uuid,text)',
    'partner_onboarding_private.guard_partner_business_key_correction_v1()',
    'partner_onboarding_private.guard_partner_business_identity_update_v1()',
    'partner_onboarding_private.claim_editable_profile_sha256_v1(uuid)',
    'partner_onboarding_private.revise_claimed_partner_profile_v1(uuid,uuid,jsonb)',
    'partner_onboarding_private.require_active_staff_authority_v1(uuid,text)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Private current-state helper ACL mismatch for %', v_signature;
    end if;
  end loop;

  if pg_catalog.has_function_privilege(
       'anon', 'public.get_partner_orderability_receipt_v1(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'public.get_partner_orderability_receipt_v1(uuid)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role', 'public.get_partner_orderability_receipt_v1(uuid)', 'EXECUTE'
     ) then
    raise exception 'Orderability receipt must be service-only';
  end if;

  foreach v_signature in array array[
    'partner_onboarding_private.bootstrap_staff_authority_v1(uuid,text)',
    'partner_onboarding_private.grant_staff_authority_v1(uuid,text,uuid)',
    'partner_onboarding_private.revoke_staff_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.reconcile_partner_business_registry_v1(uuid)',
    'partner_onboarding_private.set_runtime_config_v1(boolean,boolean,boolean,boolean,boolean,boolean,text,uuid)',
    'partner_onboarding_private.list_pending_partner_applications_v1(uuid,integer)',
    'partner_onboarding_private.issue_partner_invitation_v1(uuid,uuid,text,text,text,timestamptz,uuid)',
    'partner_onboarding_private.revoke_partner_invitation_v1(uuid,uuid,text)',
    'partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_claim_v1(uuid,uuid,text)',
    'partner_onboarding_private.grant_partner_signer_authority_v1(uuid,uuid,text,text,uuid)',
    'partner_onboarding_private.revoke_partner_signer_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.register_partner_agreement_version_v1(text,text,text,timestamptz,text,text,text,jsonb,text,uuid,timestamptz)',
    'partner_onboarding_private.select_partner_agreement_version_v1(uuid,uuid)',
    'partner_onboarding_private.revoke_partner_agreement_acceptance_v1(uuid,uuid,text)',
    'partner_onboarding_private.issue_partner_evidence_v1(uuid,text,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_evidence_v1(uuid,uuid,text)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Authenticated staff transition ACL mismatch for %', v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'partner_onboarding_private.finalize_partner_release_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_release_v1(uuid,uuid,text)',
    'partner_onboarding_private.record_partner_surface_activation_v1(uuid,uuid,text,uuid,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_surface_activation_v1(uuid,uuid,text)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Authenticated release/attestor transition ACL mismatch for %', v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'public.claim_partner_invitation_v1(text,uuid)',
    'public.create_or_resume_partner_application_v1(uuid,jsonb)',
    'public.revise_partner_application_v1(uuid,uuid,jsonb)',
    'public.revise_partner_profile_v1(uuid,uuid,jsonb)',
    'public.get_partner_agreement_for_acceptance_v1(uuid)',
    'public.record_category_partner_agreement_acceptance_v1(uuid,uuid,text,uuid,jsonb)',
    'public.list_my_partner_onboarding_assignments_v1()',
    'public.get_partner_onboarding_capabilities_v1(uuid)',
    'public.partner_has_current_release_v1(uuid,text)',
    'public.partner_card_is_current_v1(uuid,text,uuid,uuid)',
    'public.get_partner_orderability_receipt_v1(uuid)',
    'partner_onboarding_private.epoch_release_receipt_id_v1(uuid)',
    'partner_onboarding_private.current_release_receipt_id_v1(uuid)',
    'partner_onboarding_private.surface_activation_receipt_id_v1(uuid,text)',
    'partner_onboarding_private.invalidate_release_after_partner_change_v1()',
    'partner_onboarding_private.current_partner_business_key_v1(uuid)',
    'partner_onboarding_private.partner_business_identity_is_current_v1(uuid,text)',
    'partner_onboarding_private.guard_partner_business_identity_update_v1()',
    'partner_onboarding_private.bootstrap_staff_authority_v1(uuid,text)',
    'partner_onboarding_private.grant_staff_authority_v1(uuid,text,uuid)',
    'partner_onboarding_private.revoke_staff_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.reconcile_partner_business_registry_v1(uuid)',
    'partner_onboarding_private.set_runtime_config_v1(boolean,boolean,boolean,boolean,boolean,boolean,text,uuid)',
    'partner_onboarding_private.list_pending_partner_applications_v1(uuid,integer)',
    'partner_onboarding_private.issue_partner_invitation_v1(uuid,uuid,text,text,text,timestamptz,uuid)',
    'partner_onboarding_private.revoke_partner_invitation_v1(uuid,uuid,text)',
    'partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_claim_v1(uuid,uuid,text)',
    'partner_onboarding_private.grant_partner_signer_authority_v1(uuid,uuid,text,text,uuid)',
    'partner_onboarding_private.revoke_partner_signer_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.register_partner_agreement_version_v1(text,text,text,timestamptz,text,text,text,jsonb,text,uuid,timestamptz)',
    'partner_onboarding_private.select_partner_agreement_version_v1(uuid,uuid)',
    'partner_onboarding_private.revoke_partner_agreement_acceptance_v1(uuid,uuid,text)',
    'partner_onboarding_private.issue_partner_evidence_v1(uuid,text,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_evidence_v1(uuid,uuid,text)',
    'partner_onboarding_private.finalize_partner_release_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_release_v1(uuid,uuid,text)',
    'partner_onboarding_private.record_partner_surface_activation_v1(uuid,uuid,text,uuid,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_surface_activation_v1(uuid,uuid,text)',
    'partner_onboarding_private.require_active_staff_authority_v1(uuid,text)'
  ] loop
    select p.proconfig into v_config
    from pg_catalog.pg_proc p
    where p.oid = v_signature::pg_catalog.regprocedure;

    if not exists (
      select 1
      from pg_catalog.pg_proc p
      where p.oid = v_signature::pg_catalog.regprocedure
        and p.prosecdef
    ) or not (
      'search_path=' = any(coalesce(v_config, array[]::text[]))
      or 'search_path=""' = any(coalesce(v_config, array[]::text[]))
    ) then
      raise exception 'Security-definer/search_path mismatch for %', v_signature;
    end if;
  end loop;

  if exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'partners'
      and p.policyname = 'Synthetic legacy public status visibility'
  ) then
    raise exception 'Legacy status-only public partners policy survived 003';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'partners'
      and p.policyname in (
        'Legacy partner owner inserts pending profile',
        'Legacy partner owner updates pending profile'
      )
  ) then
    raise exception 'Legacy direct pending-profile write policy survived 001';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger
    join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'partners'
      and trigger.tgname = 'invalidate_partner_release_after_reviewed_change'
      and not trigger.tgisinternal
      and trigger.tgenabled <> 'D'
  ) then
    raise exception 'Reviewed-profile release invalidation trigger is missing or disabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger
    join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'partners'
      and trigger.tgname = 'guard_partner_business_identity_update_v1'
      and not trigger.tgisinternal
      and trigger.tgenabled <> 'D'
  ) then
    raise exception 'Raw partner business-identity drift guard is missing or disabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger
    join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'partner_onboarding_private'
      and relation.relname = 'partner_business_key_corrections'
      and trigger.tgname = 'guard_partner_business_key_correction_v1'
      and not trigger.tgisinternal
      and trigger.tgenabled <> 'D'
  ) then
    raise exception 'Historical business-key correction guard is missing or disabled';
  end if;
end;
$structure$;

-- PUBLIC_FUNCTION_CATALOG_EXACT: every public RPC/helper introduced by the
-- review package has one reviewed signature, an empty search_path, and only
-- its deliberately assigned browser/service roles.
do $public_function_catalog_exact$
declare
  v_expected_input constant text[] := array[
    'public.claim_partner_invitation_v1(text,uuid)',
    'public.create_or_resume_partner_application_v1(uuid,jsonb)',
    'public.get_partner_agreement_for_acceptance_v1(uuid)',
    'public.get_partner_onboarding_capabilities_v1(uuid)',
    'public.get_partner_orderability_receipt_v1(uuid)',
    'public.list_my_partner_onboarding_assignments_v1()',
    'public.partner_card_is_current_v1(uuid,text,uuid,uuid)',
    'public.partner_has_current_release_v1(uuid,text)',
    'public.record_category_partner_agreement_acceptance_v1(uuid,uuid,text,uuid,jsonb)',
    'public.revise_partner_application_v1(uuid,uuid,jsonb)',
    'public.revise_partner_profile_v1(uuid,uuid,jsonb)'
  ];
  v_client_input constant text[] := array[
    'public.claim_partner_invitation_v1(text,uuid)',
    'public.create_or_resume_partner_application_v1(uuid,jsonb)',
    'public.get_partner_agreement_for_acceptance_v1(uuid)',
    'public.get_partner_onboarding_capabilities_v1(uuid)',
    'public.list_my_partner_onboarding_assignments_v1()',
    'public.record_category_partner_agreement_acceptance_v1(uuid,uuid,text,uuid,jsonb)',
    'public.revise_partner_profile_v1(uuid,uuid,jsonb)'
  ];
  v_public_read_input constant text[] := array[
    'public.partner_card_is_current_v1(uuid,text,uuid,uuid)',
    'public.partner_has_current_release_v1(uuid,text)'
  ];
  v_expected text[];
  v_actual text[];
  v_client_oids oid[];
  v_public_read_oids oid[];
  v_stable_oids oid[];
  v_signature text;
  v_oid oid;
  v_config text[];
  v_allow_anon boolean;
  v_allow_authenticated boolean;
  v_allow_service boolean;
begin
  select pg_catalog.array_agg(
           pg_catalog.to_regprocedure(signature)::text
           order by pg_catalog.to_regprocedure(signature)::text
         )
  into v_expected
  from pg_catalog.unnest(v_expected_input) signature;

  select pg_catalog.array_agg(
           pg_catalog.to_regprocedure(signature)::oid
           order by pg_catalog.to_regprocedure(signature)::oid
         )
  into v_client_oids
  from pg_catalog.unnest(v_client_input) signature;

  select pg_catalog.array_agg(
           pg_catalog.to_regprocedure(signature)::oid
           order by pg_catalog.to_regprocedure(signature)::oid
         )
  into v_public_read_oids
  from pg_catalog.unnest(v_public_read_input) signature;

  select pg_catalog.array_agg(
           pg_catalog.to_regprocedure(signature)::oid
           order by pg_catalog.to_regprocedure(signature)::oid
         )
  into v_stable_oids
  from pg_catalog.unnest(array[
    'public.get_partner_agreement_for_acceptance_v1(uuid)',
    'public.get_partner_onboarding_capabilities_v1(uuid)',
    'public.get_partner_orderability_receipt_v1(uuid)',
    'public.list_my_partner_onboarding_assignments_v1()',
    'public.partner_card_is_current_v1(uuid,text,uuid,uuid)',
    'public.partner_has_current_release_v1(uuid,text)'
  ]::text[]) signature;

  select pg_catalog.array_agg(
           p.oid::pg_catalog.regprocedure::text
           order by p.oid::pg_catalog.regprocedure::text
         )
  into v_actual
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = any(array[
      'claim_partner_invitation_v1',
      'create_or_resume_partner_application_v1',
      'get_partner_agreement_for_acceptance_v1',
      'get_partner_onboarding_capabilities_v1',
      'get_partner_orderability_receipt_v1',
      'list_my_partner_onboarding_assignments_v1',
      'partner_card_is_current_v1',
      'partner_has_current_release_v1',
      'record_category_partner_agreement_acceptance_v1',
      'revise_partner_application_v1',
      'revise_partner_profile_v1'
    ]::name[]);

  if v_actual is distinct from v_expected then
    raise exception 'Public review-function inventory mismatch: expected %, got %',
      v_expected, v_actual;
  end if;

  foreach v_signature in array v_expected loop
    v_oid := (v_signature::pg_catalog.regprocedure)::oid;
    select p.proconfig into v_config
    from pg_catalog.pg_proc p
    where p.oid = v_oid
      and p.prokind = 'f'
      and p.prosecdef
      and pg_catalog.pg_get_function_identity_arguments(p.oid) is not null;

    if not found
       or pg_catalog.array_length(v_config, 1) is distinct from 1
       or v_config[1] <> all(array['search_path=', 'search_path=""']::text[]) then
      raise exception 'Public function kind/definer/search_path mismatch for %',
        v_signature;
    end if;

    v_allow_anon := v_oid = any(v_public_read_oids);
    v_allow_authenticated :=
      v_oid = any(v_client_oids) or v_allow_anon;
    v_allow_service :=
      v_oid = pg_catalog.to_regprocedure(
        'public.get_partner_orderability_receipt_v1(uuid)'
      )::oid;

    if not exists (
      select 1
      from pg_catalog.pg_proc procedure
      join pg_catalog.pg_language language
        on language.oid = procedure.prolang
      where procedure.oid = v_oid
        and procedure.prokind = 'f'
        and pg_catalog.pg_get_userbyid(procedure.proowner) = current_user
        and pg_catalog.pg_get_function_result(procedure.oid) = case
          when v_allow_anon then 'boolean'
          else 'jsonb'
        end
        and language.lanname = case
          when v_allow_anon then 'sql'
          else 'plpgsql'
        end
        and procedure.prosecdef
        and procedure.proleakproof is false
        and procedure.proisstrict is false
        and procedure.provolatile = case
          when v_oid = any(v_stable_oids) then 's'::"char"
          else 'v'::"char"
        end
        and procedure.proparallel = 'u'
        and procedure.proretset is false
        and procedure.procost = 100
        and procedure.prorows = 0
        and procedure.prosupport = 0
    ) then
      raise exception 'Public function execution metadata mismatch for %',
        v_signature;
    end if;

    if pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
         is distinct from v_allow_anon
       or pg_catalog.has_function_privilege(
            'authenticated', v_signature, 'EXECUTE'
          ) is distinct from v_allow_authenticated
       or pg_catalog.has_function_privilege('service_role', v_signature, 'EXECUTE')
          is distinct from v_allow_service
       or pg_catalog.has_function_privilege(
            'supabase_auth_admin', v_signature, 'EXECUTE'
          ) then
      raise exception 'Public function role ACL mismatch for %', v_signature;
    end if;

    if exists (
      select 1
      from pg_catalog.pg_proc p,
           lateral pg_catalog.aclexplode(
             coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
           ) acl
      where p.oid = v_oid
        and acl.privilege_type = 'EXECUTE'
        and acl.grantee = 0
    ) then
      raise exception 'PUBLIC retains EXECUTE on %', v_signature;
    end if;

    if exists (
      select 1
      from pg_catalog.pg_proc p,
           lateral pg_catalog.aclexplode(
             coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
           ) acl
      where p.oid = v_oid
        and acl.privilege_type = 'EXECUTE'
        and (
          acl.grantor <> p.proowner
          or not (
            acl.grantee = p.proowner
            or (
              v_allow_anon
              and acl.grantee = (
                select role.oid from pg_catalog.pg_roles role
                where role.rolname = 'anon'
              )
            )
            or (
              v_allow_authenticated
              and acl.grantee = (
                select role.oid from pg_catalog.pg_roles role
                where role.rolname = 'authenticated'
              )
            )
            or (
              v_allow_service
              and acl.grantee = (
                select role.oid from pg_catalog.pg_roles role
                where role.rolname = 'service_role'
              )
            )
          )
          or acl.is_grantable
        )
    ) then
      raise exception 'Unexpected EXECUTE grantee, grantor, or grant option for %',
        v_signature;
    end if;
  end loop;
end;
$public_function_catalog_exact$;

-- CATALOG_WIDE_PRIVATE_TABLE_INVENTORY: fail if a migration adds an
-- unreviewed private table or leaves any raw DML path to a platform role.
do $catalog_wide_private_table_inventory$
declare
  v_expected constant text[] := array[
    'audit_events', 'current_agreement_versions',
    'partner_actor_authority_grants', 'partner_actor_authority_revocations',
    'partner_agreement_acceptance_revocations', 'partner_agreement_acceptances',
    'partner_agreement_versions', 'partner_application_corrections',
    'partner_application_requests', 'partner_applications',
    'partner_business_key_corrections', 'partner_business_registry',
    'partner_claim_profile_corrections', 'partner_claim_revocations',
    'partner_claims',
    'partner_evidence_receipts', 'partner_evidence_revocations',
    'partner_invite_revocations', 'partner_invites',
    'partner_profile_correction_requests',
    'partner_reclassification_resets',
    'partner_release_receipts', 'partner_release_revocations',
    'partner_state', 'partner_surface_activation_receipts',
    'partner_surface_activation_revocations', 'runtime_config',
    'staff_authority_grants', 'staff_authority_revocations',
    'staff_bootstrap_authorizations'
  ];
  v_actual text[];
  v_table text;
begin
  select pg_catalog.array_agg(c.relname order by c.relname)
  into v_actual
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'partner_onboarding_private'
    and c.relkind in ('r', 'p');

  if v_actual is distinct from v_expected then
    raise exception 'Private table inventory mismatch: expected %, got %',
      v_expected, v_actual;
  end if;

  foreach v_table in array v_actual loop
    if pg_catalog.has_table_privilege(
         'supabase_auth_admin', 'partner_onboarding_private.' || v_table,
         'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
       ) then
      raise exception 'supabase_auth_admin has raw private-table access to %', v_table;
    end if;
  end loop;
end;
$catalog_wide_private_table_inventory$;

-- CATALOG_WIDE_PRIVATE_FUNCTION_INVENTORY: exact signatures and ACLs prevent
-- an unreviewed overload from becoming a hidden cross-tenant transition path.
do $catalog_wide_private_function_inventory$
declare
  v_expected_input constant text[] := array[
    'partner_onboarding_private.bootstrap_staff_authority_v1(uuid,text)',
    'partner_onboarding_private.canonical_json(jsonb)',
    'partner_onboarding_private.current_acceptance_receipt_id_v1(uuid)',
    'partner_onboarding_private.current_claim_receipt_id_v1(uuid)',
    'partner_onboarding_private.current_evidence_receipt_id_v1(uuid,text)',
    'partner_onboarding_private.claim_editable_profile_sha256_v1(uuid)',
    'partner_onboarding_private.current_partner_business_key_v1(uuid)',
    'partner_onboarding_private.current_release_receipt_id_v1(uuid)',
    'partner_onboarding_private.epoch_release_receipt_id_v1(uuid)',
    'partner_onboarding_private.finalize_partner_release_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.grant_partner_signer_authority_v1(uuid,uuid,text,text,uuid)',
    'partner_onboarding_private.grant_staff_authority_v1(uuid,text,uuid)',
    'partner_onboarding_private.guard_partner_business_key_correction_v1()',
    'partner_onboarding_private.guard_partner_business_identity_update_v1()',
    'partner_onboarding_private.has_active_staff_authority_v1(uuid,text)',
    'partner_onboarding_private.invalidate_release_after_partner_change_v1()',
    'partner_onboarding_private.issue_partner_evidence_v1(uuid,text,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.issue_partner_invitation_v1(uuid,uuid,text,text,text,timestamptz,uuid)',
    'partner_onboarding_private.jsonb_text_array_v1(jsonb)',
    'partner_onboarding_private.list_pending_partner_applications_v1(uuid,integer)',
    'partner_onboarding_private.normalized_business_key(text,text)',
    'partner_onboarding_private.normalized_person_text_v1(text)',
    'partner_onboarding_private.partner_business_identity_is_current_v1(uuid,text)',
    'partner_onboarding_private.partner_media_sha256(uuid)',
    'partner_onboarding_private.partner_preview_sha256(uuid)',
    'partner_onboarding_private.partner_profile_sha256(uuid)',
    'partner_onboarding_private.raise_partner_request_denied_v1()',
    'partner_onboarding_private.reconcile_partner_business_registry_v1(uuid)',
    'partner_onboarding_private.record_partner_surface_activation_v1(uuid,uuid,text,uuid,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.register_partner_agreement_version_v1(text,text,text,timestamptz,text,text,text,jsonb,text,uuid,timestamptz)',
    'partner_onboarding_private.reject_append_only_mutation()',
    'partner_onboarding_private.relationship_type_for_application_v1(jsonb)',
    'partner_onboarding_private.require_active_staff_authority_v1(uuid,text)',
    'partner_onboarding_private.revise_claimed_partner_profile_v1(uuid,uuid,jsonb)',
    'partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_agreement_acceptance_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_claim_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_evidence_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_invitation_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_release_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_signer_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_surface_activation_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_staff_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.select_partner_agreement_version_v1(uuid,uuid)',
    'partner_onboarding_private.set_runtime_config_v1(boolean,boolean,boolean,boolean,boolean,boolean,text,uuid)',
    'partner_onboarding_private.set_updated_at()',
    'partner_onboarding_private.sha256_text(text)',
    'partner_onboarding_private.surface_activation_receipt_id_v1(uuid,text)',
    'partner_onboarding_private.verified_auth_email_v1(uuid)'
  ];
  v_authenticated_input constant text[] := array[
    'partner_onboarding_private.bootstrap_staff_authority_v1(uuid,text)',
    'partner_onboarding_private.finalize_partner_release_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.grant_partner_signer_authority_v1(uuid,uuid,text,text,uuid)',
    'partner_onboarding_private.grant_staff_authority_v1(uuid,text,uuid)',
    'partner_onboarding_private.issue_partner_evidence_v1(uuid,text,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.issue_partner_invitation_v1(uuid,uuid,text,text,text,timestamptz,uuid)',
    'partner_onboarding_private.list_pending_partner_applications_v1(uuid,integer)',
    'partner_onboarding_private.reconcile_partner_business_registry_v1(uuid)',
    'partner_onboarding_private.record_partner_surface_activation_v1(uuid,uuid,text,uuid,text,jsonb,uuid,uuid)',
    'partner_onboarding_private.register_partner_agreement_version_v1(text,text,text,timestamptz,text,text,text,jsonb,text,uuid,timestamptz)',
    'partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(uuid,text,uuid,uuid)',
    'partner_onboarding_private.revoke_partner_agreement_acceptance_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_claim_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_evidence_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_invitation_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_release_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_signer_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_partner_surface_activation_v1(uuid,uuid,text)',
    'partner_onboarding_private.revoke_staff_authority_v1(uuid,uuid,text)',
    'partner_onboarding_private.select_partner_agreement_version_v1(uuid,uuid)',
    'partner_onboarding_private.set_runtime_config_v1(boolean,boolean,boolean,boolean,boolean,boolean,text,uuid)'
  ];
  v_expected text[];
  v_authenticated_oids oid[];
  v_actual text[];
  v_signature text;
  v_oid oid;
  v_config text[];
begin
  select pg_catalog.array_agg(
           pg_catalog.to_regprocedure(signature)::text
           order by pg_catalog.to_regprocedure(signature)::text
         )
  into v_expected
  from pg_catalog.unnest(v_expected_input) signature;
  select pg_catalog.array_agg(
           pg_catalog.to_regprocedure(signature)::oid
           order by pg_catalog.to_regprocedure(signature)::oid
         )
  into v_authenticated_oids
  from pg_catalog.unnest(v_authenticated_input) signature;
  select pg_catalog.array_agg(p.oid::pg_catalog.regprocedure::text order by p.oid::pg_catalog.regprocedure::text)
  into v_actual
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'partner_onboarding_private';

  if pg_catalog.array_position(v_expected, null) is not null
     or v_actual is distinct from v_expected then
    raise exception 'Private function inventory mismatch: expected %, got %',
      v_expected, v_actual;
  end if;

  foreach v_signature in array v_actual loop
    v_oid := v_signature::pg_catalog.regprocedure::oid;
    if pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', v_oid, 'EXECUTE')
       or pg_catalog.has_function_privilege('supabase_auth_admin', v_oid, 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE')
          is distinct from (v_oid = any(v_authenticated_oids)) then
      raise exception 'Private function role ACL mismatch for %', v_signature;
    end if;

    select p.proconfig into v_config from pg_catalog.pg_proc p where p.oid = v_oid;
    if not (
      'search_path=' = any(coalesce(v_config, array[]::text[]))
      or 'search_path=""' = any(coalesce(v_config, array[]::text[]))
    ) then
      raise exception 'Private function lacks empty search_path: %', v_signature;
    end if;
  end loop;
end;
$catalog_wide_private_function_inventory$;

-- PostgreSQL and a JavaScript JSON.stringify implementation must hash this
-- assertion vector identically. The digest was independently calculated over
-- the UTF-8 canonical string printed below.
do $canonical_golden_vector$
declare
  v_assertions constant jsonb := pg_catalog.jsonb_build_object(
    'typed_signature', 'Signer B',
    'signer_title', 'Authorized Representative',
    'assent_text', 'I agree to the synthetic terms.',
    'signer_legal_name', 'Signer B',
    'assertions_version', 'heha-partner-acceptance-v1',
    'electronic_records_consent', true,
    'signer_authority_confirmed', true,
    'reviewed_complete_agreement', true
  );
  v_expected constant text := '{"assent_text":"I agree to the synthetic terms.","assertions_version":"heha-partner-acceptance-v1","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}';
  v_expected_sha constant text := '5327bdf5a2d33cdc26368ead401444941f8ef5cdb88f0d4ef0d4b8def19947f6';
begin
  if partner_onboarding_private.canonical_json(v_assertions) <> v_expected
     or partner_onboarding_private.sha256_text(v_expected) <> v_expected_sha
     or partner_onboarding_private.sha256_text(
       partner_onboarding_private.canonical_json(v_assertions)
     ) <> v_expected_sha then
    raise exception 'Canonical assertions golden vector mismatch';
  end if;
end;
$canonical_golden_vector$;

do $application_relationship_resolver_parity$
begin
  if partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Restaurant"}'::jsonb
     ) is distinct from 'restaurant'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Vendor","business_type":"Product maker"}'::jsonb
     ) is distinct from 'vendor'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Vendor","business_type":"Farmers market"}'::jsonb
     ) is distinct from 'market'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Grocery"}'::jsonb
     ) is distinct from 'market'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"FarmersMarket"}'::jsonb
     ) is distinct from 'market'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Market"}'::jsonb
     ) is distinct from 'market'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Markets"}'::jsonb
     ) is distinct from 'market'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Private Chef"}'::jsonb
     ) is distinct from 'solo_chef'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"PrivateChef"}'::jsonb
     ) is distinct from 'solo_chef'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"SoloChef"}'::jsonb
     ) is distinct from 'solo_chef'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Solo Chef"}'::jsonb
     ) is distinct from 'solo_chef'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"MealPrep"}'::jsonb
     ) is distinct from 'solo_chef'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Meal Prep"}'::jsonb
     ) is distinct from 'solo_chef'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"Driver"}'::jsonb
     ) is distinct from 'driver'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"category":"SOM"}'::jsonb
     ) is distinct from 'som'
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"categories":["Restaurant","Vendor"]}'::jsonb
     ) is not null
     or partner_onboarding_private.relationship_type_for_application_v1(
       '{"categories":["Restaurant","Catering"]}'::jsonb
     ) is not null then
    raise exception 'Application relationship resolver parity vector mismatch';
  end if;
end;
$application_relationship_resolver_parity$;

-- ---------------------------------------------------------------------------
-- Synthetic partners and service authorities.
-- ---------------------------------------------------------------------------

insert into public.partners (
  id, name, legal_name, postal_code, category, categories, location, bio,
  hours, image_url, gallery_urls, status, complete_pct, heha_partner,
  website_eligible, swipe_eligible, local_eligible, local_lane,
  primary_cta_destination, primary_cta_label, primary_cta_path, is_test_record
) values
  (
    '10000000-0000-4000-8000-0000000000a1',
    'Synthetic Main Kitchen', 'Synthetic Main Kitchen LLC', '33602',
    null, array['Restaurant'], 'Tampa, FL', 'Synthetic proof profile',
    '{"monday":{"open":"09:00","close":"17:00"}}'::jsonb,
    'https://example.invalid/main.jpg', '["https://example.invalid/gallery.jpg"]'::jsonb,
    'pending', 100, false, false, false, false, 'meals',
    'local', 'Order locally',
    '/restaurants/20000000-0000-4000-8000-0000000000a2', false
  ),
  (
    '10000000-0000-4000-8000-0000000000b2',
    'Synthetic Revoked Invite', 'Synthetic Revoked Invite LLC', '33603',
    'Vendor', array['Vendor'], 'Tampa, FL', 'Synthetic revoked invite',
    '{}'::jsonb, null, '[]'::jsonb, 'pending', 20, false, false, false, false, null,
    null, null, null, false
  ),
  (
    '10000000-0000-4000-8000-0000000000c3',
    'Synthetic Expired Invite', 'Synthetic Expired Invite LLC', '33604',
    'Catering', array['Catering'], 'Tampa, FL', 'Synthetic expired invite',
    '{}'::jsonb, null, '[]'::jsonb, 'pending', 20, false, false, false, false, null,
    null, null, null, false
  ),
  (
    '10000000-0000-4000-8000-0000000000d4',
    'Synthetic Legacy Live', 'Synthetic Legacy Live LLC', '33605',
    'Restaurant', array['Restaurant'], 'Tampa, FL', 'Legacy flags are not evidence',
    '{}'::jsonb, null, '[]'::jsonb, 'live', 100, true, true, true, true, 'meals',
    'local', 'Order',
    '/restaurants/10000000-0000-4000-8000-0000000000d4', false
  );

insert into auth.users (id, email, email_confirmed_at)
values (
  '00000000-0000-4000-8000-0000000000f6',
  'unconfirmed-reviewer@example.invalid',
  null
);

insert into partner_onboarding_private.staff_bootstrap_authorizations (
  id, user_id, authority_type, authorization_reference,
  authorized_by_database_role, authorized_at
) values (
  '40000000-0000-4000-8000-0000000000e5',
  '00000000-0000-4000-8000-0000000000e5',
  'security_admin',
  'SYNTHETIC-DB-OWNER-BOOTSTRAP-AUTHORIZATION',
  current_user,
  '2026-08-31 12:00:00+00'::timestamptz
);

set local role service_role;
select pg_temp.expect_sqlstate(
  'service role cannot bootstrap a human security admin', '42501',
  $sql$select partner_onboarding_private.bootstrap_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000e5', 'security_admin'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_sqlstate(
  'authenticated cannot read bootstrap authorization ledger', '42501',
  $sql$select count(*)
       from partner_onboarding_private.staff_bootstrap_authorizations$sql$
);
select pg_temp.expect_sqlstate(
  'authenticated cannot insert bootstrap authorization ledger', '42501',
  $sql$insert into partner_onboarding_private.staff_bootstrap_authorizations (
         user_id, authority_type, authorization_reference,
         authorized_by_database_role, authorized_at
       ) values (
         '00000000-0000-4000-8000-0000000000d4', 'security_admin',
         'UNAUTHORIZED-FIRST-CALLER', 'authenticated',
         pg_catalog.clock_timestamp()
       )$sql$
);
select pg_temp.expect_partner_denied(
  'arbitrary verified first caller lacks bootstrap authorization',
  $sql$select partner_onboarding_private.bootstrap_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000d4', 'security_admin'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'security_admin_grant', partner_onboarding_private.bootstrap_staff_authority_v1(
  '00000000-0000-4000-8000-0000000000e5', 'security_admin'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'security_admin_bootstrap_replay',
       partner_onboarding_private.bootstrap_staff_authority_v1(
  '00000000-0000-4000-8000-0000000000e5', 'security_admin'
)::text;
select pg_temp.expect_partner_denied(
  'bootstrap cannot mint a non-security authority',
  $sql$select partner_onboarding_private.bootstrap_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000e5', 'legal_admin'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'bootstrap cannot create a second founding security admin',
  $sql$select partner_onboarding_private.bootstrap_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000d4', 'security_admin'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'legal_admin_grant', partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000104', 'legal_admin',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'evidence_reviewer_grant', partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000105', 'evidence_reviewer',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_reviewer_grant', partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000106', 'release_reviewer',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_attestor_grant', partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000101', 'swipe_attestor',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'website_attestor_grant', partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000102', 'website_attestor',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_attestor_grant', partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-000000000103', 'local_attestor',
  '00000000-0000-4000-8000-0000000000e5'
)::text;

select pg_temp.expect_partner_denied(
  'security admin operational self-grant denied generically',
  $sql$select partner_onboarding_private.grant_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000e5', 'legal_admin',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);

select pg_temp.expect_partner_denied(
  'authenticated staff actor UUID impersonation denied',
  $sql$select partner_onboarding_private.grant_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000d4', 'evidence_reviewer',
    '00000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'non-admin cannot grant staff authority',
  $sql$select partner_onboarding_private.grant_staff_authority_v1(
    '00000000-0000-4000-8000-0000000000d4', 'evidence_reviewer',
    '00000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'non-admin cannot revoke staff authority',
  $sql$select partner_onboarding_private.revoke_staff_authority_v1(
    (select value::uuid from pg_temp.partner_onboarding_proof_state
     where key = 'legal_admin_grant'),
    '00000000-0000-4000-8000-0000000000d4',
    'synthetic_unauthorized_staff_revocation'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  'last active security admin cannot revoke self',
  $sql$select partner_onboarding_private.revoke_staff_authority_v1(
    (select value::uuid from pg_temp.partner_onboarding_proof_state
     where key = 'security_admin_grant'),
    '00000000-0000-4000-8000-0000000000e5',
    'synthetic_last_admin_revocation'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'second_security_admin_grant',
       partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-0000000000d4', 'security_admin',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'first_security_admin_revocation',
       partner_onboarding_private.revoke_staff_authority_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'security_admin_grant'),
  '00000000-0000-4000-8000-0000000000d4',
  'synthetic_security_admin_rotation'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'security_admin_regrant',
       partner_onboarding_private.grant_staff_authority_v1(
  '00000000-0000-4000-8000-0000000000e5', 'security_admin',
  '00000000-0000-4000-8000-0000000000d4'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'second_security_admin_revocation',
       partner_onboarding_private.revoke_staff_authority_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'second_security_admin_grant'),
  '00000000-0000-4000-8000-0000000000e5',
  'synthetic_security_admin_rotation_complete'
)::text;

reset role;

do $bootstrap_authorization_replay$
begin
  if (select value from pg_temp.partner_onboarding_proof_state
      where key = 'security_admin_grant') is distinct from
     (select value from pg_temp.partner_onboarding_proof_state
      where key = 'security_admin_bootstrap_replay')
     or (
       select count(*)
       from partner_onboarding_private.staff_bootstrap_authorizations
       where user_id = '00000000-0000-4000-8000-0000000000e5'
         and authority_type = 'security_admin'
     ) <> 1 then
    raise exception 'Bootstrap authorization/replay contract mismatch';
  end if;
end;
$bootstrap_authorization_replay$;

do $staff_authority_rotation$
declare
  v_first uuid := (
    select value::uuid from pg_temp.partner_onboarding_proof_state
    where key = 'security_admin_grant'
  );
  v_regrant uuid := (
    select value::uuid from pg_temp.partner_onboarding_proof_state
    where key = 'security_admin_regrant'
  );
begin
  if v_first = v_regrant
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-0000000000e5', 'security_admin'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-0000000000d4', 'security_admin'
     ) is not false then
    raise exception 'Staff authority rotation/regrant did not preserve one active admin';
  end if;
end;
$staff_authority_rotation$;

-- STAFF_SEPARATION_OF_DUTIES
do $staff_separation_of_duties$
declare
  v_active_count integer;
  v_multi_role_count integer;
begin
  select count(*) into v_active_count
  from partner_onboarding_private.staff_authority_grants grant_row
  where not exists (
    select 1
    from partner_onboarding_private.staff_authority_revocations revocation
    where revocation.authority_grant_id = grant_row.id
  );

  select count(*) into v_multi_role_count
  from (
    select grant_row.user_id
    from partner_onboarding_private.staff_authority_grants grant_row
    where not exists (
      select 1
      from partner_onboarding_private.staff_authority_revocations revocation
      where revocation.authority_grant_id = grant_row.id
    )
    group by grant_row.user_id
    having count(distinct grant_row.authority_type) <> 1
  ) collision;

  if v_active_count <> 7
     or v_multi_role_count <> 0
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-0000000000e5', 'security_admin'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-000000000104', 'legal_admin'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-000000000105', 'evidence_reviewer'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-000000000106', 'release_reviewer'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-000000000101', 'swipe_attestor'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-000000000102', 'website_attestor'
     ) is not true
     or partner_onboarding_private.has_active_staff_authority_v1(
       '00000000-0000-4000-8000-000000000103', 'local_attestor'
     ) is not true then
    raise exception 'Staff separation-of-duties mapping is not exact';
  end if;
end;
$staff_separation_of_duties$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  'business-registry actor UUID impersonation denied',
  $sql$select partner_onboarding_private.reconcile_partner_business_registry_v1(
    '00000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'non-admin cannot reconcile the business registry',
  $sql$select partner_onboarding_private.reconcile_partner_business_registry_v1(
    '00000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'business_registry_reconciliation_first',
       partner_onboarding_private.reconcile_partner_business_registry_v1(
         '00000000-0000-4000-8000-0000000000e5'
       )::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'business_registry_reconciliation_replay',
       partner_onboarding_private.reconcile_partner_business_registry_v1(
         '00000000-0000-4000-8000-0000000000e5'
       )::text;

reset role;

do $business_registry_reconciliation$
declare
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'business_registry_reconciliation_first'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'business_registry_reconciliation_replay'
  );
begin
  if v_first ->> 'projection_version' <>
       'heha-partner-business-registry-reconciliation-v1'
     or (v_first ->> 'eligible_partner_count')::integer <> 4
     or (v_first ->> 'inserted_reservation_count')::integer <> 4
     or v_first ->> 'status' <> 'verified'
     or (v_replay ->> 'eligible_partner_count')::integer <> 4
     or (v_replay ->> 'inserted_reservation_count')::integer <> 0
     or (
       select count(*)
       from public.partners partner
       join partner_onboarding_private.partner_business_registry registry
         on registry.partner_id = partner.id
        and registry.business_key_sha256 =
          partner_onboarding_private.normalized_business_key(
            partner.name,
            coalesce(partner.location, partner.neighborhood, partner.postal_code)
          )
       where partner.id in (
         '10000000-0000-4000-8000-0000000000a1',
         '10000000-0000-4000-8000-0000000000b2',
         '10000000-0000-4000-8000-0000000000c3',
         '10000000-0000-4000-8000-0000000000d4'
       )
     ) <> 4 then
    raise exception 'Business registry reconciliation/replay contract mismatch';
  end if;
end;
$business_registry_reconciliation$;

insert into partner_onboarding_private.partner_state (
  partner_id, legal_relationship_type, business_key_sha256
) values (
  '10000000-0000-4000-8000-0000000000c3',
  'catering',
  partner_onboarding_private.normalized_business_key(
    'Synthetic Expired Invite', 'Tampa, FL'
  )
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  '31-byte invitation token denied',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '00000000-0000-4000-8000-0000000000a1',
    'restaurant', 'operator_only', pg_catalog.repeat('a', 31),
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
select pg_temp.expect_partner_denied(
  '513-byte invitation token denied',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '00000000-0000-4000-8000-0000000000a1',
    'restaurant', 'operator_only', pg_catalog.repeat('a', 513),
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'non-ASCII-allowlist invitation token denied',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '00000000-0000-4000-8000-0000000000a1',
    'restaurant', 'operator_only', pg_catalog.repeat('a', 31) || '!',
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'main_invite', partner_onboarding_private.issue_partner_invitation_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000a1',
  'restaurant', 'operator_only',
  'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
  pg_catalog.clock_timestamp() + interval '2 days',
  '00000000-0000-4000-8000-0000000000e5'
)::text;

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'revoked_invite', partner_onboarding_private.issue_partner_invitation_v1(
  '10000000-0000-4000-8000-0000000000b2',
  '00000000-0000-4000-8000-0000000000c3',
  'vendor', 'operator_only',
  'revoked_invite_token_abcdefghijklmnopqrstuvwxyz_002',
  pg_catalog.clock_timestamp() + interval '2 days',
  '00000000-0000-4000-8000-0000000000e5'
)::text;

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'revoked_invite_revocation', partner_onboarding_private.revoke_partner_invitation_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'revoked_invite'),
  '00000000-0000-4000-8000-0000000000e5',
  'synthetic_revocation'
)::text;
reset role;

do $invite_first_single_raw_profile$
begin
  if (
       select count(*)
       from public.partners partner
       where partner_onboarding_private.normalized_business_key(
         partner.name,
         coalesce(partner.location, partner.neighborhood, partner.postal_code)
       ) = partner_onboarding_private.normalized_business_key(
         'Synthetic Main Kitchen', 'Tampa, FL'
       )
     ) <> 1 then
    raise exception 'INVITE_FIRST_RAW_PROFILE_COUNT must remain exactly one';
  end if;
end;
$invite_first_single_raw_profile$;

-- An expired receipt is seeded directly because the service issue function
-- correctly refuses to create an already-expired invitation.
insert into partner_onboarding_private.partner_invites (
  id, partner_id, recipient_user_id, legal_relationship_type,
  relationship_epoch, claim_epoch, claim_role, token_sha256,
  expires_at, issued_by, issued_at
) values (
  '20000000-0000-4000-8000-0000000000c3',
  '10000000-0000-4000-8000-0000000000c3',
  '00000000-0000-4000-8000-0000000000c3',
  'catering', 1, 1, 'operator_only',
  partner_onboarding_private.sha256_text(
    'expired_invite_token_abcdefghijklmnopqrstuvwxyz_003'
  ),
  pg_catalog.clock_timestamp() - interval '1 day',
  '00000000-0000-4000-8000-000000000104',
  pg_catalog.clock_timestamp() - interval '2 days'
);

-- Legacy live/eligible flags cannot reach any released view, and anonymous
-- callers cannot query the mutable partners table directly.
set local role anon;
select pg_temp.expect_boolean(
  'legacy live row absent from Swipe', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_temp.expect_boolean(
  'legacy live row absent from website', false,
  $sql$select exists (
    select 1 from public.public_partner_directory
    where id = '10000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_temp.expect_boolean(
  'legacy live row absent from Local', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000d4'
  )$sql$
);
select pg_temp.expect_sqlstate(
  'anonymous raw partners read denied', '42501',
  $sql$select count(*) from public.partners$sql$
);
reset role;

-- ---------------------------------------------------------------------------
-- Uniform denials, recipient binding, expiry, revocation, and applications.
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
select pg_temp.expect_partner_denied(
  'claim switch defaults off',
  $sql$select public.claim_partner_invitation_v1(
    'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
    '30000000-0000-4000-8000-000000000001'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
select pg_temp.expect_partner_denied(
  'application switch defaults off',
  $sql$select public.create_or_resume_partner_application_v1(
    '30000000-0000-4000-8000-000000000002',
    '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Vendor","categories":["Vendor"]}'::jsonb
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, false, false, false, false, false,
  'proof-claim-enabled',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'wrong recipient BOLA denied generically',
  $sql$select public.claim_partner_invitation_v1(
    'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
    '30000000-0000-4000-8000-000000000003'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
select pg_temp.expect_partner_denied(
  'expired invitation denied generically',
  $sql$select public.claim_partner_invitation_v1(
    'expired_invite_token_abcdefghijklmnopqrstuvwxyz_003',
    '30000000-0000-4000-8000-000000000004'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'revoked invitation denied generically',
  $sql$select public.claim_partner_invitation_v1(
    'revoked_invite_token_abcdefghijklmnopqrstuvwxyz_002',
    '30000000-0000-4000-8000-000000000005'
  )$sql$
);
reset role;

-- RAW_PROFILE_RECLASSIFICATION_RESET: a legacy no-owner/no-application row
-- may contain a stale relationship classification. With only an expired
-- invitation and no claim/evidence/release artifacts, the legal reset repairs
-- the relationship directly from the canonical stored profile.
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'raw_profile_reset_before', pg_catalog.jsonb_build_object(
  'relationship_epoch', state.relationship_epoch,
  'claim_epoch', state.claim_epoch,
  'release_epoch', state.release_epoch
)::text
from partner_onboarding_private.partner_state state
where state.partner_id = '10000000-0000-4000-8000-0000000000c3';

update partner_onboarding_private.partner_state
set legal_relationship_type = 'vendor'
where partner_id = '10000000-0000-4000-8000-0000000000c3';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'raw_profile_reclassification_reset_first',
       partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  '10000000-0000-4000-8000-0000000000c3',
  'synthetic_legacy_profile_relationship_repair',
  '30000000-0000-4000-8000-00000000010c',
  '00000000-0000-4000-8000-000000000104'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'raw_profile_reclassification_reset_replay',
       partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  '10000000-0000-4000-8000-0000000000c3',
  'synthetic_legacy_profile_relationship_repair',
  '30000000-0000-4000-8000-00000000010c',
  '00000000-0000-4000-8000-000000000104'
)::text;
select pg_temp.expect_partner_denied(
  'raw profile reset conflicting replay denied generically',
  $sql$select partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
    '10000000-0000-4000-8000-0000000000c3',
    'synthetic_changed_profile_relationship_repair',
    '30000000-0000-4000-8000-00000000010c',
    '00000000-0000-4000-8000-000000000104'
  )$sql$
);
reset role;

do $raw_profile_reclassification_reset$
declare
  v_before jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'raw_profile_reset_before'
  );
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'raw_profile_reclassification_reset_first'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'raw_profile_reclassification_reset_replay'
  );
begin
  if v_first is distinct from v_replay
     or v_first ->> 'status' <> 'ready_for_invitation'
     or v_first ->> 'receipt_status' <> 'verified'
     or not exists (
       select 1
       from partner_onboarding_private.partner_reclassification_resets reset_receipt
       where reset_receipt.id = (v_first ->> 'reset_receipt_id')::uuid
         and reset_receipt.partner_id = '10000000-0000-4000-8000-0000000000c3'
         and reset_receipt.prior_legal_relationship_type = 'vendor'
         and reset_receipt.reset_mode = 'profile_relationship_repaired'
         and reset_receipt.replacement_legal_relationship_type = 'catering'
         and reset_receipt.prior_relationship_epoch =
           (v_before ->> 'relationship_epoch')::integer
         and reset_receipt.prior_claim_epoch =
           (v_before ->> 'claim_epoch')::integer
         and reset_receipt.prior_release_epoch =
           (v_before ->> 'release_epoch')::integer
     )
     or not exists (
       select 1
       from partner_onboarding_private.partner_state state
       where state.partner_id = '10000000-0000-4000-8000-0000000000c3'
         and state.legal_relationship_type = 'catering'
         and state.relationship_epoch =
           (v_before ->> 'relationship_epoch')::integer + 1
         and state.claim_epoch = (v_before ->> 'claim_epoch')::integer + 1
         and state.release_epoch = (v_before ->> 'release_epoch')::integer + 1
         and state.reclassification_pending is false
         and state.operator_user_id is null
     )
     or not exists (
       select 1
       from public.partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000c3'
         and partner.owner_id is null
         and partner.category = 'Catering'
         and partner.categories = array['Catering']::text[]
         and partner.status = 'pending'
         and partner.heha_partner is false
         and partner.website_eligible is false
         and partner.swipe_eligible is false
         and partner.local_eligible is false
     ) then
    raise exception 'Raw-profile relationship repair reset contract mismatch';
  end if;
end;
$raw_profile_reclassification_reset$;

insert into public.partners (
  id, owner_id, name, legal_name, postal_code, category, categories,
  location, status, is_test_record
) values (
  '10000000-0000-4000-8000-0000000000f8',
  '00000000-0000-4000-8000-0000000000d4',
  'Synthetic Raw Owned Legacy', 'Synthetic Raw Owned Legacy LLC', '33618',
  'Vendor', array['Vendor'], 'Tampa, FL', 'pending', false
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  'raw owner-nonnull profile invitation denied without side effects',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    '10000000-0000-4000-8000-0000000000f8',
    '00000000-0000-4000-8000-0000000000d4',
    'vendor', 'operator_only',
    'raw_owned_legacy_invite_token_abcdefghijklmnop_012',
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
reset role;

do $raw_owned_invitation_denial_side_effects$
begin
  if not exists (
       select 1 from public.partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000f8'
         and partner.owner_id = '00000000-0000-4000-8000-0000000000d4'
     )
     or exists (
       select 1 from partner_onboarding_private.partner_business_registry registry
       where registry.partner_id = '10000000-0000-4000-8000-0000000000f8'
     )
     or exists (
       select 1 from partner_onboarding_private.partner_state state
       where state.partner_id = '10000000-0000-4000-8000-0000000000f8'
     )
     or exists (
       select 1 from partner_onboarding_private.partner_invites invitation
       where invitation.partner_id = '10000000-0000-4000-8000-0000000000f8'
     ) then
    raise exception 'Raw owner-nonnull invitation denial left private side effects';
  end if;
end;
$raw_owned_invitation_denial_side_effects$;

delete from public.partners
where id = '10000000-0000-4000-8000-0000000000f8'
  and name = 'Synthetic Raw Owned Legacy';

-- LEGACY_LIVE_PROFILE_CLAIM_NORMALIZATION: old status/eligibility fields are
-- not a protected release. A reviewed invitation can claim that existing raw
-- profile, but the claim transaction first makes it fully private and records
-- the exact prior exposure before allowing a claimed-profile revision.
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'legacy_live_profile_before_claim', pg_catalog.jsonb_build_object(
  'owner_id', partner.owner_id,
  'status', partner.status,
  'heha_partner', partner.heha_partner,
  'website_eligible', partner.website_eligible,
  'swipe_eligible', partner.swipe_eligible,
  'local_eligible', partner.local_eligible
)::text
from public.partners partner
where partner.id = '10000000-0000-4000-8000-0000000000d4';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'legacy_live_profile_invite',
       partner_onboarding_private.issue_partner_invitation_v1(
  '10000000-0000-4000-8000-0000000000d4',
  '00000000-0000-4000-8000-0000000000d4',
  'restaurant', 'operator_only',
  'legacy_live_profile_invite_token_abcdefghijklmnop_010',
  pg_catalog.clock_timestamp() + interval '2 days',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'legacy_live_profile_claim', public.claim_partner_invitation_v1(
  'legacy_live_profile_invite_token_abcdefghijklmnop_010',
  '30000000-0000-4000-8000-00000000010d'
)::text;
reset role;

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'legacy_live_claimed_profile_payload', pg_catalog.jsonb_build_object(
  'bio', 'Synthetic normalized legacy claimed profile',
  'business_type', partner.business_type,
  'categories', partner.categories,
  'category', partner.category,
  'color', coalesce(partner.color, '#ff8a24'),
  'complete_pct', partner.complete_pct,
  'contact', partner.contact,
  'delivery_days', partner.delivery_days,
  'hours', partner.hours,
  'instagram', partner.instagram,
  'items', partner.items,
  'location', partner.location,
  'name', partner.name,
  'neighborhood', partner.neighborhood,
  'offerings', partner.offerings,
  'phone', partner.phone,
  'photo_emoji', coalesce(partner.photo_emoji, '🍽️'),
  'tagline', partner.tagline,
  'website', partner.website
)::text
from public.partners partner
where partner.id = '10000000-0000-4000-8000-0000000000d4';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'legacy_live_claimed_profile_revision', public.revise_partner_profile_v1(
  '10000000-0000-4000-8000-0000000000d4',
  '30000000-0000-4000-8000-00000000010e',
  (select value::jsonb from pg_temp.partner_onboarding_proof_state
   where key = 'legacy_live_claimed_profile_payload')
)::text;
reset role;

do $legacy_live_profile_claim_normalization$
declare
  v_before jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'legacy_live_profile_before_claim'
  );
  v_claim jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'legacy_live_profile_claim'
  );
  v_revision jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'legacy_live_claimed_profile_revision'
  );
begin
  if v_before is distinct from
       '{"owner_id":null,"status":"live","heha_partner":true,"website_eligible":true,"swipe_eligible":true,"local_eligible":true}'::jsonb
     or v_claim ->> 'status' <> 'pending'
     or v_revision ->> 'correction_source' <> 'claim'
     or v_revision ->> 'source_receipt_id' <>
       v_claim ->> 'claim_evidence_id'
     or not exists (
       select 1
       from public.partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000d4'
         and partner.owner_id = '00000000-0000-4000-8000-0000000000d4'
         and partner.status = 'pending'
         and partner.heha_partner is false
         and partner.website_eligible is false
         and partner.swipe_eligible is false
         and partner.local_eligible is false
         and partner.bio = 'Synthetic normalized legacy claimed profile'
     )
     or not exists (
       select 1
       from partner_onboarding_private.audit_events audit
       where audit.partner_id = '10000000-0000-4000-8000-0000000000d4'
         and audit.actor_id = '00000000-0000-4000-8000-0000000000d4'
         and audit.event_type = 'partner_profile_normalized_for_claim_v1'
         and audit.receipt_id = (v_claim ->> 'claim_evidence_id')::uuid
         and audit.event_data is not distinct from pg_catalog.jsonb_build_object(
           'prior_status', 'live',
           'prior_heha_partner', true,
           'prior_website_eligible', true,
           'prior_swipe_eligible', true,
           'prior_local_eligible', true,
           'normalized_status', 'pending'
         )
     )
     or exists (
       select 1 from public.public_swipe_partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000d4'
     )
     or exists (
       select 1 from public.public_local_partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000d4'
     ) then
    raise exception 'Legacy live claim normalization/profile revision mismatch';
  end if;
end;
$legacy_live_profile_claim_normalization$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, true, false, false, false, false,
  'proof-application-enabled',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
select pg_temp.expect_sqlstate(
  'legacy authenticated direct partner INSERT is closed after foundation',
  '42501',
  $sql$insert into public.partners (
         id, name, category, categories, status, owner_id, is_test_record
       ) values (
         '10000000-0000-4000-8000-0000000000f8',
         'Synthetic Direct Write Bypass', 'Vendor', array['Vendor'],
         'pending', '00000000-0000-4000-8000-0000000000c3', false
       )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_first', public.create_or_resume_partner_application_v1(
  '30000000-0000-4000-8000-000000000010',
  '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Vendor","categories":["Vendor"],"bio":"same request"}'::jsonb
)::text;
select pg_temp.expect_sqlstate(
  'legacy authenticated direct partner UPDATE is closed after foundation',
  '42501',
  $sql$update public.partners
       set bio = 'unreceipted authenticated edit'
       where id = (
         select (value::jsonb ->> 'id')::uuid
         from pg_temp.partner_onboarding_proof_state
         where key = 'application_first'
       )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_replay', public.create_or_resume_partner_application_v1(
  '30000000-0000-4000-8000-000000000010',
  '{"categories":["Vendor"],"category":"Vendor","location":"Tampa, FL","postal_code":"33606","legal_name":"Synthetic Applicant LLC","name":"Synthetic Applicant","bio":"same request"}'::jsonb
)::text;
select pg_temp.expect_partner_denied(
  'application conflicting replay denied',
  $sql$select public.create_or_resume_partner_application_v1(
    '30000000-0000-4000-8000-000000000010',
    '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Vendor","categories":["Vendor"],"bio":"changed request"}'::jsonb
  )$sql$
);
reset role;

do $application_receipt$
declare
  v_first jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'application_first');
  v_replay jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'application_replay');
begin
  if v_first ->> 'id' is null
     or v_first ->> 'application_receipt_id' is null
     or v_first ->> 'application_sha256' !~ '^[a-f0-9]{64}$'
     or v_first ->> 'receipt_status' <> 'verified'
     or v_first ->> 'owner_id' <> '00000000-0000-4000-8000-0000000000c3'
     or v_first ->> 'id' <> v_replay ->> 'id'
     or v_first ->> 'application_receipt_id' <> v_replay ->> 'application_receipt_id'
     or v_first ->> 'application_sha256' <> v_replay ->> 'application_sha256' then
    raise exception 'Application receipt/replay contract mismatch';
  end if;

  if exists (
    select 1 from partner_onboarding_private.partner_state s
    where s.partner_id = (v_first ->> 'id')::uuid
  ) then
    raise exception 'Self-application must not create claim/relationship state';
  end if;
end;
$application_receipt$;

do $application_first_single_raw_profile$
declare
  v_application jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_first'
  );
begin
  if (
       select count(*)
       from public.partners partner
       where partner_onboarding_private.normalized_business_key(
         partner.name,
         coalesce(partner.location, partner.neighborhood, partner.postal_code)
       ) = partner_onboarding_private.normalized_business_key(
         'Synthetic Applicant', 'Tampa, FL'
       )
     ) <> 1
     or not exists (
       select 1
       from partner_onboarding_private.partner_business_registry registry
       where registry.partner_id = (v_application ->> 'id')::uuid
         and registry.business_key_sha256 =
           partner_onboarding_private.normalized_business_key(
             'Synthetic Applicant', 'Tampa, FL'
           )
     ) then
    raise exception 'APPLICATION_FIRST_RAW_PROFILE_COUNT must remain one raw/root row';
  end if;
end;
$application_first_single_raw_profile$;

-- The applicant may append a correction while the application is still
-- private and unclaimed. The receipt is immutable/idempotent, the normalized
-- business identity cannot move, and no other authenticated actor can revise
-- the application (APPLICATION_REVISION_BOLA_REPLAY).
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_revision_first', public.revise_partner_profile_v1(
  (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  ),
  '30000000-0000-4000-8000-000000000013',
  '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"corrected request","website":"https://example.invalid/applicant"}'::jsonb
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_revision_replay', public.revise_partner_profile_v1(
  (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  ),
  '30000000-0000-4000-8000-000000000013',
  '{"website":"https://example.invalid/applicant","bio":"corrected request","categories":["Vendor"],"category":"Vendor","location":"Tampa Bay, FL","postal_code":"33606","legal_name":"Synthetic Applicant Corrected LLC","name":"Synthetic Applicant Corrected"}'::jsonb
)::text;
select pg_temp.expect_partner_denied(
  'application revision conflicting replay denied generically',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000013',
    '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"conflicting correction"}'::jsonb
  )$sql$
);
select pg_temp.expect_partner_denied(
  'application revision cannot append an identical no-op receipt',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000014',
    '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"corrected request","website":"https://example.invalid/applicant"}'::jsonb
  )$sql$
);
select pg_temp.expect_partner_denied(
  'application revision cannot collide with another reserved root',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000015',
    '{"name":"Synthetic Main Kitchen","legal_name":"Synthetic Main Kitchen LLC","postal_code":"33602","location":"Tampa, FL","category":"Vendor","categories":["Vendor"],"bio":"collides with another root"}'::jsonb
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'application revision cross-owner BOLA denied generically',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000016',
    '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"cross-owner attempt"}'::jsonb
  )$sql$
);
reset role;

do $application_revision_receipt$
declare
  v_application jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_first'
  );
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_revision_first'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_revision_replay'
  );
  v_old_key text := partner_onboarding_private.normalized_business_key(
    'Synthetic Applicant', 'Tampa, FL'
  );
  v_new_key text := partner_onboarding_private.normalized_business_key(
    'Synthetic Applicant Corrected', 'Tampa Bay, FL'
  );
begin
  if v_first ->> 'id' <> v_application ->> 'id'
     or v_first ->> 'owner_id' <> '00000000-0000-4000-8000-0000000000c3'
     or v_first ->> 'correction_source' <> 'application'
     or v_first ->> 'source_receipt_id' <>
       v_application ->> 'application_receipt_id'
     or v_first ->> 'correction_receipt_id' is null
     or v_first ->> 'submitted_sha256' !~ '^[a-f0-9]{64}$'
     or v_first ->> 'submitted_sha256' = v_application ->> 'application_sha256'
     or v_first ->> 'previous_sha256' <>
       v_application ->> 'application_sha256'
     or v_first ->> 'resulting_sha256' !~ '^[a-f0-9]{64}$'
     or v_first ->> 'receipt_status' <> 'verified'
     or v_first ->> 'correction_receipt_id' <>
       v_replay ->> 'correction_receipt_id'
     or v_first ->> 'submitted_sha256' <> v_replay ->> 'submitted_sha256'
     or (
       select count(*)
       from partner_onboarding_private.partner_application_corrections correction
       where correction.application_id =
         (v_application ->> 'application_receipt_id')::uuid
     ) <> 1
     or partner_onboarding_private.current_partner_business_key_v1(
       (v_application ->> 'id')::uuid
     ) is distinct from v_new_key
     or partner_onboarding_private.partner_business_identity_is_current_v1(
       (v_application ->> 'id')::uuid,
       v_old_key
     ) is not true
     or not exists (
       select 1
       from partner_onboarding_private.partner_business_registry registry
       where registry.partner_id = (v_application ->> 'id')::uuid
         and registry.business_key_sha256 = v_old_key
     )
     or not exists (
       select 1
       from partner_onboarding_private.partner_business_key_corrections key_correction
       where key_correction.partner_id = (v_application ->> 'id')::uuid
         and key_correction.application_id =
           (v_application ->> 'application_receipt_id')::uuid
         and key_correction.application_correction_id =
           (v_first ->> 'correction_receipt_id')::uuid
         and key_correction.previous_business_key_sha256 = v_old_key
         and key_correction.corrected_business_key_sha256 = v_new_key
         and key_correction.corrected_by =
           '00000000-0000-4000-8000-0000000000c3'
     )
     or not exists (
       select 1
       from partner_onboarding_private.partner_profile_correction_requests router
       where router.partner_id = (v_application ->> 'id')::uuid
         and router.actor_id = '00000000-0000-4000-8000-0000000000c3'
         and router.request_key = '30000000-0000-4000-8000-000000000013'
         and router.correction_source = 'application'
         and router.application_receipt_id =
           (v_application ->> 'application_receipt_id')::uuid
         and router.application_correction_receipt_id =
           (v_first ->> 'correction_receipt_id')::uuid
         and router.claim_receipt_id is null
         and router.claim_profile_correction_receipt_id is null
         and router.submitted_sha256 = v_first ->> 'submitted_sha256'
         and router.previous_sha256 = v_first ->> 'previous_sha256'
         and router.resulting_sha256 = v_first ->> 'resulting_sha256'
         and router.private_profile_status = v_first ->> 'status'
     ) then
    raise exception 'Application correction receipt/BOLA/replay contract mismatch';
  end if;
end;
$application_revision_receipt$;

select pg_temp.expect_sqlstate(
  'application profile correction router receipt is append-only', '42501',
  $sql$update partner_onboarding_private.partner_profile_correction_requests
       set private_profile_status = 'missing_info'
       where actor_id = '00000000-0000-4000-8000-0000000000c3'
         and request_key = '30000000-0000-4000-8000-000000000013'$sql$
);

select pg_temp.expect_partner_denied(
  'raw direct business identity drift denied',
  $sql$update public.partners
       set name = 'Synthetic Unreceipted Drift'
       where id = (
         select (value::jsonb ->> 'id')::uuid
         from pg_temp.partner_onboarding_proof_state where key = 'application_first'
       )$sql$
);

-- A presentation-only edit that normalizes to the already receipted key is
-- allowed; it does not create a second identity or key receipt.
update public.partners
set name = '  SYNTHETIC APPLICANT CORRECTED  ',
    location = 'tampa bay, fl'
where id = (
  select (value::jsonb ->> 'id')::uuid
  from pg_temp.partner_onboarding_proof_state where key = 'application_first'
);

do $same_normalized_business_edit$
declare
  v_partner_id uuid := (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  );
begin
  if partner_onboarding_private.current_partner_business_key_v1(v_partner_id)
       is distinct from partner_onboarding_private.normalized_business_key(
         'Synthetic Applicant Corrected', 'Tampa Bay, FL'
       )
     or (
       select count(*)
       from partner_onboarding_private.partner_business_key_corrections correction
       where correction.partner_id = v_partner_id
     ) <> 1 then
    raise exception 'Same-normalized profile edit changed business identity';
  end if;
end;
$same_normalized_business_edit$;

-- BUSINESS_KEY_A_B_A_RECOVERY: a partner may correct back to its original
-- root identity without minting a new business. Both the root and historical
-- alias remain globally reserved to the same partner.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_revision_root_recovery', public.revise_partner_profile_v1(
  (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  ),
  '30000000-0000-4000-8000-000000000097',
  '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Vendor","categories":["Vendor"],"bio":"corrected request","website":"https://example.invalid/applicant"}'::jsonb
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_revision_root_recovery_replay', public.revise_partner_profile_v1(
  (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  ),
  '30000000-0000-4000-8000-000000000097',
  '{"website":"https://example.invalid/applicant","bio":"corrected request","categories":["Vendor"],"category":"Vendor","location":"Tampa, FL","postal_code":"33606","legal_name":"Synthetic Applicant LLC","name":"Synthetic Applicant"}'::jsonb
)::text;
reset role;

do $business_key_a_b_a_recovery$
declare
  v_partner_id uuid := (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  );
  v_application_id uuid := (
    select (value::jsonb ->> 'application_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  );
  v_root text := partner_onboarding_private.normalized_business_key(
    'Synthetic Applicant', 'Tampa, FL'
  );
  v_alias text := partner_onboarding_private.normalized_business_key(
    'Synthetic Applicant Corrected', 'Tampa Bay, FL'
  );
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_revision_root_recovery'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_revision_root_recovery_replay'
  );
begin
  if v_first ->> 'correction_receipt_id' is null
     or v_first ->> 'correction_receipt_id' <>
       v_replay ->> 'correction_receipt_id'
     or v_first ->> 'correction_source' <> 'application'
     or v_first ->> 'source_receipt_id' <> v_application_id::text
     or v_first ->> 'submitted_sha256' <>
       v_replay ->> 'submitted_sha256'
     or partner_onboarding_private.current_partner_business_key_v1(v_partner_id)
          is distinct from v_root
     or partner_onboarding_private.partner_business_identity_is_current_v1(
       v_partner_id, v_root
     ) is not true
     or partner_onboarding_private.partner_business_identity_is_current_v1(
       v_partner_id, v_alias
     ) is not true
     or not exists (
       select 1
       from partner_onboarding_private.partner_business_registry registry
       where registry.partner_id = v_partner_id
         and registry.business_key_sha256 = v_root
     )
     or (
       select count(*)
       from partner_onboarding_private.partner_application_corrections correction
       where correction.application_id = v_application_id
     ) <> 2
     or (
       select count(*)
       from partner_onboarding_private.partner_business_key_corrections correction
       where correction.partner_id = v_partner_id
         and correction.application_id = v_application_id
     ) <> 2
     or not exists (
       select 1
       from partner_onboarding_private.partner_business_key_corrections correction
       where correction.partner_id = v_partner_id
         and correction.previous_business_key_sha256 = v_alias
         and correction.corrected_business_key_sha256 = v_root
         and correction.application_correction_id =
           (v_first ->> 'correction_receipt_id')::uuid
     ) then
    raise exception 'A-to-B-to-A business-key history did not preserve one root and two receipts';
  end if;
end;
$business_key_a_b_a_recovery$;

update public.partners
set name = 'Synthetic Applicant',
    location = 'Tampa, FL'
where id = (
  select (value::jsonb ->> 'id')::uuid
  from pg_temp.partner_onboarding_proof_state where key = 'application_first'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, false, false, false, false, false,
  'proof-application-revision-off',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
select pg_temp.expect_partner_denied(
  'application revision switch off denied generically',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000017',
    '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Vendor","categories":["Vendor"],"bio":"blocked while off"}'::jsonb
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, true, false, false, false, false,
  'proof-application-revision-on',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

-- The application review queue is an authenticated, actor-bound reviewer
-- projection. It exposes only applications that have not entered the invite /
-- claim relationship state, and every invalid reviewer/limit is generic.
set local role service_role;
select pg_temp.expect_sqlstate(
  'service role cannot impersonate a human application reviewer', '42501',
  $sql$select partner_onboarding_private.list_pending_partner_applications_v1(
    '00000000-0000-4000-8000-0000000000e5', 10
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000f6', true
);
select pg_temp.expect_partner_denied(
  'unconfirmed application reviewer denied generically',
  $sql$select partner_onboarding_private.list_pending_partner_applications_v1(
    '00000000-0000-4000-8000-0000000000f6', 10
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'unauthorized application reviewer denied generically',
  $sql$select partner_onboarding_private.list_pending_partner_applications_v1(
    '00000000-0000-4000-8000-0000000000d4', 10
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
select pg_temp.expect_partner_denied(
  'zero application queue limit denied generically',
  $sql$select partner_onboarding_private.list_pending_partner_applications_v1(
    '00000000-0000-4000-8000-000000000105', 0
  )$sql$
);
select pg_temp.expect_partner_denied(
  'oversized application queue limit denied generically',
  $sql$select partner_onboarding_private.list_pending_partner_applications_v1(
    '00000000-0000-4000-8000-000000000105', 101
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_queue_pending',
       partner_onboarding_private.list_pending_partner_applications_v1(
         '00000000-0000-4000-8000-000000000105', 10
       )::text;
reset role;

insert into public.partners (
  id, name, legal_name, postal_code, category, categories, location, bio,
  image_url, gallery_urls, status, complete_pct, heha_partner,
  website_eligible, swipe_eligible, local_eligible, local_lane,
  primary_cta_destination, primary_cta_label, primary_cta_path, is_test_record
) values (
  '10000000-0000-4000-8000-0000000000e7',
  'Synthetic Applicant Corrected', 'Synthetic Applicant Corrected LLC', '33606',
  'Vendor', array['Vendor'], 'Tampa Bay, FL',
  'Synthetic duplicate application-key invitation target',
  null, '[]'::jsonb, 'pending', 20, false, false, false, false, null,
  null, null, null, false
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  'application business key cannot invite a different partner row',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    '10000000-0000-4000-8000-0000000000e7',
    '00000000-0000-4000-8000-0000000000c3',
    'vendor', 'operator_only',
    'duplicate_application_invite_token_abcdefghijklmnopqrstuvwxyz_005',
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
reset role;

delete from public.partners
where id = '10000000-0000-4000-8000-0000000000e7';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  'application-backed invitation rejects a non-owner recipient without side effects',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '00000000-0000-4000-8000-0000000000d4',
    'vendor', 'operator_only',
    'application_wrong_owner_invite_token_abcdefghijklmnop_011',
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_onboarding_invite',
       partner_onboarding_private.issue_partner_invitation_v1(
         (
           select (value::jsonb ->> 'id')::uuid
           from pg_temp.partner_onboarding_proof_state
           where key = 'application_first'
         ),
         '00000000-0000-4000-8000-0000000000c3',
         'vendor', 'operator_only',
         'application_invite_token_abcdefghijklmnopqrstuvwxyz_004',
         pg_catalog.clock_timestamp() + interval '2 days',
         '00000000-0000-4000-8000-0000000000e5'
       )::text;

select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_queue_after_invite',
       partner_onboarding_private.list_pending_partner_applications_v1(
         '00000000-0000-4000-8000-000000000105', 10
       )::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
select pg_temp.expect_partner_denied(
  'APPLICATION_REVISION_STALE_AFTER_INVITE denied generically',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000018',
    '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"stale after invite"}'::jsonb
  )$sql$
);
reset role;

do $application_queue_projection$
declare
  v_application jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_first'
  );
  v_revision jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_revision_root_recovery'
  );
  v_pending jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_queue_pending'
  );
  v_after jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_queue_after_invite'
  );
begin
  if v_pending ->> 'projection_version' <> 'heha-partner-application-review-queue-v1'
     or v_pending ->> 'reviewer_id' <> '00000000-0000-4000-8000-000000000105'
     or pg_catalog.jsonb_array_length(v_pending -> 'applications') <> 1
     or v_pending #>> '{applications,0,partner_id}' <> v_application ->> 'id'
     or v_pending #>> '{applications,0,application_id}' <>
       v_application ->> 'application_receipt_id'
     or v_pending #>> '{applications,0,owner_id}' <>
       '00000000-0000-4000-8000-0000000000c3'
     or v_pending #>> '{applications,0,application_sha256}' <>
       v_revision ->> 'submitted_sha256'
     or v_pending #>> '{applications,0,correction_receipt_id}' <>
       v_revision ->> 'correction_receipt_id'
     or pg_catalog.jsonb_array_length(v_after -> 'applications') <> 0 then
    raise exception 'Application queue authorization/isolation transition mismatch';
  end if;
end;
$application_queue_projection$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'duplicate application BOLA denied',
  $sql$select public.create_or_resume_partner_application_v1(
    '30000000-0000-4000-8000-000000000011',
    '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Vendor","categories":["Vendor"],"bio":"same request"}'::jsonb
  )$sql$
);
select pg_temp.expect_partner_denied(
  'corrected application business alias remains globally reserved',
  $sql$select public.create_or_resume_partner_application_v1(
    '30000000-0000-4000-8000-000000000019',
    '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"corrected alias collision"}'::jsonb
  )$sql$
);
select pg_temp.expect_partner_denied(
  'invited relationship business key cannot become a second application',
  $sql$select public.create_or_resume_partner_application_v1(
    '30000000-0000-4000-8000-000000000012',
    '{"name":"Synthetic Main Kitchen","legal_name":"Synthetic Main Kitchen LLC","postal_code":"33602","location":"Tampa, FL","category":"Restaurant","categories":["Restaurant"],"bio":"conflicts with invited relationship"}'::jsonb
  )$sql$
);
reset role;

-- UNCLAIMED_RECLASSIFICATION_RESET: an active invitation blocks legal reset.
-- Once security revokes it, the legal admin may append one idempotent reset;
-- the owner must then submit a receipted correction before another invite.
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_state_before_reclassification_reset',
       relationship_epoch::text || ':' || claim_epoch::text || ':' || release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = (
  select (value::jsonb ->> 'id')::uuid
  from pg_temp.partner_onboarding_proof_state where key = 'application_first'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
select pg_temp.expect_partner_denied(
  'active invitation blocks unclaimed reclassification reset',
  $sql$select partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    'synthetic_category_correction',
    '30000000-0000-4000-8000-000000000098',
    '00000000-0000-4000-8000-000000000104'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'non-legal actor cannot reset unclaimed reclassification',
  $sql$select partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    'synthetic_category_correction',
    '30000000-0000-4000-8000-000000000098',
    '00000000-0000-4000-8000-0000000000d4'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_onboarding_invite_revocation',
       partner_onboarding_private.revoke_partner_invitation_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'application_onboarding_invite'),
  '00000000-0000-4000-8000-0000000000e5',
  'synthetic_unclaimed_reclassification'
)::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'unclaimed_reclassification_reset_first',
       partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  (select (value::jsonb ->> 'id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
  'synthetic_category_correction',
  '30000000-0000-4000-8000-000000000098',
  '00000000-0000-4000-8000-000000000104'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'unclaimed_reclassification_reset_replay',
       partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  (select (value::jsonb ->> 'id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
  'synthetic_category_correction',
  '30000000-0000-4000-8000-000000000098',
  '00000000-0000-4000-8000-000000000104'
)::text;
select pg_temp.expect_partner_denied(
  'unclaimed reclassification reset conflicting replay denied generically',
  $sql$select partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    'synthetic_conflicting_category_correction',
    '30000000-0000-4000-8000-000000000098',
    '00000000-0000-4000-8000-000000000104'
  )$sql$
);
reset role;

do $unclaimed_reclassification_reset_receipt$
declare
  v_partner_id uuid := (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  );
  v_before text[] := pg_catalog.string_to_array(
    (select value from pg_temp.partner_onboarding_proof_state
     where key = 'application_state_before_reclassification_reset'), ':'
  );
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'unclaimed_reclassification_reset_first'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'unclaimed_reclassification_reset_replay'
  );
begin
  if v_first ->> 'reset_receipt_id' is null
     or v_first ->> 'reset_receipt_id' <> v_replay ->> 'reset_receipt_id'
     or v_first ->> 'receipt_status' <> 'verified'
     or v_first ->> 'status' <> 'reclassification_pending'
     or not exists (
       select 1 from partner_onboarding_private.partner_state state
       where state.partner_id = v_partner_id
         and state.reclassification_pending
         and state.relationship_epoch = v_before[1]::integer + 1
         and state.claim_epoch = v_before[2]::integer + 1
         and state.release_epoch = v_before[3]::integer + 1
         and state.operator_user_id is null
     )
     or partner_onboarding_private.current_claim_receipt_id_v1(v_partner_id)
          is not null
     or partner_onboarding_private.current_acceptance_receipt_id_v1(v_partner_id)
          is not null
     or partner_onboarding_private.current_release_receipt_id_v1(v_partner_id)
          is not null
     or exists (
       select 1 from public.partner_public_cards_v1 card
       where card.partner_id = v_partner_id
     ) then
    raise exception 'Unclaimed reclassification reset receipt/epoch contract mismatch';
  end if;
end;
$unclaimed_reclassification_reset_receipt$;

select pg_temp.expect_sqlstate(
  'unclaimed reclassification reset receipt is append-only', '42501',
  $sql$update partner_onboarding_private.partner_reclassification_resets
       set reason_code = 'mutated'
       where id = (
         select (value::jsonb ->> 'reset_receipt_id')::uuid
         from pg_temp.partner_onboarding_proof_state
         where key = 'unclaimed_reclassification_reset_first'
       )$sql$
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select pg_temp.expect_partner_denied(
  'invitation denied while reclassification correction is pending',
  $sql$select partner_onboarding_private.issue_partner_invitation_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '00000000-0000-4000-8000-0000000000c3',
    'market', 'operator_only',
    'application_reclassified_invite_token_abcdefghijklmnop_008',
    pg_catalog.clock_timestamp() + interval '2 days',
    '00000000-0000-4000-8000-0000000000e5'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'reclassification_owner_correction', public.revise_partner_profile_v1(
  (select (value::jsonb ->> 'id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
  '30000000-0000-4000-8000-000000000099',
  '{"name":"Synthetic Applicant","legal_name":"Synthetic Applicant LLC","postal_code":"33606","location":"Tampa, FL","category":"Grocery","categories":["Grocery"],"bio":"market reclassification","website":"https://example.invalid/applicant"}'::jsonb
)::text;
reset role;

do $reclassification_owner_correction$
declare
  v_partner_id uuid := (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  );
begin
  if not exists (
       select 1 from partner_onboarding_private.partner_state state
       where state.partner_id = v_partner_id
         and state.legal_relationship_type = 'market'
         and state.reclassification_pending is false
     )
     or not exists (
       select 1 from public.partners partner
       where partner.id = v_partner_id
         and partner.category = 'Grocery'
         and partner.status in ('draft', 'submitted', 'pending', 'missing_info')
     ) then
    raise exception 'Owner correction did not clear/reclassify pending relationship';
  end if;
end;
$reclassification_owner_correction$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
select pg_temp.expect_partner_denied(
  'completed reclassification makes old reset replay stale',
  $sql$select partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    'synthetic_category_correction',
    '30000000-0000-4000-8000-000000000098',
    '00000000-0000-4000-8000-000000000104'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_reclassified_fresh_invite',
       partner_onboarding_private.issue_partner_invitation_v1(
  (select (value::jsonb ->> 'id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
  '00000000-0000-4000-8000-0000000000c3',
  'market', 'operator_only',
  'application_reclassified_fresh_invite_token_abcdefghijkl_009',
  pg_catalog.clock_timestamp() + interval '2 days',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
reset role;

-- profile_correction_cross_provenance_replay: once the former applicant has
-- entered a claimed relationship, the unified router still returns the one
-- immutable application-mode receipt for the exact historical request. It
-- must not dispatch the same key into the claim correction child.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c3', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'application_reclassified_claim', public.claim_partner_invitation_v1(
  'application_reclassified_fresh_invite_token_abcdefghijkl_009',
  '30000000-0000-4000-8000-00000000010f'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'profile_correction_cross_provenance_replay',
       public.revise_partner_profile_v1(
  (select (value::jsonb ->> 'id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
  '30000000-0000-4000-8000-000000000013',
  '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"corrected request","website":"https://example.invalid/applicant"}'::jsonb
)::text;
select pg_temp.expect_partner_denied(
  'profile correction cross-provenance conflicting replay denied generically',
  $sql$select public.revise_partner_profile_v1(
    (select (value::jsonb ->> 'id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'application_first'),
    '30000000-0000-4000-8000-000000000013',
    '{"name":"Synthetic Applicant Corrected","legal_name":"Synthetic Applicant Corrected LLC","postal_code":"33606","location":"Tampa Bay, FL","category":"Vendor","categories":["Vendor"],"bio":"changed cross-provenance replay","website":"https://example.invalid/applicant"}'::jsonb
  )$sql$
);
reset role;

do $profile_correction_cross_provenance_replay$
declare
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'application_revision_first'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'profile_correction_cross_provenance_replay'
  );
begin
  if v_replay is distinct from v_first
     or v_replay ->> 'correction_source' <> 'application'
     or (
       select count(*)
       from partner_onboarding_private.partner_profile_correction_requests router
       where router.actor_id = '00000000-0000-4000-8000-0000000000c3'
         and router.request_key = '30000000-0000-4000-8000-000000000013'
     ) <> 1
     or exists (
       select 1
       from partner_onboarding_private.partner_claim_profile_corrections correction
       where correction.partner_id = (v_first ->> 'id')::uuid
         and correction.actor_id = '00000000-0000-4000-8000-0000000000c3'
     ) then
    raise exception 'Cross-provenance exact replay minted a second correction';
  end if;
end;
$profile_correction_cross_provenance_replay$;

-- Intended operator accepts once. Identical request-key/token replay returns the
-- exact same claim receipt; any changed replay or reuse is generic.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
select pg_temp.expect_partner_denied(
  '31-byte claim token denied',
  $sql$select public.claim_partner_invitation_v1(
    pg_catalog.repeat('a', 31),
    '30000000-0000-4000-8000-00000000f101'
  )$sql$
);
select pg_temp.expect_partner_denied(
  '513-byte claim token denied',
  $sql$select public.claim_partner_invitation_v1(
    pg_catalog.repeat('a', 513),
    '30000000-0000-4000-8000-00000000f102'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'non-ASCII-allowlist claim token denied',
  $sql$select public.claim_partner_invitation_v1(
    pg_catalog.repeat('a', 31) || '!',
    '30000000-0000-4000-8000-00000000f103'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'claim_first', public.claim_partner_invitation_v1(
  'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
  '30000000-0000-4000-8000-000000000020'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'claim_replay', public.claim_partner_invitation_v1(
  'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
  '30000000-0000-4000-8000-000000000020'
)::text;
select pg_temp.expect_partner_denied(
  'claim conflicting replay denied',
  $sql$select public.claim_partner_invitation_v1(
    'different_valid_token_abcdefghijklmnopqrstuvwxyz_999',
    '30000000-0000-4000-8000-000000000020'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'single-use invite reuse denied',
  $sql$select public.claim_partner_invitation_v1(
    'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
    '30000000-0000-4000-8000-000000000021'
  )$sql$
);
reset role;

do $claim_receipt$
declare
  v_first jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'claim_first');
  v_replay jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'claim_replay');
begin
  if v_first ->> 'claim_evidence_id' is null
     or v_first ->> 'claim_evidence_id' <> v_replay ->> 'claim_evidence_id'
     or v_first ->> 'id' <> '10000000-0000-4000-8000-0000000000a1'
     or v_first ->> 'owner_id' <> '00000000-0000-4000-8000-0000000000a1'
     or v_first ->> 'receipt_status' <> 'verified' then
    raise exception 'Claim receipt/replay contract mismatch';
  end if;
end;
$claim_receipt$;

-- A claimed operator may revise only the private operational profile. The
-- submitted snapshot binds the exact stored classification (including a
-- legacy NULL category plus canonical categories), preserves structured
-- hours, and advances the release generation before any publication.
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'claimed_profile_revision_before', pg_catalog.jsonb_build_object(
  'release_epoch', state.release_epoch,
  'name', partner.name,
  'category', partner.category,
  'categories', partner.categories,
  'business_type', partner.business_type,
  'location', partner.location,
  'neighborhood', partner.neighborhood,
  'hours', partner.hours,
  'claim_receipt_id', partner_onboarding_private.current_claim_receipt_id_v1(
    partner.id
  )
)::text
from public.partners partner
join partner_onboarding_private.partner_state state
  on state.partner_id = partner.id
where partner.id = '10000000-0000-4000-8000-0000000000a1';

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'claimed_profile_revision_payload', pg_catalog.jsonb_build_object(
  'bio', 'Synthetic claim-bound operational profile revision',
  'business_type', partner.business_type,
  'categories', partner.categories,
  'category', partner.category,
  'color', coalesce(partner.color, '#ff8a24'),
  'complete_pct', partner.complete_pct,
  'contact', partner.contact,
  'delivery_days', partner.delivery_days,
  'hours', partner.hours,
  'instagram', partner.instagram,
  'items', partner.items,
  'location', partner.location,
  'name', partner.name,
  'neighborhood', partner.neighborhood,
  'offerings', partner.offerings,
  'phone', partner.phone,
  'photo_emoji', coalesce(partner.photo_emoji, '🍽️'),
  'tagline', partner.tagline,
  'website', 'https://example.invalid/claimed-main'
)::text
from public.partners partner
where partner.id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'claimed_profile_revision_first', public.revise_partner_profile_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '30000000-0000-4000-8000-000000000100',
  (select value::jsonb from pg_temp.partner_onboarding_proof_state
   where key = 'claimed_profile_revision_payload')
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'claimed_profile_revision_replay', public.revise_partner_profile_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '30000000-0000-4000-8000-000000000100',
  (select value::jsonb from pg_temp.partner_onboarding_proof_state
   where key = 'claimed_profile_revision_payload')
)::text;
select pg_temp.expect_partner_denied(
  'claimed_profile_revision_conflicting_replay_denied',
  $sql$select public.revise_partner_profile_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '30000000-0000-4000-8000-000000000100',
    pg_catalog.jsonb_set(
      (select value::jsonb from pg_temp.partner_onboarding_proof_state
       where key = 'claimed_profile_revision_payload'),
      '{bio}',
      '"conflicting claimed profile revision"'::jsonb
    )
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'claimed_profile_revision_cross_tenant_denied',
  $sql$select public.revise_partner_profile_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '30000000-0000-4000-8000-000000000101',
    (select value::jsonb from pg_temp.partner_onboarding_proof_state
     where key = 'claimed_profile_revision_payload')
  )$sql$
);
reset role;

-- claimed_profile_revision_receipt
-- claimed_profile_revision_identity_immutable
-- claimed_profile_revision_release_invalidated
-- claimed_profile_revision_release_epoch_invalidated
do $claimed_profile_revision_receipt$
declare
  v_before jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'claimed_profile_revision_before'
  );
  v_payload jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'claimed_profile_revision_payload'
  );
  v_first jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'claimed_profile_revision_first'
  );
  v_replay jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'claimed_profile_revision_replay'
  );
begin
  if v_first ->> 'id' <> '10000000-0000-4000-8000-0000000000a1'
     or v_first ->> 'owner_id' <> '00000000-0000-4000-8000-0000000000a1'
     or v_first ->> 'correction_source' <> 'claim'
     or v_first ->> 'source_receipt_id' <> v_before ->> 'claim_receipt_id'
     or v_first ->> 'correction_receipt_id' is null
     or v_first ->> 'submitted_sha256' !~ '^[a-f0-9]{64}$'
     or v_first ->> 'submitted_sha256' is distinct from
       partner_onboarding_private.sha256_text(
         partner_onboarding_private.canonical_json(v_payload)
       )
     or v_first ->> 'previous_sha256' !~ '^[a-f0-9]{64}$'
     or v_first ->> 'resulting_sha256' !~ '^[a-f0-9]{64}$'
     or v_first ->> 'previous_sha256' = v_first ->> 'resulting_sha256'
     or v_first ->> 'receipt_status' <> 'verified'
     or v_first is distinct from v_replay
     or partner_onboarding_private.claim_editable_profile_sha256_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_first ->> 'resulting_sha256'
     or (
       select state.release_epoch
       from partner_onboarding_private.partner_state state
       where state.partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> (v_before ->> 'release_epoch')::integer + 1
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.epoch_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or exists (
       select 1 from public.partner_public_cards_v1 card
       where card.partner_id = '10000000-0000-4000-8000-0000000000a1'
     )
     or exists (
       select 1 from public.public_swipe_partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000a1'
     )
     or exists (
       select 1 from public.public_local_partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000a1'
     )
     or not exists (
       select 1
       from public.partners partner
       where partner.id = '10000000-0000-4000-8000-0000000000a1'
         and pg_catalog.to_jsonb(partner.name) is not distinct from
           v_before -> 'name'
         and pg_catalog.to_jsonb(partner.category) is not distinct from
           v_before -> 'category'
         and pg_catalog.to_jsonb(partner.categories) is not distinct from
           v_before -> 'categories'
         and pg_catalog.to_jsonb(partner.business_type) is not distinct from
           v_before -> 'business_type'
         and pg_catalog.to_jsonb(partner.location) is not distinct from
           v_before -> 'location'
         and pg_catalog.to_jsonb(partner.neighborhood) is not distinct from
           v_before -> 'neighborhood'
         and partner.hours is not distinct from v_before -> 'hours'
         and partner.category is null
         and partner.categories = array['Restaurant']::text[]
         and partner.hours =
           '{"monday":{"open":"09:00","close":"17:00"}}'::jsonb
         and partner.bio =
           'Synthetic claim-bound operational profile revision'
     )
     or not exists (
       select 1
       from partner_onboarding_private.partner_claim_profile_corrections correction
       where correction.id = (v_first ->> 'correction_receipt_id')::uuid
         and correction.partner_id = '10000000-0000-4000-8000-0000000000a1'
         and correction.claim_id = (v_first ->> 'source_receipt_id')::uuid
         and correction.actor_id = '00000000-0000-4000-8000-0000000000a1'
         and correction.correction_snapshot = v_payload
         and correction.correction_sha256 = v_first ->> 'submitted_sha256'
         and correction.previous_profile_sha256 = v_first ->> 'previous_sha256'
         and correction.resulting_profile_sha256 = v_first ->> 'resulting_sha256'
     )
     or not exists (
       select 1
       from partner_onboarding_private.partner_profile_correction_requests router
       where router.partner_id = '10000000-0000-4000-8000-0000000000a1'
         and router.actor_id = '00000000-0000-4000-8000-0000000000a1'
         and router.request_key = '30000000-0000-4000-8000-000000000100'
         and router.correction_source = 'claim'
         and router.application_receipt_id is null
         and router.application_correction_receipt_id is null
         and router.claim_receipt_id = (v_first ->> 'source_receipt_id')::uuid
         and router.claim_profile_correction_receipt_id =
           (v_first ->> 'correction_receipt_id')::uuid
         and router.submitted_sha256 = v_first ->> 'submitted_sha256'
         and router.previous_sha256 = v_first ->> 'previous_sha256'
         and router.resulting_sha256 = v_first ->> 'resulting_sha256'
         and router.private_profile_status = v_first ->> 'status'
     ) then
    raise exception 'Claimed profile correction receipt, identity, or generation mismatch';
  end if;
end;
$claimed_profile_revision_receipt$;

select pg_temp.expect_sqlstate(
  'claimed profile correction receipt is immutable', '42501',
  $sql$update partner_onboarding_private.partner_claim_profile_corrections
       set correction_sha256 = repeat('0', 64)
       where id = (
         select (value::jsonb ->> 'correction_receipt_id')::uuid
         from pg_temp.partner_onboarding_proof_state
         where key = 'claimed_profile_revision_first'
       )$sql$
);
select pg_temp.expect_sqlstate(
  'claimed profile router receipt is append-only', '42501',
  $sql$update partner_onboarding_private.partner_profile_correction_requests
       set private_profile_status = 'missing_info'
       where actor_id = '00000000-0000-4000-8000-0000000000a1'
         and request_key = '30000000-0000-4000-8000-000000000100'$sql$
);

set local role service_role;
select pg_temp.expect_partner_denied(
  'claimed private revision has no orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

-- ---------------------------------------------------------------------------
-- Separate operator and signer, immutable document/assertions, and acceptance.
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'agreement_version', partner_onboarding_private.register_partner_agreement_version_v1(
  'restaurant',
  'restaurant-synthetic-v1',
  'Synthetic Restaurant Agreement',
  pg_catalog.clock_timestamp() - interval '1 day',
  'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT',
  partner_onboarding_private.sha256_text('SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'),
  'I agree to the synthetic terms.',
  '{"privacy":"synthetic-v1","fees":"synthetic-v1"}'::jsonb,
  'SYNTHETIC-LEGAL-REVIEW-ONLY',
  '00000000-0000-4000-8000-000000000104',
  pg_catalog.clock_timestamp() - interval '2 days'
)::text;
select partner_onboarding_private.select_partner_agreement_version_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
  '00000000-0000-4000-8000-000000000104'
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'signer_grant', partner_onboarding_private.grant_partner_signer_authority_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000b2',
  'Signer B',
  'Authorized Representative',
  '00000000-0000-4000-8000-000000000104'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, true, true, false, false, false,
  'proof-acceptance-enabled',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'operator_assignments', public.list_my_partner_onboarding_assignments_v1()::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'signer_assignments', public.list_my_partner_onboarding_assignments_v1()::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'outsider_assignments', public.list_my_partner_onboarding_assignments_v1()::text;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_temp.expect_partner_denied(
  'assignment RPC missing actor denied generically',
  $sql$select public.list_my_partner_onboarding_assignments_v1()$sql$
);
reset role;

do $assignment_projection$
declare
  v_operator jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'operator_assignments');
  v_signer jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'signer_assignments');
  v_outsider jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'outsider_assignments');
begin
  if v_operator ->> 'authorized_actor_id' <> '00000000-0000-4000-8000-0000000000a1'
     or pg_catalog.jsonb_array_length(v_operator -> 'assignments') <> 1
     or v_operator #>> '{assignments,0,partner_id}' <> '10000000-0000-4000-8000-0000000000a1'
     or v_operator #>> '{assignments,0,role}' <> 'operator'
     or v_signer ->> 'authorized_actor_id' <> '00000000-0000-4000-8000-0000000000b2'
     or pg_catalog.jsonb_array_length(v_signer -> 'assignments') <> 1
     or v_signer #>> '{assignments,0,partner_id}' <> '10000000-0000-4000-8000-0000000000a1'
     or v_signer #>> '{assignments,0,role}' <> 'authorized_signer'
     or pg_catalog.jsonb_array_length(v_outsider -> 'assignments') <> 0 then
    raise exception 'Assignment projection leaked or omitted a tenant assignment';
  end if;
end;
$assignment_projection$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
select pg_temp.expect_partner_denied(
  'operator cannot substitute for separate signer',
  $sql$select public.get_partner_agreement_for_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'capability BOLA denied generically',
  $sql$select public.get_partner_onboarding_capabilities_v1(
    '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'agreement_loaded', public.get_partner_agreement_for_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_first', public.record_category_partner_agreement_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
  partner_onboarding_private.sha256_text('SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'),
  '30000000-0000-4000-8000-000000000030',
  '{"typed_signature":"Signer B","signer_title":"Authorized Representative","assent_text":"I agree to the synthetic terms.","signer_legal_name":"Signer B","assertions_version":"heha-partner-acceptance-v1","electronic_records_consent":true,"signer_authority_confirmed":true,"reviewed_complete_agreement":true}'::jsonb
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_replay', public.record_category_partner_agreement_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
  partner_onboarding_private.sha256_text('SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'),
  '30000000-0000-4000-8000-000000000030',
  '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}'::jsonb
)::text;
select pg_temp.expect_partner_denied(
  'acceptance conflicting replay denied',
  $sql$select public.record_category_partner_agreement_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
    partner_onboarding_private.sha256_text('SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'),
    '30000000-0000-4000-8000-000000000030',
    '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Changed Title","typed_signature":"Signer B"}'::jsonb
  )$sql$
);
select pg_temp.expect_partner_denied(
  'stale document hash denied',
  $sql$select public.record_category_partner_agreement_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
    repeat('0', 64),
    '30000000-0000-4000-8000-000000000031',
    '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}'::jsonb
  )$sql$
);
reset role;

do $acceptance_receipt$
declare
  v_loaded jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'agreement_loaded');
  v_first jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'acceptance_first');
  v_replay jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'acceptance_replay');
begin
  if v_loaded ->> 'accepted_owner_id' <> '00000000-0000-4000-8000-0000000000a1'
     or v_loaded ->> 'authorized_actor_id' <> '00000000-0000-4000-8000-0000000000b2'
     or v_loaded ->> 'document_snapshot' <> 'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'
     or v_first ->> 'accepted_owner_id' <> '00000000-0000-4000-8000-0000000000a1'
     or v_first ->> 'accepted_by' <> '00000000-0000-4000-8000-0000000000b2'
     or v_first ->> 'acceptance_id' <> v_replay ->> 'acceptance_id'
     or v_first ->> 'assertions_sha256' <> '5327bdf5a2d33cdc26368ead401444941f8ef5cdb88f0d4ef0d4b8def19947f6'
     or v_first -> 'assertions_snapshot' <> v_replay -> 'assertions_snapshot'
     or v_first ->> 'receipt_status' <> 'verified' then
    raise exception 'Agreement load/acceptance receipt contract mismatch';
  end if;
end;
$acceptance_receipt$;

-- SIGNER_AUTHORITY_REVOCATION_RECOVERY: legal revocation is append-only and
-- idempotent, immediately makes the old signer's acceptance stale, and
-- requires a distinct current authority/acceptance before release can resume.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'non-legal actor cannot revoke signer authority',
  $sql$select partner_onboarding_private.revoke_partner_signer_authority_v1(
    (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'signer_grant'),
    '00000000-0000-4000-8000-0000000000d4',
    'synthetic_unauthorized_signer_revocation'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'signer_revocation_first',
       partner_onboarding_private.revoke_partner_signer_authority_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'signer_grant'),
  '00000000-0000-4000-8000-000000000104',
  'synthetic_signer_authority_revocation'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'signer_revocation_replay',
       partner_onboarding_private.revoke_partner_signer_authority_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'signer_grant'),
  '00000000-0000-4000-8000-000000000104',
  'synthetic_signer_authority_revocation'
)::text;
select pg_temp.expect_partner_denied(
  'signer revocation conflicting replay denied generically',
  $sql$select partner_onboarding_private.revoke_partner_signer_authority_v1(
    (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'signer_grant'),
    '00000000-0000-4000-8000-000000000104',
    'synthetic_conflicting_signer_revocation'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'SIGNER_REVOCATION_STALE_RELEASE_DENIAL',
  $sql$select partner_onboarding_private.finalize_partner_release_v1(
    '10000000-0000-4000-8000-0000000000a1',
    partner_onboarding_private.partner_preview_sha256(
      '10000000-0000-4000-8000-0000000000a1'
    ),
    '30000000-0000-4000-8000-000000000033',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'signer_grant_recovery',
       partner_onboarding_private.grant_partner_signer_authority_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000d4',
  'Signer D',
  'Authorized Representative',
  '00000000-0000-4000-8000-000000000104'
)::text;
reset role;

do $signer_revocation_invalidates_acceptance$
begin
  if partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null then
    raise exception 'Revoked signer left its acceptance current';
  end if;
end;
$signer_revocation_invalidates_acceptance$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true
);
select pg_temp.expect_partner_denied(
  'revoked signer cannot reload agreement',
  $sql$select public.get_partner_agreement_for_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'revoked signer cannot replay stale acceptance',
  $sql$select public.record_category_partner_agreement_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
    partner_onboarding_private.sha256_text('SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'),
    '30000000-0000-4000-8000-000000000030',
    '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}'::jsonb
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_after_signer_recovery',
       public.record_category_partner_agreement_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version'),
  partner_onboarding_private.sha256_text('SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'),
  '30000000-0000-4000-8000-000000000034',
  '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer D","signer_title":"Authorized Representative","typed_signature":"Signer D"}'::jsonb
)::text;
reset role;

do $signer_authority_revocation_recovery$
declare
  v_old_acceptance uuid := (
    select (value::jsonb ->> 'acceptance_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'acceptance_first'
  );
  v_new_acceptance uuid := (
    select (value::jsonb ->> 'acceptance_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'acceptance_after_signer_recovery'
  );
begin
  if (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'signer_revocation_first'
     ) is distinct from (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'signer_revocation_replay'
     )
     or v_new_acceptance is null
     or v_new_acceptance = v_old_acceptance
     or partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_new_acceptance
     or (
       select count(*)
       from partner_onboarding_private.partner_actor_authority_revocations revocation
       where revocation.authority_grant_id = (
         select value::uuid from pg_temp.partner_onboarding_proof_state
         where key = 'signer_grant'
       )
     ) <> 1 then
    raise exception 'Signer authority revocation/recovery contract mismatch';
  end if;
end;
$signer_authority_revocation_recovery$;

select pg_temp.expect_sqlstate(
  'agreement document append-only', '42501',
  $sql$update partner_onboarding_private.partner_agreement_versions
       set document_snapshot = 'mutated'
       where id = (select value::uuid from pg_temp.partner_onboarding_proof_state where key = 'agreement_version')$sql$
);
select pg_temp.expect_sqlstate(
  'acceptance assertions append-only', '42501',
  $sql$update partner_onboarding_private.partner_agreement_acceptances
       set assertions_snapshot = '{}'::jsonb
       where id = (
         select (value::jsonb ->> 'acceptance_id')::uuid
         from pg_temp.partner_onboarding_proof_state where key = 'acceptance_first'
       )$sql$
);

-- Release is denied both while its switch is off and after it is enabled but
-- before every current evidence receipt exists.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'release switch defaults off independently',
  $sql$select partner_onboarding_private.finalize_partner_release_v1(
    '10000000-0000-4000-8000-0000000000a1',
    partner_onboarding_private.partner_preview_sha256('10000000-0000-4000-8000-0000000000a1'),
    '30000000-0000-4000-8000-000000000040',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, true, true, true, false, false,
  'proof-release-enabled-surfaces-off',
  '00000000-0000-4000-8000-0000000000e5'
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'release requires complete current evidence set',
  $sql$select partner_onboarding_private.finalize_partner_release_v1(
    '10000000-0000-4000-8000-0000000000a1',
    partner_onboarding_private.partner_preview_sha256('10000000-0000-4000-8000-0000000000a1'),
    '30000000-0000-4000-8000-000000000041',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
reset role;

-- ---------------------------------------------------------------------------
-- Current evidence, release-only state, and separate actual-surface receipts.
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'profile_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'profile',
  partner_onboarding_private.partner_profile_sha256('10000000-0000-4000-8000-0000000000a1'),
  '{"status":"verified","review":"synthetic profile"}'::jsonb,
  '30000000-0000-4000-8000-000000000050',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'media_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'media',
  partner_onboarding_private.partner_media_sha256('10000000-0000-4000-8000-0000000000a1'),
  '{"status":"verified","review":"synthetic media"}'::jsonb,
  '30000000-0000-4000-8000-000000000051',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'compliance_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'compliance', repeat('c', 64),
  '{"status":"verified","review":"synthetic compliance"}'::jsonb,
  '30000000-0000-4000-8000-000000000052',
  '00000000-0000-4000-8000-000000000105'
)::text;
select pg_temp.expect_partner_denied(
  'restaurant Local identity rejects mismatched lane',
  $sql$select partner_onboarding_private.issue_partner_evidence_v1(
    '10000000-0000-4000-8000-0000000000a1', 'local_identity', repeat('d', 64),
    '{"status":"verified","local_lane":"restaurants","swipe_partner_id":"10000000-0000-4000-8000-0000000000a1","local_partner_id":"20000000-0000-4000-8000-0000000000a2","primary_cta_destination":"local","primary_cta_path":"/restaurants/20000000-0000-4000-8000-0000000000a2"}'::jsonb,
    '30000000-0000-4000-8000-000000000057',
    '00000000-0000-4000-8000-000000000105'
  )$sql$
);
select pg_temp.expect_partner_denied(
  'restaurant Local identity rejects mismatched route prefix',
  $sql$select partner_onboarding_private.issue_partner_evidence_v1(
    '10000000-0000-4000-8000-0000000000a1', 'local_identity', repeat('d', 64),
    '{"status":"verified","local_lane":"meals","swipe_partner_id":"10000000-0000-4000-8000-0000000000a1","local_partner_id":"20000000-0000-4000-8000-0000000000a2","primary_cta_destination":"local","primary_cta_path":"/vendors/20000000-0000-4000-8000-0000000000a2"}'::jsonb,
    '30000000-0000-4000-8000-000000000058',
    '00000000-0000-4000-8000-000000000105'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_identity_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'local_identity', repeat('d', 64),
  '{"status":"verified","local_lane":"meals","swipe_partner_id":"10000000-0000-4000-8000-0000000000a1","local_partner_id":"20000000-0000-4000-8000-0000000000a2","primary_cta_destination":"local","primary_cta_path":"/restaurants/20000000-0000-4000-8000-0000000000a2"}'::jsonb,
  '30000000-0000-4000-8000-000000000053',
  '00000000-0000-4000-8000-000000000105'
)::text;
select pg_temp.expect_partner_denied(
  'smoke evidence missing exact fulfillment receipts denied',
  $sql$select partner_onboarding_private.issue_partner_evidence_v1(
    '10000000-0000-4000-8000-0000000000a1', 'smoke_test', repeat('e', 64),
    '{"status":"passed","passed":true,"order_path_passed":true,"local_partner_id":"20000000-0000-4000-8000-0000000000a2","customer_order_receipt_id":"synthetic-customer-order","partner_acceptance_receipt_id":"synthetic-partner-acceptance","driver_receipt_id":"synthetic-driver"}'::jsonb,
    '30000000-0000-4000-8000-000000000059',
    '00000000-0000-4000-8000-000000000105'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'smoke_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'smoke_test', repeat('e', 64),
  '{"status":"passed","passed":true,"order_path_passed":true,"local_partner_id":"20000000-0000-4000-8000-0000000000a2","customer_order_receipt_id":"synthetic-customer-order","partner_acceptance_receipt_id":"synthetic-partner-acceptance","driver_receipt_id":"synthetic-driver","delivery_receipt_id":"synthetic-delivery"}'::jsonb,
  '30000000-0000-4000-8000-000000000054',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'consent_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'partner_consent',
  partner_onboarding_private.partner_preview_sha256('10000000-0000-4000-8000-0000000000a1'),
  '{"status":"approved","approved":true,"review":"synthetic partner consent"}'::jsonb,
  '30000000-0000-4000-8000-000000000055',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'heha_review_evidence', partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'heha_review',
  partner_onboarding_private.partner_preview_sha256('10000000-0000-4000-8000-0000000000a1'),
  '{"status":"approved","approved":true,"review":"synthetic HEHA review"}'::jsonb,
  '30000000-0000-4000-8000-000000000056',
  '00000000-0000-4000-8000-000000000105'
)::text;

do $application_invite_owner_binding$
declare
  v_partner_id uuid := (
    select (value::jsonb ->> 'id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'application_first'
  );
begin
  if not exists (
       select 1 from public.partners partner
       where partner.id = v_partner_id
         and partner.owner_id = '00000000-0000-4000-8000-0000000000c3'
     )
     or (
       select count(*)
       from partner_onboarding_private.partner_invites invitation
       where invitation.partner_id = v_partner_id
     ) <> 1
     or not exists (
       select 1
       from partner_onboarding_private.partner_state state
       where state.partner_id = v_partner_id
         and state.operator_user_id is null
     ) then
    raise exception 'Application invite owner binding or rollback safety mismatch';
  end if;
end;
$application_invite_owner_binding$;

select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_first', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256('10000000-0000-4000-8000-0000000000a1'),
  '30000000-0000-4000-8000-000000000060',
  '00000000-0000-4000-8000-000000000106'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_replay', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256('10000000-0000-4000-8000-0000000000a1'),
  '30000000-0000-4000-8000-000000000060',
  '00000000-0000-4000-8000-000000000106'
)::text;
reset role;

do $release_receipt$
declare
  v_first jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'release_first');
  v_replay jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'release_replay');
begin
  if v_first ->> 'release_receipt_id' is null
     or v_first ->> 'release_receipt_id' <> v_replay ->> 'release_receipt_id'
     or v_first ->> 'receipt_status' <> 'verified'
     or (v_first ->> 'swipe_publication_authorized')::boolean is not true
     or (v_first ->> 'local_orderability_authorized')::boolean is not true
     or (v_first ->> 'public_swipe_visible')::boolean is not false
     or (v_first ->> 'local_orderable')::boolean is not false then
    raise exception 'Release receipt/replay contract mismatch';
  end if;
end;
$release_receipt$;

set local role anon;
select pg_temp.expect_boolean(
  'release alone is not Swipe-visible', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'release alone is not Local-visible', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'capabilities_release_only', public.get_partner_onboarding_capabilities_v1(
  '10000000-0000-4000-8000-0000000000a1'
)::text;
reset role;

do $release_only_capabilities$
declare
  v_cap jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'capabilities_release_only');
begin
  if v_cap #>> '{claim,status}' <> 'verified'
     or v_cap #>> '{agreement,status}' <> 'accepted'
     or v_cap #>> '{profile,status}' <> 'verified'
     or v_cap #>> '{media,status}' <> 'approved'
     or v_cap #>> '{local_profile,status}' <> 'verified'
     or v_cap #>> '{smoke_test,status}' <> 'passed'
     or v_cap #>> '{publication,partner_consent_status}' <> 'approved'
     or v_cap #>> '{publication,heha_review_status}' <> 'approved'
     or (v_cap #>> '{publication,public_swipe_visible}')::boolean is not false
     or (v_cap #>> '{publication,local_orderable}')::boolean is not false then
    raise exception 'Release-only capability projection is not exact/fail-closed';
  end if;
end;
$release_only_capabilities$;

set local role service_role;
select pg_temp.expect_partner_denied(
  'release alone has no Local orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, true, true, true, true, true,
  'proof-surface-switches-enabled',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

set local role service_role;
-- Enabling switches still does not manufacture an activation acknowledgement.
select pg_temp.expect_partner_denied(
  'surface switches alone have no Local receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_activation', partner_onboarding_private.record_partner_surface_activation_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'release_first'),
  'swipe',
  '10000000-0000-4000-8000-0000000000a1',
  'synthetic-swipe-ack-001',
  pg_catalog.jsonb_build_object(
    'activated', true,
    'release_receipt_id', (select value::jsonb ->> 'release_receipt_id' from pg_temp.partner_onboarding_proof_state where key = 'release_first'),
    'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
    'target_receipt_id', 'synthetic-swipe-ack-001',
    'surface', 'swipe',
    'environment', 'test',
    'attestation_version', 'heha-target-activation-v1',
    'target_system', 'heha-swipe',
    'attested_by', '00000000-0000-4000-8000-000000000101'
  ),
  '30000000-0000-4000-8000-000000000061',
  '00000000-0000-4000-8000-000000000101'
)::text;
reset role;

set local role anon;
select pg_temp.expect_boolean(
  'Swipe activation makes only Swipe visible', true,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'Swipe activation cannot make Local orderable', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'capabilities_swipe_only', public.get_partner_onboarding_capabilities_v1(
  '10000000-0000-4000-8000-0000000000a1'
)::text;
select pg_temp.expect_sqlstate(
  'orderability receipt is not browser executable', '42501',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

do $swipe_only_capabilities$
declare
  v_cap jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'capabilities_swipe_only');
begin
  if (v_cap #>> '{publication,public_swipe_visible}')::boolean is not true
     or (v_cap #>> '{publication,local_orderable}')::boolean is not false then
    raise exception 'Swipe-only capability booleans mismatch';
  end if;
end;
$swipe_only_capabilities$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_activation', partner_onboarding_private.record_partner_surface_activation_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid from pg_temp.partner_onboarding_proof_state where key = 'release_first'),
  'local_orderability',
  '20000000-0000-4000-8000-0000000000a2',
  'synthetic-local-order-guard-ack-001',
  pg_catalog.jsonb_build_object(
    'activated', true,
    'release_receipt_id', (select value::jsonb ->> 'release_receipt_id' from pg_temp.partner_onboarding_proof_state where key = 'release_first'),
    'target_partner_id', '20000000-0000-4000-8000-0000000000a2',
    'target_receipt_id', 'synthetic-local-order-guard-ack-001',
    'surface', 'local_orderability',
    'environment', 'test',
    'attestation_version', 'heha-target-activation-v1',
    'target_system', 'heha-local',
    'attested_by', '00000000-0000-4000-8000-000000000103'
  ),
  '30000000-0000-4000-8000-000000000062',
  '00000000-0000-4000-8000-000000000103'
)::text;
reset role;

set local role service_role;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'orderability_receipt', public.get_partner_orderability_receipt_v1(
  '20000000-0000-4000-8000-0000000000a2'
)::text;
reset role;

do $separate_surface_receipts$
declare
  v_release jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'release_first');
  v_swipe jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'swipe_activation');
  v_local jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'local_activation');
  v_orderability jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'orderability_receipt');
begin
  if v_release ->> 'release_receipt_id' is null
     or v_swipe ->> 'activation_receipt_id' is null
     or v_local ->> 'activation_receipt_id' is null
     or v_swipe ->> 'activation_receipt_id' = v_local ->> 'activation_receipt_id'
     or v_swipe ->> 'surface' <> 'swipe'
     or v_local ->> 'surface' <> 'local_orderability'
     or v_orderability ->> 'activation_receipt_id' <> v_local ->> 'activation_receipt_id'
     or v_orderability ->> 'release_receipt_id' <> v_release ->> 'release_receipt_id'
     or v_orderability ->> 'swipe_partner_id' <> '10000000-0000-4000-8000-0000000000a1'
     or v_orderability ->> 'local_partner_id' <> '20000000-0000-4000-8000-0000000000a2'
     or v_orderability ->> 'target_receipt_id' <> 'synthetic-local-order-guard-ack-001'
     or (v_orderability ->> 'local_orderable')::boolean is not true then
    raise exception 'Release/Swipe/Local receipt separation mismatch';
  end if;
end;
$separate_surface_receipts$;

set local role anon;
select pg_temp.expect_boolean(
  'Swipe view exposes released Swipe snapshot', true,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'Local view requires and now has Local receipt', true,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'capabilities_both_surfaces', public.get_partner_onboarding_capabilities_v1(
  '10000000-0000-4000-8000-0000000000a1'
)::text;
reset role;

do $both_surface_capabilities$
declare
  v_cap jsonb := (select value::jsonb from pg_temp.partner_onboarding_proof_state where key = 'capabilities_both_surfaces');
begin
  if (v_cap #>> '{publication,public_swipe_visible}')::boolean is not true
     or (v_cap #>> '{publication,local_orderable}')::boolean is not true then
    raise exception 'Activated capability booleans mismatch';
  end if;
end;
$both_surface_capabilities$;

-- ---------------------------------------------------------------------------
-- Runtime/current-receipt locking and release revocation while runtime is off.
-- ---------------------------------------------------------------------------

do $runtime_and_current_receipts$
declare
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_first'
  );
  v_swipe uuid := (
    select (value::jsonb ->> 'activation_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'swipe_activation'
  );
  v_local uuid := (
    select (value::jsonb ->> 'activation_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'local_activation'
  );
begin
  if not exists (
    select 1
    from partner_onboarding_private.runtime_config runtime
    where runtime.singleton
      and runtime.environment = 'test'
      and runtime.config_version = 'proof-surface-switches-enabled'
      and runtime.claim_enabled
      and runtime.application_enabled
      and runtime.acceptance_enabled
      and runtime.release_enabled
      and runtime.swipe_publication_enabled
      and runtime.local_ordering_enabled
  )
     or partner_onboarding_private.epoch_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_release
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_release
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'swipe'
     ) is distinct from v_swipe
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'local_orderability'
     ) is distinct from v_local
     or (
       select count(*)
       from partner_onboarding_private.partner_surface_activation_receipts activation
       where activation.partner_id = '10000000-0000-4000-8000-0000000000a1'
         and activation.surface = 'local_orderability'
         and activation.target_partner_id = '20000000-0000-4000-8000-0000000000a2'
         and activation.id = partner_onboarding_private.surface_activation_receipt_id_v1(
           activation.partner_id, activation.surface
         )
     ) <> 1 then
    raise exception 'Runtime version/current release and exact Local mapping mismatch';
  end if;
end;
$runtime_and_current_receipts$;

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_before_kill_switch', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
-- KILL_SWITCH_BARE_DISABLE
select partner_onboarding_private.set_runtime_config_v1(
  true, true, true, false, false, false,
  'proof-bare-kill-switch-off',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

do $kill_switch_off_invalidates_generation$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_kill_switch'
  );
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_first'
  );
  v_swipe uuid := (
    select (value::jsonb ->> 'activation_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'swipe_activation'
  );
  v_local uuid := (
    select (value::jsonb ->> 'activation_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'local_activation'
  );
begin
  if (
       select release_epoch from partner_onboarding_private.partner_state
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> v_before + 1
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.epoch_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'swipe'
     ) is not null
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'local_orderability'
     ) is not null
     or public.partner_card_is_current_v1(
       '10000000-0000-4000-8000-0000000000a1', 'swipe', v_release, v_swipe
     )
     or public.partner_card_is_current_v1(
       '10000000-0000-4000-8000-0000000000a1', 'local_orderability', v_release, v_local
     ) then
    raise exception 'Bare kill switch failed to invalidate release generation';
  end if;
end;
$kill_switch_off_invalidates_generation$;

set local role anon;
select pg_temp.expect_boolean(
  'kill switch hides Swipe without revocation', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'kill switch hides Local without revocation', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role service_role;
select pg_temp.expect_partner_denied(
  'kill switch hides Local orderability without revocation',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
select partner_onboarding_private.set_runtime_config_v1(
  true, true, true, true, true, true,
  'proof-bare-kill-switch-reenabled',
  '00000000-0000-4000-8000-0000000000e5'
);
reset role;

-- KILL_SWITCH_BARE_REENABLE_NO_RESURRECTION
do $kill_switch_bare_reenable_no_resurrection$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_kill_switch'
  );
  v_old_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_first'
  );
begin
  if (
       select release_epoch from partner_onboarding_private.partner_state
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> v_before + 1
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.epoch_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'swipe'
     ) is not null
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'local_orderability'
     ) is not null
     or (
       select count(*)
       from public.partner_public_cards_v1 stale_card
       where stale_card.partner_id = '10000000-0000-4000-8000-0000000000a1'
         and stale_card.release_receipt_id = v_old_release
     ) <> 2 then
    raise exception 'Bare re-enable resurrected stale release or activation receipts';
  end if;
end;
$kill_switch_bare_reenable_no_resurrection$;

set local role anon;
select pg_temp.expect_boolean(
  'bare re-enable does not resurrect Swipe', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'bare re-enable does not resurrect Local', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role service_role;
select pg_temp.expect_partner_denied(
  'bare re-enable does not resurrect an orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'release request replay after kill-switch invalidation denied generically',
  $sql$select partner_onboarding_private.finalize_partner_release_v1(
    '10000000-0000-4000-8000-0000000000a1',
    partner_onboarding_private.partner_preview_sha256(
      '10000000-0000-4000-8000-0000000000a1'
    ),
    '30000000-0000-4000-8000-000000000060',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_second', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '30000000-0000-4000-8000-000000000063',
  '00000000-0000-4000-8000-000000000106'
)::text;
reset role;

-- ---------------------------------------------------------------------------
-- Exact activation attestations, distinct attestors, collision, and atomic
-- surface revocation. A successor release may reuse a historical target only
-- after the prior release has been invalidated.
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
select pg_temp.expect_partner_denied(
  'missing activation environment denied generically',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'swipe', '10000000-0000-4000-8000-0000000000a1',
    'synthetic-swipe-ack-missing-key',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
      'target_receipt_id', 'synthetic-swipe-ack-missing-key',
      'surface', 'swipe',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-swipe',
      'attested_by', '00000000-0000-4000-8000-000000000101'
    ),
    '30000000-0000-4000-8000-000000000064',
    '00000000-0000-4000-8000-000000000101'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'release reviewer alone cannot attest Swipe',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'swipe', '10000000-0000-4000-8000-0000000000a1',
    'synthetic-release-reviewer-swipe-ack',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
      'target_receipt_id', 'synthetic-release-reviewer-swipe-ack',
      'surface', 'swipe', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-swipe',
      'attested_by', '00000000-0000-4000-8000-000000000106'
    ),
    '30000000-0000-4000-8000-000000000065',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true
);
select pg_temp.expect_partner_denied(
  'website attestor cannot attest Swipe',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'swipe', '10000000-0000-4000-8000-0000000000a1',
    'synthetic-website-wrong-swipe-ack',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
      'target_receipt_id', 'synthetic-website-wrong-swipe-ack',
      'surface', 'swipe', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-swipe',
      'attested_by', '00000000-0000-4000-8000-000000000102'
    ),
    '30000000-0000-4000-8000-000000000066',
    '00000000-0000-4000-8000-000000000102'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
select pg_temp.expect_partner_denied(
  'Local attestor cannot attest Swipe',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'swipe', '10000000-0000-4000-8000-0000000000a1',
    'synthetic-local-wrong-swipe-ack',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
      'target_receipt_id', 'synthetic-local-wrong-swipe-ack',
      'surface', 'swipe', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-swipe',
      'attested_by', '00000000-0000-4000-8000-000000000103'
    ),
    '30000000-0000-4000-8000-000000000067',
    '00000000-0000-4000-8000-000000000103'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
select pg_temp.expect_partner_denied(
  'historical Swipe target receipt cannot be reused',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'swipe', '10000000-0000-4000-8000-0000000000a1',
    'synthetic-swipe-ack-001',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
      'target_receipt_id', 'synthetic-swipe-ack-001',
      'surface', 'swipe', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-swipe',
      'attested_by', '00000000-0000-4000-8000-000000000101'
    ),
    '30000000-0000-4000-8000-000000000068',
    '00000000-0000-4000-8000-000000000101'
  )$sql$
);

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_activation_second',
       partner_onboarding_private.record_partner_surface_activation_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
  'swipe', '10000000-0000-4000-8000-0000000000a1',
  'synthetic-swipe-ack-002',
  pg_catalog.jsonb_build_object(
    'activated', true,
    'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
      from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'target_partner_id', '10000000-0000-4000-8000-0000000000a1',
    'target_receipt_id', 'synthetic-swipe-ack-002',
    'surface', 'swipe', 'environment', 'test',
    'attestation_version', 'heha-target-activation-v1',
    'target_system', 'heha-swipe',
    'attested_by', '00000000-0000-4000-8000-000000000101'
  ),
  '30000000-0000-4000-8000-000000000069',
  '00000000-0000-4000-8000-000000000101'
)::text;

select pg_temp.expect_partner_denied(
  'Swipe attestor cannot attest Local',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'local_orderability', '20000000-0000-4000-8000-0000000000a2',
    'synthetic-swipe-wrong-local-ack',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '20000000-0000-4000-8000-0000000000a2',
      'target_receipt_id', 'synthetic-swipe-wrong-local-ack',
      'surface', 'local_orderability', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-local',
      'attested_by', '00000000-0000-4000-8000-000000000101'
    ),
    '30000000-0000-4000-8000-000000000070',
    '00000000-0000-4000-8000-000000000101'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true
);
select pg_temp.expect_partner_denied(
  'website attestor cannot attest Local',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'local_orderability', '20000000-0000-4000-8000-0000000000a2',
    'synthetic-website-wrong-local-ack',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '20000000-0000-4000-8000-0000000000a2',
      'target_receipt_id', 'synthetic-website-wrong-local-ack',
      'surface', 'local_orderability', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-local',
      'attested_by', '00000000-0000-4000-8000-000000000102'
    ),
    '30000000-0000-4000-8000-000000000071',
    '00000000-0000-4000-8000-000000000102'
  )$sql$
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_activation_second',
       partner_onboarding_private.record_partner_surface_activation_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
  'local_orderability', '20000000-0000-4000-8000-0000000000a2',
  'synthetic-local-order-guard-ack-002',
  pg_catalog.jsonb_build_object(
    'activated', true,
    'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
      from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'target_partner_id', '20000000-0000-4000-8000-0000000000a2',
    'target_receipt_id', 'synthetic-local-order-guard-ack-002',
    'surface', 'local_orderability', 'environment', 'test',
    'attestation_version', 'heha-target-activation-v1',
    'target_system', 'heha-local',
    'attested_by', '00000000-0000-4000-8000-000000000103'
  ),
  '30000000-0000-4000-8000-000000000072',
  '00000000-0000-4000-8000-000000000103'
)::text;
select pg_temp.expect_partner_denied(
  'duplicate current Local target mapping denied',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'local_orderability', '20000000-0000-4000-8000-0000000000a2',
    'synthetic-local-order-guard-ack-collision',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '20000000-0000-4000-8000-0000000000a2',
      'target_receipt_id', 'synthetic-local-order-guard-ack-collision',
      'surface', 'local_orderability', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-local',
      'attested_by', '00000000-0000-4000-8000-000000000103'
    ),
    '30000000-0000-4000-8000-000000000073',
    '00000000-0000-4000-8000-000000000103'
  )$sql$
);

reset role;
set local role service_role;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'kill_switch_recovery_orderability',
       public.get_partner_orderability_receipt_v1(
  '20000000-0000-4000-8000-0000000000a2'
)::text;
reset role;

-- KILL_SWITCH_FRESH_GENERATION_RECOVERY
do $kill_switch_fresh_generation_recovery$
declare
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_second'
  );
  v_old_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_first'
  );
  v_swipe uuid := (
    select (value::jsonb ->> 'activation_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'swipe_activation_second'
  );
  v_local uuid := (
    select (value::jsonb ->> 'activation_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'local_activation_second'
  );
  v_orderability jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'kill_switch_recovery_orderability'
  );
begin
  if v_release is null
     or v_release = v_old_release
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_release
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'swipe'
     ) is distinct from v_swipe
     or partner_onboarding_private.surface_activation_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'local_orderability'
     ) is distinct from v_local
     or (v_orderability ->> 'release_receipt_id')::uuid is distinct from v_release
     or (v_orderability ->> 'activation_receipt_id')::uuid is distinct from v_local
     or v_orderability ->> 'local_partner_id'
          <> '20000000-0000-4000-8000-0000000000a2' then
    raise exception 'Fresh post-kill-switch generation did not restore exact receipts';
  end if;
end;
$kill_switch_fresh_generation_recovery$;

-- Replaying the already revoked first release is harmless and cannot delete
-- the successor cards.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select partner_onboarding_private.revoke_partner_release_v1(
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_first'),
  '00000000-0000-4000-8000-000000000106',
  'synthetic_stale_release_replay'
);
reset role;

do $successor_cards_survive_stale_revoke$
declare
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_second'
  );
begin
  if (
       select count(*) from public.partner_public_cards_v1
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
         and release_receipt_id = v_release
     ) <> 2
     or (
       select count(*)
       from partner_onboarding_private.partner_surface_activation_receipts activation
       where activation.release_receipt_id = v_release
         and activation.id = partner_onboarding_private.surface_activation_receipt_id_v1(
           activation.partner_id, activation.surface
         )
     ) <> 2 then
    raise exception 'Stale release replay deleted or duplicated successor cards';
  end if;
end;
$successor_cards_survive_stale_revoke$;

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_before_surface_revocation', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
select partner_onboarding_private.revoke_partner_surface_activation_v1(
  (select (value::jsonb ->> 'activation_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'local_activation_second'),
  '00000000-0000-4000-8000-000000000103',
  'synthetic_atomic_surface_revocation'
);
select pg_temp.expect_partner_denied(
  'activation request replay after surface revocation denied',
  $sql$select partner_onboarding_private.record_partner_surface_activation_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
    'local_orderability', '20000000-0000-4000-8000-0000000000a2',
    'synthetic-local-order-guard-ack-002',
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', (select value::jsonb ->> 'release_receipt_id'
        from pg_temp.partner_onboarding_proof_state where key = 'release_second'),
      'target_partner_id', '20000000-0000-4000-8000-0000000000a2',
      'target_receipt_id', 'synthetic-local-order-guard-ack-002',
      'surface', 'local_orderability', 'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', 'heha-local',
      'attested_by', '00000000-0000-4000-8000-000000000103'
    ),
    '30000000-0000-4000-8000-000000000072',
    '00000000-0000-4000-8000-000000000103'
  )$sql$
);
reset role;

set local role service_role;
select pg_temp.expect_partner_denied(
  'surface revocation removes Local orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

do $atomic_surface_revocation$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_surface_revocation'
  );
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_second'
  );
begin
  if (
       select release_epoch from partner_onboarding_private.partner_state
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> v_before + 1
     or not exists (
       select 1 from partner_onboarding_private.partner_release_revocations
       where release_receipt_id = v_release
     )
     or exists (
       select 1 from public.partner_public_cards_v1
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     )
     or exists (
       select 1 from public.public_swipe_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     )
     or exists (
       select 1 from public.public_local_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     )
     or not exists (
       select 1 from public.partners
       where id = '10000000-0000-4000-8000-0000000000a1'
         and status = 'paused'
         and heha_partner is false
         and swipe_eligible is false
         and website_eligible is false
         and local_eligible is false
     ) then
    raise exception 'Surface revocation did not invalidate the whole release atomically';
  end if;
end;
$atomic_surface_revocation$;

create or replace function pg_temp.record_synthetic_activation(
  p_partner_id uuid,
  p_release_receipt_id uuid,
  p_surface text,
  p_target_partner_id uuid,
  p_target_receipt_id text,
  p_request_key uuid,
  p_activated_by uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select partner_onboarding_private.record_partner_surface_activation_v1(
    p_partner_id,
    p_release_receipt_id,
    p_surface,
    p_target_partner_id,
    p_target_receipt_id,
    pg_catalog.jsonb_build_object(
      'activated', true,
      'release_receipt_id', p_release_receipt_id,
      'target_partner_id', p_target_partner_id,
      'target_receipt_id', p_target_receipt_id,
      'surface', p_surface,
      'environment', 'test',
      'attestation_version', 'heha-target-activation-v1',
      'target_system', case p_surface
        when 'swipe' then 'heha-swipe'
        when 'website' then 'heha-website'
        when 'local_orderability' then 'heha-local'
      end,
      'attested_by', p_activated_by
    ),
    p_request_key,
    p_activated_by
  );
$function$;

grant execute on function pg_temp.record_synthetic_activation(
  uuid, uuid, text, uuid, text, uuid, uuid
) to authenticated;

-- A fresh release after atomic surface revocation may activate the same target
-- identities with new immutable target receipts.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_third', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '30000000-0000-4000-8000-000000000074',
  '00000000-0000-4000-8000-000000000106'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_activation_third', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_third'),
  'swipe', '10000000-0000-4000-8000-0000000000a1',
  'synthetic-swipe-ack-003',
  '30000000-0000-4000-8000-000000000075',
  '00000000-0000-4000-8000-000000000101'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_activation_third', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_third'),
  'local_orderability', '20000000-0000-4000-8000-0000000000a2',
  'synthetic-local-order-guard-ack-003',
  '30000000-0000-4000-8000-000000000076',
  '00000000-0000-4000-8000-000000000103'
)::text;
reset role;

set local role service_role;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'orderability_receipt_third', public.get_partner_orderability_receipt_v1(
  '20000000-0000-4000-8000-0000000000a2'
)::text;
reset role;

do $historical_target_reuse$
declare
  v_release jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'release_third'
  );
  v_swipe jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'swipe_activation_third'
  );
  v_local jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'local_activation_third'
  );
  v_order jsonb := (
    select value::jsonb from pg_temp.partner_onboarding_proof_state
    where key = 'orderability_receipt_third'
  );
begin
  if v_swipe ->> 'release_receipt_id' <> v_release ->> 'release_receipt_id'
     or v_local ->> 'release_receipt_id' <> v_release ->> 'release_receipt_id'
     or v_swipe ->> 'target_partner_id' <>
       '10000000-0000-4000-8000-0000000000a1'
     or v_local ->> 'target_partner_id' <>
       '20000000-0000-4000-8000-0000000000a2'
     or v_swipe ->> 'target_receipt_id' <> 'synthetic-swipe-ack-003'
     or v_local ->> 'target_receipt_id' <>
       'synthetic-local-order-guard-ack-003'
     or v_order ->> 'swipe_partner_id' <>
       '10000000-0000-4000-8000-0000000000a1'
     or v_order ->> 'local_partner_id' <>
       '20000000-0000-4000-8000-0000000000a2'
     or not exists (
       select 1 from public.public_swipe_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     )
     or not exists (
       select 1 from public.public_local_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     ) then
    raise exception 'Successor release did not safely reuse historical target identities';
  end if;
end;
$historical_target_reuse$;

-- A watched source-profile change invalidates the current epoch, deletes every
-- public card, pauses operational flags, and requires current profile/preview
-- evidence before a new release can be created.
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_before_profile_change', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';

update public.partners
set name = 'Synthetic Main Kitchen Reviewed Successor'
where id = '10000000-0000-4000-8000-0000000000a1';

do $profile_change_invalidation$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_profile_change'
  );
begin
  if (
       select release_epoch from partner_onboarding_private.partner_state
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> v_before + 1
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.epoch_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or exists (
       select 1 from public.partner_public_cards_v1
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     )
     or exists (
       select 1 from public.public_swipe_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     )
     or exists (
       select 1 from public.public_local_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     )
     or not exists (
       select 1 from public.partners
       where id = '10000000-0000-4000-8000-0000000000a1'
         and name = 'Synthetic Main Kitchen Reviewed Successor'
         and status = 'paused'
         and heha_partner is false
         and website_eligible is false
         and swipe_eligible is false
         and local_eligible is false
     ) then
    raise exception 'Reviewed-profile invalidation trigger failed closed-state contract';
  end if;
end;
$profile_change_invalidation$;

set local role service_role;
select pg_temp.expect_partner_denied(
  'profile change invalidates Local orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'profile_evidence_after_change',
       partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'profile',
  partner_onboarding_private.partner_profile_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '{"status":"verified","review":"synthetic successor profile"}'::jsonb,
  '30000000-0000-4000-8000-000000000077',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'consent_evidence_after_change',
       partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'partner_consent',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '{"status":"approved","approved":true,"review":"synthetic successor consent"}'::jsonb,
  '30000000-0000-4000-8000-000000000078',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'heha_review_evidence_after_change',
       partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'heha_review',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '{"status":"approved","approved":true,"review":"synthetic successor HEHA review"}'::jsonb,
  '30000000-0000-4000-8000-000000000079',
  '00000000-0000-4000-8000-000000000105'
)::text;

select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_fourth', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '30000000-0000-4000-8000-000000000080',
  '00000000-0000-4000-8000-000000000106'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_activation_fourth', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_fourth'),
  'swipe', '10000000-0000-4000-8000-0000000000a1',
  'synthetic-swipe-ack-004',
  '30000000-0000-4000-8000-000000000081',
  '00000000-0000-4000-8000-000000000101'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_activation_fourth', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_fourth'),
  'local_orderability', '20000000-0000-4000-8000-0000000000a2',
  'synthetic-local-order-guard-ack-004',
  '30000000-0000-4000-8000-000000000082',
  '00000000-0000-4000-8000-000000000103'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'stale unrevoked release cannot revoke current successor cards',
  $sql$select partner_onboarding_private.revoke_partner_release_v1(
    (select (value::jsonb ->> 'release_receipt_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'release_third'),
    '00000000-0000-4000-8000-000000000106',
    'synthetic_stale_unrevoked_release'
  )$sql$
);
reset role;

do $stale_revoke_preserves_current_cards$
declare
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_fourth'
  );
begin
  if (
       select count(*) from public.partner_public_cards_v1
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
         and release_receipt_id = v_release
     ) <> 2
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_release then
    raise exception 'Stale release revocation disturbed the current successor';
  end if;
end;
$stale_revoke_preserves_current_cards$;

-- Newer evidence invalidates the release exactly once. Revoking that newest
-- evidence cannot resurrect the older receipt; a third receipt is required.
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_before_newer_evidence', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'compliance_evidence_second',
       partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'compliance', repeat('f', 64),
  '{"status":"verified","review":"synthetic compliance successor two"}'::jsonb,
  '30000000-0000-4000-8000-000000000083',
  '00000000-0000-4000-8000-000000000105'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'compliance_evidence_second_replay',
       partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'compliance', repeat('f', 64),
  '{"review":"synthetic compliance successor two","status":"verified"}'::jsonb,
  '30000000-0000-4000-8000-000000000083',
  '00000000-0000-4000-8000-000000000105'
)::text;
reset role;

set local role service_role;
select pg_temp.expect_partner_denied(
  'newer evidence invalidates old Local orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

do $newer_evidence_invalidates_once$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_newer_evidence'
  );
begin
  if (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'compliance_evidence_second'
     ) is distinct from (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'compliance_evidence_second_replay'
     )
     or (
       select release_epoch from partner_onboarding_private.partner_state
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> v_before + 1
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null then
    raise exception 'New evidence replay bumped twice or left old release public';
  end if;
end;
$newer_evidence_invalidates_once$;

set local role anon;
select pg_temp.expect_boolean(
  'newer evidence hides stale Swipe card from anonymous readers', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'newer evidence hides stale Local card from anonymous readers', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'compliance_evidence_second_revocation',
       partner_onboarding_private.revoke_partner_evidence_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'compliance_evidence_second'),
  '00000000-0000-4000-8000-000000000105',
  'synthetic_latest_evidence_revocation'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'revoked newest evidence cannot release by falling back',
  $sql$select partner_onboarding_private.finalize_partner_release_v1(
    '10000000-0000-4000-8000-0000000000a1',
    partner_onboarding_private.partner_preview_sha256(
      '10000000-0000-4000-8000-0000000000a1'
    ),
    '30000000-0000-4000-8000-000000000084',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
reset role;

do $latest_evidence_no_resurrection$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_newer_evidence'
  );
begin
  if partner_onboarding_private.current_evidence_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'compliance'
     ) is not null
     or (
       select release_epoch from partner_onboarding_private.partner_state
       where partner_id = '10000000-0000-4000-8000-0000000000a1'
     ) <> v_before + 2 then
    raise exception 'Revoked latest evidence resurrected an older receipt';
  end if;
end;
$latest_evidence_no_resurrection$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'compliance_evidence_third',
       partner_onboarding_private.issue_partner_evidence_v1(
  '10000000-0000-4000-8000-0000000000a1', 'compliance', repeat('9', 64),
  '{"status":"verified","review":"synthetic compliance successor three"}'::jsonb,
  '30000000-0000-4000-8000-000000000085',
  '00000000-0000-4000-8000-000000000105'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_fifth', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '30000000-0000-4000-8000-000000000086',
  '00000000-0000-4000-8000-000000000106'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_activation_fifth', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_fifth'),
  'swipe', '10000000-0000-4000-8000-0000000000a1',
  'synthetic-swipe-ack-005',
  '30000000-0000-4000-8000-000000000087',
  '00000000-0000-4000-8000-000000000101'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_activation_fifth', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_fifth'),
  'local_orderability', '20000000-0000-4000-8000-0000000000a2',
  'synthetic-local-order-guard-ack-005',
  '30000000-0000-4000-8000-000000000088',
  '00000000-0000-4000-8000-000000000103'
)::text;
reset role;

do $fresh_evidence_restores_release$
declare
  v_evidence uuid := (
    select value::uuid from pg_temp.partner_onboarding_proof_state
    where key = 'compliance_evidence_third'
  );
  v_release uuid := (
    select (value::jsonb ->> 'release_receipt_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'release_fifth'
  );
begin
  if partner_onboarding_private.current_evidence_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1', 'compliance'
     ) is distinct from v_evidence
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_release
     or not exists (
       select 1 from public.public_swipe_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     )
     or not exists (
       select 1 from public.public_local_partners
       where id = '10000000-0000-4000-8000-0000000000a1'
     ) then
    raise exception 'Fresh evidence did not restore a current activated release';
  end if;
end;
$fresh_evidence_restores_release$;

-- ---------------------------------------------------------------------------
-- Agreement-version selection is monotonic: a switch invalidates the release,
-- same-version replay preserves selected_at, and reselecting an old version
-- cannot resurrect its pre-selection acceptance.
-- ---------------------------------------------------------------------------

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_before_agreement_change', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'agreement_version_second',
       partner_onboarding_private.register_partner_agreement_version_v1(
  'restaurant',
  'restaurant-synthetic-v2',
  'Synthetic Restaurant Agreement Successor',
  pg_catalog.clock_timestamp() - interval '1 hour',
  'SYNTHETIC SUCCESSOR DOCUMENT -- NO LEGAL EFFECT',
  partner_onboarding_private.sha256_text(
    'SYNTHETIC SUCCESSOR DOCUMENT -- NO LEGAL EFFECT'
  ),
  'I agree to the synthetic successor terms.',
  '{"privacy":"synthetic-v2","fees":"synthetic-v2"}'::jsonb,
  'SYNTHETIC-LEGAL-REVIEW-SUCCESSOR',
  '00000000-0000-4000-8000-000000000104',
  pg_catalog.clock_timestamp() - interval '2 hours'
)::text;
select partner_onboarding_private.select_partner_agreement_version_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'agreement_version_second'),
  '00000000-0000-4000-8000-000000000104'
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_after_agreement_v2', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'selected_at_agreement_v2', selected_at::text
from partner_onboarding_private.current_agreement_versions
where legal_relationship_type = 'restaurant';

select partner_onboarding_private.select_partner_agreement_version_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'agreement_version_second'),
  '00000000-0000-4000-8000-000000000104'
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_after_agreement_v2_replay', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'selected_at_agreement_v2_replay', selected_at::text
from partner_onboarding_private.current_agreement_versions
where legal_relationship_type = 'restaurant';

select partner_onboarding_private.select_partner_agreement_version_v1(
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'agreement_version'),
  '00000000-0000-4000-8000-000000000104'
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'epoch_after_agreement_v1_reselection', release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';
reset role;

do $agreement_selection_monotonicity$
declare
  v_before bigint := (
    select value::bigint from pg_temp.partner_onboarding_proof_state
    where key = 'epoch_before_agreement_change'
  );
begin
  if (
       select value::bigint from pg_temp.partner_onboarding_proof_state
       where key = 'epoch_after_agreement_v2'
     ) <> v_before + 1
     or (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'epoch_after_agreement_v2_replay'
     ) is distinct from (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'epoch_after_agreement_v2'
     )
     or (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'selected_at_agreement_v2_replay'
     ) is distinct from (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'selected_at_agreement_v2'
     )
     or (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'epoch_after_agreement_v1_reselection'
     ) is distinct from (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'epoch_after_agreement_v2'
     )
     or partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null then
    raise exception 'Agreement selection replay or stale-acceptance resurrection mismatch';
  end if;
end;
$agreement_selection_monotonicity$;

set local role anon;
select pg_temp.expect_boolean(
  'agreement version change hides stale Swipe card', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'agreement version change hides stale Local card', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
select pg_temp.expect_partner_denied(
  'reselected v1 cannot release on stale v1 acceptance',
  $sql$select partner_onboarding_private.finalize_partner_release_v1(
    '10000000-0000-4000-8000-0000000000a1',
    partner_onboarding_private.partner_preview_sha256(
      '10000000-0000-4000-8000-0000000000a1'
    ),
    '30000000-0000-4000-8000-000000000089',
    '00000000-0000-4000-8000-000000000106'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_fresh_v1',
       public.record_category_partner_agreement_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'agreement_version'),
  partner_onboarding_private.sha256_text(
    'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'
  ),
  '30000000-0000-4000-8000-000000000090',
  '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer D","signer_title":"Authorized Representative","typed_signature":"Signer D"}'::jsonb
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_fresh_v1_replay',
       public.record_category_partner_agreement_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'agreement_version'),
  partner_onboarding_private.sha256_text(
    'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'
  ),
  '30000000-0000-4000-8000-000000000090',
  '{"typed_signature":"Signer D","signer_title":"Authorized Representative","assent_text":"I agree to the synthetic terms.","signer_legal_name":"Signer D","assertions_version":"heha-partner-acceptance-v1","electronic_records_consent":true,"signer_authority_confirmed":true,"reviewed_complete_agreement":true}'::jsonb
)::text;
select pg_temp.expect_partner_denied(
  'second fresh acceptance request denied once v1 is current',
  $sql$select public.record_category_partner_agreement_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select value::uuid from pg_temp.partner_onboarding_proof_state
     where key = 'agreement_version'),
    partner_onboarding_private.sha256_text(
      'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'
    ),
    '30000000-0000-4000-8000-000000000091',
    '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer D","signer_title":"Authorized Representative","typed_signature":"Signer D"}'::jsonb
  )$sql$
);
reset role;

do $fresh_acceptance_required$
declare
  v_original uuid := (
    select (value::jsonb ->> 'acceptance_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'acceptance_first'
  );
  v_fresh uuid := (
    select (value::jsonb ->> 'acceptance_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'acceptance_fresh_v1'
  );
  v_replay uuid := (
    select (value::jsonb ->> 'acceptance_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'acceptance_fresh_v1_replay'
  );
begin
  if v_fresh is null
     or v_fresh = v_original
     or v_fresh is distinct from v_replay
     or partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_fresh then
    raise exception 'Fresh acceptance did not restore the reselected version exactly once';
  end if;
end;
$fresh_acceptance_required$;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000106', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'release_sixth', partner_onboarding_private.finalize_partner_release_v1(
  '10000000-0000-4000-8000-0000000000a1',
  partner_onboarding_private.partner_preview_sha256(
    '10000000-0000-4000-8000-0000000000a1'
  ),
  '30000000-0000-4000-8000-000000000092',
  '00000000-0000-4000-8000-000000000106'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'swipe_activation_sixth', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_sixth'),
  'swipe', '10000000-0000-4000-8000-0000000000a1',
  'synthetic-swipe-ack-006',
  '30000000-0000-4000-8000-000000000093',
  '00000000-0000-4000-8000-000000000101'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'local_activation_sixth', pg_temp.record_synthetic_activation(
  '10000000-0000-4000-8000-0000000000a1',
  (select (value::jsonb ->> 'release_receipt_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'release_sixth'),
  'local_orderability', '20000000-0000-4000-8000-0000000000a2',
  'synthetic-local-order-guard-ack-006',
  '30000000-0000-4000-8000-000000000094',
  '00000000-0000-4000-8000-000000000103'
)::text;
reset role;

-- ---------------------------------------------------------------------------
-- Legal acceptance revocation resets the relationship. Replays of stale claim,
-- acceptance, and evidence receipts cannot resurrect it; recovery requires a
-- new invitation, claim, relationship-epoch signer grant, and acceptance.
-- ---------------------------------------------------------------------------

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'state_before_acceptance_revocation',
       relationship_epoch::text || ':' || claim_epoch::text || ':' || release_epoch::text
from partner_onboarding_private.partner_state
where partner_id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d4', true
);
select pg_temp.expect_partner_denied(
  'non-legal actor cannot revoke an agreement acceptance',
  $sql$select partner_onboarding_private.revoke_partner_agreement_acceptance_v1(
    (select (value::jsonb ->> 'acceptance_id')::uuid
     from pg_temp.partner_onboarding_proof_state where key = 'acceptance_fresh_v1'),
    '00000000-0000-4000-8000-0000000000d4',
    'synthetic_unauthorized_acceptance_revocation'
  )$sql$
);
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_revocation_first',
       partner_onboarding_private.revoke_partner_agreement_acceptance_v1(
  (select (value::jsonb ->> 'acceptance_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'acceptance_fresh_v1'),
  '00000000-0000-4000-8000-000000000104',
  'synthetic_legal_acceptance_revocation'
)::text;
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'acceptance_revocation_replay',
       partner_onboarding_private.revoke_partner_agreement_acceptance_v1(
  (select (value::jsonb ->> 'acceptance_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'acceptance_fresh_v1'),
  '00000000-0000-4000-8000-000000000104',
  'synthetic_legal_acceptance_revocation'
)::text;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000105', true
);
select pg_temp.expect_partner_denied(
  'relationship-stale evidence request replay denied',
  $sql$select partner_onboarding_private.issue_partner_evidence_v1(
    '10000000-0000-4000-8000-0000000000a1', 'compliance', repeat('9', 64),
    '{"status":"verified","review":"synthetic compliance successor three"}'::jsonb,
    '30000000-0000-4000-8000-000000000085',
    '00000000-0000-4000-8000-000000000105'
  )$sql$
);
reset role;

set local role service_role;
select pg_temp.expect_partner_denied(
  'acceptance revocation removes Local orderability receipt',
  $sql$select public.get_partner_orderability_receipt_v1(
    '20000000-0000-4000-8000-0000000000a2'
  )$sql$
);
reset role;

do $acceptance_revocation_fail_closed$
declare
  v_before text[] := pg_catalog.string_to_array(
    (select value from pg_temp.partner_onboarding_proof_state
     where key = 'state_before_acceptance_revocation'),
    ':'
  );
begin
  if (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'acceptance_revocation_first'
     ) is distinct from (
       select value from pg_temp.partner_onboarding_proof_state
       where key = 'acceptance_revocation_replay'
     )
     or not exists (
       select 1
       from partner_onboarding_private.partner_state state
       where state.partner_id = '10000000-0000-4000-8000-0000000000a1'
         and state.relationship_epoch = v_before[1]::integer + 1
         and state.claim_epoch = v_before[2]::integer + 1
         and state.release_epoch = v_before[3]::integer + 1
         and state.operator_user_id is null
     )
     or partner_onboarding_private.current_claim_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or not exists (
       select 1 from public.partners
       where id = '10000000-0000-4000-8000-0000000000a1'
         and owner_id is null
         and status = 'paused'
         and heha_partner is false
         and website_eligible is false
         and swipe_eligible is false
         and local_eligible is false
     ) then
    raise exception 'Agreement acceptance revocation did not reset relationship atomically';
  end if;
end;
$acceptance_revocation_fail_closed$;

insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'stale_claim_profile_revision_payload', pg_catalog.jsonb_build_object(
  'bio', 'Synthetic stale-claim revision attempt',
  'business_type', partner.business_type,
  'categories', partner.categories,
  'category', partner.category,
  'color', coalesce(partner.color, '#ff8a24'),
  'complete_pct', partner.complete_pct,
  'contact', partner.contact,
  'delivery_days', partner.delivery_days,
  'hours', partner.hours,
  'instagram', partner.instagram,
  'items', partner.items,
  'location', partner.location,
  'name', partner.name,
  'neighborhood', partner.neighborhood,
  'offerings', partner.offerings,
  'phone', partner.phone,
  'photo_emoji', coalesce(partner.photo_emoji, '🍽️'),
  'tagline', partner.tagline,
  'website', partner.website
)::text
from public.partners partner
where partner.id = '10000000-0000-4000-8000-0000000000a1';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
select pg_temp.expect_partner_denied(
  'claimed_profile_revision_stale_claim_denied',
  $sql$select public.revise_partner_profile_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '30000000-0000-4000-8000-00000000010a',
    (select value::jsonb from pg_temp.partner_onboarding_proof_state
     where key = 'stale_claim_profile_revision_payload')
  )$sql$
);
reset role;

set local role anon;
select pg_temp.expect_boolean(
  'acceptance revocation hides Swipe card from anonymous readers', false,
  $sql$select exists (
    select 1 from public.public_swipe_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
select pg_temp.expect_boolean(
  'acceptance revocation hides Local card from anonymous readers', false,
  $sql$select exists (
    select 1 from public.public_local_partners
    where id = '10000000-0000-4000-8000-0000000000a1'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
select pg_temp.expect_partner_denied(
  'old exact claim request cannot return a stale receipt',
  $sql$select public.claim_partner_invitation_v1(
    'main_invite_token_abcdefghijklmnopqrstuvwxyz_001',
    '30000000-0000-4000-8000-000000000020'
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true
);
select pg_temp.expect_partner_denied(
  'old exact acceptance request cannot return a revoked receipt',
  $sql$select public.record_category_partner_agreement_acceptance_v1(
    '10000000-0000-4000-8000-0000000000a1',
    (select value::uuid from pg_temp.partner_onboarding_proof_state
     where key = 'agreement_version'),
    partner_onboarding_private.sha256_text(
      'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'
    ),
    '30000000-0000-4000-8000-000000000090',
    '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}'::jsonb
  )$sql$
);
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'recovery_invite', partner_onboarding_private.issue_partner_invitation_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000a1',
  'restaurant', 'operator_only',
  'recovery_invite_token_abcdefghijklmnopqrstuvwxyz_007',
  pg_catalog.clock_timestamp() + interval '2 days',
  '00000000-0000-4000-8000-0000000000e5'
)::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'recovery_claim', public.claim_partner_invitation_v1(
  'recovery_invite_token_abcdefghijklmnopqrstuvwxyz_007',
  '30000000-0000-4000-8000-000000000095'
)::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'recovery_signer_grant',
       partner_onboarding_private.grant_partner_signer_authority_v1(
  '10000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000b2',
  'Signer B', 'Authorized Representative',
  '00000000-0000-4000-8000-000000000104'
)::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'recovery_acceptance',
       public.record_category_partner_agreement_acceptance_v1(
  '10000000-0000-4000-8000-0000000000a1',
  (select value::uuid from pg_temp.partner_onboarding_proof_state
   where key = 'agreement_version'),
  partner_onboarding_private.sha256_text(
    'SYNTHETIC DOCUMENT -- NO LEGAL EFFECT'
  ),
  '30000000-0000-4000-8000-000000000096',
  '{"assertions_version":"heha-partner-acceptance-v1","assent_text":"I agree to the synthetic terms.","electronic_records_consent":true,"reviewed_complete_agreement":true,"signer_authority_confirmed":true,"signer_legal_name":"Signer B","signer_title":"Authorized Representative","typed_signature":"Signer B"}'::jsonb
)::text;
reset role;

do $acceptance_relationship_recovery$
declare
  v_claim uuid := (
    select (value::jsonb ->> 'claim_evidence_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'recovery_claim'
  );
  v_acceptance uuid := (
    select (value::jsonb ->> 'acceptance_id')::uuid
    from pg_temp.partner_onboarding_proof_state where key = 'recovery_acceptance'
  );
begin
  if partner_onboarding_private.current_claim_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_claim
     or partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is distinct from v_acceptance
     or v_acceptance = (
       select (value::jsonb ->> 'acceptance_id')::uuid
       from pg_temp.partner_onboarding_proof_state where key = 'acceptance_fresh_v1'
     )
     or not exists (
       select 1 from public.partners
       where id = '10000000-0000-4000-8000-0000000000a1'
         and owner_id = '00000000-0000-4000-8000-0000000000a1'
     ) then
    raise exception 'Acceptance reset did not require a full current-epoch recovery';
  end if;
end;
$acceptance_relationship_recovery$;

-- Terminal claim revocation proves the recovered claim remains independently
-- revocable and all prior release receipts stay non-current.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e5', true
);
insert into pg_temp.partner_onboarding_proof_state(key, value)
select 'recovery_claim_revocation', partner_onboarding_private.revoke_partner_claim_v1(
  (select (value::jsonb ->> 'claim_evidence_id')::uuid
   from pg_temp.partner_onboarding_proof_state where key = 'recovery_claim'),
  '00000000-0000-4000-8000-0000000000e5',
  'synthetic_recovered_claim_revocation'
)::text;
reset role;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true
);
select pg_temp.expect_partner_denied(
  'claimed_profile_revision_revoked_claim_denied',
  $sql$select public.revise_partner_profile_v1(
    '10000000-0000-4000-8000-0000000000a1',
    '30000000-0000-4000-8000-00000000010b',
    (select value::jsonb from pg_temp.partner_onboarding_proof_state
     where key = 'stale_claim_profile_revision_payload')
  )$sql$
);
reset role;

do $recovered_claim_revocation_fail_closed$
begin
  if partner_onboarding_private.current_claim_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.current_acceptance_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null
     or partner_onboarding_private.current_release_receipt_id_v1(
       '10000000-0000-4000-8000-0000000000a1'
     ) is not null then
    raise exception 'Recovered claim revocation left a current receipt';
  end if;
end;
$recovered_claim_revocation_fail_closed$;

select 'PASS: partner onboarding V1 ACL, BOLA, idempotency, immutability, release, activation, orderability, and revocation proof.';

rollback;
