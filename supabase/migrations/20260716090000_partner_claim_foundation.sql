-- PARTNER-BRIDGE-001 / Swipe issue #79
-- Secure in-place claim foundation for HEHA-created Community Listings.
--
-- Review-only migration. Do not apply to production until:
-- - ADR-001 / two-project identity direction is approved;
-- - migration lineage is reconciled;
-- - duplicate/split partner records and media-rights blockers are reviewed;
-- - RLS and Business A / Business B negative tests pass.
--
-- Core invariant: claiming attaches auth.uid() to the existing public.partners.id.
-- It never creates a second partner row and never changes public publication,
-- HEHA Partner, certification, eligibility, routing, pricing, or Local-order status.

alter table public.partners
  add column if not exists relationship_status text not null default 'community_listed',
  add column if not exists listing_source text not null default 'heha_created',
  add column if not exists claimed_at timestamptz,
  add column if not exists claimed_by uuid references auth.users(id) on delete set null,
  add column if not exists opted_out_at timestamptz,
  add column if not exists opted_out_by uuid references auth.users(id) on delete set null;

alter table public.partners
  drop constraint if exists partners_relationship_status_check;

alter table public.partners
  add constraint partners_relationship_status_check
  check (
    relationship_status = any (
      array[
        'community_listed',
        'claim_invited',
        'claimed',
        'official_partner',
        'opted_out',
        'removed'
      ]::text[]
    )
  );

alter table public.partners
  drop constraint if exists partners_listing_source_check;

alter table public.partners
  add constraint partners_listing_source_check
  check (
    listing_source = any (
      array['heha_created', 'partner_created', 'imported', 'scout', 'unknown']::text[]
    )
  );

-- Existing ownership is evidence that the profile is already claimed, but it is
-- not evidence of Official HEHA Partner or HEHA Certified status.
update public.partners
set relationship_status = 'claimed',
    claimed_at = coalesce(claimed_at, created_at, now()),
    claimed_by = coalesce(claimed_by, owner_id)
where owner_id is not null
  and relationship_status in ('community_listed', 'claim_invited');

create or replace function app_private.set_partner_listing_origin()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is not null and new.owner_id = actor_id then
    new.listing_source := 'partner_created';
    new.relationship_status := 'claimed';
    new.claimed_at := coalesce(new.claimed_at, now());
    new.claimed_by := actor_id;
  else
    new.listing_source := coalesce(nullif(new.listing_source, ''), 'heha_created');
    new.relationship_status := coalesce(nullif(new.relationship_status, ''), 'community_listed');
  end if;

  return new;
end;
$$;

revoke all on function app_private.set_partner_listing_origin() from public, anon, authenticated;

drop trigger if exists aa_partner_listing_origin on public.partners;
create trigger aa_partner_listing_origin
before insert on public.partners
for each row
execute function app_private.set_partner_listing_origin();

create table if not exists public.partner_claim_invites (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  token_hash bytea not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  outreach_channel text,
  recipient_hint text,
  constraint partner_claim_invites_expiry_check check (expires_at > created_at),
  constraint partner_claim_invites_terminal_state_check check (
    not (consumed_at is not null and revoked_at is not null)
  )
);

create index if not exists partner_claim_invites_partner_id_idx
  on public.partner_claim_invites(partner_id, created_at desc);

create unique index if not exists partner_claim_invites_one_active_per_partner_uidx
  on public.partner_claim_invites(partner_id)
  where consumed_at is null and revoked_at is null;

alter table public.partner_claim_invites enable row level security;

revoke all on table public.partner_claim_invites from public, anon;
revoke insert, update, delete on table public.partner_claim_invites from authenticated;
grant select on table public.partner_claim_invites to authenticated;

drop policy if exists partner_claim_invites_internal_read on public.partner_claim_invites;
create policy partner_claim_invites_internal_read
on public.partner_claim_invites
for select
to authenticated
using (
  app_private.has_internal_role(
    array['super_admin', 'developer_admin', 'pm_admin', 'som_admin']::text[]
  )
);

create or replace function public.create_partner_claim_invite(
  p_partner_id uuid,
  p_expires_in interval default interval '7 days',
  p_outreach_channel text default null,
  p_recipient_hint text default null
)
returns table (
  invite_id uuid,
  partner_id uuid,
  raw_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  partner_row public.partners%rowtype;
  generated_token text;
  generated_hash bytea;
  generated_invite_id uuid;
  generated_expires_at timestamptz;
begin
  if actor_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  if not app_private.has_internal_role(
    array['super_admin', 'developer_admin', 'pm_admin', 'som_admin']::text[]
  ) then
    raise exception using errcode = '42501', message = 'HEHA internal claim-invite access required.';
  end if;

  if p_expires_in is null
     or p_expires_in < interval '15 minutes'
     or p_expires_in > interval '30 days' then
    raise exception using errcode = '22023', message = 'Claim invite expiry must be between 15 minutes and 30 days.';
  end if;

  select *
  into partner_row
  from public.partners
  where id = p_partner_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Partner profile not found.';
  end if;

  if partner_row.owner_id is not null then
    raise exception using errcode = '23505', message = 'This partner profile is already claimed.';
  end if;

  if partner_row.relationship_status in ('opted_out', 'removed') then
    raise exception using errcode = '42501', message = 'This listing is not eligible for a claim invitation.';
  end if;

  update public.partner_claim_invites
  set revoked_at = now(),
      revoked_by = actor_id
  where partner_claim_invites.partner_id = p_partner_id
    and consumed_at is null
    and revoked_at is null;

  generated_token := encode(extensions.gen_random_bytes(32), 'hex');
  generated_hash := extensions.digest(generated_token, 'sha256');
  generated_invite_id := gen_random_uuid();
  generated_expires_at := now() + p_expires_in;

  insert into public.partner_claim_invites (
    id,
    partner_id,
    token_hash,
    created_by,
    expires_at,
    outreach_channel,
    recipient_hint
  ) values (
    generated_invite_id,
    p_partner_id,
    generated_hash,
    actor_id,
    generated_expires_at,
    nullif(btrim(p_outreach_channel), ''),
    nullif(btrim(p_recipient_hint), '')
  );

  insert into public.admin_audit_logs (
    user_id,
    action_type,
    related_type,
    related_id,
    previous_value,
    new_value
  ) values (
    actor_id,
    'partner_claim_invite_created',
    'partner',
    p_partner_id,
    jsonb_build_object('relationship_status', partner_row.relationship_status),
    jsonb_build_object(
      'relationship_status', partner_row.relationship_status,
      'invite_id', generated_invite_id,
      'expires_at', generated_expires_at,
      'outreach_channel', nullif(btrim(p_outreach_channel), '')
    )
  );

  return query
  select generated_invite_id, p_partner_id, generated_token, generated_expires_at;
end;
$$;

create or replace function public.preview_partner_claim(p_raw_token text)
returns table (
  partner_id uuid,
  partner_name text,
  expires_at timestamptz,
  claimable boolean
)
language plpgsql
security definer
stable
set search_path = pg_catalog, public, extensions, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  if nullif(btrim(p_raw_token), '') is null then
    raise exception using errcode = '22023', message = 'Claim token is required.';
  end if;

  return query
  select
    p.id,
    p.name,
    i.expires_at,
    (
      i.consumed_at is null
      and i.revoked_at is null
      and i.expires_at > now()
      and p.owner_id is null
      and p.relationship_status not in ('opted_out', 'removed')
    ) as claimable
  from public.partner_claim_invites i
  join public.partners p on p.id = i.partner_id
  where i.token_hash = extensions.digest(btrim(p_raw_token), 'sha256')
  limit 1;
end;
$$;

create or replace function public.claim_partner_profile(p_raw_token text)
returns table (
  partner_id uuid,
  partner_name text,
  relationship_status text,
  claimed_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  invite_row public.partner_claim_invites%rowtype;
  partner_row public.partners%rowtype;
  claim_time timestamptz := now();
begin
  if actor_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  if nullif(btrim(p_raw_token), '') is null then
    raise exception using errcode = '22023', message = 'Claim token is required.';
  end if;

  select *
  into invite_row
  from public.partner_claim_invites
  where token_hash = extensions.digest(btrim(p_raw_token), 'sha256')
  for update;

  if not found
    or invite_row.consumed_at is not null
    or invite_row.revoked_at is not null
    or invite_row.expires_at <= claim_time
  then
    raise exception using
      errcode = 'P0002',
      message = 'This claim link is invalid, expired, revoked, or already used.';
  end if;

  select *
  into partner_row
  from public.partners
  where id = invite_row.partner_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Partner profile not found.';
  end if;

  if partner_row.relationship_status in ('opted_out', 'removed') then
    raise exception using errcode = '42501', message = 'This listing is no longer claimable.';
  end if;

  if partner_row.owner_id is not null and partner_row.owner_id <> actor_id then
    raise exception using errcode = '23505', message = 'This partner profile has already been claimed.';
  end if;

  update public.partners
  set owner_id = actor_id,
      relationship_status = case
        when relationship_status = 'official_partner' then 'official_partner'
        else 'claimed'
      end,
      claimed_at = coalesce(claimed_at, claim_time),
      claimed_by = coalesce(claimed_by, actor_id),
      updated_at = claim_time
  where id = partner_row.id;

  update public.partner_claim_invites
  set consumed_at = claim_time,
      consumed_by = actor_id
  where id = invite_row.id;

  insert into public.admin_audit_logs (
    user_id,
    action_type,
    related_type,
    related_id,
    previous_value,
    new_value
  ) values (
    actor_id,
    'partner_profile_claimed',
    'partner',
    partner_row.id,
    jsonb_build_object(
      'owner_id', partner_row.owner_id,
      'relationship_status', partner_row.relationship_status
    ),
    jsonb_build_object(
      'owner_id', actor_id,
      'relationship_status', case
        when partner_row.relationship_status = 'official_partner' then 'official_partner'
        else 'claimed'
      end,
      'invite_id', invite_row.id,
      'claimed_at', claim_time
    )
  );

  return query
  select
    partner_row.id,
    partner_row.name,
    case
      when partner_row.relationship_status = 'official_partner' then 'official_partner'
      else 'claimed'
    end,
    claim_time;
end;
$$;

create or replace function public.revoke_partner_claim_invite(p_invite_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  affected integer;
  revoked_partner_id uuid;
begin
  if actor_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  if not app_private.has_internal_role(
    array['super_admin', 'developer_admin', 'pm_admin', 'som_admin']::text[]
  ) then
    raise exception using errcode = '42501', message = 'HEHA internal claim-invite access required.';
  end if;

  update public.partner_claim_invites
  set revoked_at = now(),
      revoked_by = actor_id
  where id = p_invite_id
    and consumed_at is null
    and revoked_at is null
  returning partner_id into revoked_partner_id;

  get diagnostics affected = row_count;

  if affected = 1 then
    insert into public.admin_audit_logs (
      user_id,
      action_type,
      related_type,
      related_id,
      previous_value,
      new_value
    ) values (
      actor_id,
      'partner_claim_invite_revoked',
      'partner',
      revoked_partner_id,
      jsonb_build_object('invite_id', p_invite_id, 'revoked_at', null),
      jsonb_build_object('invite_id', p_invite_id, 'revoked_at', now())
    );
  end if;

  return affected = 1;
end;
$$;

revoke all on function public.create_partner_claim_invite(uuid, interval, text, text) from public, anon;
revoke all on function public.preview_partner_claim(text) from public, anon;
revoke all on function public.claim_partner_profile(text) from public, anon;
revoke all on function public.revoke_partner_claim_invite(uuid) from public, anon;

grant execute on function public.create_partner_claim_invite(uuid, interval, text, text) to authenticated;
grant execute on function public.preview_partner_claim(text) to authenticated;
grant execute on function public.claim_partner_profile(text) to authenticated;
grant execute on function public.revoke_partner_claim_invite(uuid) to authenticated;

comment on column public.partners.relationship_status is
  'Business relationship state. Separate from public listing status, HEHA Partner, certification, routing, and product approval.';
comment on column public.partners.listing_source is
  'How the canonical partner profile originated. Claiming never changes the canonical partners.id.';
comment on table public.partner_claim_invites is
  'One-time hashed invitations used to attach an authenticated business owner to an existing canonical HEHA Swipe partner profile.';
comment on function public.create_partner_claim_invite(uuid, interval, text, text) is
  'Internal-only RPC. Returns the raw one-time token once; only its SHA-256 hash is stored.';
comment on function public.claim_partner_profile(text) is
  'Authenticated one-time claim RPC that assigns auth.uid() to an existing unclaimed partners.id without changing publication or certification.';

-- Rollback, after confirming no claim data must be retained:
-- drop function if exists public.revoke_partner_claim_invite(uuid);
-- drop function if exists public.claim_partner_profile(text);
-- drop function if exists public.preview_partner_claim(text);
-- drop function if exists public.create_partner_claim_invite(uuid, interval, text, text);
-- drop table if exists public.partner_claim_invites;
-- drop trigger if exists aa_partner_listing_origin on public.partners;
-- drop function if exists app_private.set_partner_listing_origin();
-- alter table public.partners
--   drop column if exists opted_out_by,
--   drop column if exists opted_out_at,
--   drop column if exists claimed_by,
--   drop column if exists claimed_at,
--   drop column if exists listing_source,
--   drop column if exists relationship_status;
