-- Review-only hybrid partner lifecycle. PRODUCTION FREEZE: exact donor heads and live
-- baseline must be reviewed before this migration is applied outside a disposable DB.

create schema if not exists app_private;

alter table public.partners
  add column if not exists claim_status text not null default 'unclaimed',
  add column if not exists partnership_status text not null default 'not_requested',
  add column if not exists contract_status text not null default 'not_required',
  add column if not exists listing_status text not null default 'hidden',
  add column if not exists contract_not_required_approved boolean not null default false;

alter table public.partners
  drop constraint if exists partners_claim_status_check,
  add constraint partners_claim_status_check check
    (claim_status in ('unclaimed', 'claim_invited', 'claimed')),
  drop constraint if exists partners_partnership_status_check,
  add constraint partners_partnership_status_check check
    (partnership_status in ('not_requested', 'requested', 'under_review', 'official_partner', 'terminated')),
  drop constraint if exists partners_contract_status_check,
  add constraint partners_contract_status_check check
    (contract_status in ('not_required', 'not_signed', 'signed', 'terminated')),
  drop constraint if exists partners_listing_status_check,
  add constraint partners_listing_status_check check
    (listing_status in ('listed', 'hidden', 'opted_out', 'removed')),
  drop constraint if exists partners_claim_owner_consistency,
  add constraint partners_claim_owner_consistency check
    ((claim_status = 'claimed') = (owner_id is not null)) not valid,
  drop constraint if exists partners_official_contract_consistency,
  add constraint partners_official_contract_consistency check (
    partnership_status <> 'official_partner'
    or (claim_status = 'claimed' and
        (contract_status = 'signed' or
         (contract_status = 'not_required' and contract_not_required_approved)))
  );

-- Forward-only mapping. Legacy status remains intact for compatibility. Unknown values
-- fail closed as hidden; legacy certification is review evidence, not contract evidence.
update public.partners
set claim_status = case when owner_id is null then 'unclaimed' else 'claimed' end,
    partnership_status = case
      when coalesce(heha_partner, false) then 'under_review'
      else 'not_requested'
    end,
    contract_status = case
      when coalesce(heha_partner, false) then 'not_signed'
      else 'not_required'
    end,
    listing_status = case lower(coalesce(status, ''))
      when 'live' then 'listed' when 'listed' then 'listed' when 'approved' then 'listed'
      when 'removed' then 'removed' when 'rejected' then 'removed'
      else 'hidden'
    end
where claim_status = 'unclaimed'
  and partnership_status = 'not_requested'
  and contract_status = 'not_required'
  and listing_status = 'hidden';

alter table public.partners validate constraint partners_claim_owner_consistency;

create table if not exists public.partner_claim_invitations (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  recipient_email text not null,
  token_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  check (recipient_email = lower(btrim(recipient_email))),
  check (expires_at > created_at)
);

create unique index if not exists partner_claim_one_active_invite_idx
  on public.partner_claim_invitations(partner_id)
  where consumed_at is null and revoked_at is null;

create table if not exists public.partner_lifecycle_events (
  id bigint generated always as identity primary key,
  partner_id uuid not null references public.partners(id) on delete restrict,
  event_type text not null,
  actor_id uuid references auth.users(id) on delete set null,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now()
);

alter table public.partner_claim_invitations enable row level security;
alter table public.partner_lifecycle_events enable row level security;

create policy partner_claim_invites_internal_read on public.partner_claim_invitations
  for select to authenticated
  using (app_private.has_internal_role(array['super_admin', 'developer_admin']));
create policy partner_lifecycle_internal_read on public.partner_lifecycle_events
  for select to authenticated
  using (app_private.has_internal_role(array['super_admin', 'developer_admin']));

revoke all on public.partner_claim_invitations from public, anon, authenticated;
revoke all on public.partner_lifecycle_events from public, anon, authenticated;
grant select on public.partner_claim_invitations, public.partner_lifecycle_events to authenticated;

create or replace function app_private.guard_hybrid_partner_statuses()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp as $$
declare actor uuid := auth.uid();
begin
  if actor is null or app_private.has_internal_role(array['super_admin', 'developer_admin']) then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.claim_status := case when new.owner_id = actor then 'claimed' else 'unclaimed' end;
    new.partnership_status := 'not_requested';
    new.contract_status := 'not_required';
    new.listing_status := 'hidden';
    new.contract_not_required_approved := false;
  elsif new.claim_status is distinct from old.claim_status
     or new.partnership_status is distinct from old.partnership_status
     or new.contract_status is distinct from old.contract_status
     or new.listing_status is distinct from old.listing_status
     or new.contract_not_required_approved is distinct from old.contract_not_required_approved
     or new.owner_id is distinct from old.owner_id then
    raise exception using errcode = '42501',
      message = 'Partner owners cannot alter protected lifecycle or ownership fields.';
  end if;
  return new;
end $$;

drop trigger if exists aa_guard_hybrid_partner_statuses on public.partners;
create trigger aa_guard_hybrid_partner_statuses before insert or update on public.partners
for each row execute function app_private.guard_hybrid_partner_statuses();

revoke all on function app_private.guard_hybrid_partner_statuses() from public, anon, authenticated;

create or replace function public.request_partner_partnership(p_partner_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp as $$
declare p public.partners; saved_claims text;
begin
  select * into p from public.partners where id = p_partner_id for update;
  if p.owner_id is distinct from auth.uid() or p.claim_status <> 'claimed' then
    raise exception using errcode = '42501', message = 'Only the claimed owner may request partnership.';
  end if;
  if p.partnership_status not in ('not_requested', 'terminated') then
    raise exception using errcode = '23514', message = 'Partnership cannot be requested from the current state.';
  end if;
  saved_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  update public.partners set partnership_status = 'requested', contract_status = 'not_signed',
    contract_not_required_approved = false, updated_at = now() where id = p_partner_id;
  perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values (p_partner_id,'partnership_requested',auth.uid(),to_jsonb(p),
    jsonb_build_object('partnership_status','requested','contract_status','not_signed'));
end $$;

create or replace function public.review_partner_partnership(
  p_partner_id uuid, p_partnership_status text, p_contract_status text,
  p_not_required_approved boolean default false
) returns void language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp as $$
declare p public.partners;
begin
  if not app_private.has_internal_role(array['super_admin', 'developer_admin']) then
    raise exception using errcode = '42501', message = 'Internal partnership review required.';
  end if;
  select * into p from public.partners where id = p_partner_id for update;
  if p_partnership_status not in ('under_review','official_partner','terminated') then
    raise exception using errcode = '23514', message = 'Invalid internal partnership transition.';
  end if;
  if (p_partnership_status = 'under_review' and p.partnership_status <> 'requested')
     or (p_partnership_status = 'official_partner' and p.partnership_status <> 'under_review')
     or (p_partnership_status = 'terminated' and p.partnership_status not in ('requested','under_review','official_partner')) then
    raise exception using errcode = '23514', message = 'Partnership transition is not allowed from the current state.';
  end if;
  update public.partners set partnership_status=p_partnership_status,
    contract_status=p_contract_status,
    contract_not_required_approved=p_not_required_approved, updated_at=now()
  where id=p_partner_id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p_partner_id,'partnership_reviewed',auth.uid(),to_jsonb(p),jsonb_build_object(
    'partnership_status',p_partnership_status,'contract_status',p_contract_status));
end $$;

create or replace function public.redeem_partner_claim(p_token text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp as $$
declare invitation public.partner_claim_invitations; p public.partners;
  actor uuid := auth.uid(); jwt jsonb := auth.jwt(); supplied_hash text; saved_claims text;
begin
  if actor is null or coalesce((jwt->>'email_verified')::boolean,false) is not true then
    raise exception using errcode='42501', message='A verified authenticated recipient is required.';
  end if;
  supplied_hash := encode(extensions.digest(p_token, 'sha256'), 'hex');
  select * into invitation from public.partner_claim_invitations
   where token_hash=supplied_hash for update;
  if not found or invitation.consumed_at is not null or invitation.revoked_at is not null
     or invitation.expires_at <= now()
     or lower(jwt->>'email') <> invitation.recipient_email then
    raise exception using errcode='42501', message='Claim invitation is invalid.';
  end if;
  select * into p from public.partners where id=invitation.partner_id for update;
  if p.owner_id is not null or p.claim_status not in ('unclaimed','claim_invited') then
    raise exception using errcode='23505', message='Partner is already claimed or requires manual reconciliation.';
  end if;
  saved_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  update public.partners set owner_id=actor, claim_status='claimed', updated_at=now() where id=p.id;
  perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
  update public.partner_claim_invitations set consumed_at=now(), consumed_by=actor where id=invitation.id;
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p.id,'claim_redeemed',actor,to_jsonb(p),jsonb_build_object('claim_status','claimed','owner_id',actor));
  return p.id;
end $$;

create or replace function public.issue_partner_claim(
  p_partner_id uuid, p_recipient_email text, p_expires_at timestamptz
) returns text language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, extensions, pg_temp as $$
declare raw_token text := encode(extensions.gen_random_bytes(32),'hex'); p public.partners;
begin
  if not app_private.has_internal_role(array['super_admin','developer_admin']) then
    raise exception using errcode='42501', message='Internal claim issuance required.';
  end if;
  select * into p from public.partners where id=p_partner_id for update;
  if p.owner_id is not null or p.claim_status <> 'unclaimed' then
    raise exception using errcode='23505', message='Profile is claimed or requires manual reconciliation.';
  end if;
  update public.partner_claim_invitations set revoked_at=now()
    where partner_id=p_partner_id and consumed_at is null and revoked_at is null;
  insert into public.partner_claim_invitations(partner_id,recipient_email,token_hash,expires_at,created_by)
  values(p_partner_id,lower(btrim(p_recipient_email)),
    encode(extensions.digest(raw_token,'sha256'),'hex'),p_expires_at,auth.uid());
  update public.partners set claim_status='claim_invited',updated_at=now() where id=p_partner_id;
  return raw_token;
end $$;

create or replace function public.opt_out_partner_listing(p_partner_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp as $$
declare p public.partners; actor uuid := auth.uid(); saved_claims text;
begin
  select * into p from public.partners where id=p_partner_id for update;
  if actor is null or p.owner_id is distinct from actor or p.claim_status <> 'claimed' then
    raise exception using errcode='42501', message='Only the claimed owner may opt out.';
  end if;
  saved_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  update public.partners set listing_status='opted_out',updated_at=now() where id=p_partner_id;
  perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
  insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
  values(p_partner_id,'listing_opted_out',actor,to_jsonb(p),jsonb_build_object('listing_status','opted_out'));
end $$;

create or replace function app_private.record_partner_owner_release()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if old.owner_id is not null and new.owner_id is null then
    new.claim_status := 'unclaimed';
    insert into public.partner_lifecycle_events(partner_id,event_type,actor_id,before_state,after_state)
    values(old.id,'owner_released',auth.uid(),to_jsonb(old),jsonb_build_object('claim_status','unclaimed'));
  elsif old.owner_id is null and new.owner_id is not null
        and old.claim_status in ('unclaimed','claim_invited') and new.claim_status = 'claimed' then
    null; -- redeem_partner_claim owns the verified-recipient and invitation locks.
  elsif old.owner_id is distinct from new.owner_id then
    raise exception using errcode='23505', message='Direct owner transfer fails closed; release and verified reclaim are required.';
  end if;
  return new;
end $$;

drop trigger if exists a_owner_release_provenance on public.partners;
create trigger a_owner_release_provenance before update of owner_id on public.partners
for each row execute function app_private.record_partner_owner_release();

revoke all on function public.request_partner_partnership(uuid) from public, anon;
grant execute on function public.request_partner_partnership(uuid) to authenticated;
revoke all on function public.review_partner_partnership(uuid,text,text,boolean) from public, anon;
grant execute on function public.review_partner_partnership(uuid,text,text,boolean) to authenticated;
revoke all on function public.redeem_partner_claim(text) from public, anon;
grant execute on function public.redeem_partner_claim(text) to authenticated;
revoke all on function public.issue_partner_claim(uuid,text,timestamptz) from public, anon;
grant execute on function public.issue_partner_claim(uuid,text,timestamptz) to authenticated;
revoke all on function public.opt_out_partner_listing(uuid) from public, anon;
grant execute on function public.opt_out_partner_listing(uuid) to authenticated;
