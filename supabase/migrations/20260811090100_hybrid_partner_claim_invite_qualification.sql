-- Follow-up qualification fix for PR #120's hybrid claim-invite RPC.
-- Review-only and Production-frozen with the rest of the hybrid successor.
-- The function returns a column named partner_id, so every table reference that
-- also exposes partner_id must be explicitly qualified to avoid PL/pgSQL name
-- ambiguity at runtime.

create or replace function public.create_partner_claim_invite(
  p_partner_id uuid,
  p_expires_in interval default interval '7 days',
  p_outreach_channel text default null,
  p_intended_user_id uuid default null,
  p_intended_email text default null
) returns table(invite_id uuid, partner_id uuid, raw_token text, expires_at timestamptz, recipient_hint text)
language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  p public.partners%rowtype;
  raw text;
  normalized_email text := nullif(lower(btrim(p_intended_email)), '');
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
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[]) then
    raise exception using errcode='42501', message='HEHA internal claim-invite access required.';
  end if;
  if p_expires_in is null or p_expires_in < interval '15 minutes' or p_expires_in > interval '30 days' then
    raise exception using errcode='22023', message='Claim invite expiry must be between 15 minutes and 30 days.';
  end if;
  if (p_intended_user_id is null) = (normalized_email is null) then
    raise exception using errcode='22023', message='Provide exactly one intended recipient user or email.';
  end if;
  if normalized_email is not null and (length(normalized_email) > 320 or position('@' in normalized_email) <= 1) then
    raise exception using errcode='22023', message='A valid intended recipient email is required.';
  end if;

  if p_intended_user_id is not null then
    select u.email
    into account_email
    from auth.users as u
    where u.id = p_intended_user_id
      and u.email_confirmed_at is not null;
    if not found then
      raise exception using errcode='42501', message='Intended recipient account must have a verified email.';
    end if;
    bound_user := p_intended_user_id;
  else
    select u.id, u.email
    into bound_user, account_email
    from auth.users as u
    where lower(btrim(u.email)) = normalized_email
      and u.email_confirmed_at is not null
    order by u.created_at asc
    limit 1;
    if bound_user is null then
      bound_email := normalized_email;
      account_email := normalized_email;
    end if;
  end if;

  hint := left(split_part(lower(account_email),'@',1),1)
    || '***@' || split_part(lower(account_email),'@',2);

  select partner_row.*
  into p
  from public.partners as partner_row
  where partner_row.id = p_partner_id
  for update;

  if not found then
    raise exception using errcode='P0002', message='Partner profile not found.';
  end if;
  if p.owner_id is not null then
    raise exception using errcode='23505', message='This partner profile is already claimed.';
  end if;
  if p.listing_status in ('opted_out','removed') then
    raise exception using errcode='42501', message='This listing is not eligible for a claim invitation.';
  end if;

  update public.partner_claim_invites as invite_row
  set revoked_at = now(),
      revoked_by = actor_id
  where invite_row.partner_id = p_partner_id
    and invite_row.consumed_at is null
    and invite_row.revoked_at is null;

  raw := encode(extensions.gen_random_bytes(32),'hex');
  exp := now() + p_expires_in;

  insert into public.partner_claim_invites(
    id,
    partner_id,
    token_hash,
    created_by,
    expires_at,
    outreach_channel,
    intended_user_id,
    intended_email_normalized,
    recipient_hint
  ) values (
    new_id,
    p_partner_id,
    extensions.digest(raw,'sha256'),
    actor_id,
    exp,
    nullif(btrim(p_outreach_channel),''),
    bound_user,
    bound_email,
    hint
  );

  perform set_config('app.hybrid_partner_context','claim',true);
  update public.partners as partner_row
  set claim_status = 'claim_invited',
      updated_at = now()
  where partner_row.id = p_partner_id;

  insert into public.partner_lifecycle_events(
    partner_id,
    event_type,
    actor_id,
    before_state,
    after_state
  ) values (
    p_partner_id,
    'claim_invite_created',
    actor_id,
    app_private.partner_lifecycle_receipt(p),
    jsonb_build_object(
      'partner_id',p_partner_id,
      'claim_status','claim_invited',
      'invite_id',new_id,
      'expires_at',exp
    )
  );

  return query
  select new_id, p_partner_id, raw, exp, hint;
end;
$$;

-- Preserve the deterministic donor ACL after replacement.
revoke all on function public.create_partner_claim_invite(uuid,interval,text,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.create_partner_claim_invite(uuid,interval,text,uuid,text)
  to authenticated, service_role;
