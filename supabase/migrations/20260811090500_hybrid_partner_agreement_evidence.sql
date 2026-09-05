-- Immutable agreement-version and acceptance-evidence records for PR #120.
-- REVIEW ONLY / PRODUCTION FROZEN.
--
-- Review finding (P1, discussion_r3775021040): `approve_heha_partnership` took only
-- a partner UUID, invented `contract_signed_at`, set `contract_status='signed'` and
-- enabled the public Official Partner flag with no agreement version, signer
-- identity, acceptance record or evidence ID. A super-admin or service-role call
-- could manufacture a legally meaningful "signed" state and an audit receipt with
-- no evidence at all, contradicting the stated invariant that Official Partner
-- requires a signed agreement.
--
-- This migration models the evidence, then makes it structurally required:
--   * `partner_agreement_versions`      - immutable, versioned agreement documents;
--   * `partner_agreement_acceptances`   - immutable owner acceptance evidence;
--   * `partners.contract_evidence_id`   - composite FK proving the evidence on a
--                                         partner row belongs to that same partner;
--   * CHECK constraints so `contract_status='signed'` and
--     `partnership_status='official_partner'` are unreachable without evidence,
--     including through direct SQL.
--
-- What qualifies as a legally valid signature, and the retention / anonymization
-- policy for terminal evidence, remain explicit Geronimo/legal approval gates.
-- Nothing here authorizes a Production apply.

-- ---------------------------------------------------------------------------
-- 1. Immutable agreement versions.
-- ---------------------------------------------------------------------------
create table if not exists public.partner_agreement_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  document_sha256 bytea not null,
  effective_at timestamptz not null default now(),
  retired_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.partner_agreement_versions
  drop constraint if exists partner_agreement_versions_sha_check,
  add constraint partner_agreement_versions_sha_check
    check (octet_length(document_sha256) = 32),
  drop constraint if exists partner_agreement_versions_retired_check,
  add constraint partner_agreement_versions_retired_check
    check (retired_at is null or retired_at >= effective_at),
  drop constraint if exists partner_agreement_versions_version_check,
  add constraint partner_agreement_versions_version_check
    check (length(btrim(version)) between 1 and 64);

-- Only one agreement version may be current at a time.
create unique index if not exists partner_agreement_versions_current_uidx
  on public.partner_agreement_versions((retired_at is null)) where retired_at is null;

alter table public.partner_agreement_versions enable row level security;
revoke all on table public.partner_agreement_versions from public, anon, authenticated, service_role;
grant select on table public.partner_agreement_versions to authenticated, service_role;

drop policy if exists partner_agreement_versions_read on public.partner_agreement_versions;
create policy partner_agreement_versions_read
on public.partner_agreement_versions for select to authenticated
using (
  retired_at is null
  or app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[])
);

-- ---------------------------------------------------------------------------
-- 2. Immutable acceptance evidence.
--
-- `accepted_owner_id` deliberately carries NO foreign key: it is the immutable
-- snapshot of who owned the profile at acceptance time and must survive Auth
-- deletion as evidence. `accepted_by` deliberately DOES carry an ON DELETE SET
-- NULL foreign key: when the accepting account is deleted, that column becomes
-- NULL and the approval gate treats the evidence as no longer attributable.
-- ---------------------------------------------------------------------------
create table if not exists public.partner_agreement_acceptances (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  agreement_version_id uuid not null references public.partner_agreement_versions(id) on delete restrict,
  accepted_owner_id uuid not null,
  accepted_by uuid references auth.users(id) on delete set null,
  acceptance_status text not null default 'accepted',
  accepted_at timestamptz not null default now(),
  signature_source text not null,
  evidence_sha256 bytea not null,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_reason text,
  created_at timestamptz not null default now()
);

alter table public.partner_agreement_acceptances
  drop constraint if exists partner_agreement_acceptances_status_check,
  add constraint partner_agreement_acceptances_status_check
    check (acceptance_status in ('accepted','revoked','terminated')),
  drop constraint if exists partner_agreement_acceptances_source_check,
  add constraint partner_agreement_acceptances_source_check
    check (signature_source in ('in_app_acceptance','counter_signed_document','recorded_offline')),
  drop constraint if exists partner_agreement_acceptances_sha_check,
  add constraint partner_agreement_acceptances_sha_check
    check (octet_length(evidence_sha256) = 32),
  drop constraint if exists partner_agreement_acceptances_terminal_check,
  add constraint partner_agreement_acceptances_terminal_check
    check (
      (acceptance_status = 'accepted' and revoked_at is null and revoked_reason is null)
      or (acceptance_status in ('revoked','terminated') and revoked_at is not null)
    );

-- At most one live acceptance per partner keeps the evidence chain deterministic.
create unique index if not exists partner_agreement_acceptances_live_uidx
  on public.partner_agreement_acceptances(partner_id) where acceptance_status = 'accepted';
create index if not exists partner_agreement_acceptances_partner_idx
  on public.partner_agreement_acceptances(partner_id);

-- Composite uniqueness lets public.partners prove, structurally, that the evidence
-- it points at belongs to that same partner row. Added conditionally: the partners
-- foreign key below depends on this constraint's index, so a drop/re-add pair
-- would fail on corrective re-apply.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname='partner_agreement_acceptances_id_partner_key'
      and conrelid='public.partner_agreement_acceptances'::regclass
  ) then
    alter table public.partner_agreement_acceptances
      add constraint partner_agreement_acceptances_id_partner_key unique (id, partner_id);
  end if;
end $$;

alter table public.partner_agreement_acceptances enable row level security;
revoke all on table public.partner_agreement_acceptances from public, anon, authenticated, service_role;
grant select on table public.partner_agreement_acceptances to authenticated, service_role;

drop policy if exists partner_agreement_acceptances_read on public.partner_agreement_acceptances;
create policy partner_agreement_acceptances_read
on public.partner_agreement_acceptances for select to authenticated
using (
  app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[])
  or exists (
    select 1 from public.partners as p
    where p.id = partner_agreement_acceptances.partner_id
      and p.owner_id = auth.uid()
  )
);

-- ---------------------------------------------------------------------------
-- 3. Immutability enforcement. Evidence is append-only; the only permitted
-- mutations are the terminal status transition and the Auth-deletion FK unlink.
-- ---------------------------------------------------------------------------
create or replace function app_private.guard_partner_agreement_version_immutability()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode='42501', message='Agreement versions are immutable evidence and cannot be deleted.';
  end if;

  if new.id is distinct from old.id
     or new.version is distinct from old.version
     or new.document_sha256 is distinct from old.document_sha256
     or new.effective_at is distinct from old.effective_at
     or new.created_at is distinct from old.created_at then
    raise exception using errcode='42501', message='Agreement version records are immutable except for retirement.';
  end if;

  -- created_by may only be released by Auth deletion, never re-pointed.
  if new.created_by is distinct from old.created_by and new.created_by is not null then
    raise exception using errcode='42501', message='Agreement version authorship is immutable.';
  end if;

  if old.retired_at is not null and new.retired_at is distinct from old.retired_at then
    raise exception using errcode='42501', message='An agreement version can only be retired once.';
  end if;

  return new;
end;
$$;
revoke all on function app_private.guard_partner_agreement_version_immutability()
  from public, anon, authenticated, service_role;

drop trigger if exists partner_agreement_versions_immutability on public.partner_agreement_versions;
create trigger partner_agreement_versions_immutability
before update or delete on public.partner_agreement_versions
for each row execute function app_private.guard_partner_agreement_version_immutability();

create or replace function app_private.guard_partner_agreement_acceptance_immutability()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode='42501', message='Acceptance evidence is immutable and cannot be deleted.';
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

  -- Auth deletion may release the live actor references; nothing may re-point them.
  if new.accepted_by is distinct from old.accepted_by and new.accepted_by is not null then
    raise exception using errcode='42501', message='Acceptance signer identity is immutable.';
  end if;
  if new.revoked_by is distinct from old.revoked_by and new.revoked_by is not null
     and old.revoked_by is not null then
    raise exception using errcode='42501', message='Acceptance revocation authorship is immutable.';
  end if;

  if old.acceptance_status <> 'accepted' and new.acceptance_status is distinct from old.acceptance_status then
    raise exception using errcode='42501', message='Acceptance evidence has already reached a terminal state.';
  end if;

  return new;
end;
$$;
revoke all on function app_private.guard_partner_agreement_acceptance_immutability()
  from public, anon, authenticated, service_role;

drop trigger if exists partner_agreement_acceptances_immutability on public.partner_agreement_acceptances;
create trigger partner_agreement_acceptances_immutability
before update or delete on public.partner_agreement_acceptances
for each row execute function app_private.guard_partner_agreement_acceptance_immutability();

-- ---------------------------------------------------------------------------
-- 4. Structurally require evidence on the canonical partner row.
-- ---------------------------------------------------------------------------
alter table public.partners
  add column if not exists contract_evidence_id uuid;

-- Fail closed before the constraints are validated: any pre-existing `signed`
-- state carried in by the forward-only mapping has, by definition, no evidence
-- record, so it is demoted rather than grandfathered. The disable/update/enable
-- sequence is one DO statement, and therefore one atomic transaction unit even
-- when this corrective file is replayed directly with psql. If the UPDATE fails,
-- PostgreSQL rolls the trigger state back with the statement. RI triggers remain
-- active throughout.
do $reconcile_unsigned_contracts$
begin
  execute 'alter table public.partners disable trigger user';
  update public.partners
  set partnership_status = case when partnership_status = 'official_partner' then 'under_review' else partnership_status end,
      contract_status = 'not_signed',
      contract_signed_at = null,
      official_partner_since = null,
      heha_partner = false
  where contract_status = 'signed'
    and contract_evidence_id is null;
  execute 'alter table public.partners enable trigger user';
end;
$reconcile_unsigned_contracts$;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname='partners_contract_evidence_fk'
      and conrelid='public.partners'::regclass
  ) then
    alter table public.partners
      add constraint partners_contract_evidence_fk
        foreign key (contract_evidence_id, id)
        references public.partner_agreement_acceptances(id, partner_id)
        on delete restrict;
  end if;
end $$;

alter table public.partners
  drop constraint if exists partners_signed_requires_evidence,
  add constraint partners_signed_requires_evidence
    check (contract_status <> 'signed' or contract_evidence_id is not null) not valid,
  drop constraint if exists partners_official_requires_evidence,
  add constraint partners_official_requires_evidence
    check (partnership_status <> 'official_partner' or contract_evidence_id is not null) not valid;

alter table public.partners validate constraint partners_signed_requires_evidence;
alter table public.partners validate constraint partners_official_requires_evidence;

-- The lifecycle receipt references evidence by ID only; agreement content, the
-- document hash and the acceptance hash are never copied into audit rows.
create or replace function app_private.partner_lifecycle_receipt(p public.partners)
returns jsonb language sql stable
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'partner_id', p.id,
    'owner_id', p.owner_id,
    'claim_status', p.claim_status,
    'partnership_status', p.partnership_status,
    'contract_status', p.contract_status,
    'listing_status', p.listing_status,
    'heha_partner', p.heha_partner,
    'claimed_at', p.claimed_at,
    'partnership_requested_at', p.partnership_requested_at,
    'official_partner_since', p.official_partner_since,
    'contract_signed_at', p.contract_signed_at,
    'contract_evidence_id', p.contract_evidence_id,
    'opted_out_at', p.opted_out_at
  );
$$;
revoke all on function app_private.partner_lifecycle_receipt(public.partners)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Agreement version administration.
-- ---------------------------------------------------------------------------
create or replace function public.register_partner_agreement_version(
  p_version text,
  p_document_sha256 bytea
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor uuid := auth.uid();
  jwt_role text := coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  new_id uuid;
begin
  if not (jwt_role='service_role' or app_private.has_internal_role(array['super_admin'])) then
    raise exception using errcode='42501', message='Not authorized to register partner agreement versions.';
  end if;
  if nullif(btrim(p_version),'') is null then
    raise exception using errcode='22023', message='Agreement version label is required.';
  end if;
  if p_document_sha256 is null or octet_length(p_document_sha256) <> 32 then
    raise exception using errcode='22023', message='A SHA-256 agreement document digest is required.';
  end if;

  -- Superseding is explicit: the previous current version is retired first.
  update public.partner_agreement_versions
  set retired_at = now()
  where retired_at is null;

  insert into public.partner_agreement_versions(version, document_sha256, created_by)
  values (btrim(p_version), p_document_sha256, actor)
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.retire_partner_agreement_version(p_version_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  jwt_role text := coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
begin
  if not (jwt_role='service_role' or app_private.has_internal_role(array['super_admin'])) then
    raise exception using errcode='42501', message='Not authorized to retire partner agreement versions.';
  end if;

  update public.partner_agreement_versions
  set retired_at = now()
  where id = p_version_id and retired_at is null;

  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Owner acceptance. Only the current claimed owner may create evidence, and
-- only against the current agreement version.
-- ---------------------------------------------------------------------------
create or replace function public.record_partner_agreement_acceptance(
  p_partner_id uuid,
  p_agreement_version text,
  p_signature_source text,
  p_evidence_sha256 bytea
) returns uuid
language plpgsql security definer
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
  if p_signature_source not in ('in_app_acceptance','counter_signed_document','recorded_offline') then
    raise exception using errcode='22023', message='Unsupported agreement signature source.';
  end if;
  if p_evidence_sha256 is null or octet_length(p_evidence_sha256) <> 32 then
    raise exception using errcode='22023', message='A SHA-256 acceptance evidence digest is required.';
  end if;

  -- Canonical lock order starts with partner.
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id = p_partner_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='Partner profile not found.';
  end if;

  if p.owner_id is distinct from actor or p.claim_status <> 'claimed' then
    raise exception using errcode='42501', message='Only the claimed owner may accept the partner agreement.';
  end if;

  select version_row.* into v
  from public.partner_agreement_versions as version_row
  where version_row.version = btrim(p_agreement_version)
  for share;
  if not found then
    raise exception using errcode='P0002', message='Agreement version not found.';
  end if;
  if v.retired_at is not null then
    raise exception using errcode='42501', message='This agreement version has been superseded.';
  end if;

  insert into public.partner_agreement_acceptances(
    partner_id, agreement_version_id, accepted_owner_id, accepted_by,
    signature_source, evidence_sha256
  ) values (
    p.id, v.id, p.owner_id, actor, p_signature_source, p_evidence_sha256
  )
  returning id into new_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'agreement_accepted',actor,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'agreement_acceptance_id',new_id,
      'agreement_version_id',v.id,'signature_source',p_signature_source));

  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Evidence revocation / termination. Revoking evidence that a partner is
-- currently relying on immediately downgrades that partner; a signed contract
-- can never outlive the evidence that produced it.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_partner_agreement_acceptance(
  p_acceptance_id uuid,
  p_status text default 'revoked',
  p_reason text default null
) returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor uuid := auth.uid();
  jwt_role text := coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  a public.partner_agreement_acceptances%rowtype;
  p public.partners%rowtype;
  partner_key uuid;
begin
  if not (jwt_role='service_role' or app_private.has_internal_role(array['super_admin'])) then
    raise exception using errcode='42501', message='Not authorized to revoke agreement evidence.';
  end if;
  if p_status not in ('revoked','terminated') then
    raise exception using errcode='22023', message='Invalid agreement evidence terminal status.';
  end if;

  -- Unlocked lookup only discovers the partner id; no state from it is trusted.
  select acceptance_row.partner_id into partner_key
  from public.partner_agreement_acceptances as acceptance_row
  where acceptance_row.id = p_acceptance_id;
  if partner_key is null then
    raise exception using errcode='P0002', message='Agreement acceptance evidence not found.';
  end if;

  -- Canonical lock order starts with partner, then the evidence row.
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id = partner_key
  for update;

  select acceptance_row.* into a
  from public.partner_agreement_acceptances as acceptance_row
  where acceptance_row.id = p_acceptance_id
  for update;

  if a.acceptance_status <> 'accepted' then
    return false;
  end if;

  if p.contract_evidence_id = a.id then
    perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
    -- partnership_status and contract_status move together so the existing
    -- partners_partnership_contract_consistency pairing keeps holding.
    update public.partners as partner_row
    set partnership_status = case
          when p_status='terminated' then 'terminated'
          when partner_row.partnership_status='official_partner' then 'under_review'
          else partner_row.partnership_status end,
        contract_status = case when p_status='terminated' then 'terminated' else 'not_signed' end,
        contract_signed_at = null,
        official_partner_since = null,
        contract_evidence_id = null,
        heha_partner = false,
        updated_at = now()
    where partner_row.id = p.id;
  end if;

  update public.partner_agreement_acceptances as acceptance_row
  set acceptance_status = p_status,
      revoked_at = now(),
      revoked_by = actor,
      revoked_reason = nullif(btrim(p_reason),'')
  where acceptance_row.id = p_acceptance_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'agreement_evidence_revoked',actor,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'agreement_acceptance_id',p_acceptance_id,
      'acceptance_status',p_status));

  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Evidence-gated Official Partner approval.
--
-- The evidence-free single-argument entry point is removed outright so no
-- caller can reach `signed` / `official_partner` without an acceptance record.
-- ---------------------------------------------------------------------------
drop function if exists public.approve_heha_partnership(uuid);

create or replace function public.approve_heha_partnership(
  p_partner_id uuid,
  p_agreement_acceptance_id uuid
) returns void
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  p public.partners%rowtype;
  a public.partner_agreement_acceptances%rowtype;
  v public.partner_agreement_versions%rowtype;
  jwt_role text := coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
begin
  if not (jwt_role='service_role' or app_private.has_internal_role(array['super_admin'])) then
    raise exception using errcode='42501', message='Not authorized to approve HEHA partnerships.';
  end if;
  if p_agreement_acceptance_id is null then
    raise exception using errcode='22023', message='Agreement acceptance evidence is required.';
  end if;

  -- Canonical lock order starts with partner, then the evidence row, so an
  -- approval and a concurrent revocation serialize deterministically.
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id = p_partner_id
  for update;

  if not found or p.claim_status <> 'claimed' or p.partnership_status <> 'under_review' then
    raise exception using errcode='23514', message='Partner is not in a valid reviewed and claimed state.';
  end if;

  select acceptance_row.* into a
  from public.partner_agreement_acceptances as acceptance_row
  where acceptance_row.id = p_agreement_acceptance_id
  for update;

  if not found then
    raise exception using errcode='P0002', message='Agreement acceptance evidence not found.';
  end if;
  if a.partner_id <> p.id then
    raise exception using errcode='42501', message='Agreement acceptance evidence belongs to a different partner.';
  end if;
  if a.acceptance_status <> 'accepted' then
    raise exception using errcode='42501', message='Agreement acceptance evidence is revoked or terminated.';
  end if;
  if a.accepted_owner_id is distinct from p.owner_id then
    raise exception using errcode='42501', message='Agreement acceptance evidence was signed by a different owner.';
  end if;
  if a.accepted_by is null then
    raise exception using errcode='42501', message='Agreement acceptance signer account no longer exists.';
  end if;

  select version_row.* into v
  from public.partner_agreement_versions as version_row
  where version_row.id = a.agreement_version_id
  for share;
  if not found then
    raise exception using errcode='P0002', message='Agreement version evidence not found.';
  end if;
  if v.retired_at is not null then
    raise exception using errcode='42501', message='Agreement acceptance evidence is for a superseded agreement version.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
  update public.partners as partner_row
  set partnership_status='official_partner',
      contract_status='signed',
      contract_evidence_id=a.id,
      contract_signed_at=a.accepted_at,
      official_partner_since=coalesce(partner_row.official_partner_since, a.accepted_at),
      heha_partner=true,
      updated_at=now()
  where partner_row.id=p_partner_id;

  -- The audit row references evidence by ID and version only; it never copies
  -- the agreement document digest or the acceptance evidence digest.
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_approved',auth.uid(),app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'claim_status','claimed','partnership_status','official_partner',
      'contract_status','signed','heha_partner',true,
      'agreement_acceptance_id',a.id,'agreement_version_id',v.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Deterministic ACLs for the evidence surface.
-- ---------------------------------------------------------------------------
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

comment on table public.partner_agreement_versions is
  'Immutable agreement document versions. Retirement is one-way and supersedes the previous current version.';
comment on table public.partner_agreement_acceptances is
  'Immutable owner acceptance evidence. accepted_owner_id is an unlinked immutable snapshot; accepted_by is FK-linked so Auth deletion invalidates the evidence for approval.';
comment on column public.partners.contract_evidence_id is
  'Composite FK to the acceptance evidence for this same partner. Required by CHECK for contract_status=signed and partnership_status=official_partner.';
