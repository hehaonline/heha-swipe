-- Fail closed around the public partner boundary.
--
-- Raw partner rows contain owner identifiers, contact details, precise location,
-- review history, analytics, pricing internals and routing notes. Browser roles
-- must use the explicit public-card views below instead of the base table.
--
-- The public views are deliberately security-definer projections. This is the
-- narrow exception required to keep anonymous and signed-in discovery working
-- after anon loses all base-table privileges and the public-row RLS policy is
-- removed. The exception is bounded by all of the following:
--   * an exact column allowlist;
--   * explicit approved/live, destination-eligibility and test-record filters;
--   * security_barrier=true;
--   * the same owner as public.partners;
--   * SELECT-only grants to anon/authenticated; and
--   * disposable ACL, persona, row-filter and column-contract proofs.

alter table public.partners enable row level security;

-- SELECT policies are reset as one deterministic set. A FOR ALL policy could
-- also authorize SELECT, so stop for human review rather than silently changing
-- an unexpected write policy.
do $policy_reset$
declare
  existing_policy record;
begin
  if exists (
    select 1
    from pg_catalog.pg_policy
    where polrelid = 'public.partners'::regclass
      and polcmd = '*'
  ) then
    raise exception using
      errcode = '55000',
      message = 'public.partners has a FOR ALL policy; review it before applying the public projection hardening';
  end if;

  for existing_policy in
    select polname
    from pg_catalog.pg_policy
    where polrelid = 'public.partners'::regclass
      and polcmd = 'r'
  loop
    execute pg_catalog.format(
      'drop policy %I on public.partners',
      existing_policy.polname
    );
  end loop;
end;
$policy_reset$;

create policy "Owners can view own partner"
on public.partners
for select
to authenticated
using (
  (select auth.uid()) is not null
  and (select auth.uid()) = owner_id
);

create policy partners_internal_read
on public.partners
for select
to authenticated
using (
  app_private.has_internal_role(
    array[
      'super_admin',
      'pm_admin',
      'community_events_admin',
      'som_admin',
      'developer_admin'
    ]::text[]
  )
);

revoke all on table public.partners from public, anon;
revoke delete, truncate, references, trigger on table public.partners from authenticated;
grant select, insert, update on table public.partners to authenticated;

-- PR #118 owns a broader exact-version publication-consent gate. If its private
-- projection is present, leave its already-safe public views intact so this
-- privacy repair cannot weaken destination consent, revocation or profile-hash
-- checks. The exact contract assertion below still fails closed on any unsafe
-- or drifted view definition.
do $public_views$
declare
  heha_partner_expression text := 'p.heha_partner';
  listing_predicate text := '';
begin
  if pg_catalog.to_regclass('app_private.partner_publication_projection') is not null then
    return;
  end if;

  -- Preserve PR #120's lifecycle gate if this forward fix is replayed after the
  -- still-frozen lifecycle migration, without exposing its internal statuses.
  if exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public.partners'::regclass
      and attname = 'partnership_status'
      and not attisdropped
  ) and exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public.partners'::regclass
      and attname = 'listing_status'
      and not attisdropped
  ) then
    heha_partner_expression := '(p.partnership_status = ''official_partner'')';
    listing_predicate := 'and p.listing_status = ''listed''';
  end if;

  -- Removing columns requires DROP + CREATE; CREATE OR REPLACE cannot shrink a
  -- PostgreSQL view. The audited production schema has no dependent relations,
  -- and a dependency discovered during replay aborts this transaction.
  drop view if exists public.public_partner_directory;
  drop view if exists public.public_swipe_partners;
  drop view if exists public.public_local_partners;

  execute pg_catalog.format($directory$
    create view public.public_partner_directory
    with (security_invoker = false, security_barrier = true)
    as
    select
      p.id,
      p.created_at,
      p.name,
      p.category,
      p.categories,
      p.instagram,
      p.website,
      p.bio,
      p.tags,
      p.rating,
      p.review_count,
      p.distance_text,
      p.color,
      p.photo_emoji,
      %s as heha_partner,
      p.status,
      p.hours,
      p.business_type,
      p.offerings,
      p.neighborhood,
      p.tagline,
      p.items,
      p.image_url,
      p.price_range,
      p.gallery_urls,
      p.partner_type,
      p.delivery_days,
      p.heha_pillar,
      p.local_eligible,
      p.local_lane,
      p.primary_cta_destination,
      p.primary_cta_label,
      p.primary_cta_path
    from public.partners p
    where p.status = any (array['approved', 'live']::text[])
      and coalesce(p.website_eligible, false) = true
      and p.is_test_record = false
      %s
  $directory$, heha_partner_expression, listing_predicate);

  execute pg_catalog.format($swipe$
    create view public.public_swipe_partners
    with (security_invoker = false, security_barrier = true)
    as
    select
      p.id,
      p.created_at,
      p.name,
      p.category,
      p.categories,
      p.instagram,
      p.website,
      p.bio,
      p.tags,
      p.rating,
      p.review_count,
      p.distance_text,
      p.color,
      p.photo_emoji,
      %s as heha_partner,
      p.status,
      p.hours,
      p.business_type,
      p.offerings,
      p.neighborhood,
      p.tagline,
      p.items,
      p.image_url,
      p.price_range,
      p.gallery_urls,
      p.partner_type,
      p.delivery_days,
      p.heha_pillar,
      p.local_eligible,
      p.local_lane,
      p.primary_cta_destination,
      p.primary_cta_label,
      p.primary_cta_path
    from public.partners p
    where p.status = any (array['approved', 'live']::text[])
      and coalesce(p.swipe_eligible, false) = true
      and p.is_test_record = false
      %s
  $swipe$, heha_partner_expression, listing_predicate);

  execute pg_catalog.format($local$
    create view public.public_local_partners
    with (security_invoker = false, security_barrier = true)
    as
    select
      p.id,
      p.created_at,
      p.name,
      p.category,
      p.categories,
      p.instagram,
      p.website,
      p.bio,
      p.tags,
      p.rating,
      p.review_count,
      p.distance_text,
      p.color,
      p.photo_emoji,
      %s as heha_partner,
      p.status,
      p.hours,
      p.business_type,
      p.offerings,
      p.neighborhood,
      p.tagline,
      p.items,
      p.image_url,
      p.price_range,
      p.gallery_urls,
      p.partner_type,
      p.delivery_days,
      p.heha_pillar,
      p.local_eligible,
      p.local_lane,
      p.primary_cta_destination,
      p.primary_cta_label,
      p.primary_cta_path
    from public.partners p
    where p.status = any (array['approved', 'live']::text[])
      and coalesce(p.local_eligible, false) = true
      and p.local_lane is not null
      and p.is_test_record = false
      %s
  $local$, heha_partner_expression, listing_predicate);
end;
$public_views$;

revoke all on table public.public_partner_directory from public, anon, authenticated;
revoke all on table public.public_swipe_partners from public, anon, authenticated;
revoke all on table public.public_local_partners from public, anon, authenticated;

grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

do $public_contract$
declare
  expected_columns constant text[] := array[
    'id',
    'created_at',
    'name',
    'category',
    'categories',
    'instagram',
    'website',
    'bio',
    'tags',
    'rating',
    'review_count',
    'distance_text',
    'color',
    'photo_emoji',
    'heha_partner',
    'status',
    'hours',
    'business_type',
    'offerings',
    'neighborhood',
    'tagline',
    'items',
    'image_url',
    'price_range',
    'gallery_urls',
    'partner_type',
    'delivery_days',
    'heha_pillar',
    'local_eligible',
    'local_lane',
    'primary_cta_destination',
    'primary_cta_label',
    'primary_cta_path'
  ]::text[];
  view_name text;
  actual_columns text[];
  view_options text[];
  view_owner oid;
  partner_owner oid;
begin
  select c.relowner
  into partner_owner
  from pg_catalog.pg_class c
  where c.oid = 'public.partners'::regclass;

  foreach view_name in array array[
    'public_partner_directory',
    'public_swipe_partners',
    'public_local_partners'
  ]::text[] loop
    select pg_catalog.array_agg(cols.column_name order by cols.ordinal_position)
    into actual_columns
    from information_schema.columns cols
    where cols.table_schema = 'public'
      and cols.table_name = view_name;

    if actual_columns is distinct from expected_columns then
      raise exception using
        errcode = '55000',
        message = pg_catalog.format(
          'unsafe column contract for public.%I: expected %s, found %s',
          view_name,
          expected_columns,
          actual_columns
        );
    end if;

    select c.reloptions, c.relowner
    into view_options, view_owner
    from pg_catalog.pg_class c
    where c.oid = pg_catalog.to_regclass(pg_catalog.format('public.%I', view_name));

    if not ('security_barrier=true' = any (coalesce(view_options, array[]::text[])))
       or 'security_invoker=true' = any (coalesce(view_options, array[]::text[]))
       or view_owner is distinct from partner_owner then
      raise exception using
        errcode = '55000',
        message = pg_catalog.format(
          'public.%I must be a same-owner security-barrier definer projection',
          view_name
        );
    end if;
  end loop;
end;
$public_contract$;

comment on view public.public_partner_directory is
  'SELECT-only public website card projection. Raw owner, contact, location, analytics, pricing, review and routing internals are excluded.';
comment on view public.public_swipe_partners is
  'SELECT-only public Swipe card projection. Raw owner, contact, location, analytics, pricing, review, routing and lifecycle internals are excluded.';
comment on view public.public_local_partners is
  'SELECT-only public Local bridge card projection. Raw owner, contact, location, analytics, pricing, review and routing internals are excluded.';
