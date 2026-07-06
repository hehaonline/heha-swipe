-- Partner Community Offer submission foundation.
-- Partner submissions enter the existing admin deal review workflow but never receive admin controls.

alter table public.admin_deal_requests
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
  add column if not exists source text not null default 'admin',
  add column if not exists suggested_offer_key text,
  add column if not exists custom_offer text,
  add column if not exists available_days text[] not null default '{}',
  add column if not exists minimum_purchase numeric(10,2),
  add column if not exists first_time_only boolean not null default false,
  add column if not exists max_uses_per_day integer,
  add column if not exists verification_preference text not null default 'heha_help_decide',
  add column if not exists partner_note text;

alter table public.admin_deal_requests
  drop constraint if exists admin_deal_requests_source_check,
  add constraint admin_deal_requests_source_check check (source in ('admin', 'partner')),
  drop constraint if exists admin_deal_requests_minimum_purchase_check,
  add constraint admin_deal_requests_minimum_purchase_check check (minimum_purchase is null or minimum_purchase >= 0),
  drop constraint if exists admin_deal_requests_max_uses_per_day_check,
  add constraint admin_deal_requests_max_uses_per_day_check check (max_uses_per_day is null or max_uses_per_day between 1 and 10000),
  drop constraint if exists admin_deal_requests_verification_preference_check,
  add constraint admin_deal_requests_verification_preference_check
    check (verification_preference in ('in_app_code', 'show_swipe_app', 'weekly_partner_code', 'heha_help_decide'));

create index if not exists admin_deal_requests_owner_idx
  on public.admin_deal_requests(owner_id, created_at desc);

create index if not exists admin_deal_requests_partner_source_idx
  on public.admin_deal_requests(partner_id, source, created_at desc);

grant select, insert on table public.admin_deal_requests to authenticated;

create or replace function app_private.guard_partner_deal_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    return new;
  end if;

  if app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      raise exception using errcode = '42501', message = 'Partner offer submissions must belong to the signed-in owner.';
    end if;

    if not exists (
      select 1 from public.partners p
      where p.id = new.partner_id and p.owner_id = actor_id
    ) then
      raise exception using errcode = '42501', message = 'Partner offers may only target your own business listing.';
    end if;

    if nullif(btrim(new.deal_title), '') is null then
      raise exception using errcode = '22023', message = 'Community Offer title is required.';
    end if;

    if nullif(btrim(coalesce(new.proposed_discount, new.custom_offer)), '') is null then
      raise exception using errcode = '22023', message = 'Choose a suggested Community Offer or describe a custom offer.';
    end if;

    if new.end_date is not null and new.start_date is not null and new.end_date < new.start_date then
      raise exception using errcode = '22023', message = 'Community Offer end date cannot be before the start date.';
    end if;

    new.source := 'partner';
    new.deal_type := 'community_pass';
    new.approval_status := 'draft';
    new.final_status := 'draft';
    new.content_needed := false;
    new.platform_visibility := '{}'::jsonb;
    new.risk_notes := null;
    new.created_by := actor_id;
    new.updated_by := actor_id;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  raise exception using errcode = '42501', message = 'Partner owners cannot directly modify deal review records after submission.';
end;
$$;

revoke all on function app_private.guard_partner_deal_request() from public, anon, authenticated;

drop trigger if exists partner_deal_request_guard on public.admin_deal_requests;
create trigger partner_deal_request_guard
before insert or update on public.admin_deal_requests
for each row
execute function app_private.guard_partner_deal_request();

drop policy if exists "Owners can view own partner deal requests" on public.admin_deal_requests;
create policy "Owners can view own partner deal requests"
on public.admin_deal_requests
for select
to authenticated
using (source = 'partner' and owner_id = auth.uid());

drop policy if exists "Owners can submit own partner deal requests" on public.admin_deal_requests;
create policy "Owners can submit own partner deal requests"
on public.admin_deal_requests
for insert
to authenticated
with check (
  owner_id = auth.uid()
  and exists (
    select 1 from public.partners p
    where p.id = partner_id and p.owner_id = auth.uid()
  )
);

comment on column public.admin_deal_requests.source is
  'Origin of the deal request. Partner submissions are review-only and never auto-activate.';

comment on column public.admin_deal_requests.verification_preference is
  'Partner preference for future offer verification. Redemption system activation remains HEHA-controlled.';
