-- Disposable proof fixture only. Never apply this file to a hosted project.
-- Exact pg_get_functiondef/prosrc captured read-only from HEHA Swipe on
-- 2026-09-17. It differs from the repository predecessor only in formatting.
CREATE OR REPLACE FUNCTION app_private.guard_partner_media_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app_private', 'auth', 'pg_temp'
AS $function$
declare
  actor_id uuid := auth.uid();
  active_gallery_count integer;
begin
  if actor_id is null then
    if tg_op = 'UPDATE' then new.updated_at := now(); end if;
    return new;
  end if;

  if app_private.has_internal_role(array['super_admin','developer_admin','pm_admin']) then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
      if new.status in ('approved','rejected','applied','needs_info') and new.reviewed_at is null then
        new.reviewed_at := now();
        new.reviewed_by := actor_id;
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      raise exception using errcode='42501', message='Partner media requests must belong to the signed-in owner.';
    end if;
    if not exists (select 1 from public.partners p where p.id=new.partner_id and p.owner_id=actor_id) then
      raise exception using errcode='42501', message='Partner media requests may only target your own listing.';
    end if;
    if new.storage_path is not null and new.storage_path not like actor_id::text || '/' || new.partner_id::text || '/%' then
      raise exception using errcode='42501', message='Partner media storage path does not match the signed-in owner and listing.';
    end if;
    if new.media_type='gallery' and new.change_type<>'remove' then
      select count(*) into active_gallery_count from public.partner_media_requests r
      where r.partner_id=new.partner_id and r.media_type='gallery' and r.status in ('submitted','needs_info','approved');
      if active_gallery_count >= 6 then
        raise exception using errcode='23514', message='A maximum of six active gallery uploads is allowed while media is under review.';
      end if;
    end if;
    if new.media_type in ('logo','cover') and new.change_type<>'remove' and exists (
      select 1 from public.partner_media_requests r
      where r.partner_id=new.partner_id and r.media_type=new.media_type and r.status in ('submitted','needs_info')
    ) then
      raise exception using errcode='23505', message='A logo or cover upload is already waiting for HEHA review.';
    end if;
    new.status := 'submitted';
    new.submitted_at := now();
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_note := null;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  raise exception using errcode='42501', message='Partner owners cannot directly modify media requests after submission.';
end;
$function$;

REVOKE ALL ON FUNCTION app_private.guard_partner_media_request()
  FROM PUBLIC, anon, authenticated, service_role;

DO $fixture_guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid='app_private.guard_partner_media_request()'::regprocedure
      AND md5(p.prosrc)='ee900bcda5fdabd3e5400358ed09158d'
      AND pg_get_userbyid(p.proowner)='postgres' AND l.lanname='plpgsql'
      AND p.prosecdef AND p.provolatile='v' AND NOT p.proisstrict
      AND NOT p.proleakproof AND p.proparallel='u' AND p.prokind='f'
      AND p.prorettype='trigger'::regtype
      AND p.proconfig=ARRAY['search_path=pg_catalog, public, app_private, auth, pg_temp']
      AND p.proacl::text='{postgres=X/postgres}'
  ) THEN
    RAISE EXCEPTION 'Hosted predecessor fixture does not reproduce the exact captured catalog state.';
  END IF;
END;
$fixture_guard$;
