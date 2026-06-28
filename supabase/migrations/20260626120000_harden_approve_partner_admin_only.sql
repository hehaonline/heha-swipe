-- Full hardening for public.approve_partner(uuid)
--
-- Context:
--   The original function was SECURITY DEFINER with a mutable search_path and no
--   authorization check, so ANY caller with EXECUTE could approve partner listings.
--   A minimal prod stop-gap already revoked EXECUTE from anon/PUBLIC. This migration
--   closes the remaining risk that any *authenticated* (non-admin) user could approve.
--
-- Authorized paths after this change:
--   * service_role  (backend / Edge Functions)
--   * active internal admin: super_admin or pm_admin (via app_private.has_internal_role)
--   Everyone else (incl. ordinary authenticated users and anon) is denied (SQLSTATE 42501).
--
-- Safety:
--   * search_path pinned to '' with every object fully schema-qualified.
--   * Function body is the only behavioral change; the UPDATE itself is unchanged.
--   * No partner data is modified by this migration.
--
-- NOTE: Not yet applied to production. Apply only after review + admin-path confirmation.

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
     or app_private.has_internal_role(array['super_admin', 'pm_admin']) then
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

-- Grant review (keep the minimal stop-gap; make this migration self-contained/idempotent):
--   * anon / PUBLIC: no EXECUTE.
--   * authenticated: retains EXECUTE so admins (who are authenticated) can call it;
--     the in-body gate denies non-admins (defense in depth).
--   * service_role: retains EXECUTE for backend approval.
revoke execute on function public.approve_partner(uuid) from public;
revoke execute on function public.approve_partner(uuid) from anon;
grant  execute on function public.approve_partner(uuid) to authenticated;
grant  execute on function public.approve_partner(uuid) to service_role;
