-- ONE HEHA S1 — private Swipe identity foundation.
--
-- REVIEW ONLY. This file is intentionally outside supabase/migrations.
-- Apply only to disposable synthetic PostgreSQL/Supabase environments after an
-- exact-head approval. It performs no account linking merely by being committed.

begin;

create schema if not exists one_heha_private;
create schema if not exists community_pass_private;

revoke all on schema one_heha_private from public;
revoke all on schema one_heha_private from anon;
revoke all on schema one_heha_private from authenticated;
revoke all on schema community_pass_private from public;
revoke all on schema community_pass_private from anon;
revoke all on schema community_pass_private from authenticated;

grant usage on schema one_heha_private to service_role;
grant usage on schema community_pass_private to service_role;

create or replace function one_heha_private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function one_heha_private.set_updated_at() from public;
revoke all on function one_heha_private.set_updated_at() from anon;
revoke all on function one_heha_private.set_updated_at() from authenticated;
revoke all on function one_heha_private.set_updated_at() from service_role;

create or replace function one_heha_private.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'ONE_HEHA_APPEND_ONLY'
    using errcode = '42501';
end;
$function$;

revoke all on function one_heha_private.reject_append_only_mutation() from public;
revoke all on function one_heha_private.reject_append_only_mutation() from anon;
revoke all on function one_heha_private.reject_append_only_mutation() from authenticated;
revoke all on function one_heha_private.reject_append_only_mutation() from service_role;

create table if not exists one_heha_private.identity_links (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  canonical_user_id uuid,
  swipe_user_id uuid references auth.users(id) on delete set null,
  environment text not null check (environment in ('test', 'live')),
  status text not null check (
    status in (
      'pending',
      'active',
      'revoked',
      'deleted',
      'reconciliation_exception'
    )
  ),
  link_method text not null check (
    link_method in ('dual_reauthentication_jws_v1', 'manual_review_v1')
  ),
  link_version text not null,
  linked_at timestamptz,
  last_verified_at timestamptz,
  revoked_at timestamptz,
  revocation_reason_code text,
  tombstone_hash text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint identity_links_active_identity_check check (
    status <> 'active'
    or (
      canonical_user_id is not null
      and swipe_user_id is not null
      and linked_at is not null
      and last_verified_at is not null
      and revoked_at is null
      and tombstone_hash is null
    )
  ),
  constraint identity_links_revoked_check check (
    status not in ('revoked', 'deleted')
    or revoked_at is not null
  ),
  constraint identity_links_tombstone_shape_check check (
    tombstone_hash is null
    or tombstone_hash ~ '^[a-f0-9]{64}$'
  )
);

create unique index if not exists identity_links_active_canonical_unique
  on one_heha_private.identity_links(canonical_user_id, environment)
  where status = 'active' and canonical_user_id is not null;

create unique index if not exists identity_links_active_swipe_unique
  on one_heha_private.identity_links(swipe_user_id, environment)
  where status = 'active' and swipe_user_id is not null;

-- One canonical deletion may minimize more than one historical source link with
-- the same opaque tombstone. The tombstone is indexed for lookup, not unique.
drop index if exists one_heha_private.identity_links_tombstone_unique;
create index if not exists identity_links_tombstone_idx
  on one_heha_private.identity_links(environment, tombstone_hash)
  where tombstone_hash is not null;

create index if not exists identity_links_canonical_lookup_idx
  on one_heha_private.identity_links(environment, canonical_user_id, status);

create index if not exists identity_links_swipe_lookup_idx
  on one_heha_private.identity_links(environment, swipe_user_id, status);

create table if not exists one_heha_private.link_handshakes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  request_id uuid not null,
  swipe_user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null check (environment in ('test', 'live')),
  identity_classification text not null check (
    identity_classification in (
      'verified_non_sso',
      'sso',
      'unverified',
      'missing',
      'ambiguous',
      'conflict',
      'deleted'
    )
  ),
  nonce_hash text not null check (nonce_hash ~ '^[a-f0-9]{64}$'),
  state text not null default 'pending' check (
    state in (
      'pending',
      'consumed',
      'expired',
      'cancelled',
      'manual_review',
      'reconciliation_exception'
    )
  ),
  swipe_reauthenticated_at timestamptz not null,
  local_reauthenticated_at timestamptz,
  local_assertion_jti_hash text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  constraint link_handshakes_lifetime_check check (
    expires_at > created_at
    and expires_at <= created_at + interval '5 minutes'
  ),
  constraint link_handshakes_consumption_check check (
    (state = 'consumed' and consumed_at is not null and local_assertion_jti_hash is not null)
    or state <> 'consumed'
  ),
  constraint link_handshakes_jti_shape_check check (
    local_assertion_jti_hash is null
    or local_assertion_jti_hash ~ '^[a-f0-9]{64}$'
  )
);

create unique index if not exists link_handshakes_request_unique
  on one_heha_private.link_handshakes(environment, request_id);

create unique index if not exists link_handshakes_jti_unique
  on one_heha_private.link_handshakes(environment, local_assertion_jti_hash)
  where local_assertion_jti_hash is not null;

create unique index if not exists link_handshakes_pending_swipe_unique
  on one_heha_private.link_handshakes(environment, swipe_user_id)
  where state = 'pending';

create index if not exists link_handshakes_expiry_idx
  on one_heha_private.link_handshakes(environment, state, expires_at);

create table if not exists one_heha_private.identity_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  link_id uuid references one_heha_private.identity_links(id) on delete restrict,
  handshake_id uuid references one_heha_private.link_handshakes(id) on delete restrict,
  canonical_user_id uuid,
  swipe_user_id uuid,
  environment text not null check (environment in ('test', 'live')),
  event_type text not null check (
    event_type in (
      'link_requested',
      'local_identity_verified',
      'link_activated',
      'link_rejected',
      'link_revoked',
      'canonical_account_deletion_requested',
      'canonical_account_deleted',
      'reconciliation_exception'
    )
  ),
  reason_code text,
  idempotency_key text not null,
  event_data jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(event_data) = 'object'
  ),
  occurred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create unique index if not exists identity_events_idempotency_unique
  on one_heha_private.identity_events(environment, idempotency_key);

create index if not exists identity_events_link_time_idx
  on one_heha_private.identity_events(link_id, occurred_at desc);

create index if not exists identity_events_canonical_time_idx
  on one_heha_private.identity_events(environment, canonical_user_id, occurred_at desc);

alter table one_heha_private.identity_links enable row level security;
alter table one_heha_private.identity_links force row level security;
alter table one_heha_private.link_handshakes enable row level security;
alter table one_heha_private.link_handshakes force row level security;
alter table one_heha_private.identity_events enable row level security;
alter table one_heha_private.identity_events force row level security;

revoke all on table one_heha_private.identity_links from public;
revoke all on table one_heha_private.identity_links from anon;
revoke all on table one_heha_private.identity_links from authenticated;
revoke all on table one_heha_private.identity_links from service_role;
revoke all on table one_heha_private.link_handshakes from public;
revoke all on table one_heha_private.link_handshakes from anon;
revoke all on table one_heha_private.link_handshakes from authenticated;
revoke all on table one_heha_private.link_handshakes from service_role;
revoke all on table one_heha_private.identity_events from public;
revoke all on table one_heha_private.identity_events from anon;
revoke all on table one_heha_private.identity_events from authenticated;
revoke all on table one_heha_private.identity_events from service_role;

drop trigger if exists identity_links_set_updated_at on one_heha_private.identity_links;
create trigger identity_links_set_updated_at
before update on one_heha_private.identity_links
for each row execute function one_heha_private.set_updated_at();

drop trigger if exists identity_events_append_only on one_heha_private.identity_events;
create trigger identity_events_append_only
before update or delete on one_heha_private.identity_events
for each row execute function one_heha_private.reject_append_only_mutation();

commit;
