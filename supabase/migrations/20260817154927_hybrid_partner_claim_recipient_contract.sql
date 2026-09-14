-- Permanent-recipient and stable error contract for HEHA partner claims.
-- REVIEW ONLY / PRODUCTION FROZEN.
--
-- Anonymous Auth users share the authenticated database role. A claim bound to
-- an existing UUID is therefore eligible only while that exact auth.users row is
-- non-anonymous, email-verified and still carries a usable normalized email.

create or replace function app_private.verified_permanent_claim_email(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, auth, pg_temp
as $$
  select lower(btrim(u.email))
  from auth.users as u
  where u.id=p_user_id
    and u.email_confirmed_at is not null
    and coalesce(u.is_anonymous,false)=false
    and nullif(lower(btrim(u.email)),'') is not null
    and position('@' in lower(btrim(u.email))) > 1;
$$;

revoke all on function app_private.verified_permanent_claim_email(uuid)
  from public, anon, authenticated, service_role;

-- The effective invite issuer is redefined here so direct UUIDs and existing
-- email accounts use the same permanent-recipient qualification.
create or replace function public.create_partner_claim_invite(
  p_partner_id uuid,
  p_expires_in interval default interval '7 days',
  p_outreach_channel text default null,
  p_intended_user_id uuid default null,
  p_intended_email text default null
) returns table(
  invite_id uuid,
  partner_id uuid,
  raw_token text,
  expires_at timestamptz,
  recipient_hint text
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  p public.partners%rowtype;
  raw text;
  normalized_email text := nullif(lower(btrim(p_intended_email)),'');
  bound_user uuid;
  bound_email text;
  account_email text;
  hint text;
  new_id uuid := gen_random_uuid();
  exp timestamptz;
begin
  if actor_id is null then
    raise exception using errcode='28000', message='Authentication required.';
  end if;
  if not app_private.has_internal_role(
    array['super_admin','developer_admin','pm_admin']::text[]
  ) then
    raise exception using errcode='42501', message='HEHA internal claim-invite access required.';
  end if;
  if p_expires_in is null
     or p_expires_in < interval '15 minutes'
     or p_expires_in > interval '30 days' then
    raise exception using
      errcode='22023',
      message='Claim invite expiry must be between 15 minutes and 30 days.';
  end if;
  if (p_intended_user_id is null)=(normalized_email is null) then
    raise exception using
      errcode='22023',
      message='Provide exactly one intended recipient user or email.';
  end if;
  if normalized_email is not null
     and (length(normalized_email)>320 or position('@' in normalized_email)<=1) then
    raise exception using
      errcode='22023',
      message='A valid intended recipient email is required.';
  end if;

  if p_intended_user_id is not null then
    account_email := app_private.verified_permanent_claim_email(p_intended_user_id);
    if account_email is null then
      raise exception using
        errcode='42501',
        message='Intended recipient account must be permanent and have a verified email.',
        detail='HEHA_CLAIM_RECIPIENT_INELIGIBLE';
    end if;
    bound_user := p_intended_user_id;
  else
    select u.id, app_private.verified_permanent_claim_email(u.id)
    into bound_user, account_email
    from auth.users as u
    where lower(btrim(u.email))=normalized_email
      and app_private.verified_permanent_claim_email(u.id) is not null
    order by u.created_at, u.id
    limit 1;

    if bound_user is null then
      bound_email := normalized_email;
      account_email := normalized_email;
    end if;
  end if;

  hint := left(split_part(account_email,'@',1),1)
    || '***@' || split_part(account_email,'@',2);

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='Partner profile not found.';
  end if;
  if p.owner_id is not null then
    raise exception using
      errcode='23505',
      message='This business profile has already been claimed.',
      detail='HEHA_CLAIM_ALREADY_CLAIMED';
  end if;
  if p.listing_status in ('opted_out','removed') then
    raise exception using
      errcode='42501',
      message='This profile is not available to claim.',
      detail='HEHA_CLAIM_PROFILE_UNAVAILABLE';
  end if;

  update public.partner_claim_invites as invite_row
  set revoked_at=now(), revoked_by=actor_id
  where invite_row.partner_id=p_partner_id
    and invite_row.consumed_at is null
    and invite_row.revoked_at is null;

  raw := encode(extensions.gen_random_bytes(32),'hex');
  exp := now()+p_expires_in;
  insert into public.partner_claim_invites(
    id,partner_id,token_hash,created_by,expires_at,outreach_channel,
    intended_user_id,intended_email_normalized,recipient_hint
  ) values (
    new_id,p_partner_id,extensions.digest(raw,'sha256'),actor_id,exp,
    nullif(btrim(p_outreach_channel),''),bound_user,bound_email,hint
  );

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'claim');
  update public.partners as partner_row
  set claim_status='claim_invited', updated_at=now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(
    partner_id,event_type,actor_id,before_state,after_state
  ) values (
    p.id,
    'claim_invite_created',
    actor_id,
    app_private.partner_lifecycle_receipt(p),
    jsonb_build_object(
      'partner_id',p.id,
      'claim_status','claim_invited',
      'invite_id',new_id,
      'expires_at',exp
    )
  );

  return query select new_id,p.id,raw,exp,hint;
end;
$$;

create or replace function app_private.apply_verified_partner_claim(
  p_partner_id uuid,
  p_actor_id uuid,
  p_claim_time timestamptz
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, pg_temp
as $$
begin
  perform app_private.authorize_partner_lifecycle_mutation(p_partner_id,'claim');
  update public.partners as partner_row
  set owner_id=p_actor_id,
      claim_status='claimed',
      claimed_at=p_claim_time,
      claimed_by=p_actor_id,
      updated_at=p_claim_time
  where partner_row.id=p_partner_id
    and partner_row.owner_id is null;

  if not found then
    raise exception using
      errcode='23505',
      message='This business profile has already been claimed.',
      detail='HEHA_CLAIM_ALREADY_CLAIMED';
  end if;
end;
$$;

revoke all on function app_private.apply_verified_partner_claim(uuid,uuid,timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.preview_partner_claim(p_raw_token text)
returns table(
  partner_id uuid,
  partner_name text,
  expires_at timestamptz,
  claimable boolean
)
language plpgsql
security definer
stable
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor uuid := auth.uid();
  actor_email text;
  i public.partner_claim_invites%rowtype;
  p public.partners%rowtype;
begin
  if actor is null then
    raise exception using errcode='28000', message='Authentication required.';
  end if;
  if nullif(btrim(p_raw_token),'') is null then
    raise exception using
      errcode='P0002',
      message='This claim link is not recognized.',
      detail='HEHA_CLAIM_NOT_RECOGNIZED';
  end if;

  actor_email := app_private.verified_permanent_claim_email(actor);
  if actor_email is null then
    raise exception using
      errcode='42501',
      message='Use a permanent HEHA account with a verified email to claim this profile.',
      detail='HEHA_CLAIM_RECIPIENT_INELIGIBLE';
  end if;

  select invite_row.* into i
  from public.partner_claim_invites as invite_row
  where invite_row.token_hash=extensions.digest(btrim(p_raw_token),'sha256')
  limit 1;
  if not found then
    raise exception using
      errcode='P0002',
      message='This claim link is not recognized.',
      detail='HEHA_CLAIM_NOT_RECOGNIZED';
  end if;
  if i.consumed_at is not null then
    raise exception using
      errcode='P0002',
      message='This claim link has already been used.',
      detail='HEHA_CLAIM_ALREADY_USED';
  end if;
  if i.revoked_at is not null then
    raise exception using
      errcode='P0002',
      message='This claim link is no longer active.',
      detail='HEHA_CLAIM_REVOKED';
  end if;
  if i.intended_user_id is null and i.intended_email_normalized is null then
    raise exception using
      errcode='42501',
      message='This claim link is no longer active.',
      detail='HEHA_CLAIM_REVOKED';
  end if;
  -- statement_timestamp() reflects when this preview call began, unlike now(),
  -- which is fixed at the start of a caller-controlled SQL transaction.
  if i.expires_at <= statement_timestamp() then
    raise exception using
      errcode='P0002',
      message='This claim link has expired.',
      detail='HEHA_CLAIM_EXPIRED';
  end if;

  if i.intended_user_id is not null then
    if i.intended_user_id <> actor then
      raise exception using
        errcode='42501',
        message='This claim link belongs to a different account.',
        detail='HEHA_CLAIM_RECIPIENT_MISMATCH';
    end if;
  elsif actor_email <> i.intended_email_normalized then
    raise exception using
      errcode='42501',
      message='This claim link belongs to a different account.',
      detail='HEHA_CLAIM_RECIPIENT_MISMATCH';
  end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=i.partner_id;
  if not found then
    raise exception using
      errcode='42501',
      message='This profile is not available to claim.',
      detail='HEHA_CLAIM_PROFILE_UNAVAILABLE';
  end if;
  if p.owner_id is not null then
    raise exception using
      errcode='23505',
      message='This business profile has already been claimed.',
      detail='HEHA_CLAIM_ALREADY_CLAIMED';
  end if;
  if p.claim_status not in ('unclaimed','claim_invited')
     or p.listing_status in ('opted_out','removed') then
    raise exception using
      errcode='42501',
      message='This profile is not available to claim.',
      detail='HEHA_CLAIM_PROFILE_UNAVAILABLE';
  end if;

  return query select p.id,p.name,i.expires_at,true;
end;
$$;

create or replace function public.claim_partner_profile(p_raw_token text)
returns table(
  partner_id uuid,
  partner_name text,
  claim_status text,
  claimed_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor uuid := auth.uid();
  actor_email text;
  i public.partner_claim_invites%rowtype;
  p public.partners%rowtype;
  claim_time timestamptz;
begin
  if actor is null then
    raise exception using errcode='28000', message='Authentication required.';
  end if;
  if nullif(btrim(p_raw_token),'') is null then
    raise exception using
      errcode='P0002',
      message='This claim link is not recognized.',
      detail='HEHA_CLAIM_NOT_RECOGNIZED';
  end if;

  actor_email := app_private.verified_permanent_claim_email(actor);
  if actor_email is null then
    raise exception using
      errcode='42501',
      message='Use a permanent HEHA account with a verified email to claim this profile.',
      detail='HEHA_CLAIM_RECIPIENT_INELIGIBLE';
  end if;

  -- The first read discovers only the partner key. Every trusted value is read
  -- again after locking partner first and invitation second.
  select invite_row.* into i
  from public.partner_claim_invites as invite_row
  where invite_row.token_hash=extensions.digest(btrim(p_raw_token),'sha256');
  if not found then
    raise exception using
      errcode='P0002',
      message='This claim link is not recognized.',
      detail='HEHA_CLAIM_NOT_RECOGNIZED';
  end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=i.partner_id
  for update;
  if not found then
    raise exception using
      errcode='42501',
      message='This profile is not available to claim.',
      detail='HEHA_CLAIM_PROFILE_UNAVAILABLE';
  end if;

  select invite_row.* into i
  from public.partner_claim_invites as invite_row
  where invite_row.id=i.id
  for update;
  if not found then
    raise exception using
      errcode='P0002',
      message='This claim link is not recognized.',
      detail='HEHA_CLAIM_NOT_RECOGNIZED';
  end if;

  -- now() is fixed at transaction start. Capture the real wall-clock time only
  -- after both rows are locked so a transaction opened before expiry cannot
  -- redeem the invite after its actual deadline or backdate claim provenance.
  claim_time := clock_timestamp();

  if i.consumed_at is not null then
    raise exception using
      errcode='P0002',
      message='This claim link has already been used.',
      detail='HEHA_CLAIM_ALREADY_USED';
  end if;
  if i.revoked_at is not null then
    raise exception using
      errcode='P0002',
      message='This claim link is no longer active.',
      detail='HEHA_CLAIM_REVOKED';
  end if;
  if i.intended_user_id is null and i.intended_email_normalized is null then
    raise exception using
      errcode='42501',
      message='This claim link is no longer active.',
      detail='HEHA_CLAIM_REVOKED';
  end if;
  if i.expires_at <= claim_time then
    raise exception using
      errcode='P0002',
      message='This claim link has expired.',
      detail='HEHA_CLAIM_EXPIRED';
  end if;

  -- Recheck permanent-recipient eligibility while both claim rows are locked.
  actor_email := app_private.verified_permanent_claim_email(actor);
  if actor_email is null then
    raise exception using
      errcode='42501',
      message='Use a permanent HEHA account with a verified email to claim this profile.',
      detail='HEHA_CLAIM_RECIPIENT_INELIGIBLE';
  end if;
  if i.intended_user_id is not null then
    if i.intended_user_id <> actor then
      raise exception using
        errcode='42501',
        message='This claim link belongs to a different account.',
        detail='HEHA_CLAIM_RECIPIENT_MISMATCH';
    end if;
  elsif actor_email <> i.intended_email_normalized then
    raise exception using
      errcode='42501',
      message='This claim link belongs to a different account.',
      detail='HEHA_CLAIM_RECIPIENT_MISMATCH';
  end if;

  if p.owner_id is not null then
    raise exception using
      errcode='23505',
      message='This business profile has already been claimed.',
      detail='HEHA_CLAIM_ALREADY_CLAIMED';
  end if;
  if p.claim_status not in ('unclaimed','claim_invited')
     or p.listing_status in ('opted_out','removed') then
    raise exception using
      errcode='42501',
      message='This profile is not available to claim.',
      detail='HEHA_CLAIM_PROFILE_UNAVAILABLE';
  end if;

  perform app_private.apply_verified_partner_claim(p.id,actor,claim_time);
  update public.partner_claim_invites as invite_row
  set consumed_at=claim_time, consumed_by=actor
  where invite_row.id=i.id;

  insert into public.partner_lifecycle_events(
    partner_id,event_type,actor_id,before_state,after_state
  ) values (
    p.id,
    'claim_redeemed',
    actor,
    app_private.partner_lifecycle_receipt(p),
    jsonb_build_object(
      'partner_id',p.id,
      'owner_id',actor,
      'claim_status','claimed',
      'claimed_at',claim_time
    )
  );

  return query select p.id,p.name,'claimed'::text,claim_time;
end;
$$;

revoke all on function public.create_partner_claim_invite(uuid,interval,text,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.preview_partner_claim(text)
  from public,anon,authenticated,service_role;
revoke all on function public.claim_partner_profile(text)
  from public,anon,authenticated,service_role;

grant execute on function public.create_partner_claim_invite(uuid,interval,text,uuid,text)
  to authenticated,service_role;
grant execute on function public.preview_partner_claim(text)
  to authenticated,service_role;
grant execute on function public.claim_partner_profile(text)
  to authenticated,service_role;
