-- Converged partner-publication boundary for the #118 + #120 + #124 RC.
-- REVIEW ONLY / PRODUCTION FROZEN.
--
-- This migration is intentionally last in the combined lexical order. It is
-- the sole final owner of app_private.partner_publication_projection and the
-- three public partner views. It preserves the append-only owner-consent
-- ledger, adds an independent exact-version HEHA staff review ledger, keeps
-- raw partner rows owner/internal-only, and exposes only the reviewed 33-column
-- public card contract.

-- ---------------------------------------------------------------------------
-- 1. Fail closed unless every donor dependency reached this exact point.
-- ---------------------------------------------------------------------------
do $donor_contract$
declare
  required_column text;
  view_name text;
  expected_columns constant text[] := array[
    'id','created_at','name','category','categories','instagram','website','bio',
    'tags','rating','review_count','distance_text','color','photo_emoji',
    'heha_partner','status','hours','business_type','offerings','neighborhood',
    'tagline','items','image_url','price_range','gallery_urls','partner_type',
    'delivery_days','heha_pillar','local_eligible','local_lane',
    'primary_cta_destination','primary_cta_label','primary_cta_path'
  ]::text[];
  actual_columns text[];
begin
  if pg_catalog.to_regclass('public.partners') is null
     or pg_catalog.to_regclass('public.user_roles') is null
     or pg_catalog.to_regclass('public.partner_publication_consent_events') is null
     or pg_catalog.to_regclass('app_private.partner_publication_projection') is null then
    raise exception using
      errcode='55000',
      message='The publication-consent and lifecycle donor objects must exist before the integration migration.';
  end if;

  if pg_catalog.to_regprocedure('app_private.partner_public_profile_snapshot(public.partners)') is null
     or pg_catalog.to_regprocedure('app_private.partner_public_profile_hash(public.partners)') is null
     or pg_catalog.to_regprocedure('app_private.is_wave1_food_partner(public.partners)') is null
     or pg_catalog.to_regprocedure('app_private.wave1_local_lane(public.partners)') is null
     or pg_catalog.to_regprocedure(
       'app_private.has_current_partner_publication_authorization(public.partners,text)'
     ) is null
     or pg_catalog.to_regprocedure('app_private.has_internal_role(text[])') is null
     or pg_catalog.to_regprocedure('app_private.is_service_role_request()') is null then
    raise exception using
      errcode='55000',
      message='The exact consent snapshot and non-forgeable authority helpers are required before publication integration.';
  end if;

  foreach required_column in array array[
    'id','owner_id','status','is_test_record','website_eligible','swipe_eligible',
    'local_eligible','local_lane','primary_cta_destination','primary_cta_label',
    'primary_cta_path','claim_status','partnership_status','contract_status',
    'listing_status'
  ]::text[] loop
    if not exists (
      select 1
      from pg_catalog.pg_attribute
      where attrelid='public.partners'::regclass
        and attname=required_column
        and not attisdropped
    ) then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('Required lifecycle column public.partners.%I is missing.',required_column);
    end if;
  end loop;

  foreach view_name in array array[
    'public_partner_directory','public_swipe_partners','public_local_partners'
  ]::text[] loop
    if pg_catalog.to_regclass(pg_catalog.format('public.%I',view_name)) is null then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('Required donor view public.%I is missing.',view_name);
    end if;

    select pg_catalog.array_agg(column_name order by ordinal_position)
    into actual_columns
    from information_schema.columns
    where table_schema='public' and table_name=view_name;

    if actual_columns is distinct from expected_columns then
      raise exception using
        errcode='55000',
        message=pg_catalog.format(
          'Unsafe donor column contract for public.%I: expected %s, found %s',
          view_name,
          expected_columns,
          actual_columns
        );
    end if;
  end loop;
end;
$donor_contract$;

-- ---------------------------------------------------------------------------
-- 2. Independent, append-only HEHA staff review evidence.
--
-- Owner consent and HEHA review remain separate facts. The service backend may
-- record a decision only for an identified, currently active super_admin or
-- pm_admin. Both the current owner and the exact server-captured public profile
-- are snapshotted so owner transfer or profile drift invalidates publication.
-- ---------------------------------------------------------------------------
do $consent_event_pair_key$
declare
  id_attnum smallint;
  sequence_attnum smallint;
begin
  select attnum into id_attnum
  from pg_catalog.pg_attribute
  where attrelid='public.partner_publication_consent_events'::regclass
    and attname='id'
    and not attisdropped;

  select attnum into sequence_attnum
  from pg_catalog.pg_attribute
  where attrelid='public.partner_publication_consent_events'::regclass
    and attname='event_sequence'
    and not attisdropped;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid='public.partner_publication_consent_events'::regclass
      and conname='partner_publication_consent_events_id_sequence_key'
  ) then
    alter table public.partner_publication_consent_events
      add constraint partner_publication_consent_events_id_sequence_key
      unique(id,event_sequence);
  elsif not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid='public.partner_publication_consent_events'::regclass
      and conname='partner_publication_consent_events_id_sequence_key'
      and contype='u'
      and conkey=array[id_attnum,sequence_attnum]::smallint[]
  ) then
    raise exception using
      errcode='55000',
      message='Consent event composite identity constraint is malformed.';
  end if;
end;
$consent_event_pair_key$;

create table if not exists public.partner_publication_review_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  event_sequence bigint generated always as identity unique,
  partner_id uuid not null references public.partners(id) on delete restrict,
  owner_id uuid not null,
  destination text not null,
  decision text not null,
  consent_event_id uuid not null,
  consent_event_sequence bigint not null,
  profile_snapshot jsonb not null,
  profile_snapshot_hash text not null,
  request_key uuid not null unique,
  request_payload_hash text not null,
  reviewed_by uuid not null,
  reviewed_at timestamptz not null default pg_catalog.now(),
  reason text,
  constraint partner_publication_review_destination_check
    check (destination=any(array['heha_swipe','heha_local']::text[])),
  constraint partner_publication_review_decision_check
    check (decision=any(array['approved','rejected']::text[])),
  constraint partner_publication_review_consent_event_fkey
    foreign key(consent_event_id,consent_event_sequence)
    references public.partner_publication_consent_events(id,event_sequence)
    on delete restrict,
  constraint partner_publication_review_snapshot_object_check
    check (pg_catalog.jsonb_typeof(profile_snapshot)='object'),
  constraint partner_publication_review_snapshot_hash_check
    check (profile_snapshot_hash ~ '^[0-9a-f]{64}$'),
  constraint partner_publication_review_request_hash_check
    check (request_payload_hash ~ '^[0-9a-f]{64}$'),
  constraint partner_publication_review_reason_check
    check (
      reason is null
      or pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 2000
    ),
  constraint partner_publication_review_rejection_reason_check
    check (decision<>'rejected' or reason is not null)
);

comment on table public.partner_publication_review_events is
  'Private append-only HEHA staff publication review evidence. Owner and reviewer UUIDs are immutable evidence snapshots and are subject to the approved retention/anonymization policy.';

create index if not exists partner_publication_review_partner_timeline_idx
  on public.partner_publication_review_events
  (partner_id,destination,event_sequence desc);

alter table public.partner_publication_review_events enable row level security;

do $review_table_contract$
declare
  expected_columns constant text[] := array[
    'id','event_sequence','partner_id','owner_id','destination','decision',
    'consent_event_id','consent_event_sequence','profile_snapshot',
    'profile_snapshot_hash','request_key','request_payload_hash','reviewed_by',
    'reviewed_at','reason'
  ]::text[];
  expected_constraints constant text[] := array[
    'partner_publication_review_consent_event_fkey:f',
    'partner_publication_review_decision_check:c',
    'partner_publication_review_destination_check:c',
    'partner_publication_review_events_event_sequence_key:u',
    'partner_publication_review_events_partner_id_fkey:f',
    'partner_publication_review_events_pkey:p',
    'partner_publication_review_events_request_key_key:u',
    'partner_publication_review_reason_check:c',
    'partner_publication_review_rejection_reason_check:c',
    'partner_publication_review_request_hash_check:c',
    'partner_publication_review_snapshot_hash_check:c',
    'partner_publication_review_snapshot_object_check:c'
  ]::text[];
  actual_columns text[];
  actual_constraints text[];
  consent_id_attnum smallint;
  consent_sequence_attnum smallint;
  review_consent_id_attnum smallint;
  review_consent_sequence_attnum smallint;
begin
  select pg_catalog.array_agg(column_name order by ordinal_position)
  into actual_columns
  from information_schema.columns
  where table_schema='public'
    and table_name='partner_publication_review_events';

  if actual_columns is distinct from expected_columns then
    raise exception using
      errcode='55000',
      message=pg_catalog.format(
        'Unexpected partner publication review ledger contract: expected %s, found %s',
        expected_columns,
        actual_columns
      );
  end if;

  select pg_catalog.array_agg(conname::text||':'||contype::text order by conname)
  into actual_constraints
  from pg_catalog.pg_constraint
  where conrelid='public.partner_publication_review_events'::regclass;

  if actual_constraints is distinct from expected_constraints then
    raise exception using
      errcode='55000',
      message=pg_catalog.format(
        'Unexpected partner publication review constraints: expected %s, found %s',
        expected_constraints,
        actual_constraints
      );
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy
    where polrelid='public.partner_publication_review_events'::regclass
  ) then
    raise exception using
      errcode='55000',
      message='Partner publication review ledger must not carry browser RLS policies.';
  end if;

  select attnum into consent_id_attnum
  from pg_catalog.pg_attribute
  where attrelid='public.partner_publication_consent_events'::regclass
    and attname='id' and not attisdropped;
  select attnum into consent_sequence_attnum
  from pg_catalog.pg_attribute
  where attrelid='public.partner_publication_consent_events'::regclass
    and attname='event_sequence' and not attisdropped;
  select attnum into review_consent_id_attnum
  from pg_catalog.pg_attribute
  where attrelid='public.partner_publication_review_events'::regclass
    and attname='consent_event_id' and not attisdropped;
  select attnum into review_consent_sequence_attnum
  from pg_catalog.pg_attribute
  where attrelid='public.partner_publication_review_events'::regclass
    and attname='consent_event_sequence' and not attisdropped;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid='public.partner_publication_review_events'::regclass
      and conname='partner_publication_review_consent_event_fkey'
      and contype='f'
      and confrelid='public.partner_publication_consent_events'::regclass
      and confdeltype='r'
      and conkey=array[review_consent_id_attnum,review_consent_sequence_attnum]::smallint[]
      and confkey=array[consent_id_attnum,consent_sequence_attnum]::smallint[]
  ) then
    raise exception using
      errcode='55000',
      message='Partner publication review consent-event binding is not the exact composite restrictive foreign key.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid='public.partner_publication_review_events'::regclass
      and attname='event_sequence'
      and attidentity='a'
      and attnotnull
      and atttypid='pg_catalog.int8'::regtype
  ) or not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid='public.partner_publication_review_events'::regclass
      and attname='profile_snapshot_hash'
      and attnotnull
      and atttypid='pg_catalog.text'::regtype
  ) then
    raise exception using
      errcode='55000',
      message='Partner publication review identity/type contract is malformed.';
  end if;
end;
$review_table_contract$;

create or replace function app_private.guard_partner_publication_review_immutability()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception using
    errcode='42501',
    message='Partner publication review evidence is append-only.';
end;
$function$;

revoke all on function app_private.guard_partner_publication_review_immutability()
  from public,anon,authenticated,service_role;

drop trigger if exists partner_publication_review_events_immutable
  on public.partner_publication_review_events;
create trigger partner_publication_review_events_immutable
before update or delete on public.partner_publication_review_events
for each row execute function app_private.guard_partner_publication_review_immutability();

revoke all on table public.partner_publication_review_events
  from public,anon,authenticated,service_role;
revoke all on sequence public.partner_publication_review_events_event_sequence_seq
  from public,anon,authenticated,service_role;
grant select on table public.partner_publication_review_events to service_role;

create or replace function public.record_partner_publication_review(
  p_request_key uuid,
  p_partner_id uuid,
  p_destination text,
  p_expected_profile_snapshot_hash text,
  p_decision text,
  p_reviewed_by uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  partner_row public.partners%rowtype;
  current_consent public.partner_publication_consent_events%rowtype;
  existing_event public.partner_publication_review_events%rowtype;
  current_snapshot jsonb;
  current_snapshot_hash text;
  normalized_reason text := nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
  payload_hash text;
  new_id uuid;
begin
  if not app_private.is_service_role_request() then
    raise exception using
      errcode='42501',
      message='Only the service role may record HEHA publication review evidence.';
  end if;
  if p_request_key is null or p_partner_id is null or p_reviewed_by is null then
    raise exception using
      errcode='22023',
      message='Request, partner and reviewer identifiers are required.';
  end if;
  if p_destination is null
     or p_destination<>all(array['heha_swipe','heha_local']::text[]) then
    raise exception using errcode='22023',message='Invalid publication destination.';
  end if;
  if p_decision is null
     or p_decision<>all(array['approved','rejected']::text[]) then
    raise exception using errcode='22023',message='Invalid publication review decision.';
  end if;
  if p_expected_profile_snapshot_hash is null
     or p_expected_profile_snapshot_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode='22023',
      message='An exact SHA-256 public profile snapshot hash is required.';
  end if;
  if p_decision='rejected' and normalized_reason is null then
    raise exception using errcode='22023',message='A rejection reason is required.';
  end if;
  if normalized_reason is not null
     and pg_catalog.char_length(normalized_reason) not between 3 and 2000 then
    raise exception using errcode='22023',message='Review reason length is invalid.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-publication-review-request:'||p_request_key::text,0)
  );

  payload_hash := pg_catalog.encode(
    extensions.digest(
      pg_catalog.jsonb_build_object(
        'partner_id',p_partner_id,
        'destination',p_destination,
        'expected_profile_snapshot_hash',p_expected_profile_snapshot_hash,
        'decision',p_decision,
        'reviewed_by',p_reviewed_by,
        'reason',normalized_reason
      )::text,
      'sha256'
    ),
    'hex'
  );

  select event_row.* into existing_event
  from public.partner_publication_review_events event_row
  where event_row.request_key=p_request_key;

  if found then
    if existing_event.request_payload_hash is distinct from payload_hash then
      raise exception using
        errcode='23505',
        message='This review request key was already used with different evidence.';
    end if;
    return existing_event.id;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-publication-review-partner:'||p_partner_id::text,0)
  );

  select p.* into partner_row
  from public.partners p
  where p.id=p_partner_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='Partner profile not found.';
  end if;
  if partner_row.owner_id is null then
    raise exception using
      errcode='23514',
      message='A currently owned partner profile is required for publication review.';
  end if;

  -- FOR SHARE prevents an active reviewer role from being deactivated between
  -- authorization and evidence insertion. Exact replay returned above does not
  -- depend on the reviewer's later employment/role state.
  perform 1
  from public.user_roles role_row
  where role_row.user_id=p_reviewed_by
    and role_row.active
    and role_row.role=any(array['super_admin','pm_admin']::text[])
  order by role_row.id
  limit 1
  for share;
  if not found then
    raise exception using
      errcode='42501',
      message='Publication reviewer must be an active super_admin or pm_admin.';
  end if;

  current_snapshot := app_private.partner_public_profile_snapshot(partner_row);
  current_snapshot_hash := app_private.partner_public_profile_hash(partner_row);
  if current_snapshot_hash is distinct from p_expected_profile_snapshot_hash then
    raise exception using
      errcode='23514',
      message='The partner profile changed before HEHA publication review was recorded.';
  end if;

  if not app_private.has_current_partner_publication_authorization(
    partner_row,
    p_destination
  ) then
    raise exception using
      errcode='23514',
      message='Current owner preparation and publication consent are required before HEHA staff review.';
  end if;

  select consent_row.* into current_consent
  from public.partner_publication_consent_events consent_row
  where consent_row.partner_id=partner_row.id
    and consent_row.destination=p_destination
    and consent_row.action='publish_profile'
  order by consent_row.event_sequence desc
  limit 1;

  if not found
     or current_consent.owner_id is distinct from partner_row.owner_id
     or current_consent.state<>'granted'
     or current_consent.consent_statement_version<>'wave1-profile-consent-2026-08-10'
     or current_consent.media_permission_confirmed is not true
     or current_consent.profile_snapshot is distinct from current_snapshot
     or current_consent.profile_snapshot_hash is distinct from current_snapshot_hash then
    raise exception using
      errcode='23514',
      message='Current exact-version owner publication consent is required before HEHA staff review.';
  end if;

  insert into public.partner_publication_review_events(
    partner_id,owner_id,destination,decision,consent_event_id,
    consent_event_sequence,profile_snapshot,profile_snapshot_hash,request_key,
    request_payload_hash,reviewed_by,reason
  ) values (
    partner_row.id,partner_row.owner_id,p_destination,p_decision,current_consent.id,
    current_consent.event_sequence,current_snapshot,current_snapshot_hash,p_request_key,
    payload_hash,p_reviewed_by,normalized_reason
  )
  returning id into new_id;

  return new_id;
end;
$function$;

revoke all on function public.record_partner_publication_review(
  uuid,uuid,text,text,text,uuid,text
) from public,anon,authenticated,service_role;
grant execute on function public.record_partner_publication_review(
  uuid,uuid,text,text,text,uuid,text
) to service_role;

-- The legacy approve_partner RPC conflates review, routing and publication. It
-- is not part of the integrated contract. HEHA relationship approval remains
-- the separate evidence-bound approve_heha_partnership(uuid,uuid) RPC.
do $retire_legacy_approval$
begin
  if pg_catalog.to_regprocedure('public.approve_partner(uuid)') is not null then
    execute 'revoke all on function public.approve_partner(uuid) from public,anon,authenticated,service_role';
    execute 'drop function public.approve_partner(uuid)';
  end if;

  if pg_catalog.to_regprocedure('public.approve_heha_partnership(uuid,uuid)') is null then
    raise exception using
      errcode='55000',
      message='Evidence-bound approve_heha_partnership(uuid,uuid) is required.';
  end if;
end;
$retire_legacy_approval$;

-- ---------------------------------------------------------------------------
-- 3. Raw partner rows: exact owner/internal SELECT boundary and deterministic
-- ACLs. Public discovery is exclusively through the allowlisted views.
-- ---------------------------------------------------------------------------
alter table public.partners enable row level security;

do $partner_select_policy_reset$
declare
  existing_policy record;
begin
  if exists (
    select 1
    from pg_catalog.pg_policy
    where polrelid='public.partners'::regclass
      and polcmd='*'
  ) then
    raise exception using
      errcode='55000',
      message='public.partners has a FOR ALL policy; review it before applying the integrated publication boundary.';
  end if;

  for existing_policy in
    select polname
    from pg_catalog.pg_policy
    where polrelid='public.partners'::regclass
      and polcmd='r'
  loop
    execute pg_catalog.format('drop policy %I on public.partners',existing_policy.polname);
  end loop;
end;
$partner_select_policy_reset$;

create policy "Owners can view own partner"
on public.partners
for select
to authenticated
using (
  (select auth.uid()) is not null
  and (select auth.uid())=owner_id
);

create policy partners_internal_read
on public.partners
for select
to authenticated
using (
  app_private.has_internal_role(
    array[
      'super_admin',
      'pm_admin',
      'community_events_admin',
      'som_admin',
      'developer_admin'
    ]::text[]
  )
);

revoke all on table public.partners from public,anon,authenticated;
grant select,insert,update on table public.partners to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Sole final private projection. The current-owner consent decision and the
-- current HEHA staff decision are independently resolved per destination.
-- Both must match the exact current server snapshot and hash.
-- ---------------------------------------------------------------------------
drop view if exists public.public_partner_directory;
drop view if exists public.public_swipe_partners;
drop view if exists public.public_local_partners;
drop view if exists app_private.partner_publication_projection;

create view app_private.partner_publication_projection
with (security_invoker=false,security_barrier=true)
as
with base as (
  select
    p.*,
    app_private.is_wave1_food_partner(p) as publication_is_wave1_food_partner,
    app_private.wave1_local_lane(p) as publication_derived_local_lane,
    app_private.partner_public_profile_snapshot(p) as publication_current_profile_snapshot,
    app_private.partner_public_profile_hash(p) as publication_current_profile_snapshot_hash
  from public.partners p
), latest_consent_events as (
  select distinct on (event_row.partner_id,event_row.destination,event_row.action)
    event_row.*
  from public.partner_publication_consent_events event_row
  order by
    event_row.partner_id,
    event_row.destination,
    event_row.action,
    event_row.event_sequence desc
), latest_review_events as (
  select distinct on (review_row.partner_id,review_row.destination)
    review_row.*
  from public.partner_publication_review_events review_row
  order by
    review_row.partner_id,
    review_row.destination,
    review_row.event_sequence desc
)
select
  base.*,
  (
    base.owner_id is not null
    and swipe_prepare.owner_id=base.owner_id
    and swipe_publish.owner_id=base.owner_id
    and swipe_prepare.state='granted'
    and swipe_publish.state='granted'
    and swipe_prepare.consent_statement_version='wave1-profile-consent-2026-08-10'
    and swipe_publish.consent_statement_version='wave1-profile-consent-2026-08-10'
    and swipe_prepare.media_permission_confirmed is true
    and swipe_publish.media_permission_confirmed is true
    and swipe_publish.profile_snapshot=base.publication_current_profile_snapshot
    and swipe_publish.profile_snapshot_hash=base.publication_current_profile_snapshot_hash
  ) as publication_current_swipe_owner_authorized,
  (
    base.owner_id is not null
    and local_prepare.owner_id=base.owner_id
    and local_publish.owner_id=base.owner_id
    and local_prepare.state='granted'
    and local_publish.state='granted'
    and local_prepare.consent_statement_version='wave1-profile-consent-2026-08-10'
    and local_publish.consent_statement_version='wave1-profile-consent-2026-08-10'
    and local_prepare.media_permission_confirmed is true
    and local_publish.media_permission_confirmed is true
    and local_prepare.service_area_attested is true
    and local_prepare.local_lane=base.publication_derived_local_lane
    and local_publish.local_lane=base.publication_derived_local_lane
    and local_publish.profile_snapshot=base.publication_current_profile_snapshot
    and local_publish.profile_snapshot_hash=base.publication_current_profile_snapshot_hash
  ) as publication_current_local_owner_authorized,
  (
    base.owner_id is not null
    and swipe_review.owner_id=base.owner_id
    and swipe_review.decision='approved'
    and swipe_review.consent_event_id=swipe_publish.id
    and swipe_review.consent_event_sequence=swipe_publish.event_sequence
    and swipe_review.profile_snapshot=base.publication_current_profile_snapshot
    and swipe_review.profile_snapshot_hash=base.publication_current_profile_snapshot_hash
  ) as publication_current_swipe_staff_approved,
  (
    base.owner_id is not null
    and local_review.owner_id=base.owner_id
    and local_review.decision='approved'
    and local_review.consent_event_id=local_publish.id
    and local_review.consent_event_sequence=local_publish.event_sequence
    and local_review.profile_snapshot=base.publication_current_profile_snapshot
    and local_review.profile_snapshot_hash=base.publication_current_profile_snapshot_hash
  ) as publication_current_local_staff_approved
from base
left join latest_consent_events swipe_prepare
  on swipe_prepare.partner_id=base.id
 and swipe_prepare.destination='heha_swipe'
 and swipe_prepare.action='prepare_profile'
left join latest_consent_events swipe_publish
  on swipe_publish.partner_id=base.id
 and swipe_publish.destination='heha_swipe'
 and swipe_publish.action='publish_profile'
left join latest_consent_events local_prepare
  on local_prepare.partner_id=base.id
 and local_prepare.destination='heha_local'
 and local_prepare.action='prepare_profile'
left join latest_consent_events local_publish
  on local_publish.partner_id=base.id
 and local_publish.destination='heha_local'
 and local_publish.action='publish_profile'
left join latest_review_events swipe_review
  on swipe_review.partner_id=base.id
 and swipe_review.destination='heha_swipe'
left join latest_review_events local_review
  on local_review.partner_id=base.id
 and local_review.destination='heha_local';

revoke all on table app_private.partner_publication_projection
  from public,anon,authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 5. Exact public 33-column contract. Targeted HEHA Local routes remain
-- disabled until a least-privilege exporter/outbox is implemented and proved.
-- Directory and Swipe therefore emit only their safe Swipe fallback CTA, and
-- the Local bridge view intentionally returns no rows.
-- ---------------------------------------------------------------------------
create view public.public_partner_directory
with (security_invoker=false,security_barrier=true)
as
select
  id,
  created_at,
  name,
  category,
  categories,
  instagram,
  website,
  bio,
  tags,
  rating,
  review_count,
  distance_text,
  color,
  photo_emoji,
  (partnership_status='official_partner') as heha_partner,
  status,
  hours,
  business_type,
  offerings,
  neighborhood,
  tagline,
  case when publication_is_wave1_food_partner then '[]'::jsonb else items end as items,
  image_url,
  case when publication_is_wave1_food_partner then null else price_range end as price_range,
  gallery_urls,
  partner_type,
  delivery_days,
  heha_pillar,
  false as local_eligible,
  null::text as local_lane,
  'swipe'::text as primary_cta_destination,
  'Discover Partner'::text as primary_cta_label,
  ('/?partner='||id::text)::text as primary_cta_path
from app_private.partner_publication_projection
where status=any(array['approved','live']::text[])
  and listing_status='listed'
  and coalesce(website_eligible,false)=true
  and is_test_record=false
  and publication_current_swipe_owner_authorized is true
  and publication_current_swipe_staff_approved is true;

create view public.public_swipe_partners
with (security_invoker=false,security_barrier=true)
as
select
  id,
  created_at,
  name,
  category,
  categories,
  instagram,
  website,
  bio,
  tags,
  rating,
  review_count,
  distance_text,
  color,
  photo_emoji,
  (partnership_status='official_partner') as heha_partner,
  status,
  hours,
  business_type,
  offerings,
  neighborhood,
  tagline,
  case when publication_is_wave1_food_partner then '[]'::jsonb else items end as items,
  image_url,
  case when publication_is_wave1_food_partner then null else price_range end as price_range,
  gallery_urls,
  partner_type,
  delivery_days,
  heha_pillar,
  false as local_eligible,
  null::text as local_lane,
  'swipe'::text as primary_cta_destination,
  'Discover Partner'::text as primary_cta_label,
  ('/?partner='||id::text)::text as primary_cta_path
from app_private.partner_publication_projection
where status=any(array['approved','live']::text[])
  and listing_status='listed'
  and coalesce(swipe_eligible,false)=true
  and is_test_record=false
  and publication_current_swipe_owner_authorized is true
  and publication_current_swipe_staff_approved is true;

create view public.public_local_partners
with (security_invoker=false,security_barrier=true)
as
select
  id,
  created_at,
  name,
  category,
  categories,
  instagram,
  website,
  bio,
  tags,
  rating,
  review_count,
  distance_text,
  color,
  photo_emoji,
  (partnership_status='official_partner') as heha_partner,
  status,
  hours,
  business_type,
  offerings,
  neighborhood,
  tagline,
  case when publication_is_wave1_food_partner then '[]'::jsonb else items end as items,
  image_url,
  case when publication_is_wave1_food_partner then null else price_range end as price_range,
  gallery_urls,
  partner_type,
  delivery_days,
  heha_pillar,
  false as local_eligible,
  null::text as local_lane,
  'swipe'::text as primary_cta_destination,
  'Discover Partner'::text as primary_cta_label,
  ('/?partner='||id::text)::text as primary_cta_path
from app_private.partner_publication_projection
where false;

revoke all on table public.public_partner_directory
  from public,anon,authenticated,service_role;
revoke all on table public.public_swipe_partners
  from public,anon,authenticated,service_role;
revoke all on table public.public_local_partners
  from public,anon,authenticated,service_role;
grant select on table public.public_partner_directory to anon,authenticated,service_role;
grant select on table public.public_swipe_partners to anon,authenticated,service_role;
grant select on table public.public_local_partners to anon,authenticated,service_role;

comment on view public.public_partner_directory is
  'SELECT-only website card projection. Exact current owner consent and exact-hash HEHA staff review are required; raw owner, contact, routing, analytics and lifecycle fields are excluded.';
comment on view public.public_swipe_partners is
  'SELECT-only Swipe card projection. Exact current owner consent and exact-hash HEHA staff review are required; Official Partner is derived only from partnership_status.';
comment on view public.public_local_partners is
  'SELECT-only Local bridge contract, intentionally empty until a least-privilege Swipe-to-Local exporter is implemented and independently proved.';

-- Owner-facing status must distinguish owner consent, current HEHA review and
-- actual public visibility. In particular, consent alone is not publication,
-- and the intentionally disabled Local bridge must never be reported as live.
create or replace function public.get_my_partner_publication_status(p_partner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  actor_id uuid := auth.uid();
  partner_row public.partners%rowtype;
  snapshot_hash text;
  prepare_destinations text[] := array[]::text[];
  publication_destinations text[] := array[]::text[];
  staff_review_destinations text[] := array[]::text[];
  public_destinations text[] := array[]::text[];
  destination text;
  consent_event public.partner_publication_consent_events%rowtype;
  swipe_staff_approved boolean := false;
  local_staff_approved boolean := false;
begin
  if actor_id is null then
    raise exception using
      errcode='42501',
      message='Sign in to view partner publication status.';
  end if;

  select p.* into partner_row
  from public.partners p
  where p.id=p_partner_id
    and p.owner_id=actor_id;
  if not found then
    raise exception using
      errcode='42501',
      message='This partner profile is not owned by the signed-in account.';
  end if;

  snapshot_hash := app_private.partner_public_profile_hash(partner_row);
  foreach destination in array array['heha_swipe','heha_local']::text[] loop
    consent_event := app_private.latest_partner_consent_event(
      partner_row.id,
      destination,
      'prepare_profile'
    );
    if consent_event.id is not null
       and consent_event.owner_id is not distinct from actor_id
       and consent_event.state='granted' then
      prepare_destinations := pg_catalog.array_append(
        prepare_destinations,
        destination
      );
      if app_private.has_current_partner_publication_authorization(
        partner_row,
        destination
      ) then
        publication_destinations := pg_catalog.array_append(
          publication_destinations,
          destination
        );
      end if;
    end if;
  end loop;

  select
    projection.publication_current_swipe_staff_approved,
    projection.publication_current_local_staff_approved
  into swipe_staff_approved,local_staff_approved
  from app_private.partner_publication_projection projection
  where projection.id=partner_row.id;

  if coalesce(swipe_staff_approved,false) then
    staff_review_destinations := pg_catalog.array_append(
      staff_review_destinations,
      'heha_swipe'
    );
  end if;
  if coalesce(local_staff_approved,false) then
    staff_review_destinations := pg_catalog.array_append(
      staff_review_destinations,
      'heha_local'
    );
  end if;

  if exists (
    select 1
    from public.public_swipe_partners public_row
    where public_row.id=partner_row.id
  ) then
    public_destinations := pg_catalog.array_append(
      public_destinations,
      'heha_swipe'
    );
  end if;
  if exists (
    select 1
    from public.public_local_partners public_row
    where public_row.id=partner_row.id
  ) then
    public_destinations := pg_catalog.array_append(
      public_destinations,
      'heha_local'
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'partner_id',partner_row.id,
    'profile_snapshot_hash',snapshot_hash,
    'profile_snapshot',app_private.partner_public_profile_snapshot(partner_row),
    'prepare_destinations',prepare_destinations,
    'publication_destinations',publication_destinations,
    'needs_publication_approval',prepare_destinations is distinct from publication_destinations,
    'staff_review_destinations',staff_review_destinations,
    'public_destinations',public_destinations
  );
end;
$function$;

revoke all on function public.get_my_partner_publication_status(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.get_my_partner_publication_status(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Fail-closed postconditions for columns, owners, view options, ACLs and
-- policy enumeration. These run on every corrective re-application.
-- ---------------------------------------------------------------------------
do $publication_postconditions$
declare
  expected_columns constant text[] := array[
    'id','created_at','name','category','categories','instagram','website','bio',
    'tags','rating','review_count','distance_text','color','photo_emoji',
    'heha_partner','status','hours','business_type','offerings','neighborhood',
    'tagline','items','image_url','price_range','gallery_urls','partner_type',
    'delivery_days','heha_pillar','local_eligible','local_lane',
    'primary_cta_destination','primary_cta_label','primary_cta_path'
  ]::text[];
  expected_policies constant text[] := array[
    'Owners can view own partner','partners_internal_read'
  ]::text[];
  actual_columns text[];
  actual_policies text[];
  partner_owner oid;
  view_name text;
  view_options text[];
  view_owner oid;
begin
  select pg_catalog.array_agg(polname order by polname)
  into actual_policies
  from pg_catalog.pg_policy
  where polrelid='public.partners'::regclass
    and polcmd in ('r','*');

  if actual_policies is distinct from expected_policies then
    raise exception using
      errcode='55000',
      message=pg_catalog.format('Unexpected public.partners SELECT policy set: %s',actual_policies);
  end if;

  if pg_catalog.has_table_privilege('anon','public.partners','SELECT')
     or pg_catalog.has_table_privilege('anon','public.partners','INSERT')
     or pg_catalog.has_table_privilege('anon','public.partners','UPDATE')
     or pg_catalog.has_table_privilege('anon','public.partners','DELETE')
     or pg_catalog.has_table_privilege('anon','public.partners','TRUNCATE')
     or pg_catalog.has_table_privilege('anon','public.partners','REFERENCES')
     or pg_catalog.has_table_privilege('anon','public.partners','TRIGGER') then
    raise exception using errcode='55000',message='anon retains a raw public.partners privilege.';
  end if;

  if exists (
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
  ) then
    raise exception using
      errcode='55000',
      message='PUBLIC retains a raw public.partners privilege.';
  end if;

  if not pg_catalog.has_table_privilege('authenticated','public.partners','SELECT')
     or not pg_catalog.has_table_privilege('authenticated','public.partners','INSERT')
     or not pg_catalog.has_table_privilege('authenticated','public.partners','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.partners','DELETE')
     or pg_catalog.has_table_privilege('authenticated','public.partners','TRUNCATE')
     or pg_catalog.has_table_privilege('authenticated','public.partners','REFERENCES')
     or pg_catalog.has_table_privilege('authenticated','public.partners','TRIGGER') then
    raise exception using
      errcode='55000',
      message='authenticated public.partners ACL is not exactly SELECT/INSERT/UPDATE.';
  end if;

  if pg_catalog.has_table_privilege('anon','public.partner_publication_review_events','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.partner_publication_review_events','SELECT')
     or pg_catalog.has_table_privilege('anon','public.partner_publication_review_events','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.partner_publication_review_events','INSERT')
     or pg_catalog.has_table_privilege('service_role','public.partner_publication_review_events','INSERT')
     or pg_catalog.has_table_privilege('service_role','public.partner_publication_review_events','UPDATE')
     or pg_catalog.has_table_privilege('service_role','public.partner_publication_review_events','DELETE') then
    raise exception using
      errcode='55000',
      message='Partner publication review evidence has an unsafe direct grant.';
  end if;

  if not (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid='public.partner_publication_review_events'::regclass
  ) or not pg_catalog.has_table_privilege(
    'service_role','public.partner_publication_review_events','SELECT'
  ) or exists (
    select 1
    from pg_catalog.pg_class relation_row
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation_row.relacl,
        pg_catalog.acldefault('r',relation_row.relowner)
      )
    ) privilege_row
    where relation_row.oid='public.partner_publication_review_events'::regclass
      and privilege_row.grantee=0
  ) then
    raise exception using
      errcode='55000',
      message='Partner publication review RLS/service/PUBLIC ACL contract is malformed.';
  end if;

  select relowner into partner_owner
  from pg_catalog.pg_class
  where oid='public.partners'::regclass;

  foreach view_name in array array[
    'public_partner_directory','public_swipe_partners','public_local_partners'
  ]::text[] loop
    select pg_catalog.array_agg(column_name order by ordinal_position)
    into actual_columns
    from information_schema.columns
    where table_schema='public' and table_name=view_name;

    if actual_columns is distinct from expected_columns then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('Unsafe public.%I column contract: %s',view_name,actual_columns);
    end if;

    select reloptions,relowner into view_options,view_owner
    from pg_catalog.pg_class
    where oid=pg_catalog.to_regclass(pg_catalog.format('public.%I',view_name));

    if not ('security_barrier=true'=any(coalesce(view_options,array[]::text[])))
       or 'security_invoker=true'=any(coalesce(view_options,array[]::text[]))
       or view_owner is distinct from partner_owner then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('public.%I is not a same-owner security-barrier definer view.',view_name);
    end if;

    if not pg_catalog.has_table_privilege('anon',pg_catalog.format('public.%I',view_name),'SELECT')
       or not pg_catalog.has_table_privilege('authenticated',pg_catalog.format('public.%I',view_name),'SELECT')
       or pg_catalog.has_table_privilege('anon',pg_catalog.format('public.%I',view_name),'INSERT')
       or pg_catalog.has_table_privilege('authenticated',pg_catalog.format('public.%I',view_name),'INSERT')
       or pg_catalog.has_table_privilege('anon',pg_catalog.format('public.%I',view_name),'UPDATE')
       or pg_catalog.has_table_privilege('authenticated',pg_catalog.format('public.%I',view_name),'UPDATE')
       or pg_catalog.has_table_privilege('anon',pg_catalog.format('public.%I',view_name),'DELETE')
       or pg_catalog.has_table_privilege('authenticated',pg_catalog.format('public.%I',view_name),'DELETE') then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('Unsafe browser ACL on public.%I.',view_name);
    end if;

    if exists (
      select 1
      from pg_catalog.pg_class relation_row
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          relation_row.relacl,
          pg_catalog.acldefault('r',relation_row.relowner)
        )
      ) privilege_row
      where relation_row.oid=pg_catalog.to_regclass(pg_catalog.format('public.%I',view_name))
        and privilege_row.grantee=0
    ) then
      raise exception using
        errcode='55000',
        message=pg_catalog.format('PUBLIC retains a privilege on public.%I.',view_name);
    end if;
  end loop;
end;
$publication_postconditions$;
