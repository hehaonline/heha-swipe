-- REVIEW ONLY. Do not apply through migration automation.
-- Phase A: introduce bounded public RPCs before any legacy view or base-table
-- privilege is removed. Client cutovers can be reviewed against this packet, but
-- the functions do not exist live until a separate database approval is given.
--
-- Live reconciliation on 2026-09-04 found browser-readable wide partner paths.
-- Phase B closure must wait until HEHA Local, Wix, Make, and website consumers
-- are inventoried and safely cut over.

begin;

-- SECURITY DEFINER is intentional because the eventual target state removes
-- browser-role SELECT from public.partners. Each function has zero arguments, a
-- fixed return schema, an empty search_path, fully-qualified sources, fixed
-- predicates, and no dynamic SQL.

create or replace function public.list_public_swipe_partner_cards()
returns table (
  id uuid,
  name text,
  category text,
  categories text[],
  tagline text,
  bio text,
  neighborhood text,
  tags text[],
  offerings text[],
  image_url text,
  photo_emoji text,
  heha_partner boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    partner.id,
    partner.name,
    partner.category,
    partner.categories,
    partner.tagline,
    partner.bio,
    partner.neighborhood,
    partner.tags,
    partner.offerings,
    partner.image_url,
    partner.photo_emoji,
    partner.heha_partner,
    partner.created_at
  from public.partners as partner
  where partner.status = any (array['approved'::text, 'live'::text])
    and coalesce(partner.swipe_eligible, false) = true
    and coalesce(partner.is_test_record, false) = false
  order by
    partner.heha_partner desc nulls last,
    partner.created_at desc nulls last,
    partner.id;
$$;

revoke all on function public.list_public_swipe_partner_cards()
  from public, anon, authenticated;
grant execute on function public.list_public_swipe_partner_cards()
  to anon, authenticated;

comment on function public.list_public_swipe_partner_cards() is
  'Store-review partner cards: zero-argument, fixed 13-field approved/live projection.';

create or replace function public.list_public_partner_directory()
returns table (
  id uuid,
  name text,
  category text,
  business_type text,
  tagline text,
  bio text,
  neighborhood text,
  location text,
  tags text[],
  offerings text[],
  image_url text,
  photo_emoji text,
  heha_pillar text,
  primary_cta_destination text,
  primary_cta_label text,
  primary_cta_path text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    partner.id,
    partner.name,
    partner.category,
    partner.business_type,
    partner.tagline,
    partner.bio,
    partner.neighborhood,
    partner.location,
    partner.tags,
    partner.offerings,
    partner.image_url,
    partner.photo_emoji,
    partner.heha_pillar,
    partner.primary_cta_destination,
    partner.primary_cta_label,
    partner.primary_cta_path,
    partner.created_at
  from public.partners as partner
  where partner.status = any (array['approved'::text, 'live'::text])
    and coalesce(partner.website_eligible, false) = true
    and coalesce(partner.is_test_record, false) = false
  order by
    partner.created_at desc nulls last,
    partner.id;
$$;

revoke all on function public.list_public_partner_directory()
  from public, anon, authenticated;
grant execute on function public.list_public_partner_directory()
  to anon, authenticated;

comment on function public.list_public_partner_directory() is
  'Public directory: zero-argument, fixed 17-field approved/live website projection.';

commit;
