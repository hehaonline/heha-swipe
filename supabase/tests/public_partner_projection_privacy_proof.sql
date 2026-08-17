-- Run only against a disposable database or current-schema clone.
--
-- Exact invocation:
--   psql -X -v ON_ERROR_STOP=1 \
--     -f supabase/tests/public_partner_projection_privacy_proof.sql \
--     postgresql://...

\set ON_ERROR_STOP on

begin;

do $structural_contract$
declare
  expected_columns constant text[] := array[
    'id', 'created_at', 'name', 'category', 'categories', 'instagram',
    'website', 'bio', 'tags', 'rating', 'review_count', 'distance_text',
    'color', 'photo_emoji', 'heha_partner', 'status', 'hours',
    'business_type', 'offerings', 'neighborhood', 'tagline', 'items',
    'image_url', 'price_range', 'gallery_urls', 'partner_type',
    'delivery_days', 'heha_pillar', 'local_eligible', 'local_lane',
    'primary_cta_destination', 'primary_cta_label', 'primary_cta_path'
  ]::text[];
  expected_policies constant text[] := array[
    'Owners can view own partner',
    'partners_internal_read'
  ]::text[];
  actual_columns text[];
  actual_policies text[];
  partner_owner oid;
  view_name text;
  view_options text[];
  view_owner oid;
begin
  if not (
    select c.relrowsecurity
    from pg_catalog.pg_class c
    where c.oid = 'public.partners'::regclass
  ) then
    raise exception 'public.partners must have RLS enabled';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.partners', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.partners', 'INSERT')
     or pg_catalog.has_table_privilege('anon', 'public.partners', 'UPDATE')
     or pg_catalog.has_table_privilege('anon', 'public.partners', 'DELETE')
     or pg_catalog.has_table_privilege('anon', 'public.partners', 'TRUNCATE')
     or pg_catalog.has_table_privilege('anon', 'public.partners', 'REFERENCES')
     or pg_catalog.has_table_privilege('anon', 'public.partners', 'TRIGGER') then
    raise exception 'anon must not have raw SELECT on public.partners or any other base-table privilege';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class c
    cross join lateral pg_catalog.aclexplode(
      coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))
    ) acl
    where c.oid = 'public.partners'::regclass
      and acl.grantee = 0
  ) then
    raise exception 'PUBLIC must not have any privilege on public.partners';
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.partners', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'TRUNCATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'REFERENCES')
     or pg_catalog.has_table_privilege('authenticated', 'public.partners', 'TRIGGER') then
    raise exception 'authenticated raw partner ACL is broader or narrower than SELECT/INSERT/UPDATE';
  end if;

  select pg_catalog.array_agg(p.polname order by p.polname)
  into actual_policies
  from pg_catalog.pg_policy p
  where p.polrelid = 'public.partners'::regclass
    and p.polcmd in ('r', '*');

  if actual_policies is distinct from expected_policies then
    raise exception 'unexpected partner SELECT policy set: %', actual_policies;
  end if;

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
      raise exception 'unexpected public column contract for %: %', view_name, actual_columns;
    end if;

    select c.reloptions, c.relowner
    into view_options, view_owner
    from pg_catalog.pg_class c
    where c.oid = pg_catalog.to_regclass(pg_catalog.format('public.%I', view_name));

    if not ('security_barrier=true' = any (coalesce(view_options, array[]::text[])))
       or 'security_invoker=true' = any (coalesce(view_options, array[]::text[]))
       or view_owner is distinct from partner_owner then
      raise exception '% is not a same-owner security-barrier definer view', view_name;
    end if;

    if not pg_catalog.has_table_privilege(
      'anon',
      pg_catalog.format('public.%I', view_name),
      'SELECT'
    ) or not pg_catalog.has_table_privilege(
      'authenticated',
      pg_catalog.format('public.%I', view_name),
      'SELECT'
    ) then
      raise exception 'browser SELECT grant missing on %', view_name;
    end if;

    if pg_catalog.has_table_privilege('anon', pg_catalog.format('public.%I', view_name), 'INSERT')
       or pg_catalog.has_table_privilege('anon', pg_catalog.format('public.%I', view_name), 'UPDATE')
       or pg_catalog.has_table_privilege('anon', pg_catalog.format('public.%I', view_name), 'DELETE')
       or pg_catalog.has_table_privilege('anon', pg_catalog.format('public.%I', view_name), 'TRUNCATE')
       or pg_catalog.has_table_privilege('anon', pg_catalog.format('public.%I', view_name), 'REFERENCES')
       or pg_catalog.has_table_privilege('anon', pg_catalog.format('public.%I', view_name), 'TRIGGER')
       or pg_catalog.has_table_privilege('authenticated', pg_catalog.format('public.%I', view_name), 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', pg_catalog.format('public.%I', view_name), 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', pg_catalog.format('public.%I', view_name), 'DELETE')
       or pg_catalog.has_table_privilege('authenticated', pg_catalog.format('public.%I', view_name), 'TRUNCATE')
       or pg_catalog.has_table_privilege('authenticated', pg_catalog.format('public.%I', view_name), 'REFERENCES')
       or pg_catalog.has_table_privilege('authenticated', pg_catalog.format('public.%I', view_name), 'TRIGGER') then
      raise exception 'browser role has non-SELECT privilege on %', view_name;
    end if;

    if exists (
      select 1
      from pg_catalog.pg_class c
      cross join lateral pg_catalog.aclexplode(
        coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))
      ) acl
      where c.oid = pg_catalog.to_regclass(pg_catalog.format('public.%I', view_name))
        and acl.grantee = 0
    ) then
      raise exception 'PUBLIC has a privilege on %', view_name;
    end if;
  end loop;
end;
$structural_contract$;

set local role anon;
do $anon_persona$
declare
  actual_ids uuid[];
begin
  begin
    perform 1 from public.partners limit 1;
    raise exception 'anon unexpectedly read public.partners';
  exception
    when insufficient_privilege then null;
  end;

  select pg_catalog.array_agg(id order by id)
  into actual_ids
  from public.public_partner_directory;
  if actual_ids is distinct from array[
    '11111111-1111-4111-8111-111111111111'::uuid,
    '22222222-2222-4222-8222-222222222222'::uuid,
    '55555555-5555-4555-8555-555555555555'::uuid,
    '66666666-6666-4666-8666-666666666666'::uuid
  ] then
    raise exception 'directory row filter drifted: %', actual_ids;
  end if;

  select pg_catalog.array_agg(id order by id)
  into actual_ids
  from public.public_swipe_partners;
  if actual_ids is distinct from array[
    '11111111-1111-4111-8111-111111111111'::uuid,
    '22222222-2222-4222-8222-222222222222'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '66666666-6666-4666-8666-666666666666'::uuid
  ] then
    raise exception 'Swipe row filter drifted: %', actual_ids;
  end if;

  select pg_catalog.array_agg(id order by id)
  into actual_ids
  from public.public_local_partners;
  if actual_ids is distinct from array[
    '11111111-1111-4111-8111-111111111111'::uuid,
    '22222222-2222-4222-8222-222222222222'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '55555555-5555-4555-8555-555555555555'::uuid
  ] then
    raise exception 'Local row filter drifted: %', actual_ids;
  end if;
end;
$anon_persona$;
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
set local role authenticated;
do $owner_persona$
declare
  actual_ids uuid[];
begin
  select pg_catalog.array_agg(id order by id)
  into actual_ids
  from public.partners;

  if actual_ids is distinct from array[
    '11111111-1111-4111-8111-111111111111'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid
  ] then
    raise exception 'owner raw-row scope drifted or saved-row leak returned: %', actual_ids;
  end if;

  if (select count(*) from public.public_swipe_partners) <> 4 then
    raise exception 'signed-in discovery lost the public Swipe projection';
  end if;
end;
$owner_persona$;
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  true
);
set local role authenticated;
do $unrelated_persona$
begin
  if exists (select 1 from public.partners) then
    raise exception 'unrelated authenticated user read a raw partner row';
  end if;
end;
$unrelated_persona$;
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  true
);
set local role authenticated;
do $internal_persona$
begin
  if (select count(*) from public.partners) <> 7 then
    raise exception 'approved internal role did not retain deterministic raw partner read access';
  end if;
end;
$internal_persona$;
reset role;

rollback;

select 'public partner projection privacy proof passed' as result;
