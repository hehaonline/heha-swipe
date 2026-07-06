revoke all on public.public_partner_directory from anon, authenticated;
revoke all on public.public_swipe_partners from anon, authenticated;
revoke all on public.public_local_partners from anon, authenticated;

grant select on public.public_partner_directory to anon, authenticated;
grant select on public.public_swipe_partners to anon, authenticated;
grant select on public.public_local_partners to anon, authenticated;
