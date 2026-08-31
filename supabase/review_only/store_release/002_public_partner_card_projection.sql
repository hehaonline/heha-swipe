-- REVIEW ONLY. Do not apply through migration automation.
-- Creates a dedicated 13-field store-facing projection without owner, contact,
-- phone, email, moderation, routing, analytics, payment, or internal fields.

create or replace view public.public_swipe_partner_cards
with (security_invoker = true)
as
select
  id,
  name,
  category,
  categories,
  tagline,
  bio,
  neighborhood,
  tags,
  offerings,
  image_url,
  photo_emoji,
  heha_partner,
  created_at
from public.partners
where status = any (array['approved'::text, 'live'::text])
  and coalesce(swipe_eligible, false) = true
  and coalesce(is_test_record, false) = false;

revoke all on public.public_swipe_partner_cards from public, anon, authenticated;
grant select on public.public_swipe_partner_cards to anon, authenticated;

comment on view public.public_swipe_partner_cards is
  'Store-review public partner cards: exact 13-field contract, security invoker, approved/live records only.';

-- Reviewer checks:
-- select column_name from information_schema.columns
-- where table_schema = 'public' and table_name = 'public_swipe_partner_cards'
-- order by ordinal_position;
-- select * from public.public_swipe_partner_cards limit 1;
