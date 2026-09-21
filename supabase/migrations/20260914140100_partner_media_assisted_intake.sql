-- Review-only forward repair: staff-assisted intake never claims or publishes a listing.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
SET LOCAL lock_timeout = '2s';

CREATE TABLE public.partner_media_intake_evidence (
  request_id uuid PRIMARY KEY REFERENCES public.partner_media_requests(id) ON DELETE CASCADE,
  submitted_by uuid NOT NULL REFERENCES auth.users(id),
  source_reference text NOT NULL CHECK (length(btrim(source_reference)) BETWEEN 1 AND 2000),
  rights_reference text NOT NULL CHECK (length(btrim(rights_reference)) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.partner_media_intake_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.partner_media_intake_evidence FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.partner_media_intake_evidence TO authenticated;
CREATE POLICY "Internal staff can read media intake evidence"
ON public.partner_media_intake_evidence FOR SELECT TO authenticated
USING (app_private.has_internal_role(ARRAY['super_admin','developer_admin','pm_admin']));

CREATE FUNCTION public.submit_assisted_partner_media(
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
  IF EXISTS (SELECT 1 FROM public.partner_media_requests
    WHERE storage_path=p_storage_path AND status <> 'cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='This image already has a media request.';
  END IF;
  IF (SELECT count(*) FROM public.partner_media_requests
      WHERE partner_id=p_partner_id AND media_type=p_media_type
        AND status IN ('submitted','needs_info','approved'))
      >= (CASE WHEN p_media_type='gallery' THEN 6 ELSE 1 END) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='An active media request already fills this slot.';
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
REVOKE ALL ON FUNCTION public.submit_assisted_partner_media(uuid,uuid,text,text,text,text,bigint,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_assisted_partner_media(uuid,uuid,text,text,text,text,bigint,text,text)
  TO authenticated;
COMMENT ON TABLE public.partner_media_intake_evidence IS
  'Private staff intake receipt, not ownership, publication approval or independent proof of image rights.';
COMMIT;
