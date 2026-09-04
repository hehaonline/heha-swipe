-- REVIEW ONLY. Do not apply through migration automation.
-- Purpose: close direct browser-role access to wide partner sources and expose
-- only the exact 13-field, approved/live store-card contract.
--
-- Live reconciliation on 2026-09-04 found that anon could read 101 rows and
-- private/operational columns directly from public.partners. Two of those rows
-- were outside the intended approved/live + swipe-eligible + non-test gate.
--
-- Preconditions before any separately approved apply:
--   * Inventory Wix, Make, website, and other consumers of the three legacy
--     public views and public.partners; migrate or explicitly exempt them.
--   * Verify the live column types and exact policy names below.
--   * Preserve owner/internal read and owner self-service INSERT/UPDATE proofs.
--   * Run the reviewer checks documented in README.md against staging first.

begin;

-- SECURITY DEFINER is intentional here because browser roles must not retain
-- SELECT on the wide base table. Risk is bounded by zero arguments, a fixed
-- return schema, an empty search_path, fully-qualified sources, fixed predicates,
-- and no dynamic SQL.
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

-- Retire every browser-readable wide path. The service role and object owner are
-- intentionally untouched.
revoke all on table
  public.public_swipe_partners,
  public.public_partner_directory,
  public.public_local_partners
  from public, anon, authenticated;
revoke all on table public.partners
  from public, anon, authenticated;

-- Authenticated owner/internal flows retain only the operations they need. RLS
-- and the live owner self-service guard continue to constrain row access/writes.
grant select, insert, update on table public.partners
  to authenticated;

drop policy if exists "Anyone can view approved partners"
  on public.partners;
drop policy if exists "Saved partners visible to saver"
  on public.partners;
alter policy "Owners can view own partner"
  on public.partners
  to authenticated
  using ((select auth.uid()) = owner_id);

comment on function public.list_public_swipe_partner_cards() is
  'Store-review partner cards: zero-argument, fixed 13-field approved/live projection. SECURITY DEFINER is required because browser roles have no direct access to the wide partner table.';

commit;
