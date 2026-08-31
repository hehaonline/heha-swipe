-- HEHA partner onboarding V1 — private data foundation.
--
-- REVIEW ONLY / DISPOSABLE POSTGRESQL ONLY. This is not a Supabase migration.

-- The opt-in must be supplied by the disposable runner, never by this file.
-- Keeping the guard in the transaction makes the exception abort all later
-- statements even when the invoking client did not enable ON_ERROR_STOP.
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

create schema if not exists partner_onboarding_private;

revoke all on schema partner_onboarding_private
  from public, anon, authenticated, service_role, supabase_auth_admin;
-- Human staff transitions are authenticated RPCs; machine orderability reads
-- remain service-role RPCs. Schema USAGE exposes no table or helper access;
-- exact function EXECUTE grants are applied in 002/003.
grant usage on schema partner_onboarding_private to authenticated, service_role;

-- Close the legacy authenticated-owner write bypass before introducing any
-- successor transition. Public/owner SELECT policies remain intact.
drop policy if exists "Owners can insert partner" on public.partners;
drop policy if exists "Owners can update own partner" on public.partners;
drop policy if exists "Owners can update own preapproval partner profile" on public.partners;
drop policy if exists "Legacy partner owner inserts pending profile" on public.partners;
drop policy if exists "Legacy partner owner updates pending profile" on public.partners;
revoke insert, update on table public.partners from authenticated;

alter default privileges in schema partner_onboarding_private
  revoke all on functions from public, anon, authenticated, service_role, supabase_auth_admin;
alter default privileges in schema partner_onboarding_private
  revoke all on tables from public, anon, authenticated, service_role, supabase_auth_admin;
alter default privileges in schema partner_onboarding_private
  revoke all on sequences from public, anon, authenticated, service_role, supabase_auth_admin;

-- This is a deterministic PostgreSQL jsonb representation, not a claim of
-- RFC 8785 / JCS compatibility. Cross-runtime payloads use ASCII object keys
-- and avoid JSON numbers whose JavaScript and PostgreSQL renderings can differ.
-- The C collation makes the approved ASCII-key contract match the client sort.
create or replace function partner_onboarding_private.canonical_json(p_value jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $function$
  select case pg_catalog.jsonb_typeof(p_value)
    when 'object' then coalesce(
      (
        select '{' || pg_catalog.string_agg(
          pg_catalog.to_jsonb(entry.key)::text || ':' ||
          partner_onboarding_private.canonical_json(entry.value),
          ',' order by entry.key collate "C"
        ) || '}'
        from pg_catalog.jsonb_each(p_value) as entry(key, value)
      ),
      '{}'
    )
    when 'array' then coalesce(
      (
        select '[' || pg_catalog.string_agg(
          partner_onboarding_private.canonical_json(item.value),
          ',' order by item.ordinality
        ) || ']'
        from pg_catalog.jsonb_array_elements(p_value)
          with ordinality as item(value, ordinality)
      ),
      '[]'
    )
    else p_value::text
  end;
$function$;

create or replace function partner_onboarding_private.sha256_text(p_value text)
returns text
language sql
immutable
strict
set search_path = ''
as $function$
  select pg_catalog.encode(
    public.digest(pg_catalog.convert_to(p_value, 'UTF8'), 'sha256'),
    'hex'
  );
$function$;

create or replace function partner_onboarding_private.normalized_business_key(
  p_legal_name text,
  p_postal_code text
)
returns text
language sql
immutable
set search_path = ''
as $function$
  select partner_onboarding_private.sha256_text(
    pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_legal_name, '')), '\s+', ' ', 'g'))
    || '|' ||
    pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_postal_code, '')), '\s+', '', 'g'))
  );
$function$;

create or replace function partner_onboarding_private.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'PARTNER_ONBOARDING_APPEND_ONLY'
    using errcode = '42501';
end;
$function$;

create or replace function partner_onboarding_private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

create table if not exists partner_onboarding_private.runtime_config (
  singleton boolean primary key default true check (singleton),
  environment text not null default 'test' check (environment = 'test'),
  claim_enabled boolean not null default false,
  application_enabled boolean not null default false,
  acceptance_enabled boolean not null default false,
  release_enabled boolean not null default false,
  swipe_publication_enabled boolean not null default false,
  local_ordering_enabled boolean not null default false,
  config_version text not null default 'partner-onboarding-v1-locked',
  updated_by uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default pg_catalog.now()
);

insert into partner_onboarding_private.runtime_config (singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists partner_onboarding_private.partner_business_registry (
  partner_id uuid primary key references public.partners(id) on delete restrict,
  business_key_sha256 text not null unique check (
    business_key_sha256 ~ '^[a-f0-9]{64}$'
  ),
  registration_source text not null check (
    registration_source in ('baseline', 'application', 'invitation')
  ),
  registered_by uuid references auth.users(id) on delete restrict,
  registered_at timestamptz not null default pg_catalog.now(),
  constraint partner_business_registry_actor_source_check check (
    registered_by is not null or registration_source = 'baseline'
  ),
  constraint partner_business_registry_binding_unique unique (
    partner_id,
    business_key_sha256
  )
);

create index if not exists partner_business_registry_source_lookup_idx
  on partner_onboarding_private.partner_business_registry(
    registration_source,
    registered_at,
    partner_id
  );

create table if not exists partner_onboarding_private.partner_state (
  partner_id uuid primary key references public.partners(id) on delete cascade,
  legal_relationship_type text not null check (
    legal_relationship_type in (
      'restaurant',
      'vendor',
      'market',
      'catering',
      'solo_chef',
      'driver',
      'som'
    )
  ),
  business_key_sha256 text not null unique check (business_key_sha256 ~ '^[a-f0-9]{64}$'),
  relationship_epoch integer not null default 1 check (relationship_epoch > 0),
  claim_epoch integer not null default 1 check (claim_epoch > 0),
  release_epoch integer not null default 1 check (release_epoch > 0),
  reclassification_pending boolean not null default false,
  operator_user_id uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default pg_catalog.now(),
  constraint partner_state_business_registry_fk foreign key (
    partner_id,
    business_key_sha256
  ) references partner_onboarding_private.partner_business_registry (
    partner_id,
    business_key_sha256
  ) on delete restrict
);

alter table partner_onboarding_private.partner_state
  add column if not exists reclassification_pending boolean not null default false;

create table if not exists partner_onboarding_private.partner_invites (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete restrict,
  legal_relationship_type text not null check (
    legal_relationship_type in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som')
  ),
  relationship_epoch integer not null check (relationship_epoch > 0),
  claim_epoch integer not null check (claim_epoch > 0),
  claim_role text not null check (claim_role = 'operator_only'),
  token_sha256 text not null unique check (token_sha256 ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default pg_catalog.now(),
  constraint partner_invites_expiry_check check (expires_at > issued_at),
  constraint partner_invites_claim_binding_unique unique (
    id,
    partner_id,
    recipient_user_id,
    legal_relationship_type,
    relationship_epoch,
    claim_epoch,
    claim_role
  )
);

create table if not exists partner_onboarding_private.partner_invite_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  invite_id uuid not null unique references partner_onboarding_private.partner_invites(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.partner_reclassification_resets (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  prior_legal_relationship_type text not null check (
    prior_legal_relationship_type in (
      'restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som'
    )
  ),
  prior_relationship_epoch integer not null check (prior_relationship_epoch > 0),
  prior_claim_epoch integer not null check (prior_claim_epoch > 0),
  prior_release_epoch integer not null check (prior_release_epoch > 0),
  reset_mode text not null check (
    reset_mode in ('owner_revision_required', 'profile_relationship_repaired')
  ),
  replacement_legal_relationship_type text check (
    replacement_legal_relationship_type is null
    or replacement_legal_relationship_type in (
      'restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som'
    )
  ),
  reset_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null check (
    nullif(pg_catalog.btrim(reason_code), '') is not null
  ),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  reset_at timestamptz not null default pg_catalog.now(),
  unique (reset_by, request_key),
  constraint partner_reclassification_resets_receipt_binding_unique unique (
    id,
    partner_id
  ),
  constraint partner_reclassification_resets_mode_binding_check check (
    (
      reset_mode = 'owner_revision_required'
      and replacement_legal_relationship_type is null
    )
    or (
      reset_mode = 'profile_relationship_repaired'
      and replacement_legal_relationship_type is not null
    )
  )
);

create index if not exists partner_reclassification_resets_partner_lookup_idx
  on partner_onboarding_private.partner_reclassification_resets(
    partner_id,
    reset_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.partner_claims (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  invite_id uuid not null unique,
  accepted_by uuid not null references auth.users(id) on delete restrict,
  accepted_owner_id uuid not null references auth.users(id) on delete restrict,
  legal_relationship_type text not null check (
    legal_relationship_type in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som')
  ),
  relationship_epoch integer not null check (relationship_epoch > 0),
  claim_epoch integer not null check (claim_epoch > 0),
  claim_role text not null check (claim_role = 'operator_only'),
  request_key uuid not null,
  invite_token_sha256 text not null check (invite_token_sha256 ~ '^[a-f0-9]{64}$'),
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  accepted_at timestamptz not null default pg_catalog.now(),
  unique (accepted_by, request_key),
  unique (partner_id, claim_epoch),
  constraint partner_claims_release_binding_unique unique (
    id,
    partner_id,
    relationship_epoch
  ),
  constraint partner_claims_profile_correction_binding_unique unique (
    id,
    partner_id,
    accepted_by,
    relationship_epoch,
    claim_epoch
  ),
  constraint partner_claims_invite_binding_fk foreign key (
    invite_id,
    partner_id,
    accepted_by,
    legal_relationship_type,
    relationship_epoch,
    claim_epoch,
    claim_role
  ) references partner_onboarding_private.partner_invites (
    id,
    partner_id,
    recipient_user_id,
    legal_relationship_type,
    relationship_epoch,
    claim_epoch,
    claim_role
  ) on delete restrict
);

create table if not exists partner_onboarding_private.partner_claim_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  claim_id uuid not null unique references partner_onboarding_private.partner_claims(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.partner_claim_profile_corrections (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  claim_id uuid not null references partner_onboarding_private.partner_claims(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  relationship_epoch integer not null check (relationship_epoch > 0),
  claim_epoch integer not null check (claim_epoch > 0),
  previous_profile_sha256 text not null check (
    previous_profile_sha256 ~ '^[a-f0-9]{64}$'
  ),
  correction_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(correction_snapshot) = 'object'
  ),
  correction_sha256 text not null check (correction_sha256 ~ '^[a-f0-9]{64}$'),
  resulting_profile_sha256 text not null check (
    resulting_profile_sha256 ~ '^[a-f0-9]{64}$'
  ),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (actor_id, request_key),
  constraint partner_claim_profile_corrections_changed_profile_check check (
    previous_profile_sha256 <> resulting_profile_sha256
  ),
  constraint partner_claim_profile_corrections_receipt_binding_unique unique (
    id,
    partner_id,
    claim_id,
    actor_id
  ),
  constraint partner_claim_profile_corrections_claim_binding_fk foreign key (
    claim_id,
    partner_id,
    actor_id,
    relationship_epoch,
    claim_epoch
  ) references partner_onboarding_private.partner_claims (
    id,
    partner_id,
    accepted_by,
    relationship_epoch,
    claim_epoch
  ) on delete restrict
);

create index if not exists partner_claim_profile_corrections_current_lookup_idx
  on partner_onboarding_private.partner_claim_profile_corrections(
    partner_id,
    relationship_epoch,
    claim_epoch,
    created_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.partner_applications (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null unique references public.partners(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  business_key_sha256 text not null unique check (business_key_sha256 ~ '^[a-f0-9]{64}$'),
  candidate_relationship_type text not null check (
    candidate_relationship_type in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som')
  ),
  application_snapshot jsonb not null check (pg_catalog.jsonb_typeof(application_snapshot) = 'object'),
  application_sha256 text not null check (application_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'pending' check (status in ('draft', 'submitted', 'pending', 'missing_info')),
  created_at timestamptz not null default pg_catalog.now(),
  constraint partner_applications_request_binding_unique unique (
    id,
    partner_id,
    owner_id
  ),
  constraint partner_applications_business_registry_fk foreign key (
    partner_id,
    business_key_sha256
  ) references partner_onboarding_private.partner_business_registry (
    partner_id,
    business_key_sha256
  ) on delete restrict
);

create table if not exists partner_onboarding_private.partner_application_requests (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  application_id uuid not null,
  partner_id uuid not null references public.partners(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (actor_id, request_key),
  constraint partner_application_requests_application_binding_fk foreign key (
    application_id,
    partner_id,
    actor_id
  ) references partner_onboarding_private.partner_applications (
    id,
    partner_id,
    owner_id
  ) on delete restrict
);

create table if not exists partner_onboarding_private.partner_application_corrections (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  application_id uuid not null,
  partner_id uuid not null references public.partners(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  correction_number integer not null check (correction_number > 0),
  candidate_relationship_type text not null check (
    candidate_relationship_type in (
      'restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som'
    )
  ),
  previous_application_sha256 text not null check (
    previous_application_sha256 ~ '^[a-f0-9]{64}$'
  ),
  corrected_application_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(corrected_application_snapshot) = 'object'
  ),
  corrected_application_sha256 text not null check (
    corrected_application_sha256 ~ '^[a-f0-9]{64}$'
  ),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (actor_id, request_key),
  unique (application_id, correction_number),
  constraint partner_application_corrections_changed_hash_check check (
    previous_application_sha256 <> corrected_application_sha256
  ),
  constraint partner_application_corrections_owner_actor_check check (
    actor_id = owner_id
  ),
  constraint partner_application_corrections_application_binding_fk foreign key (
    application_id,
    partner_id,
    owner_id
  ) references partner_onboarding_private.partner_applications (
    id,
    partner_id,
    owner_id
  ) on delete restrict,
  constraint partner_application_corrections_receipt_binding_unique unique (
    id,
    application_id,
    partner_id,
    owner_id
  )
);

create index if not exists partner_application_corrections_current_lookup_idx
  on partner_onboarding_private.partner_application_corrections(
    application_id,
    correction_number desc,
    created_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.partner_business_key_corrections (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  application_id uuid not null,
  partner_id uuid not null references public.partners(id) on delete restrict,
  application_correction_id uuid not null unique,
  previous_business_key_sha256 text not null check (
    previous_business_key_sha256 ~ '^[a-f0-9]{64}$'
  ),
  corrected_business_key_sha256 text not null check (
    corrected_business_key_sha256 ~ '^[a-f0-9]{64}$'
  ),
  corrected_by uuid not null references auth.users(id) on delete restrict,
  corrected_at timestamptz not null default pg_catalog.now(),
  constraint partner_business_key_corrections_changed_key_check check (
    previous_business_key_sha256 <> corrected_business_key_sha256
  ),
  constraint partner_business_key_corrections_receipt_binding_fk foreign key (
    application_correction_id,
    application_id,
    partner_id,
    corrected_by
  ) references partner_onboarding_private.partner_application_corrections (
    id,
    application_id,
    partner_id,
    owner_id
  ) on delete restrict
);

-- Historical keys remain permanently reserved to one partner, but that same
-- partner may return to an earlier identity spelling (A->B->A). Global
-- cross-partner ownership is enforced by the serialized transition trigger in
-- 002 rather than by a key-only UNIQUE that also forbids safe same-partner
-- reuse. Drop earlier review-package constraints on reapply.
do $drop_legacy_business_key_uniques$
declare
  v_constraint record;
begin
  for v_constraint in
    select constraint_record.conname
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conrelid =
      'partner_onboarding_private.partner_business_key_corrections'::regclass
      and constraint_record.contype = 'u'
      and pg_catalog.cardinality(constraint_record.conkey) = 1
      and exists (
        select 1
        from pg_catalog.pg_attribute attribute_record
        where attribute_record.attrelid = constraint_record.conrelid
          and attribute_record.attnum = any(constraint_record.conkey)
          and attribute_record.attname in (
            'previous_business_key_sha256',
            'corrected_business_key_sha256'
          )
      )
  loop
    execute pg_catalog.format(
      'alter table partner_onboarding_private.partner_business_key_corrections drop constraint %I',
      v_constraint.conname
    );
  end loop;
end;
$drop_legacy_business_key_uniques$;

create index if not exists partner_business_key_corrections_previous_key_lookup_idx
  on partner_onboarding_private.partner_business_key_corrections(
    previous_business_key_sha256,
    partner_id
  );

create index if not exists partner_business_key_corrections_corrected_key_lookup_idx
  on partner_onboarding_private.partner_business_key_corrections(
    corrected_business_key_sha256,
    partner_id
  );

create index if not exists partner_business_key_corrections_current_lookup_idx
  on partner_onboarding_private.partner_business_key_corrections(
    partner_id,
    corrected_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.partner_profile_correction_requests (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  request_key uuid not null,
  correction_source text not null check (
    correction_source in ('application', 'claim')
  ),
  application_receipt_id uuid,
  claim_receipt_id uuid,
  relationship_epoch integer check (relationship_epoch is null or relationship_epoch > 0),
  claim_epoch integer check (claim_epoch is null or claim_epoch > 0),
  application_correction_receipt_id uuid,
  claim_profile_correction_receipt_id uuid,
  submitted_sha256 text not null check (submitted_sha256 ~ '^[a-f0-9]{64}$'),
  previous_sha256 text not null check (previous_sha256 ~ '^[a-f0-9]{64}$'),
  resulting_sha256 text not null check (resulting_sha256 ~ '^[a-f0-9]{64}$'),
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  private_profile_status text not null check (
    private_profile_status in ('draft', 'submitted', 'pending', 'missing_info')
  ),
  created_at timestamptz not null default pg_catalog.now(),
  unique (actor_id, request_key),
  constraint partner_profile_correction_requests_mode_binding_check check (
    (
      correction_source = 'application'
      and application_receipt_id is not null
      and application_correction_receipt_id is not null
      and claim_receipt_id is null
      and claim_profile_correction_receipt_id is null
      and relationship_epoch is null
      and claim_epoch is null
    )
    or (
      correction_source = 'claim'
      and application_receipt_id is null
      and application_correction_receipt_id is null
      and claim_receipt_id is not null
      and claim_profile_correction_receipt_id is not null
      and relationship_epoch is not null
      and claim_epoch is not null
    )
  ),
  constraint partner_profile_correction_requests_application_binding_fk foreign key (
    application_receipt_id,
    partner_id,
    actor_id
  ) references partner_onboarding_private.partner_applications (
    id,
    partner_id,
    owner_id
  ) on delete restrict,
  constraint partner_profile_correction_requests_application_correction_binding_fk foreign key (
    application_correction_receipt_id,
    application_receipt_id,
    partner_id,
    actor_id
  ) references partner_onboarding_private.partner_application_corrections (
    id,
    application_id,
    partner_id,
    owner_id
  ) on delete restrict,
  constraint partner_profile_correction_requests_claim_binding_fk foreign key (
    claim_receipt_id,
    partner_id,
    actor_id,
    relationship_epoch,
    claim_epoch
  ) references partner_onboarding_private.partner_claims (
    id,
    partner_id,
    accepted_by,
    relationship_epoch,
    claim_epoch
  ) on delete restrict,
  constraint partner_profile_correction_requests_claim_correction_binding_fk foreign key (
    claim_profile_correction_receipt_id,
    partner_id,
    claim_receipt_id,
    actor_id
  ) references partner_onboarding_private.partner_claim_profile_corrections (
    id,
    partner_id,
    claim_id,
    actor_id
  ) on delete restrict
);

create index if not exists partner_profile_correction_requests_partner_lookup_idx
  on partner_onboarding_private.partner_profile_correction_requests(
    partner_id,
    created_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.partner_actor_authority_grants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  authority_type text not null check (authority_type = 'authorized_signer'),
  relationship_epoch integer not null check (relationship_epoch > 0),
  verified_email text not null,
  verified_legal_name text not null,
  verified_title text not null,
  verified_by uuid not null references auth.users(id) on delete restrict,
  verified_at timestamptz not null default pg_catalog.now(),
  unique (partner_id, user_id, authority_type, relationship_epoch)
);

create table if not exists partner_onboarding_private.partner_actor_authority_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  authority_grant_id uuid not null unique references partner_onboarding_private.partner_actor_authority_grants(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.staff_bootstrap_authorizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  authority_type text not null check (authority_type = 'security_admin'),
  authorization_reference text not null check (
    nullif(pg_catalog.btrim(authorization_reference), '') is not null
  ),
  authorized_by_database_role text not null default current_user,
  authorized_at timestamptz not null default pg_catalog.now(),
  constraint staff_bootstrap_authorizations_exact_binding_unique unique (
    id,
    user_id,
    authority_type
  )
);

create table if not exists partner_onboarding_private.staff_authority_grants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  authority_type text not null check (
    authority_type in (
      'security_admin',
      'legal_admin',
      'evidence_reviewer',
      'release_reviewer',
      'swipe_attestor',
      'website_attestor',
      'local_attestor'
    )
  ),
  granted_by uuid not null references auth.users(id) on delete restrict,
  granted_at timestamptz not null default pg_catalog.now()
);

create index if not exists staff_authority_grants_lookup_idx
  on partner_onboarding_private.staff_authority_grants(
    user_id,
    authority_type,
    granted_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.staff_authority_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  authority_grant_id uuid not null unique references partner_onboarding_private.staff_authority_grants(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.partner_agreement_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  legal_relationship_type text not null check (
    legal_relationship_type in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som')
  ),
  agreement_version text not null,
  title text not null,
  effective_at timestamptz not null,
  document_snapshot text not null,
  document_sha256 text not null check (document_sha256 ~ '^[a-f0-9]{64}$'),
  assent_text text not null,
  incorporated_versions jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(incorporated_versions) = 'object'
  ),
  legal_approval_reference text not null,
  legal_approved_by uuid not null references auth.users(id) on delete restrict,
  legal_approved_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (legal_relationship_type, agreement_version),
  unique (document_sha256),
  constraint partner_agreement_versions_type_binding_unique unique (
    id,
    legal_relationship_type
  )
);

create table if not exists partner_onboarding_private.current_agreement_versions (
  legal_relationship_type text primary key check (
    legal_relationship_type in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som')
  ),
  agreement_version_id uuid not null unique,
  selected_by uuid not null references auth.users(id) on delete restrict,
  selected_at timestamptz not null default pg_catalog.now(),
  constraint current_agreement_versions_type_binding_fk foreign key (
    agreement_version_id,
    legal_relationship_type
  ) references partner_onboarding_private.partner_agreement_versions (
    id,
    legal_relationship_type
  ) on delete restrict
);

create table if not exists partner_onboarding_private.partner_agreement_acceptances (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  agreement_version_id uuid not null,
  accepted_owner_id uuid not null references auth.users(id) on delete restrict,
  accepted_by uuid not null references auth.users(id) on delete restrict,
  legal_relationship_type text not null check (
    legal_relationship_type in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som')
  ),
  relationship_epoch integer not null check (relationship_epoch > 0),
  agreement_version text not null,
  title text not null,
  effective_at timestamptz not null,
  document_snapshot text not null,
  document_sha256 text not null check (document_sha256 ~ '^[a-f0-9]{64}$'),
  assent_text text not null,
  incorporated_versions jsonb not null check (
    pg_catalog.jsonb_typeof(incorporated_versions) = 'object'
  ),
  legal_approval_reference text not null,
  legal_approved_at timestamptz not null,
  signer_email text not null,
  assertions_snapshot jsonb not null check (pg_catalog.jsonb_typeof(assertions_snapshot) = 'object'),
  assertions_sha256 text not null check (assertions_sha256 ~ '^[a-f0-9]{64}$'),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  request_evidence jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(request_evidence) = 'object'),
  accepted_at timestamptz not null default pg_catalog.now(),
  unique (accepted_by, request_key),
  constraint partner_acceptances_release_binding_unique unique (
    id,
    partner_id,
    relationship_epoch
  ),
  constraint partner_acceptances_agreement_type_binding_fk foreign key (
    agreement_version_id,
    legal_relationship_type
  ) references partner_onboarding_private.partner_agreement_versions (
    id,
    legal_relationship_type
  ) on delete restrict
);

create index if not exists partner_acceptances_current_lookup_idx
  on partner_onboarding_private.partner_agreement_acceptances(
    partner_id,
    relationship_epoch,
    agreement_version_id,
    accepted_at desc,
    id desc
  );

create table if not exists partner_onboarding_private.partner_agreement_acceptance_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  acceptance_id uuid not null unique references partner_onboarding_private.partner_agreement_acceptances(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.partner_evidence_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  evidence_type text not null check (
    evidence_type in (
      'profile',
      'media',
      'compliance',
      'local_identity',
      'smoke_test',
      'partner_consent',
      'heha_review'
    )
  ),
  relationship_epoch integer not null check (relationship_epoch > 0),
  subject_sha256 text not null check (subject_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_snapshot jsonb not null check (pg_catalog.jsonb_typeof(evidence_snapshot) = 'object'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[a-f0-9]{64}$'),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default pg_catalog.now(),
  unique (issued_by, request_key),
  constraint partner_evidence_receipts_release_binding_unique unique (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  )
);

create index if not exists partner_evidence_current_lookup_idx
  on partner_onboarding_private.partner_evidence_receipts(
    partner_id,
    relationship_epoch,
    evidence_type,
    issued_at desc
  );

create table if not exists partner_onboarding_private.partner_evidence_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  evidence_id uuid not null unique references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.partner_release_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  relationship_epoch integer not null check (relationship_epoch > 0),
  claim_evidence_id uuid not null references partner_onboarding_private.partner_claims(id) on delete restrict,
  agreement_acceptance_id uuid not null references partner_onboarding_private.partner_agreement_acceptances(id) on delete restrict,
  profile_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  profile_evidence_type text not null default 'profile' check (profile_evidence_type = 'profile'),
  media_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  media_evidence_type text not null default 'media' check (media_evidence_type = 'media'),
  compliance_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  compliance_evidence_type text not null default 'compliance' check (compliance_evidence_type = 'compliance'),
  local_identity_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  local_identity_evidence_type text not null default 'local_identity' check (
    local_identity_evidence_type = 'local_identity'
  ),
  smoke_test_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  smoke_test_evidence_type text not null default 'smoke_test' check (
    smoke_test_evidence_type = 'smoke_test'
  ),
  partner_consent_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  partner_consent_evidence_type text not null default 'partner_consent' check (
    partner_consent_evidence_type = 'partner_consent'
  ),
  heha_review_evidence_id uuid not null references partner_onboarding_private.partner_evidence_receipts(id) on delete restrict,
  heha_review_evidence_type text not null default 'heha_review' check (
    heha_review_evidence_type = 'heha_review'
  ),
  preview_sha256 text not null check (preview_sha256 ~ '^[a-f0-9]{64}$'),
  swipe_publication_authorized boolean not null,
  website_publication_authorized boolean not null,
  local_orderability_authorized boolean not null,
  release_epoch integer not null check (release_epoch > 0),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  released_by uuid not null references auth.users(id) on delete restrict,
  released_at timestamptz not null default pg_catalog.now(),
  unique (released_by, request_key),
  unique (partner_id, release_epoch),
  constraint partner_release_activation_binding_unique unique (id, partner_id),
  constraint partner_release_claim_binding_fk foreign key (
    claim_evidence_id,
    partner_id,
    relationship_epoch
  ) references partner_onboarding_private.partner_claims (
    id,
    partner_id,
    relationship_epoch
  ) on delete restrict,
  constraint partner_release_acceptance_binding_fk foreign key (
    agreement_acceptance_id,
    partner_id,
    relationship_epoch
  ) references partner_onboarding_private.partner_agreement_acceptances (
    id,
    partner_id,
    relationship_epoch
  ) on delete restrict,
  constraint partner_release_profile_evidence_binding_fk foreign key (
    profile_evidence_id,
    partner_id,
    relationship_epoch,
    profile_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict,
  constraint partner_release_media_evidence_binding_fk foreign key (
    media_evidence_id,
    partner_id,
    relationship_epoch,
    media_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict,
  constraint partner_release_compliance_evidence_binding_fk foreign key (
    compliance_evidence_id,
    partner_id,
    relationship_epoch,
    compliance_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict,
  constraint partner_release_local_identity_evidence_binding_fk foreign key (
    local_identity_evidence_id,
    partner_id,
    relationship_epoch,
    local_identity_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict,
  constraint partner_release_smoke_test_evidence_binding_fk foreign key (
    smoke_test_evidence_id,
    partner_id,
    relationship_epoch,
    smoke_test_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict,
  constraint partner_release_partner_consent_evidence_binding_fk foreign key (
    partner_consent_evidence_id,
    partner_id,
    relationship_epoch,
    partner_consent_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict,
  constraint partner_release_heha_review_evidence_binding_fk foreign key (
    heha_review_evidence_id,
    partner_id,
    relationship_epoch,
    heha_review_evidence_type
  ) references partner_onboarding_private.partner_evidence_receipts (
    id,
    partner_id,
    relationship_epoch,
    evidence_type
  ) on delete restrict
);

create table if not exists partner_onboarding_private.partner_release_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  release_receipt_id uuid not null unique references partner_onboarding_private.partner_release_receipts(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.partner_surface_activation_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  release_receipt_id uuid not null,
  surface text not null check (surface in ('swipe', 'website', 'local_orderability')),
  target_partner_id uuid not null,
  target_receipt_id text not null,
  activation_snapshot jsonb not null check (pg_catalog.jsonb_typeof(activation_snapshot) = 'object'),
  activation_sha256 text not null check (activation_sha256 ~ '^[a-f0-9]{64}$'),
  request_key uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  activated_by uuid not null references auth.users(id) on delete restrict,
  activated_at timestamptz not null default pg_catalog.now(),
  unique (activated_by, request_key),
  unique (release_receipt_id, surface),
  constraint partner_surface_activation_target_receipt_unique unique (
    surface,
    target_receipt_id
  ),
  constraint partner_surface_activation_release_binding_fk foreign key (
    release_receipt_id,
    partner_id
  ) references partner_onboarding_private.partner_release_receipts (
    id,
    partner_id
  ) on delete restrict
);

create table if not exists partner_onboarding_private.partner_surface_activation_revocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  activation_receipt_id uuid not null unique references partner_onboarding_private.partner_surface_activation_receipts(id) on delete restrict,
  revoked_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  revoked_at timestamptz not null default pg_catalog.now()
);

create table if not exists partner_onboarding_private.audit_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  partner_id uuid references public.partners(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null,
  receipt_id uuid,
  event_data jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(event_data) = 'object'),
  occurred_at timestamptz not null default pg_catalog.now()
);

create or replace function partner_onboarding_private.partner_profile_sha256(p_partner_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  select partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p.id,
        'created_at', p.created_at,
        'name', p.name,
        'legal_name', p.legal_name,
        'postal_code', p.postal_code,
        'category', p.category,
        'categories', p.categories,
        'location', p.location,
        'instagram', p.instagram,
        'website', p.website,
        'bio', p.bio,
        'tags', p.tags,
        'rating', p.rating,
        'review_count', p.review_count,
        'distance_text', p.distance_text,
        'complete_pct', p.complete_pct,
        'business_type', p.business_type,
        'offerings', p.offerings,
        'hours', p.hours,
        'neighborhood', p.neighborhood,
        'tagline', p.tagline,
        'items', p.items,
        'price_range', p.price_range,
        'partner_type', p.partner_type,
        'delivery_days', p.delivery_days,
        'pricing_notes', p.pricing_notes,
        'heha_pillar', p.heha_pillar,
        'local_lane', p.local_lane,
        'primary_cta_destination', p.primary_cta_destination,
        'primary_cta_label', p.primary_cta_label,
        'primary_cta_path', p.primary_cta_path
      )
    )
  )
  from public.partners p
  where p.id = p_partner_id;
$function$;

create or replace function partner_onboarding_private.partner_media_sha256(p_partner_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  select partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p.id,
        'color', p.color,
        'photo_emoji', p.photo_emoji,
        'image_url', p.image_url,
        'gallery_urls', p.gallery_urls
      )
    )
  )
  from public.partners p
  where p.id = p_partner_id;
$function$;

create or replace function partner_onboarding_private.partner_preview_sha256(p_partner_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  select partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'schema_version', 'partner-public-card-v1',
        'partner_id', p.id,
        'profile_sha256', partner_onboarding_private.partner_profile_sha256(p.id),
        'media_sha256', partner_onboarding_private.partner_media_sha256(p.id)
      )
    )
  )
  from public.partners p
  where p.id = p_partner_id;
$function$;

-- The profile + media hashes bind every public-card field copied from
-- public.partners. Surface and receipt identifiers are bound by the activation
-- receipt; updated_at and constant live-state fields are produced only by the
-- guarded activation transition rather than copied from the source row.
revoke all on all tables in schema partner_onboarding_private
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on all sequences in schema partner_onboarding_private
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on all functions in schema partner_onboarding_private
  from public, anon, authenticated, service_role, supabase_auth_admin;

do $append_only_triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'partner_business_registry',
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
    execute pg_catalog.format(
      'drop trigger if exists reject_append_only_mutation on partner_onboarding_private.%I',
      v_table
    );
    execute pg_catalog.format(
      'create trigger reject_append_only_mutation before update or delete on partner_onboarding_private.%I for each row execute function partner_onboarding_private.reject_append_only_mutation()',
      v_table
    );
    execute pg_catalog.format(
      'drop trigger if exists reject_append_only_truncate on partner_onboarding_private.%I',
      v_table
    );
    execute pg_catalog.format(
      'create trigger reject_append_only_truncate before truncate on partner_onboarding_private.%I for each statement execute function partner_onboarding_private.reject_append_only_mutation()',
      v_table
    );
  end loop;
end;
$append_only_triggers$;

do $private_rls$
declare
  v_table text;
begin
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
    execute pg_catalog.format(
      'alter table partner_onboarding_private.%I enable row level security',
      v_table
    );
    execute pg_catalog.format(
      'alter table partner_onboarding_private.%I force row level security',
      v_table
    );
  end loop;
end;
$private_rls$;

drop trigger if exists runtime_config_set_updated_at on partner_onboarding_private.runtime_config;
create trigger runtime_config_set_updated_at
before update on partner_onboarding_private.runtime_config
for each row execute function partner_onboarding_private.set_updated_at();

drop trigger if exists partner_state_set_updated_at on partner_onboarding_private.partner_state;
create trigger partner_state_set_updated_at
before update on partner_onboarding_private.partner_state
for each row execute function partner_onboarding_private.set_updated_at();

commit;
