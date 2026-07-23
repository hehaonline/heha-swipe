-- P0 security reconciliation: harden legacy/internal HEHA pricing constants view.
--
-- Live review on 2026-07-08 found public.heha_pricing readable by anon and
-- authenticated roles and flagged as a SECURITY DEFINER view. The active HEHA
-- Swipe and HEHA Local codebases do not reference this view by name.
--
-- This migration intentionally preserves the view and its current columns for
-- backend compatibility while removing public app access. It must remain
-- review-gated until Shahid verifies no legacy Make/Wix/other external client
-- depends on anon/authenticated SELECT access.

begin;

create or replace view public.heha_pricing
with (security_invoker = true)
as
select
  3.90::numeric as heha_fee,
  1.75::numeric as driver_pay_per_portion,
  17.50::numeric as min_order,
  60.00::numeric as max_order,
  0.20::numeric as freebird_fund_pct,
  0.80::numeric as heha_operations_pct,
  5.00::numeric as google_review_discount_pct,
  39.00::numeric as partner_launch_suggested;

revoke all on public.heha_pricing from public;
revoke all on public.heha_pricing from anon;
revoke all on public.heha_pricing from authenticated;
grant select on public.heha_pricing to service_role;

commit;
