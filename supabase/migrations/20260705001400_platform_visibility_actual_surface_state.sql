create or replace function public.sync_partner_platform_visibility()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.admin_platform_visibility (
    partner_id,
    heha_swipe_status,
    heha_local_status,
    wix_status
  ) values (
    new.id,
    case
      when new.status = any (array['approved','live']) and coalesce(new.swipe_eligible,false) then 'live'
      when coalesce(new.swipe_eligible,false) then 'ready'
      else 'not_applicable'
    end,
    case
      when coalesce(new.local_eligible,false) then 'ready'
      else 'not_applicable'
    end,
    case
      when coalesce(new.website_eligible,false) then 'ready'
      else 'not_applicable'
    end
  )
  on conflict (partner_id) where partner_id is not null do update
  set heha_swipe_status = excluded.heha_swipe_status,
      heha_local_status = case
        when not coalesce(new.local_eligible,false) then 'not_applicable'
        when public.admin_platform_visibility.heha_local_status = 'live' then 'live'
        else 'ready'
      end,
      wix_status = case
        when not coalesce(new.website_eligible,false) then 'not_applicable'
        when public.admin_platform_visibility.wix_status = 'live' then 'live'
        else 'ready'
      end,
      updated_at = now();
  return new;
end;
$$;

update public.admin_platform_visibility v
set heha_swipe_status = case
      when p.status = any (array['approved','live']) and coalesce(p.swipe_eligible,false) then 'live'
      when coalesce(p.swipe_eligible,false) then 'ready'
      else 'not_applicable'
    end,
    heha_local_status = case
      when coalesce(p.local_eligible,false) then 'ready'
      else 'not_applicable'
    end,
    wix_status = case
      when coalesce(p.website_eligible,false) then 'ready'
      else 'not_applicable'
    end,
    updated_at = now()
from public.partners p
where p.id = v.partner_id;
