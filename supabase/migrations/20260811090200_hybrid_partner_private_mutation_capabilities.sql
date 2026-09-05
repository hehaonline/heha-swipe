-- Private single-use mutation capabilities for PR #120.
-- Review-only and Production-frozen with the hybrid successor.
--
-- Custom GUC values alone are not authorization: PostgreSQL roles can set
-- arbitrary custom settings in direct SQL sessions. This migration adds a
-- private capability row keyed to the current backend, transaction and partner.
-- Approved SECURITY DEFINER workflows create one capability immediately before
-- the protected UPDATE. The final BEFORE trigger consumes it and clears the GUC,
-- preventing both caller spoofing and transaction-local authorization leakage.

create table if not exists app_private.partner_lifecycle_mutation_capabilities (
  backend_pid integer not null,
  transaction_id bigint not null,
  partner_id uuid not null,
  operation text not null check (
    operation in ('claim','partnership_request','partnership_review','listing_change')
  ),
  created_at timestamptz not null default now(),
  primary key (backend_pid, transaction_id, partner_id)
);

revoke all on table app_private.partner_lifecycle_mutation_capabilities
  from public, anon, authenticated, service_role;

create or replace function app_private.authorize_partner_lifecycle_mutation(
  p_partner_id uuid,
  p_operation text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, app_private, pg_temp
as $$
begin
  if p_operation not in ('claim','partnership_request','partnership_review','listing_change') then
    raise exception using errcode='22023', message='Invalid partner lifecycle operation.';
  end if;

  insert into app_private.partner_lifecycle_mutation_capabilities(
    backend_pid,
    transaction_id,
    partner_id,
    operation
  ) values (
    pg_backend_pid(),
    txid_current(),
    p_partner_id,
    p_operation
  )
  on conflict (backend_pid, transaction_id, partner_id)
  do update set operation=excluded.operation, created_at=now();

  perform set_config('app.hybrid_partner_context', p_operation, true);
end;
$$;

revoke all on function app_private.authorize_partner_lifecycle_mutation(uuid,text)
  from public, anon, authenticated, service_role;

create or replace function app_private.gate_partner_lifecycle_capability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, pg_temp
as $$
declare
  op text := coalesce(current_setting('app.hybrid_partner_context', true), '');
  lifecycle_changed boolean;
  exact_owner_release boolean;
begin
  lifecycle_changed :=
       new.owner_id is distinct from old.owner_id
    or new.claim_status is distinct from old.claim_status
    or new.partnership_status is distinct from old.partnership_status
    or new.contract_status is distinct from old.contract_status
    or new.listing_status is distinct from old.listing_status
    or new.claimed_at is distinct from old.claimed_at
    or new.claimed_by is distinct from old.claimed_by
    or new.partnership_requested_at is distinct from old.partnership_requested_at
    or new.official_partner_since is distinct from old.official_partner_since
    or new.contract_signed_at is distinct from old.contract_signed_at
    or new.opted_out_at is distinct from old.opted_out_at
    or new.opted_out_by is distinct from old.opted_out_by
    or new.heha_partner is distinct from old.heha_partner;

  if not lifecycle_changed then
    return new;
  end if;

  -- Auth account deletion drives owner_id to NULL through the existing FK. At
  -- this first trigger, the release-provenance trigger has not yet normalized
  -- the remaining lifecycle fields, so only a pure owner unlink is accepted.
  exact_owner_release :=
       old.owner_id is not null
   and new.owner_id is null
   and new.claim_status is not distinct from old.claim_status
   and new.partnership_status is not distinct from old.partnership_status
   and new.contract_status is not distinct from old.contract_status
   and new.listing_status is not distinct from old.listing_status
   and new.claimed_at is not distinct from old.claimed_at
   and new.claimed_by is not distinct from old.claimed_by
   and new.partnership_requested_at is not distinct from old.partnership_requested_at
   and new.official_partner_since is not distinct from old.official_partner_since
   and new.contract_signed_at is not distinct from old.contract_signed_at
   and new.opted_out_at is not distinct from old.opted_out_at
   and new.opted_out_by is not distinct from old.opted_out_by
   and new.heha_partner is not distinct from old.heha_partner;

  if exact_owner_release then
    return new;
  end if;

  if op not in ('claim','partnership_request','partnership_review','listing_change')
     or not exists (
       select 1
       from app_private.partner_lifecycle_mutation_capabilities as cap
       where cap.backend_pid=pg_backend_pid()
         and cap.transaction_id=txid_current()
         and cap.partner_id=new.id
         and cap.operation=op
     ) then
    raise exception using
      errcode='42501',
      message='Partner lifecycle mutation lacks a private single-use capability.';
  end if;

  return new;
end;
$$;

revoke all on function app_private.gate_partner_lifecycle_capability()
  from public, anon, authenticated, service_role;

drop trigger if exists a00_hybrid_lifecycle_capability_gate on public.partners;
create trigger a00_hybrid_lifecycle_capability_gate
before update on public.partners
for each row execute function app_private.gate_partner_lifecycle_capability();

create or replace function app_private.consume_partner_lifecycle_capability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, pg_temp
as $$
begin
  delete from app_private.partner_lifecycle_mutation_capabilities as cap
  where cap.backend_pid=pg_backend_pid()
    and cap.transaction_id=txid_current()
    and cap.partner_id=new.id;

  -- Clear both capability-backed contexts and the owner-release context set by
  -- the provenance trigger. This prevents privileges leaking to later SQL in
  -- the same transaction.
  if nullif(current_setting('app.hybrid_partner_context', true), '') is not null then
    perform set_config('app.hybrid_partner_context', '', true);
  end if;

  return new;
end;
$$;

revoke all on function app_private.consume_partner_lifecycle_capability()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_hybrid_lifecycle_capability_consume on public.partners;
create trigger zz_hybrid_lifecycle_capability_consume
before update on public.partners
for each row execute function app_private.consume_partner_lifecycle_capability();

-- The existing verified-claim helper now establishes the private capability.
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
    raise exception using errcode='23505', message='Partner is already claimed or requires manual reconciliation.';
  end if;
end;
$$;

revoke all on function app_private.apply_verified_partner_claim(uuid,uuid,timestamptz)
  from public, anon, authenticated, service_role;

-- Re-qualify the invite RPC and authorize its partner-state transition.
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
  if actor_id is null then raise exception using errcode='28000', message='Authentication required.'; end if;
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[]) then
    raise exception using errcode='42501', message='HEHA internal claim-invite access required.';
  end if;
  if p_expires_in is null or p_expires_in < interval '15 minutes' or p_expires_in > interval '30 days' then
    raise exception using errcode='22023', message='Claim invite expiry must be between 15 minutes and 30 days.';
  end if;
  if (p_intended_user_id is null) = (normalized_email is null) then
    raise exception using errcode='22023', message='Provide exactly one intended recipient user or email.';
  end if;
  if normalized_email is not null and (length(normalized_email)>320 or position('@' in normalized_email)<=1) then
    raise exception using errcode='22023', message='A valid intended recipient email is required.';
  end if;

  if p_intended_user_id is not null then
    select u.email into account_email
    from auth.users as u
    where u.id=p_intended_user_id and u.email_confirmed_at is not null;
    if not found then raise exception using errcode='42501', message='Intended recipient account must have a verified email.'; end if;
    bound_user:=p_intended_user_id;
  else
    select u.id,u.email into bound_user,account_email
    from auth.users as u
    where lower(btrim(u.email))=normalized_email and u.email_confirmed_at is not null
    order by u.created_at asc limit 1;
    if bound_user is null then bound_email:=normalized_email; account_email:=normalized_email; end if;
  end if;

  hint:=left(split_part(lower(account_email),'@',1),1)||'***@'||split_part(lower(account_email),'@',2);

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;

  if not found then raise exception using errcode='P0002', message='Partner profile not found.'; end if;
  if p.owner_id is not null then raise exception using errcode='23505', message='This partner profile is already claimed.'; end if;
  if p.listing_status in ('opted_out','removed') then raise exception using errcode='42501', message='This listing is not eligible for a claim invitation.'; end if;

  update public.partner_claim_invites as invite_row
  set revoked_at=now(), revoked_by=actor_id
  where invite_row.partner_id=p_partner_id
    and invite_row.consumed_at is null
    and invite_row.revoked_at is null;

  raw:=encode(extensions.gen_random_bytes(32),'hex');
  exp:=now()+p_expires_in;

  insert into public.partner_claim_invites(
    id,partner_id,token_hash,created_by,expires_at,outreach_channel,
    intended_user_id,intended_email_normalized,recipient_hint
  ) values (
    new_id,p_partner_id,extensions.digest(raw,'sha256'),actor_id,exp,
    nullif(btrim(p_outreach_channel),''),bound_user,bound_email,hint
  );

  perform app_private.authorize_partner_lifecycle_mutation(p_partner_id,'claim');
  update public.partners as partner_row
  set claim_status='claim_invited', updated_at=now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p_partner_id,'claim_invite_created',actor_id,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p_partner_id,'claim_status','claim_invited','invite_id',new_id,'expires_at',exp));

  return query select new_id,p_partner_id,raw,exp,hint;
end;
$$;

-- Invitation revocation uses the same private claim capability only when it
-- transitions the canonical partner back to unclaimed.
create or replace function public.revoke_partner_claim_invite(p_invite_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor uuid:=auth.uid();
  partner_key uuid;
  i public.partner_claim_invites%rowtype;
  p public.partners%rowtype;
begin
  if actor is null then raise exception using errcode='28000', message='Authentication required.'; end if;
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']::text[]) then
    raise exception using errcode='42501', message='HEHA internal claim-invite access required.';
  end if;

  select invite_row.partner_id into partner_key
  from public.partner_claim_invites as invite_row
  where invite_row.id=p_invite_id;
  if partner_key is null then return false; end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=partner_key
  for update;

  select invite_row.* into i
  from public.partner_claim_invites as invite_row
  where invite_row.id=p_invite_id
  for update;

  if not found or i.consumed_at is not null or i.revoked_at is not null then return false; end if;

  update public.partner_claim_invites as invite_row
  set revoked_at=now(), revoked_by=actor
  where invite_row.id=p_invite_id;

  if p.owner_id is null and not exists(
    select 1 from public.partner_claim_invites as other_invite
    where other_invite.partner_id=p.id
      and other_invite.id<>p_invite_id
      and other_invite.consumed_at is null
      and other_invite.revoked_at is null
  ) then
    perform app_private.authorize_partner_lifecycle_mutation(p.id,'claim');
    update public.partners as partner_row
    set claim_status='unclaimed', updated_at=now()
    where partner_row.id=p.id;
  end if;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'claim_invite_revoked',actor,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'invite_id',p_invite_id,'revoked',true));
  return true;
end;
$$;

-- Partnership-interest trigger advances state through a single-use capability.
create or replace function app_private.apply_partner_interest_request_state()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare p public.partners;
begin
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=new.partner_id
  for update;

  if p.owner_id is distinct from new.owner_id
     or p.claim_status<>'claimed'
     or p.partnership_status not in ('not_requested','terminated') then
    raise exception using errcode='23514', message='Partner is not eligible to request partnership.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_request');
  update public.partners as partner_row
  set partnership_status='requested',
      contract_status='not_signed',
      partnership_requested_at=pg_catalog.now(),
      official_partner_since=null,
      contract_signed_at=null,
      heha_partner=false,
      updated_at=pg_catalog.now()
  where partner_row.id=new.partner_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_requested',new.owner_id,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'claim_status','claimed','partnership_status','requested',
      'contract_status','not_signed','listing_status',p.listing_status));
  return new;
end;
$$;

-- Internal partnership review.
create or replace function public.review_partner_partnership(p_partner_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$
declare p public.partners;
begin
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']) then
    raise exception using errcode='42501', message='Internal partnership review required.';
  end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;

  if not found then raise exception using errcode='P0002', message='Partner not found.'; end if;
  if p_status='under_review' and p.partnership_status<>'requested' then
    raise exception using errcode='23514', message='Only requested partnerships may enter review.';
  end if;
  if p_status='terminated' and p.partnership_status not in ('requested','under_review','official_partner') then
    raise exception using errcode='23514', message='Partnership cannot be terminated from current state.';
  end if;
  if p_status not in ('under_review','terminated') then
    raise exception using errcode='22023', message='Invalid review transition.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
  update public.partners as partner_row
  set partnership_status=p_status,
      contract_status=case when p_status='terminated' then 'terminated' else partner_row.contract_status end,
      heha_partner=false,
      updated_at=now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_reviewed',auth.uid(),app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'partnership_status',p_status,
      'contract_status',case when p_status='terminated' then 'terminated' else p.contract_status end,
      'heha_partner',false));
end;
$$;

-- Final Official Partner approval.
create or replace function public.approve_heha_partnership(p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  p public.partners;
  jwt_role text:=coalesce(nullif(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
begin
  if not (jwt_role='service_role' or app_private.has_internal_role(array['super_admin'])) then
    raise exception using errcode='42501', message='Not authorized to approve HEHA partnerships.';
  end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;

  if not found or p.claim_status<>'claimed' or p.partnership_status<>'under_review' then
    raise exception using errcode='23514', message='Partner is not in a valid reviewed and claimed state.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'partnership_review');
  update public.partners as partner_row
  set partnership_status='official_partner',
      contract_status='signed',
      contract_signed_at=pg_catalog.now(),
      official_partner_since=coalesce(partner_row.official_partner_since,pg_catalog.now()),
      heha_partner=true,
      updated_at=pg_catalog.now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'partnership_approved',auth.uid(),app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'claim_status','claimed','partnership_status','official_partner',
      'contract_status','signed','heha_partner',true));
end;
$$;

-- Internal listing changes.
create or replace function public.set_partner_listing_status(p_partner_id uuid,p_listing_status text)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$
declare p public.partners;
begin
  if not app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']) then
    raise exception using errcode='42501', message='Internal listing review required.';
  end if;
  if p_listing_status not in ('listed','hidden','removed') then
    raise exception using errcode='22023', message='Invalid internal listing status.';
  end if;

  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;

  if not found then raise exception using errcode='P0002', message='Partner not found.'; end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'listing_change');
  update public.partners as partner_row
  set listing_status=p_listing_status,
      opted_out_at=case when p_listing_status='listed' then null else partner_row.opted_out_at end,
      opted_out_by=case when p_listing_status='listed' then null else partner_row.opted_out_by end,
      updated_at=now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'listing_status_changed',auth.uid(),app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'listing_status',p_listing_status));
end;
$$;

-- Owner opt-out.
create or replace function public.opt_out_partner_listing(p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public,app_private,auth,pg_temp
as $$
declare p public.partners; actor uuid:=auth.uid();
begin
  select partner_row.* into p
  from public.partners as partner_row
  where partner_row.id=p_partner_id
  for update;

  if actor is null or p.owner_id is distinct from actor or p.claim_status<>'claimed' then
    raise exception using errcode='42501', message='Only the claimed owner may opt out.';
  end if;

  perform app_private.authorize_partner_lifecycle_mutation(p.id,'listing_change');
  update public.partners as partner_row
  set listing_status='opted_out',
      opted_out_at=now(),
      opted_out_by=actor,
      updated_at=now()
  where partner_row.id=p_partner_id;

  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'listing_opted_out',actor,app_private.partner_lifecycle_receipt(p),
    jsonb_build_object('partner_id',p.id,'listing_status','opted_out'));
end;
$$;

-- Restore deterministic public RPC ACLs after replacement.
revoke all on function public.create_partner_claim_invite(uuid,interval,text,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.revoke_partner_claim_invite(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.review_partner_partnership(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.approve_heha_partnership(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.set_partner_listing_status(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.opt_out_partner_listing(uuid)
  from public,anon,authenticated,service_role;

grant execute on function public.create_partner_claim_invite(uuid,interval,text,uuid,text)
  to authenticated,service_role;
grant execute on function public.revoke_partner_claim_invite(uuid)
  to authenticated,service_role;
grant execute on function public.review_partner_partnership(uuid,text)
  to authenticated,service_role;
grant execute on function public.approve_heha_partnership(uuid)
  to authenticated,service_role;
grant execute on function public.set_partner_listing_status(uuid,text)
  to authenticated,service_role;
grant execute on function public.opt_out_partner_listing(uuid)
  to authenticated,service_role;
