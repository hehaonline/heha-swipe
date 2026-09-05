-- Final authority, evidence-invalidation and provenance reconciliation for
-- HEHA Swipe PR #120. REVIEW ONLY / PRODUCTION FROZEN.
--
-- This forward corrective migration closes the remaining agreement-lifecycle
-- findings without introducing a second agreement or partner source of truth.
-- It is deliberately re-apply safe because the disposable proof replays every
-- corrective definition before rerunning the behavioral contract.

-- ---------------------------------------------------------------------------
-- 1. Service authority is the database role selected by PostgREST, never a
-- caller-writable JWT GUC. Internal human authority remains the canonical
-- super_admin assignment in public.user_roles.
-- ---------------------------------------------------------------------------
create or replace function app_private.is_service_role_request()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(current_setting('role', true), '') = 'service_role'
      or session_user::text = 'service_role';
$$;

revoke all on function app_private.is_service_role_request()
  from public, anon, authenticated, service_role;

-- Agreement changes are rare and legally meaningful. A single transaction
-- advisory lock gives registration, retirement, acceptance, revocation and
-- approval one deterministic serialization point, including supersession.
create or replace function app_private.lock_partner_agreement_evidence()
returns void
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $$
  select pg_advisory_xact_lock(861580443112001::bigint);
$$;

revoke all on function app_private.lock_partner_agreement_evidence()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. A live acceptance must retain a live signer reference. Auth deletion may
-- clear accepted_by only after the referenced user is gone; that same FK update
-- terminalizes the acceptance in-place so the partial unique index cannot block
-- a future owner's valid evidence.
-- ---------------------------------------------------------------------------
create or replace function app_private.guard_partner_agreement_acceptance_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode='42501',
      message='Acceptance evidence is immutable and cannot be deleted.';
  end if;

  if new.id is distinct from old.id
     or new.partner_id is distinct from old.partner_id
     or new.agreement_version_id is distinct from old.agreement_version_id
     or new.accepted_owner_id is distinct from old.accepted_owner_id
     or new.accepted_at is distinct from old.accepted_at
     or new.signature_source is distinct from old.signature_source
     or new.evidence_sha256 is distinct from old.evidence_sha256
     or new.created_at is distinct from old.created_at then
    raise exception using errcode='42501', message='Acceptance evidence is immutable.';
  end if;

  if new.accepted_by is distinct from old.accepted_by then
    if new.accepted_by is not null
       or old.accepted_by is null
       or exists (select 1 from auth.users as u where u.id=old.accepted_by) then
      raise exception using errcode='42501', message='Acceptance signer identity is immutable.';
    end if;

    -- The only remaining shape is ON DELETE SET NULL after the signer account
    -- has actually disappeared. Terminalize the evidence in this same row write.
    if old.acceptance_status='accepted' then
      new.acceptance_status := 'terminated';
      new.revoked_at := coalesce(new.revoked_at, now());
      new.revoked_by := null;
      new.revoked_reason := coalesce(
        nullif(btrim(new.revoked_reason),''),
        'Signer account deleted.'
      );
    end if;
  end if;

  -- Auth deletion may also release a terminal revocation actor, but nothing may
  -- re-point that immutable actor reference.
  if new.revoked_by is distinct from old.revoked_by
     and new.revoked_by is not null
     and old.revoked_by is not null then
    raise exception using errcode='42501', message='Acceptance revocation authorship is immutable.';
  end if;

  if old.acceptance_status <> 'accepted'
     and new.acceptance_status is distinct from old.acceptance_status then
    raise exception using errcode='42501', message='Acceptance evidence has already reached a terminal state.';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_partner_agreement_acceptance_immutability()
  from public, anon, authenticated, service_role;

drop trigger if exists partner_agreement_acceptances_immutability
  on public.partner_agreement_acceptances;
create trigger partner_agreement_acceptances_immutability
before update or delete on public.partner_agreement_acceptances
for each row execute function app_private.guard_partner_agreement_acceptance_immutability();

-- A deployment that previously created agreement evidence could already contain
-- an accepted row whose Auth signer was removed under the older SET NULL guard.
-- Reconcile that legacy shape before validating the structural requirement.
-- Partner-first locking matches every runtime evidence workflow.
do $reconcile_orphaned_live_acceptances$
declare
  acceptance_key record;
  a public.partner_agreement_acceptances%rowtype;
  p public.partners%rowtype;
  before_receipt jsonb;
begin
  perform app_private.lock_partner_agreement_evidence();

  for acceptance_key in
    select acceptance_row.id, acceptance_row.partner_id
    from public.partner_agreement_acceptances as acceptance_row
    where acceptance_row.acceptance_status='accepted'
      and (
        acceptance_row.accepted_by is null
        or acceptance_row.accepted_by is distinct from acceptance_row.accepted_owner_id
      )
    order by acceptance_row.partner_id, acceptance_row.id
  loop
    select partner_row.* into p
    from public.partners as partner_row
    where partner_row.id=acceptance_key.partner_id
    for update;

    select acceptance_row.* into a
    from public.partner_agreement_acceptances as acceptance_row
    where acceptance_row.id=acceptance_key.id
    for update;

    if not found
       or a.acceptance_status <> 'accepted'
       or (
         a.accepted_by is not null
         and a.accepted_by is not distinct from a.accepted_owner_id
       ) then
      continue;
    end if;

    before_receipt := app_private.partner_lifecycle_receipt(p);
    if p.contract_evidence_id=a.id then
      perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
      update public.partners as partner_row
      set partnership_status=case
            when partner_row.partnership_status='official_partner' then 'under_review'
            else partner_row.partnership_status
          end,
          contract_status=case
            when partner_row.partnership_status='terminated' then 'terminated'
            when partner_row.contract_status='signed' then 'not_signed'
            else partner_row.contract_status
          end,
          contract_evidence_id=null,
          contract_signed_at=null,
          official_partner_since=null,
          heha_partner=false,
          updated_at=now()
      where partner_row.id=p.id;
    end if;

    update public.partner_agreement_acceptances as acceptance_row
    set acceptance_status='terminated',
        revoked_at=now(),
        revoked_by=null,
        revoked_reason='Signer account was unavailable or did not match the accepting owner before evidence integrity enforcement.'
    where acceptance_row.id=a.id;

    insert into public.partner_lifecycle_events(
      partner_id,event_type,actor_id,before_state,after_state
    ) values (
      p.id,
      'agreement_evidence_revoked',
      null,
      before_receipt,
      jsonb_build_object(
        'partner_id',p.id,
        'agreement_acceptance_id',a.id,
        'acceptance_status','terminated',
        'reason','invalid_signer_reconciled'
      )
    );
  end loop;
end;
$reconcile_orphaned_live_acceptances$;

alter table public.partner_agreement_acceptances
  drop constraint if exists partner_agreement_acceptances_live_signer_check,
  add constraint partner_agreement_acceptances_live_signer_check
    check (
      acceptance_status <> 'accepted'
      or (
        accepted_by is not null
        and accepted_by = accepted_owner_id
      )
    ) not valid;
alter table public.partner_agreement_acceptances
  validate constraint partner_agreement_acceptances_live_signer_check;

-- ---------------------------------------------------------------------------
-- 3. Internal retirement primitive. The public administration functions below
-- establish authority and the global advisory lock before calling this helper.
-- Every partner row is locked before its acceptance row, matching approval and
-- revocation. Superseded evidence is terminalized, and any signed state relying
-- on it is unwound in the same transaction.
-- ---------------------------------------------------------------------------
create or replace function app_private.retire_partner_agreement_version_locked(
  p_version_id uuid,
  p_actor uuid,
  p_reason text default 'Agreement version retired.'
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  v public.partner_agreement_versions%rowtype;
  acceptance_key record;
  a public.partner_agreement_acceptances%rowtype;
  p public.partners%rowtype;
  before_receipt jsonb;
begin
  select version_row.* into v
  from public.partner_agreement_versions as version_row
  where version_row.id=p_version_id
  for update;

  if not found or v.retired_at is not null then
    return false;
  end if;

  for acceptance_key in
    select acceptance_row.id, acceptance_row.partner_id
    from public.partner_agreement_acceptances as acceptance_row
    where acceptance_row.agreement_version_id=p_version_id
      and acceptance_row.acceptance_status='accepted'
    order by acceptance_row.partner_id, acceptance_row.id
  loop
    select partner_row.* into p
    from public.partners as partner_row
    where partner_row.id=acceptance_key.partner_id
    for update;

    select acceptance_row.* into a
    from public.partner_agreement_acceptances as acceptance_row
    where acceptance_row.id=acceptance_key.id
    for update;

    if not found or a.acceptance_status <> 'accepted' then
      continue;
    end if;

    before_receipt := app_private.partner_lifecycle_receipt(p);
    if p.contract_evidence_id=a.id then
      perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
      update public.partners as partner_row
      set partnership_status=case
            when partner_row.partnership_status='official_partner' then 'under_review'
            else partner_row.partnership_status
          end,
          contract_status=case
            when partner_row.partnership_status='terminated' then 'terminated'
            when partner_row.contract_status='signed' then 'not_signed'
            else partner_row.contract_status
          end,
          contract_evidence_id=null,
          contract_signed_at=null,
          official_partner_since=null,
          heha_partner=false,
          updated_at=now()
      where partner_row.id=p.id;
    end if;

    update public.partner_agreement_acceptances as acceptance_row
    set acceptance_status='terminated',
        revoked_at=now(),
        revoked_by=p_actor,
        revoked_reason=coalesce(nullif(btrim(p_reason),''),'Agreement version retired.')
    where acceptance_row.id=a.id;

    insert into public.partner_lifecycle_events(
      partner_id,event_type,actor_id,before_state,after_state
    ) values (
      p.id,
      'agreement_evidence_revoked',
      p_actor,
      before_receipt,
      jsonb_build_object(
        'partner_id',p.id,
        'agreement_acceptance_id',a.id,
        'acceptance_status','terminated',
        'reason','agreement_version_retired'
      )
    );
  end loop;

  update public.partner_agreement_versions as version_row
  set retired_at=now()
  where version_row.id=p_version_id
    and version_row.retired_at is null;

  return found;
end;
$$;

revoke all on function app_private.retire_partner_agreement_version_locked(uuid,uuid,text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Agreement administration and owner evidence flows, all serialized through
-- the private advisory lock and all service checks rooted in the database role.
-- ---------------------------------------------------------------------------
create or replace function public.register_partner_agreement_version(
  p_version text,
  p_document_sha256 bytea
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor uuid := auth.uid();
  current_version record;
  new_id uuid;
begin
  if not (
    app_private.is_service_role_request()
    or app_private.has_internal_role(array['super_admin'])
  ) then
    raise exception using
      errcode='42501',
      message='Not authorized to register partner agreement versions.';
  end if;
  if nullif(btrim(p_version),'') is null then
    raise exception using errcode='22023', message='Agreement version label is required.';
  end if;
  if p_document_sha256 is null or octet_length(p_document_sha256) <> 32 then
    raise exception using
      errcode='22023',
      message='A SHA-256 agreement document digest is required.';
  end if;

  perform app_private.lock_partner_agreement_evidence();
  for current_version in
    select version_row.id
    from public.partner_agreement_versions as version_row
    where version_row.retired_at is null
    order by version_row.effective_at, version_row.id
  loop
    perform app_private.retire_partner_agreement_version_locked(
      current_version.id,
      actor,
      'Agreement superseded by a new version.'
    );
  end loop;

  insert into public.partner_agreement_versions(version,document_sha256,created_by)
  values (btrim(p_version),p_document_sha256,actor)
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.retire_partner_agreement_version(p_version_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare actor uuid := auth.uid();
begin
  if not (
    app_private.is_service_role_request()
    or app_private.has_internal_role(array['super_admin'])
  ) then
    raise exception using
      errcode='42501',
      message='Not authorized to retire partner agreement versions.';
  end if;

  perform app_private.lock_partner_agreement_evidence();
  return app_private.retire_partner_agreement_version_locked(
    p_version_id,
    actor,
    'Agreement version retired.'
  );
end;
$$;

create or replace function public.record_partner_agreement_acceptance(
  p_partner_id uuid,
  p_agreement_version text,
  p_signature_source text,
  p_evidence_sha256 bytea
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor uuid := auth.uid();
  p public.partners%rowtype;
  v public.partner_agreement_versions%rowtype;
  new_id uuid;
begin
  if actor is null then
    raise exception using errcode='28000', message='Authentication required.';
  end if;
  if p_signature_source not in (
    'in_app_acceptance','counter_signed_document','recorded_offline'
  ) then
    raise exception using errcode='22023', message='Unsupported agreement signature source.';
  end if;
  if p_evidence_sha256 is null or octet_length(p_evidence_sha256) <> 32 then
    raise exception using
      errcode='22023',
      message='A SHA-256 acceptance evidence digest is required.';
  end if;

  perform app_private.lock_partner_agreement_evidence();
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='Partner profile not found.';
  end if;
  if p.owner_id is distinct from actor or p.claim_status <> 'claimed' then
    raise exception using
      errcode='42501',
      message='Only the claimed owner may accept the partner agreement.';
  end if;
  select version_row.* into v
  from public.partner_agreement_versions as version_row
  where version_row.version=btrim(p_agreement_version)
  for share;
  if not found then
    raise exception using errcode='P0002', message='Agreement version not found.';
  end if;
  if v.retired_at is not null then
    raise exception using errcode='42501', message='This agreement version has been superseded.';
  end if;

  insert into public.partner_agreement_acceptances(
    partner_id,agreement_version_id,accepted_owner_id,accepted_by,
    signature_source,evidence_sha256
  ) values (
    p.id,v.id,p.owner_id,actor,p_signature_source,p_evidence_sha256
  ) returning id into new_id;

  insert into public.partner_lifecycle_events(
    partner_id,event_type,actor_id,before_state,after_state
  ) values (
    p.id,
    'agreement_accepted',
    actor,
    app_private.partner_lifecycle_receipt(p),
    jsonb_build_object(
      'partner_id',p.id,
      'agreement_acceptance_id',new_id,
      'agreement_version_id',v.id,
      'signature_source',p_signature_source
    )
  );

  return new_id;
end;
$$;

create or replace function public.revoke_partner_agreement_acceptance(
  p_acceptance_id uuid,
  p_status text default 'revoked',
  p_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor uuid := auth.uid();
  a public.partner_agreement_acceptances%rowtype;
  p public.partners%rowtype;
  partner_key uuid;
  before_receipt jsonb;
begin
  if not (
    app_private.is_service_role_request()
    or app_private.has_internal_role(array['super_admin'])
  ) then
    raise exception using errcode='42501', message='Not authorized to revoke agreement evidence.';
  end if;
  if p_status not in ('revoked','terminated') then
    raise exception using
      errcode='22023',
      message='Invalid agreement evidence terminal status.';
  end if;

  perform app_private.lock_partner_agreement_evidence();
  select acceptance_row.partner_id into partner_key
  from public.partner_agreement_acceptances as acceptance_row
  where acceptance_row.id=p_acceptance_id;
  if partner_key is null then
    raise exception using errcode='P0002', message='Agreement acceptance evidence not found.';
  end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=partner_key
  for update;
  select acceptance_row.* into a
  from public.partner_agreement_acceptances as acceptance_row
  where acceptance_row.id=p_acceptance_id
  for update;

  if a.acceptance_status <> 'accepted' then
    return false;
  end if;

  before_receipt := app_private.partner_lifecycle_receipt(p);
  if p.contract_evidence_id=a.id then
    perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
    update public.partners as partner_row
    set partnership_status=case
          when p_status='terminated' then 'terminated'
          when partner_row.partnership_status='official_partner' then 'under_review'
          else partner_row.partnership_status
        end,
        contract_status=case
          when p_status='terminated' then 'terminated'
          when partner_row.contract_status='signed' then 'not_signed'
          else partner_row.contract_status
        end,
        contract_signed_at=null,
        official_partner_since=null,
        contract_evidence_id=null,
        heha_partner=false,
        updated_at=now()
    where partner_row.id=p.id;
  end if;

  update public.partner_agreement_acceptances as acceptance_row
  set acceptance_status=p_status,
      revoked_at=now(),
      revoked_by=actor,
      revoked_reason=nullif(btrim(p_reason),'')
  where acceptance_row.id=p_acceptance_id;

  insert into public.partner_lifecycle_events(
    partner_id,event_type,actor_id,before_state,after_state
  ) values (
    p.id,
    'agreement_evidence_revoked',
    actor,
    before_receipt,
    jsonb_build_object(
      'partner_id',p.id,
      'agreement_acceptance_id',p_acceptance_id,
      'acceptance_status',p_status
    )
  );

  return true;
end;
$$;

create or replace function public.approve_heha_partnership(
  p_partner_id uuid,
  p_agreement_acceptance_id uuid
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  p public.partners%rowtype;
  a public.partner_agreement_acceptances%rowtype;
  v public.partner_agreement_versions%rowtype;
begin
  if not (
    app_private.is_service_role_request()
    or app_private.has_internal_role(array['super_admin'])
  ) then
    raise exception using errcode='42501', message='Not authorized to approve HEHA partnerships.';
  end if;
  if p_agreement_acceptance_id is null then
    raise exception using errcode='22023', message='Agreement acceptance evidence is required.';
  end if;

  perform app_private.lock_partner_agreement_evidence();
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;
  if not found or p.claim_status <> 'claimed' or p.partnership_status <> 'under_review' then
    raise exception using
      errcode='23514',
      message='Partner is not in a valid reviewed and claimed state.';
  end if;

  select acceptance_row.* into a
  from public.partner_agreement_acceptances as acceptance_row
  where acceptance_row.id=p_agreement_acceptance_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='Agreement acceptance evidence not found.';
  end if;
  if a.partner_id <> p.id then
    raise exception using
      errcode='42501',
      message='Agreement acceptance evidence belongs to a different partner.';
  end if;
  if a.acceptance_status <> 'accepted' then
    raise exception using
      errcode='42501',
      message='Agreement acceptance evidence is revoked or terminated.';
  end if;
  if a.accepted_owner_id is distinct from p.owner_id then
    raise exception using
      errcode='42501',
      message='Agreement acceptance evidence was signed by a different owner.';
  end if;
  if a.accepted_by is null then
    raise exception using
      errcode='42501',
      message='Agreement acceptance signer account no longer exists.';
  end if;
  if a.accepted_by is distinct from a.accepted_owner_id then
    raise exception using
      errcode='42501',
      message='Agreement acceptance signer does not match the accepting owner.';
  end if;

  select version_row.* into v
  from public.partner_agreement_versions as version_row
  where version_row.id=a.agreement_version_id
  for share;
  if not found then
    raise exception using errcode='P0002', message='Agreement version evidence not found.';
  end if;
  if v.retired_at is not null then
    raise exception using
      errcode='42501',
      message='Agreement acceptance evidence is for a superseded agreement version.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
  update public.partners as partner_row
  set partnership_status='official_partner',
      contract_status='signed',
      contract_evidence_id=a.id,
      contract_signed_at=a.accepted_at,
      official_partner_since=coalesce(partner_row.official_partner_since,a.accepted_at),
      heha_partner=true,
      updated_at=now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(
    partner_id,event_type,actor_id,before_state,after_state
  ) values (
    p.id,
    'partnership_approved',
    auth.uid(),
    app_private.partner_lifecycle_receipt(p),
    jsonb_build_object(
      'partner_id',p.id,
      'claim_status','claimed',
      'partnership_status','official_partner',
      'contract_status','signed',
      'heha_partner',true,
      'agreement_acceptance_id',a.id,
      'agreement_version_id',v.id
    )
  );
end;
$$;

-- Termination is also an evidence terminal state. Clear the partner's evidence
-- pointer first, then terminalize every still-live acceptance for that partner.
create or replace function public.review_partner_partnership(
  p_partner_id uuid,
  p_status text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  p public.partners%rowtype;
  acceptance_row record;
begin
  if not app_private.has_internal_role(
    array['super_admin','developer_admin','pm_admin']
  ) then
    raise exception using errcode='42501', message='Internal partnership review required.';
  end if;
  if p_status not in ('under_review','terminated') then
    raise exception using errcode='22023', message='Invalid review transition.';
  end if;

  perform app_private.lock_partner_agreement_evidence();
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='Partner not found.';
  end if;
  if p_status='under_review' and p.partnership_status <> 'requested' then
    raise exception using
      errcode='23514',
      message='Only requested partnerships may enter review.';
  end if;
  if p_status='terminated'
     and p.partnership_status not in ('requested','under_review','official_partner') then
    raise exception using
      errcode='23514',
      message='Partnership cannot be terminated from current state.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
  update public.partners as partner_row
  set partnership_status=p_status,
      contract_status=case
        when p_status='terminated' then 'terminated'
        else partner_row.contract_status
      end,
      contract_evidence_id=case
        when p_status='terminated' then null
        else partner_row.contract_evidence_id
      end,
      contract_signed_at=case
        when p_status='terminated' then null
        else partner_row.contract_signed_at
      end,
      official_partner_since=case
        when p_status='terminated' then null
        else partner_row.official_partner_since
      end,
      heha_partner=false,
      updated_at=now()
  where partner_row.id=p_partner_id;

  if p_status='terminated' then
    for acceptance_row in
      select acceptance.id
      from public.partner_agreement_acceptances as acceptance
      where acceptance.partner_id=p.id
        and acceptance.acceptance_status='accepted'
      order by acceptance.id
      for update
    loop
      update public.partner_agreement_acceptances as acceptance
      set acceptance_status='terminated',
          revoked_at=now(),
          revoked_by=auth.uid(),
          revoked_reason='Partnership terminated.'
      where acceptance.id=acceptance_row.id;

      insert into public.partner_lifecycle_events(
        partner_id,event_type,actor_id,before_state,after_state
      ) values (
        p.id,
        'agreement_evidence_revoked',
        auth.uid(),
        app_private.partner_lifecycle_receipt(p),
        jsonb_build_object(
          'partner_id',p.id,
          'agreement_acceptance_id',acceptance_row.id,
          'acceptance_status','terminated',
          'reason','partnership_terminated'
        )
      );
    end loop;
  end if;

  insert into public.partner_lifecycle_events(
    partner_id,event_type,actor_id,before_state,after_state
  ) values (
    p.id,
    'partnership_reviewed',
    auth.uid(),
    app_private.partner_lifecycle_receipt(p),
    jsonb_build_object(
      'partner_id',p.id,
      'partnership_status',p_status,
      'contract_status',case
        when p_status='terminated' then 'terminated'
        else p.contract_status
      end,
      'contract_evidence_id',case
        when p_status='terminated' then null
        else p.contract_evidence_id
      end,
      'heha_partner',false
    )
  );
end;
$$;

-- Deterministic ACLs after every replacement.
revoke all on function public.register_partner_agreement_version(text,bytea)
  from public,anon,authenticated,service_role;
revoke all on function public.retire_partner_agreement_version(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.record_partner_agreement_acceptance(uuid,text,text,bytea)
  from public,anon,authenticated,service_role;
revoke all on function public.revoke_partner_agreement_acceptance(uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.approve_heha_partnership(uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.review_partner_partnership(uuid,text)
  from public,anon,authenticated,service_role;

grant execute on function public.register_partner_agreement_version(text,bytea)
  to authenticated,service_role;
grant execute on function public.retire_partner_agreement_version(uuid)
  to authenticated,service_role;
grant execute on function public.record_partner_agreement_acceptance(uuid,text,text,bytea)
  to authenticated,service_role;
grant execute on function public.revoke_partner_agreement_acceptance(uuid,text,text)
  to authenticated,service_role;
grant execute on function public.approve_heha_partnership(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.review_partner_partnership(uuid,text)
  to authenticated,service_role;
