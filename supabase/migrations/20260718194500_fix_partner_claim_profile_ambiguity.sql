-- PARTNER-BRIDGE-001A follow-up fix.
-- Review-only. Do not apply to production independently of the claim foundation.
--
-- public.claim_partner_profile() returns output columns named relationship_status
-- and claimed_at. Unqualified references to the same public.partners columns are
-- ambiguous in PL/pgSQL, so every affected table column is explicitly qualified.

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

  if not found then
    raise exception using errcode = 'P0002', message = 'This claim link is not recognized.';
  end if;
  if invite_row.consumed_at is not null then
    raise exception using errcode = 'P0002', message = 'This claim link has already been used.';
  end if;
  if invite_row.revoked_at is not null then
    raise exception using errcode = 'P0002', message = 'This claim link is revoked.';
  end if;
  if invite_row.expires_at <= claim_time then
    raise exception using errcode = 'P0002', message = 'This claim link has expired.';
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
    raise exception using errcode = '42501', message = 'This profile is no longer claimable.';
  end if;

  if partner_row.owner_id is not null and partner_row.owner_id <> actor_id then
    raise exception using errcode = '23505', message = 'This business profile has already been claimed by another account.';
  end if;

  update public.partners as p
  set owner_id = actor_id,
      relationship_status = case
        when p.relationship_status = 'official_partner' then 'official_partner'
        else 'claimed'
      end,
      claimed_at = coalesce(p.claimed_at, claim_time),
      claimed_by = coalesce(p.claimed_by, actor_id),
      updated_at = claim_time
  where p.id = partner_row.id;

  update public.partner_claim_invites as pci
  set consumed_at = claim_time,
      consumed_by = actor_id
  where pci.id = invite_row.id;

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

revoke all on function public.claim_partner_profile(text) from public, anon;
grant execute on function public.claim_partner_profile(text) to authenticated;

comment on function public.claim_partner_profile(text) is
  'Authenticated one-time claim RPC that assigns auth.uid() to an existing unclaimed partners.id without changing publication or certification.';
