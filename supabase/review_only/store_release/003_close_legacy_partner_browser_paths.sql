-- REVIEW ONLY. DO NOT APPLY YET.
-- Phase B: close every legacy browser-readable partner path after all HEHA Local,
-- Wix, Make, website, and other external consumers have been inventoried and
-- cut over to bounded interfaces.
--
-- This file is intentionally blocked even after Phase A is approved. Applying it
-- before consumer certification can break HEHA Local and external integrations.

begin;

-- The service role and relation owner remain untouched. Every browser role loses
-- the three wide projections; public/anon lose the 56-column base-table path.
revoke all on table
  public.public_swipe_partners,
  public.public_partner_directory,
  public.public_local_partners
  from public, anon, authenticated;
revoke all on table public.partners
  from public, anon, authenticated;

-- Authenticated owner/internal flows retain only the operations they need. Live
-- RLS policies and the owner self-service guard must be proved in staging before
-- this regrant is approved for production.
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

commit;

-- Required proof after a separately approved staging apply:
--   * anon cannot select public.partners or any legacy view;
--   * authenticated cannot select any legacy view;
--   * both Phase-A RPCs return only their exact typed contracts and eligible IDs;
--   * anon/auth cannot DELETE, TRUNCATE, REFERENCES, or TRIGGER public.partners;
--   * an ordinary authenticated user cannot read another owner's private row;
--   * owner and internal-role SELECT/INSERT/UPDATE flows still pass;
--   * HEHA Local, Wix, Make, and website smoke tests use certified replacements.
