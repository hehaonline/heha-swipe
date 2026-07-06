-- First-time Community Offer redemption guard.

create or replace function app_private.guard_first_time_community_offer_redemption()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  first_time_only_offer boolean := false;
begin
  select coalesce(o.first_time_only, false)
  into first_time_only_offer
  from public.community_offers_public o
  where o.deal_request_id = new.deal_request_id;

  if first_time_only_offer and exists (
    select 1
    from public.community_offer_redemptions r
    where r.deal_request_id = new.deal_request_id
      and r.user_id = new.user_id
      and r.status in ('confirmed_by_partner', 'completed')
  ) then
    raise exception using
      errcode = '22023',
      message = 'This first-time Community Offer has already been used by your account.';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_first_time_community_offer_redemption() from public, anon, authenticated;

drop trigger if exists community_offer_redemptions_first_time_guard on public.community_offer_redemptions;
create trigger community_offer_redemptions_first_time_guard
before insert on public.community_offer_redemptions
for each row
execute function app_private.guard_first_time_community_offer_redemption();
