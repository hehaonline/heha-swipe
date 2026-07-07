-- Partner security foundation.
--
-- Goals:
-- 1. Keep final public partner publishing approval with service_role and super_admin only.
-- 2. Remove pm_admin from public.approve_partner(uuid)'s in-function authorization gate.
-- 3. Disable public/frontend execution of the legacy public.record_swipe(uuid,text,text) RPC.
--
-- Safety:
-- * public.approve_partner(uuid) keeps SECURITY DEFINER with search_path pinned to ''.
-- * authenticated retains EXECUTE on approve_partner so authenticated super_admin users can call it.
-- * No partner data is modified by this migration.
-- * Partner UPDATE RLS, HEHA Certified/heha_partner logic, and publication data are unchanged.

create or replace function public.approve_partner(p_partner_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $function$
declare
  v_jwt_role text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
begin
  if v_jwt_role = 'service_role'
     or app_private.has_internal_role(array['super_admin']) then
    update public.partners
    set status = 'live',
        updated_at = pg_catalog.now()
    where id = p_partner_id;
  else
    raise exception 'Not authorized to approve partners'
      using errcode = '42501';
  end if;
end;
$function$;

revoke execute on function public.approve_partner(uuid) from public;
revoke execute on function public.approve_partner(uuid) from anon;
grant execute on function public.approve_partner(uuid) to authenticated;
grant execute on function public.approve_partner(uuid) to service_role;

do $migration$
begin
  if pg_catalog.to_regprocedure('public.record_swipe(uuid,text,text)') is not null then
    execute 'revoke execute on function public.record_swipe(uuid, text, text) from public';
    execute 'revoke execute on function public.record_swipe(uuid, text, text) from anon';
    execute 'revoke execute on function public.record_swipe(uuid, text, text) from authenticated';
    execute 'grant execute on function public.record_swipe(uuid, text, text) to service_role';
  else
    raise notice 'public.record_swipe(uuid,text,text) not present; skipping legacy RPC grant hardening';
  end if;
end;
$migration$;
