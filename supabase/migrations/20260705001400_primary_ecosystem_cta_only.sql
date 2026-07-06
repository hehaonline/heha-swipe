alter table public.partners drop constraint if exists partners_primary_cta_destination_check;
alter table public.partners add constraint partners_primary_cta_destination_check
check (primary_cta_destination is null or primary_cta_destination = any (array['local','swipe']));

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
      new.primary_cta_destination := case when new.local_eligible then 'local' else 'swipe' end;
    end if;

    if new.primary_cta_label is null then
      new.primary_cta_label := case
        when new.primary_cta_destination = 'local' then public.partner_cta_label_for_lane(new.local_lane)
        else 'Discover Partner'
      end;
    end if;

    if new.primary_cta_path is null then
      new.primary_cta_path := case
        when new.primary_cta_destination = 'local' then public.partner_cta_path_for_lane(new.local_lane, new.id)
        else '/?partner=' || new.id::text
      end;
    end if;

    if new.routing_status = 'suggested' then new.routing_status := 'needs_review'; end if;
    new.routing_updated_at := coalesce(new.routing_updated_at, now());
  end if;

  return new;
end;
$$;
