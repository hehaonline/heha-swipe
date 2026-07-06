alter table public.partners add column if not exists heha_pillar text;
alter table public.partners add column if not exists website_eligible boolean;
alter table public.partners add column if not exists swipe_eligible boolean;
alter table public.partners add column if not exists local_eligible boolean;
alter table public.partners add column if not exists local_lane text;
alter table public.partners add column if not exists primary_cta_destination text;
alter table public.partners add column if not exists primary_cta_label text;
alter table public.partners add column if not exists primary_cta_path text;
alter table public.partners add column if not exists routing_status text not null default 'suggested';
alter table public.partners add column if not exists routing_notes text;
alter table public.partners add column if not exists routing_updated_by uuid references auth.users(id) on delete set null;
alter table public.partners add column if not exists routing_updated_at timestamptz;

alter table public.partners drop constraint if exists partners_heha_pillar_check;
alter table public.partners add constraint partners_heha_pillar_check check (heha_pillar is null or heha_pillar = any (array['nourish','educate','relax','elevate']));
alter table public.partners drop constraint if exists partners_local_lane_check;
alter table public.partners add constraint partners_local_lane_check check (local_lane is null or local_lane = any (array['meals','market','vendors','chef','group_orders']));
alter table public.partners drop constraint if exists partners_primary_cta_destination_check;
alter table public.partners add constraint partners_primary_cta_destination_check check (primary_cta_destination is null or primary_cta_destination = any (array['local','swipe','external']));
alter table public.partners drop constraint if exists partners_routing_status_check;
alter table public.partners add constraint partners_routing_status_check check (routing_status = any (array['suggested','needs_review','approved','paused']));

create or replace function public.suggest_partner_local_lane(
  p_category text,
  p_business_type text,
  p_product_price_policy text,
  p_service_fee_type text,
  p_delivery_days text[]
)
returns text
language sql
immutable
as $$
  select case
    when lower(coalesce(p_category,'')) like '%private chef%'
      or lower(coalesce(p_business_type,'')) like '%private chef%'
      or lower(coalesce(p_business_type,'')) like '%retreat chef%'
      then 'chef'
    when lower(coalesce(p_category,'')) like '%catering%'
      or lower(coalesce(p_business_type,'')) like '%catering%'
      or lower(coalesce(p_business_type,'')) like '%food truck%'
      or lower(coalesce(p_business_type,'')) like '%group order%'
      or lower(coalesce(p_business_type,'')) like '%staff meal%'
      then 'group_orders'
    when lower(coalesce(p_category,'')) = 'restaurant'
      or lower(coalesce(p_business_type,'')) like '%restaurant%'
      or lower(coalesce(p_business_type,'')) like '%juice bar%'
      or lower(coalesce(p_business_type,'')) like '%beverage bar%'
      or lower(coalesce(p_business_type,'')) like '%meal prep%'
      then 'meals'
    when lower(coalesce(p_business_type,'')) like '%natural grocery%'
      or lower(coalesce(p_business_type,'')) like '%health market%'
      then 'market'
    when lower(coalesce(p_category,'')) = 'vendor' and (
      lower(coalesce(p_business_type,'')) ~ '(food|cottage|bakery|pantry|beverage|drink|herbal product)'
      or nullif(btrim(coalesce(p_product_price_policy,'')), '') is not null
      or nullif(btrim(coalesce(p_service_fee_type,'')), '') is not null
      or coalesce(cardinality(p_delivery_days), 0) > 0
    ) then 'vendors'
    when lower(coalesce(p_category,'')) = 'markets' and (
      lower(coalesce(p_business_type,'')) ~ '(natural grocery|health market|grocery)'
      or nullif(btrim(coalesce(p_product_price_policy,'')), '') is not null
      or nullif(btrim(coalesce(p_service_fee_type,'')), '') is not null
    ) then 'market'
    else null
  end;
$$;

create or replace function public.partner_cta_label_for_lane(p_lane text)
returns text language sql immutable as $$
  select case p_lane
    when 'meals' then 'Order Meals'
    when 'market' then 'Explore Market'
    when 'vendors' then 'Shop Local Vendor'
    when 'chef' then 'Explore Chef'
    when 'group_orders' then 'Group Orders'
    else 'Discover Partner'
  end;
$$;

create or replace function public.partner_cta_path_for_lane(p_lane text, p_partner_id uuid)
returns text language sql immutable as $$
  select case p_lane
    when 'meals' then '/restaurants'
    when 'market' then '/market'
    when 'vendors' then '/vendors'
    when 'chef' then '/chef'
    when 'group_orders' then '/group-orders'
    else '/?partner=' || p_partner_id::text
  end;
$$;

create or replace function public.apply_partner_routing_suggestions()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  suggested_lane text;
  is_public boolean;
begin
  if new.routing_status = 'approved' then return new; end if;

  suggested_lane := public.suggest_partner_local_lane(new.category, new.business_type, new.product_price_policy, new.service_fee_type, new.delivery_days);
  is_public := new.status = any (array['approved','live','listed']);

  if is_public then
    if new.website_eligible is null then new.website_eligible := true; end if;
    if new.swipe_eligible is null then new.swipe_eligible := true; end if;
    if new.local_lane is null then new.local_lane := suggested_lane; end if;
    if new.local_eligible is null then new.local_eligible := new.local_lane is not null; end if;

    if new.primary_cta_destination is null then
      new.primary_cta_destination := case when new.local_eligible then 'local' when new.swipe_eligible then 'swipe' else 'external' end;
    end if;

    if new.primary_cta_label is null then
      new.primary_cta_label := case
        when new.primary_cta_destination = 'local' then public.partner_cta_label_for_lane(new.local_lane)
        when new.primary_cta_destination = 'swipe' then 'Discover Partner'
        else 'Learn More'
      end;
    end if;

    if new.primary_cta_path is null then
      new.primary_cta_path := case
        when new.primary_cta_destination = 'local' then public.partner_cta_path_for_lane(new.local_lane, new.id)
        when new.primary_cta_destination = 'swipe' then '/?partner=' || new.id::text
        else new.website
      end;
    end if;

    if new.routing_status = 'suggested' then new.routing_status := 'needs_review'; end if;
    new.routing_updated_at := coalesce(new.routing_updated_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists partners_apply_routing_suggestions on public.partners;
create trigger partners_apply_routing_suggestions
before insert or update of status, category, business_type, product_price_policy, service_fee_type, delivery_days, website_eligible, swipe_eligible, local_eligible, local_lane, primary_cta_destination, primary_cta_label, primary_cta_path, routing_status
on public.partners
for each row execute function public.apply_partner_routing_suggestions();

update public.partners set status = status where status = any (array['approved','live','listed']);

create or replace view public.public_partner_directory with (security_invoker = true) as
select * from public.partners where status = any (array['approved','live']) and coalesce(website_eligible, false) = true;

create or replace view public.public_swipe_partners with (security_invoker = true) as
select * from public.partners where status = any (array['approved','live']) and coalesce(swipe_eligible, false) = true;

create or replace view public.public_local_partners with (security_invoker = true) as
select * from public.partners where status = any (array['approved','live']) and coalesce(local_eligible, false) = true and local_lane is not null;

create unique index if not exists admin_platform_visibility_partner_id_key
on public.admin_platform_visibility(partner_id)
where partner_id is not null;

insert into public.admin_platform_visibility (partner_id, heha_swipe_status, heha_local_status, wix_status, hubspot_status)
select
  p.id,
  case when p.status = any (array['approved','live']) and coalesce(p.swipe_eligible,false) then 'live' else 'draft' end,
  case when p.status = any (array['approved','live']) and coalesce(p.local_eligible,false) then 'live' when coalesce(p.local_eligible,false) then 'ready' else 'not_applicable' end,
  case when p.status = any (array['approved','live']) and coalesce(p.website_eligible,false) then 'live' else 'draft' end,
  case when h.sync_status = 'success' then 'live' when h.id is not null then 'needs_update' else 'not_applicable' end
from public.partners p
left join public.admin_hubspot_links h on h.partner_id = p.id
on conflict (partner_id) where partner_id is not null do update
set heha_swipe_status = excluded.heha_swipe_status,
    heha_local_status = excluded.heha_local_status,
    wix_status = excluded.wix_status,
    hubspot_status = excluded.hubspot_status,
    updated_at = now();

create or replace function public.sync_partner_platform_visibility()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.admin_platform_visibility (partner_id, heha_swipe_status, heha_local_status, wix_status)
  values (
    new.id,
    case when new.status = any (array['approved','live']) and coalesce(new.swipe_eligible,false) then 'live' else 'draft' end,
    case when new.status = any (array['approved','live']) and coalesce(new.local_eligible,false) then 'live' when coalesce(new.local_eligible,false) then 'ready' else 'not_applicable' end,
    case when new.status = any (array['approved','live']) and coalesce(new.website_eligible,false) then 'live' else 'draft' end
  )
  on conflict (partner_id) where partner_id is not null do update
  set heha_swipe_status = excluded.heha_swipe_status,
      heha_local_status = excluded.heha_local_status,
      wix_status = excluded.wix_status,
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists partners_sync_platform_visibility on public.partners;
create trigger partners_sync_platform_visibility
after insert or update of status, website_eligible, swipe_eligible, local_eligible, local_lane
on public.partners
for each row execute function public.sync_partner_platform_visibility();

comment on column public.partners.website_eligible is 'Eligible for broad intentional partner search on the HEHA website directory.';
comment on column public.partners.swipe_eligible is 'Eligible for HEHA Swipe discovery: show me something new.';
comment on column public.partners.local_eligible is 'Eligible for HEHA Local food/order utility.';
comment on column public.partners.local_lane is 'HEHA Local lane: meals, market, vendors, chef, or group_orders.';
