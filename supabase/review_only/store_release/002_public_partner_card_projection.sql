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

create or replace function public.list_public_swipe_partner_details()
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
  created_at timestamptz,
  location text,
  color text,
  items jsonb,
  gallery_urls jsonb,
  website text,
  instagram text,
  price_range text,
  local_eligible boolean,
  local_lane text,
  primary_cta_destination text,
  primary_cta_path text
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
    partner.created_at,
    partner.location,
    partner.color,
    coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'name', case when jsonb_typeof(item.value -> 'name') = 'string' then item.value -> 'name' end,
          'emoji', case when jsonb_typeof(item.value -> 'emoji') = 'string' then item.value -> 'emoji' end,
          'url', case
            when jsonb_typeof(item.value -> 'url') = 'string'
              and btrim(item.value ->> 'url') ~* '^https?://[a-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:][:cntrl:]]*)?$'
              and btrim(item.value ->> 'url') !~ '[[:space:][:cntrl:]]'
            then to_jsonb(btrim(item.value ->> 'url'))
          end,
          'product_url', case
            when jsonb_typeof(item.value -> 'product_url') = 'string'
              and btrim(item.value ->> 'product_url') ~* '^https?://[a-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:][:cntrl:]]*)?$'
              and btrim(item.value ->> 'product_url') !~ '[[:space:][:cntrl:]]'
            then to_jsonb(btrim(item.value ->> 'product_url'))
          end,
          'link', case
            when jsonb_typeof(item.value -> 'link') = 'string'
              and btrim(item.value ->> 'link') ~* '^https?://[a-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:][:cntrl:]]*)?$'
              and btrim(item.value ->> 'link') !~ '[[:space:][:cntrl:]]'
            then to_jsonb(btrim(item.value ->> 'link'))
          end,
          'local_product_id', case when jsonb_typeof(item.value -> 'local_product_id') in ('string', 'number') then item.value -> 'local_product_id' end,
          'product_id', case when jsonb_typeof(item.value -> 'product_id') in ('string', 'number') then item.value -> 'product_id' end
        ))
        order by item.ordinality
      )
      from jsonb_array_elements(
        case
          when jsonb_typeof(partner.items) = 'array' then partner.items
          else '[]'::jsonb
        end
      ) with ordinality as item(value, ordinality)
      where jsonb_typeof(item.value) = 'object'
    ), '[]'::jsonb) as items,
    coalesce((
      select jsonb_agg(image.value order by image.ordinality)
      from jsonb_array_elements(
        case
          when jsonb_typeof(partner.gallery_urls) = 'array' then partner.gallery_urls
          else '[]'::jsonb
        end
      ) with ordinality as image(value, ordinality)
      where jsonb_typeof(image.value) = 'string'
    ), '[]'::jsonb) as gallery_urls,
    partner.website,
    partner.instagram,
    partner.price_range,
    partner.local_eligible,
    partner.local_lane,
    partner.primary_cta_destination,
    partner.primary_cta_path
  from public.partners as partner
  where partner.status = any (array['approved'::text, 'live'::text])
    and coalesce(partner.swipe_eligible, false) = true
    and coalesce(partner.is_test_record, false) = false
  order by
    partner.heha_partner desc nulls last,
    partner.created_at desc nulls last,
    partner.id;
$$;

revoke all on function public.list_public_swipe_partner_details()
  from public, anon, authenticated;
grant execute on function public.list_public_swipe_partner_details()
  to anon, authenticated;

comment on function public.list_public_swipe_partner_details() is
  'Web-only Swipe details: zero-argument, fixed 24-field approved/live projection with whitelisted item keys and HTTP(S) links.';

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
