create or replace function public.sync_scout_swipe_card_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.partner_id is null then return new; end if;

  update public.partners
  set neighborhood = coalesce(nullif(new.neighborhood, ''), nullif(new.city, ''), neighborhood),
      tagline = coalesce(nullif(new.tagline, ''), tagline),
      bio = coalesce(nullif(new.bio, ''), bio),
      hours = coalesce(nullif(new.hours, ''), hours),
      business_type = coalesce(nullif(new.business_category, ''), business_type),
      offerings = case
        when nullif(btrim(new.offerings_text), '') is null then offerings
        else string_to_array(replace(new.offerings_text, chr(10), ','), ',')
      end,
      photo_emoji = coalesce(nullif(new.photo_emoji, ''), photo_emoji),
      color = coalesce(nullif(new.card_color, ''), color)
  where id = new.partner_id
    and coalesce(status, 'pending') in ('pending', 'review_needed');

  return new;
end;
$$;

drop trigger if exists scout_leads_sync_swipe_card on public.scout_leads;
create trigger scout_leads_sync_swipe_card
after insert or update on public.scout_leads
for each row execute function public.sync_scout_swipe_card_fields();

revoke execute on function public.sync_scout_swipe_card_fields() from public, anon, authenticated;
