-- Community Offer redemption and two-sided confirmation foundation.
--
-- Live Community Offers are projected into a safe public table. Customers receive a
-- short-lived six-digit code. Partner owners confirm the code through an RPC scoped to
-- their own listing. Customers then confirm whether the offer was received or report a problem.

create table if not exists public.community_offers_public (
  deal_request_id uuid primary key references public.admin_deal_requests(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  partner_name text not null,
  partner_category text,
  deal_title text not null,
  offer_text text not null,
  deal_terms text,
  available_days text[] not null default '{}',
  minimum_purchase numeric(10,2),
  first_time_only boolean not null default false,
  max_uses_per_day integer,
  verification_preference text not null default 'in_app_code',
  start_date date,
  end_date date,
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.community_offers_public enable row level security;
revoke all on table public.community_offers_public from anon, authenticated;
grant select on table public.community_offers_public to anon, authenticated;

drop policy if exists "Public can view active Community Offers" on public.community_offers_public;
create policy "Public can view active Community Offers"
on public.community_offers_public
for select
to anon, authenticated
using (true);

create table if not exists public.community_offer_redemptions (
  id uuid primary key default gen_random_uuid(),
  deal_request_id uuid not null references public.admin_deal_requests(id) on delete restrict,
  partner_id uuid not null references public.partners(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  redemption_code text not null,
  status text not null default 'issued',
  offer_title_snapshot text not null,
  offer_text_snapshot text not null,
  first_time_only_snapshot boolean not null default false,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  partner_confirmed_at timestamptz,
  partner_confirmed_by uuid references auth.users(id) on delete set null,
  customer_confirmed_at timestamptz,
  customer_outcome text,
  customer_problem_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_offer_redemptions_code_check
    check (redemption_code ~ '^[0-9]{6}$'),
  constraint community_offer_redemptions_status_check
    check (status in ('issued', 'confirmed_by_partner', 'completed', 'problem', 'expired', 'cancelled')),
  constraint community_offer_redemptions_customer_outcome_check
    check (customer_outcome is null or customer_outcome in ('all_good', 'problem')),
  constraint community_offer_redemptions_expiry_check
    check (expires_at > issued_at)
);

create index if not exists community_offer_redemptions_user_idx
  on public.community_offer_redemptions(user_id, created_at desc);

create index if not exists community_offer_redemptions_partner_idx
  on public.community_offer_redemptions(partner_id, created_at desc);

create index if not exists community_offer_redemptions_deal_idx
  on public.community_offer_redemptions(deal_request_id, created_at desc);

create unique index if not exists community_offer_redemptions_active_code_key
  on public.community_offer_redemptions(partner_id, redemption_code)
  where status = 'issued';

alter table public.community_offer_redemptions enable row level security;
revoke all on table public.community_offer_redemptions from anon, authenticated;
grant select on table public.community_offer_redemptions to authenticated;

drop policy if exists "Customers can view own Community Offer redemptions" on public.community_offer_redemptions;
create policy "Customers can view own Community Offer redemptions"
on public.community_offer_redemptions
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Internal users can view Community Offer redemptions" on public.community_offer_redemptions;
create policy "Internal users can view Community Offer redemptions"
on public.community_offer_redemptions
for select
to authenticated
using (app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']));

create or replace function app_private.sync_public_community_offer(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
begin
  delete from public.community_offers_public
  where deal_request_id = p_deal_id;

  insert into public.community_offers_public (
    deal_request_id,
    partner_id,
    partner_name,
    partner_category,
    deal_title,
    offer_text,
    deal_terms,
    available_days,
    minimum_purchase,
    first_time_only,
    max_uses_per_day,
    verification_preference,
    start_date,
    end_date,
    published_at,
    updated_at
  )
  select
    d.id,
    p.id,
    p.name,
    p.category,
    d.deal_title,
    coalesce(nullif(btrim(d.custom_offer), ''), nullif(btrim(d.proposed_discount), '')),
    d.deal_terms,
    coalesce(d.available_days, '{}'::text[]),
    d.minimum_purchase,
    coalesce(d.first_time_only, false),
    d.max_uses_per_day,
    coalesce(d.verification_preference, 'in_app_code'),
    d.start_date,
    d.end_date,
    coalesce(d.updated_at, now()),
    now()
  from public.admin_deal_requests d
  join public.partners p on p.id = d.partner_id
  where d.id = p_deal_id
    and d.source = 'partner'
    and d.deal_type = 'community_pass'
    and d.approval_status = 'approved'
    and d.final_status = 'live'
    and p.status in ('approved', 'live')
    and coalesce(p.swipe_eligible, false) = true
    and coalesce(nullif(btrim(d.custom_offer), ''), nullif(btrim(d.proposed_discount), '')) is not null;
end;
$$;

revoke all on function app_private.sync_public_community_offer(uuid) from public, anon, authenticated;

create or replace function app_private.sync_public_community_offer_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.community_offers_public where deal_request_id = old.id;
    return old;
  end if;

  perform app_private.sync_public_community_offer(new.id);
  return new;
end;
$$;

revoke all on function app_private.sync_public_community_offer_trigger() from public, anon, authenticated;

drop trigger if exists admin_deal_requests_sync_public_community_offer on public.admin_deal_requests;
create trigger admin_deal_requests_sync_public_community_offer
after insert or update or delete on public.admin_deal_requests
for each row
execute function app_private.sync_public_community_offer_trigger();

create or replace function app_private.sync_public_community_offers_for_partner_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  deal_row record;
begin
  for deal_row in
    select id
    from public.admin_deal_requests
    where partner_id = new.id
      and source = 'partner'
      and deal_type = 'community_pass'
  loop
    perform app_private.sync_public_community_offer(deal_row.id);
  end loop;

  return new;
end;
$$;

revoke all on function app_private.sync_public_community_offers_for_partner_trigger() from public, anon, authenticated;

drop trigger if exists partners_sync_public_community_offers on public.partners;
create trigger partners_sync_public_community_offers
after update of status, swipe_eligible, name, category on public.partners
for each row
execute function app_private.sync_public_community_offers_for_partner_trigger();

-- Backfill any already-approved live Community Offers.
insert into public.community_offers_public (
  deal_request_id,
  partner_id,
  partner_name,
  partner_category,
  deal_title,
  offer_text,
  deal_terms,
  available_days,
  minimum_purchase,
  first_time_only,
  max_uses_per_day,
  verification_preference,
  start_date,
  end_date,
  published_at,
  updated_at
)
select
  d.id,
  p.id,
  p.name,
  p.category,
  d.deal_title,
  coalesce(nullif(btrim(d.custom_offer), ''), nullif(btrim(d.proposed_discount), '')),
  d.deal_terms,
  coalesce(d.available_days, '{}'::text[]),
  d.minimum_purchase,
  coalesce(d.first_time_only, false),
  d.max_uses_per_day,
  coalesce(d.verification_preference, 'in_app_code'),
  d.start_date,
  d.end_date,
  coalesce(d.updated_at, now()),
  now()
from public.admin_deal_requests d
join public.partners p on p.id = d.partner_id
where d.source = 'partner'
  and d.deal_type = 'community_pass'
  and d.approval_status = 'approved'
  and d.final_status = 'live'
  and p.status in ('approved', 'live')
  and coalesce(p.swipe_eligible, false) = true
  and coalesce(nullif(btrim(d.custom_offer), ''), nullif(btrim(d.proposed_discount), '')) is not null
on conflict (deal_request_id) do update
set partner_name = excluded.partner_name,
    partner_category = excluded.partner_category,
    deal_title = excluded.deal_title,
    offer_text = excluded.offer_text,
    deal_terms = excluded.deal_terms,
    available_days = excluded.available_days,
    minimum_purchase = excluded.minimum_purchase,
    first_time_only = excluded.first_time_only,
    max_uses_per_day = excluded.max_uses_per_day,
    verification_preference = excluded.verification_preference,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    updated_at = now();

create or replace function public.issue_community_offer_redemption(p_deal_id uuid)
returns table (
  redemption_id uuid,
  redemption_code text,
  redemption_status text,
  expires_at timestamptz,
  partner_id uuid,
  partner_name text,
  offer_title text,
  offer_text text,
  first_time_only boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  offer_row public.community_offers_public%rowtype;
  existing_row public.community_offer_redemptions%rowtype;
  generated_code text;
  created_row public.community_offer_redemptions%rowtype;
  active_uses integer;
  attempt integer;
  today_name text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in to use a Community Offer.';
  end if;

  select * into offer_row
  from public.community_offers_public
  where deal_request_id = p_deal_id;

  if not found then
    raise exception using errcode = '22023', message = 'This Community Offer is not active.';
  end if;

  if offer_row.start_date is not null and current_date < offer_row.start_date then
    raise exception using errcode = '22023', message = 'This Community Offer has not started yet.';
  end if;

  if offer_row.end_date is not null and current_date > offer_row.end_date then
    raise exception using errcode = '22023', message = 'This Community Offer has ended.';
  end if;

  today_name := trim(to_char((now() at time zone 'America/New_York')::date, 'FMDay'));
  if cardinality(offer_row.available_days) > 0 and not (today_name = any (offer_row.available_days)) then
    raise exception using errcode = '22023', message = 'This Community Offer is not available today.';
  end if;

  update public.community_offer_redemptions
  set status = 'expired', updated_at = now()
  where status = 'issued'
    and expires_at <= now();

  select * into existing_row
  from public.community_offer_redemptions
  where user_id = actor_id
    and deal_request_id = p_deal_id
    and (
      (status = 'issued' and expires_at > now())
      or status = 'confirmed_by_partner'
    )
  order by created_at desc
  limit 1;

  if found then
    return query select
      existing_row.id,
      existing_row.redemption_code,
      existing_row.status,
      existing_row.expires_at,
      existing_row.partner_id,
      offer_row.partner_name,
      existing_row.offer_title_snapshot,
      existing_row.offer_text_snapshot,
      existing_row.first_time_only_snapshot;
    return;
  end if;

  if offer_row.max_uses_per_day is not null then
    select count(*) into active_uses
    from public.community_offer_redemptions r
    where r.deal_request_id = p_deal_id
      and (r.issued_at at time zone 'America/New_York')::date = (now() at time zone 'America/New_York')::date
      and (
        (r.status = 'issued' and r.expires_at > now())
        or r.status in ('confirmed_by_partner', 'completed')
      );

    if active_uses >= offer_row.max_uses_per_day then
      raise exception using errcode = '22023', message = 'Today''s Community Offer limit has been reached.';
    end if;
  end if;

  generated_code := null;
  for attempt in 1..20 loop
    generated_code := lpad(floor(random() * 1000000)::integer::text, 6, '0');
    exit when not exists (
      select 1
      from public.community_offer_redemptions r
      where r.partner_id = offer_row.partner_id
        and r.redemption_code = generated_code
        and r.status = 'issued'
    );
    generated_code := null;
  end loop;

  if generated_code is null then
    raise exception using errcode = '55000', message = 'Could not create a redemption code. Please try again.';
  end if;

  insert into public.community_offer_redemptions (
    deal_request_id,
    partner_id,
    user_id,
    redemption_code,
    status,
    offer_title_snapshot,
    offer_text_snapshot,
    first_time_only_snapshot,
    issued_at,
    expires_at
  ) values (
    p_deal_id,
    offer_row.partner_id,
    actor_id,
    generated_code,
    'issued',
    offer_row.deal_title,
    offer_row.offer_text,
    offer_row.first_time_only,
    now(),
    now() + interval '10 minutes'
  )
  returning * into created_row;

  return query select
    created_row.id,
    created_row.redemption_code,
    created_row.status,
    created_row.expires_at,
    created_row.partner_id,
    offer_row.partner_name,
    created_row.offer_title_snapshot,
    created_row.offer_text_snapshot,
    created_row.first_time_only_snapshot;
end;
$$;

revoke all on function public.issue_community_offer_redemption(uuid) from public, anon;
grant execute on function public.issue_community_offer_redemption(uuid) to authenticated;

create or replace function public.confirm_community_offer_code(p_partner_id uuid, p_code text)
returns table (
  redemption_id uuid,
  redemption_status text,
  offer_title text,
  offer_text text,
  first_time_only boolean,
  confirmed_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  matched_row public.community_offer_redemptions%rowtype;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in to confirm a Community Offer.';
  end if;

  if p_code is null or p_code !~ '^[0-9]{6}$' then
    raise exception using errcode = '22023', message = 'Enter the six-digit HEHA redemption code.';
  end if;

  if not exists (
    select 1 from public.partners p
    where p.id = p_partner_id and p.owner_id = actor_id
  ) then
    raise exception using errcode = '42501', message = 'You can only confirm offers for your own business listing.';
  end if;

  update public.community_offer_redemptions
  set status = 'expired', updated_at = now()
  where partner_id = p_partner_id
    and status = 'issued'
    and expires_at <= now();

  select * into matched_row
  from public.community_offer_redemptions
  where partner_id = p_partner_id
    and redemption_code = p_code
    and status = 'issued'
    and expires_at > now()
  order by issued_at desc
  limit 1
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'That code is invalid or expired.';
  end if;

  update public.community_offer_redemptions
  set status = 'confirmed_by_partner',
      partner_confirmed_at = now(),
      partner_confirmed_by = actor_id,
      updated_at = now()
  where id = matched_row.id
  returning * into matched_row;

  return query select
    matched_row.id,
    matched_row.status,
    matched_row.offer_title_snapshot,
    matched_row.offer_text_snapshot,
    matched_row.first_time_only_snapshot,
    matched_row.partner_confirmed_at;
end;
$$;

revoke all on function public.confirm_community_offer_code(uuid, text) from public, anon;
grant execute on function public.confirm_community_offer_code(uuid, text) to authenticated;

create or replace function public.confirm_community_offer_outcome(
  p_redemption_id uuid,
  p_outcome text,
  p_problem_note text default null
)
returns table (
  redemption_id uuid,
  redemption_status text,
  customer_outcome text,
  customer_confirmed_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  redemption_row public.community_offer_redemptions%rowtype;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'Sign in to confirm your Community Offer experience.';
  end if;

  if p_outcome not in ('all_good', 'problem') then
    raise exception using errcode = '22023', message = 'Choose whether the offer was received or there was a problem.';
  end if;

  select * into redemption_row
  from public.community_offer_redemptions
  where id = p_redemption_id
    and user_id = actor_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'This redemption does not belong to your account.';
  end if;

  if redemption_row.status in ('completed', 'problem') then
    return query select
      redemption_row.id,
      redemption_row.status,
      redemption_row.customer_outcome,
      redemption_row.customer_confirmed_at;
    return;
  end if;

  if redemption_row.status <> 'confirmed_by_partner' then
    raise exception using errcode = '22023', message = 'The business must confirm the offer before you finish the redemption.';
  end if;

  if p_outcome = 'problem' and nullif(btrim(coalesce(p_problem_note, '')), '') is null then
    raise exception using errcode = '22023', message = 'Tell HEHA briefly what went wrong.';
  end if;

  update public.community_offer_redemptions
  set status = case when p_outcome = 'all_good' then 'completed' else 'problem' end,
      customer_outcome = p_outcome,
      customer_problem_note = case when p_outcome = 'problem' then btrim(p_problem_note) else null end,
      customer_confirmed_at = now(),
      updated_at = now()
  where id = redemption_row.id
  returning * into redemption_row;

  return query select
    redemption_row.id,
    redemption_row.status,
    redemption_row.customer_outcome,
    redemption_row.customer_confirmed_at;
end;
$$;

revoke all on function public.confirm_community_offer_outcome(uuid, text, text) from public, anon;
grant execute on function public.confirm_community_offer_outcome(uuid, text, text) to authenticated;

comment on table public.community_offers_public is
  'Safe public projection of partner Community Offers that HEHA has approved and activated.';

comment on table public.community_offer_redemptions is
  'Short-lived Community Offer redemption codes and two-sided partner/customer confirmation state.';
