alter table public.partners
  add column if not exists is_test_record boolean not null default false;

create or replace view public.public_partner_directory
with (security_invoker = true)
as
select * from public.partners
where status = any (array['approved','live'])
  and coalesce(website_eligible, false) = true
  and is_test_record = false;

create or replace view public.public_swipe_partners
with (security_invoker = true)
as
select * from public.partners
where status = any (array['approved','live'])
  and coalesce(swipe_eligible, false) = true
  and is_test_record = false;

create or replace view public.public_local_partners
with (security_invoker = true)
as
select * from public.partners
where status = any (array['approved','live'])
  and coalesce(local_eligible, false) = true
  and local_lane is not null
  and is_test_record = false;

revoke all on public.public_partner_directory from anon, authenticated;
revoke all on public.public_swipe_partners from anon, authenticated;
revoke all on public.public_local_partners from anon, authenticated;

grant select on public.public_partner_directory to anon, authenticated;
grant select on public.public_swipe_partners to anon, authenticated;
grant select on public.public_local_partners to anon, authenticated;

comment on column public.partners.is_test_record is
  'Explicit QA/test data boundary. Test partner records never appear in public partner routing views.';
