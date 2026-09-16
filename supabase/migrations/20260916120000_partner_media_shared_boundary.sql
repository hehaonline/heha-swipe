-- Review-only forward repair. No hosted application is authorized by this file.
-- Active means an add/replace upload still submitted, needing info, or approved.
-- Applied/rejected/cancelled history and removal requests do not reserve upload slots.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
SET LOCAL lock_timeout = '2s';

-- Hold writers out while checking historical definitions and existing active rows.
LOCK TABLE public.partner_media_requests IN ACCESS EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid='app_private.guard_partner_media_request()'::regprocedure
      AND prosecdef AND provolatile='v'
      AND proconfig=ARRAY['search_path=pg_catalog, public, app_private, auth, pg_temp']
      AND md5(prosrc)='ff6a09e7cd7be3aa64544af7e79724e7'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid='public.submit_assisted_partner_media(uuid,uuid,text,text,text,text,bigint,text,text)'::regprocedure
      AND prosecdef AND provolatile='v'
      AND proconfig=ARRAY['search_path=pg_catalog, public, app_private, auth, storage, pg_temp']
      AND md5(prosrc)='f2c9bd89a3ee047d9d33ba8add506503'
  ) OR (SELECT count(*) FROM pg_trigger
    WHERE tgrelid='public.partner_media_requests'::regclass AND NOT tgisinternal) <> 1
    OR NOT EXISTS (SELECT 1 FROM pg_trigger
      WHERE tgrelid='public.partner_media_requests'::regclass
        AND tgname='partner_media_request_guard' AND tgtype=23 AND tgenabled='O'
        AND tgqual IS NULL AND tgnargs=0 AND tgattr=''::int2vector
        AND tgfoid='app_private.guard_partner_media_request()'::regprocedure)
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.partner_media_requests'::regclass)
    OR NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='partner-media-pending' AND public=false)
  THEN
    RAISE EXCEPTION 'Unexpected media boundary or bucket drift; stop for independent review.';
  END IF;
  IF EXISTS (
    SELECT storage_path FROM public.partner_media_requests
    WHERE change_type IN ('add','replace') AND status IN ('submitted','needs_info','approved')
    GROUP BY storage_path HAVING count(*)>1
  ) OR EXISTS (
    SELECT partner_id,media_type FROM public.partner_media_requests
    WHERE change_type IN ('add','replace') AND status IN ('submitted','needs_info','approved')
    GROUP BY partner_id,media_type
    HAVING count(*) > CASE WHEN media_type='gallery' THEN 6 ELSE 1 END
  ) THEN
    RAISE EXCEPTION 'Existing active media conflicts require reviewed resolution; no rows were changed.';
  END IF;
END;
$guard$;

CREATE UNIQUE INDEX partner_media_active_storage_path_uq
ON public.partner_media_requests(storage_path)
WHERE change_type IN ('add','replace') AND status IN ('submitted','needs_info','approved');

CREATE UNIQUE INDEX partner_media_active_single_slot_uq
ON public.partner_media_requests(partner_id,media_type)
WHERE media_type IN ('logo','cover') AND change_type IN ('add','replace')
  AND status IN ('submitted','needs_info','approved');

-- A private row version supplements the shared partners row lock: READ COMMITTED
-- sees the next count, while REPEATABLE READ/SERIALIZABLE must retry on a stale
-- sentinel instead of admitting a seventh item. Never UPDATE public.partners.
CREATE TABLE app_private.partner_media_serialization (
  partner_id uuid PRIMARY KEY REFERENCES public.partners(id) ON DELETE CASCADE,
  revision bigint NOT NULL DEFAULT 0
);
ALTER TABLE app_private.partner_media_serialization ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_private.partner_media_serialization FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION app_private.enforce_partner_media_capacity()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $capacity$
BEGIN
  -- Review metadata, transitions within the active gallery, and releases retain
  -- their old semantics. Unique indexes still check all path and single-slot edits.
  IF NEW.change_type NOT IN ('add','replace')
    OR NEW.status NOT IN ('submitted','needs_info','approved') THEN
    RETURN NEW;
  END IF;
  IF TG_OP='UPDATE' THEN
    IF NEW.media_type <> 'gallery' OR (
      OLD.partner_id=NEW.partner_id AND OLD.media_type='gallery'
      AND OLD.change_type IN ('add','replace')
      AND OLD.status IN ('submitted','needs_info','approved')
    ) THEN RETURN NEW; END IF;
  END IF;

  -- Same lock order as assisted intake. This does not assign an owner or publish.
  PERFORM 1 FROM public.partners WHERE id=NEW.partner_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23503', MESSAGE='Existing media partner required.';
  END IF;
  INSERT INTO app_private.partner_media_serialization(partner_id)
  VALUES(NEW.partner_id)
  ON CONFLICT(partner_id) DO UPDATE
    SET revision=app_private.partner_media_serialization.revision+1;

  -- Deliberately a separate statement after serialization (fresh RC snapshot).
  IF NEW.media_type='gallery' AND (
    SELECT count(*) FROM public.partner_media_requests r
    WHERE r.partner_id=NEW.partner_id AND r.media_type='gallery'
      AND r.change_type IN ('add','replace')
      AND r.status IN ('submitted','needs_info','approved')
      AND r.id IS DISTINCT FROM CASE WHEN TG_OP='UPDATE' THEN OLD.id ELSE NULL END
  ) >= 6 THEN
    RAISE EXCEPTION USING ERRCODE='23514',
      MESSAGE='A maximum of six active gallery uploads is allowed while media is under review.';
  END IF;
  RETURN NEW;
END;
$capacity$;
REVOKE ALL ON FUNCTION app_private.enforce_partner_media_capacity() FROM PUBLIC,anon,authenticated,service_role;

-- Run after the retained authorization/status-normalization trigger for every
-- writer, including assisted SECURITY DEFINER and service/backend writes.
CREATE TRIGGER z_partner_media_capacity
BEFORE INSERT OR UPDATE ON public.partner_media_requests
FOR EACH ROW EXECUTE FUNCTION app_private.enforce_partner_media_capacity();

-- Preserve owner authorization, immutable-submission rules, and internal/backend
-- review handling byte-for-byte; only remove the superseded asymmetric quotas.
create or replace function app_private.guard_partner_media_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
    end if;
    return new;
  end if;

  if app_private.has_internal_role(array['super_admin', 'developer_admin', 'pm_admin']) then
    if tg_op = 'UPDATE' then
      new.updated_at := now();
      if new.status in ('approved', 'rejected', 'applied', 'needs_info') and new.reviewed_at is null then
        new.reviewed_at := now();
        new.reviewed_by := actor_id;
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from actor_id then
      raise exception using
        errcode = '42501',
        message = 'Partner media requests must belong to the signed-in owner.';
    end if;

    if not exists (
      select 1
      from public.partners p
      where p.id = new.partner_id
        and p.owner_id = actor_id
    ) then
      raise exception using
        errcode = '42501',
        message = 'Partner media requests may only target your own listing.';
    end if;

    if new.storage_path is not null
       and new.storage_path not like actor_id::text || '/' || new.partner_id::text || '/%' then
      raise exception using
        errcode = '42501',
        message = 'Partner media storage path does not match the signed-in owner and listing.';
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

  raise exception using
    errcode = '42501',
    message = 'Partner owners cannot directly modify media requests after submission.';
end;
$$;


CREATE OR REPLACE FUNCTION public.submit_assisted_partner_media(
  p_request_id uuid, p_partner_id uuid, p_storage_path text,
  p_media_type text, p_original_filename text, p_mime_type text,
  p_file_size_bytes bigint, p_source_reference text, p_rights_reference text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, app_private, auth, storage, pg_temp
AS $$
DECLARE
  actor uuid := auth.uid();
  existing public.partner_media_requests%ROWTYPE;
BEGIN
  IF actor IS NULL OR NOT app_private.has_internal_role(
    ARRAY['super_admin','developer_admin','pm_admin']
  ) OR app_private.verified_permanent_claim_email(actor) IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='Verified internal media intake access required.';
  END IF;
  IF p_request_id IS NULL OR p_partner_id IS NULL OR p_media_type IS NULL
    OR p_media_type NOT IN ('logo','cover','gallery')
    OR p_mime_type IS NULL OR p_mime_type NOT IN ('image/jpeg','image/png','image/webp')
    OR p_file_size_bytes IS NULL OR p_file_size_bytes NOT BETWEEN 1 AND 8388608
    OR p_original_filename IS NULL OR length(btrim(p_original_filename)) NOT BETWEEN 1 AND 255
    OR p_source_reference IS NULL OR length(btrim(p_source_reference)) NOT BETWEEN 1 AND 2000
    OR p_rights_reference IS NULL OR length(btrim(p_rights_reference)) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Image metadata and source/rights references are required.';
  END IF;
  IF p_storage_path IS NULL
    OR (storage.foldername(p_storage_path))[1] IS DISTINCT FROM actor::text
    OR (storage.foldername(p_storage_path))[2] IS DISTINCT FROM p_partner_id::text
    OR array_length(string_to_array(p_storage_path,'/'),1) <> 3
    OR split_part(p_storage_path,'/',3) IN ('','.','..')
    OR NOT EXISTS (SELECT 1 FROM storage.objects o
      JOIN storage.buckets b ON b.id=o.bucket_id
      WHERE o.bucket_id='partner-media-pending' AND b.public=false AND o.name=p_storage_path) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='A private image in this actor and listing path is required.';
  END IF;
  -- Serializes the review queue for this listing; does not assign its owner.
  PERFORM 1 FROM public.partners WHERE id=p_partner_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Existing listing required.';
  END IF;
  SELECT * INTO existing FROM public.partner_media_requests WHERE id=p_request_id;
  IF FOUND THEN
    IF existing.partner_id=p_partner_id AND existing.owner_id=actor
      AND existing.storage_path=p_storage_path AND existing.media_type=p_media_type
      AND existing.original_filename=p_original_filename AND existing.mime_type=p_mime_type
      AND existing.file_size_bytes=p_file_size_bytes
      AND EXISTS (SELECT 1 FROM public.partner_media_intake_evidence e
        WHERE e.request_id=p_request_id AND e.submitted_by=actor
          AND e.source_reference=btrim(p_source_reference)
          AND e.rights_reference=btrim(p_rights_reference)) THEN
      RETURN existing.id;
    END IF;
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Request identifier is already used for different input.';
  END IF;
  INSERT INTO public.partner_media_requests (
    id, partner_id, owner_id, media_type, change_type, storage_path,
    original_filename, mime_type, file_size_bytes, status
  ) VALUES (
    p_request_id, p_partner_id, actor, p_media_type, 'add', p_storage_path,
    p_original_filename, p_mime_type, p_file_size_bytes, 'submitted'
  );
  INSERT INTO public.partner_media_intake_evidence
    (request_id,submitted_by,source_reference,rights_reference)
  VALUES (p_request_id,actor,btrim(p_source_reference),btrim(p_rights_reference));
  RETURN p_request_id;
END;
$$;

-- Keep existing function ACLs: CREATE OR REPLACE never widens intake authority.
-- Source/rights evidence, verified staff checks and exact request-id retries remain.
COMMIT;
