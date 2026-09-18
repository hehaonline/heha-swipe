// Fail-closed migration negative controls. No changes survive a failed session.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createDisposableMediaPsql } from "./disposable_media_target.mjs";
const database = createDisposableMediaPsql(process.env.DATABASE_URL);
const migration = readFileSync("supabase/migrations/20260916120000_partner_media_shared_boundary.sql", "utf8");
const boundaryError = /Unexpected media function\/table\/helper\/schema\/role\/ACL\/trigger\/policy\/bucket drift/;
for (const [label, setup, expected] of [
  ["unknown guard body", `CREATE OR REPLACE FUNCTION app_private.guard_partner_media_request()
    RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path=pg_catalog,public,app_private,auth,pg_temp AS $$ BEGIN RETURN NEW; END $$;`, boundaryError],
  ["guard security invoker", "ALTER FUNCTION app_private.guard_partner_media_request() SECURITY INVOKER;", boundaryError],
  ["guard function ACL widened", "GRANT EXECUTE ON FUNCTION app_private.guard_partner_media_request() TO authenticated;", boundaryError],
  ["assisted function ACL widened", `GRANT EXECUTE ON FUNCTION public.submit_assisted_partner_media(uuid,uuid,text,text,text,text,bigint,text,text) TO service_role;`, boundaryError],
  ["role helper body changed", `CREATE OR REPLACE FUNCTION app_private.has_internal_role(text[])
    RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path=pg_catalog,public,pg_temp AS $$ SELECT true $$;`, boundaryError],
  ["role helper ACL narrowed", "REVOKE EXECUTE ON FUNCTION app_private.has_internal_role(text[]) FROM authenticated;", boundaryError],
  ["claim email helper ACL widened", "GRANT EXECUTE ON FUNCTION app_private.verified_permanent_claim_email(uuid) TO authenticated;", boundaryError],
  ["private schema exposed", "GRANT USAGE ON SCHEMA app_private TO authenticated;", boundaryError],
  ["media table RLS disabled", "ALTER TABLE public.partner_media_requests DISABLE ROW LEVEL SECURITY;", boundaryError],
  ["media table ACL widened", "GRANT DELETE ON public.partner_media_requests TO authenticated;", boundaryError],
  ["intake evidence ACL widened", "GRANT INSERT ON public.partner_media_intake_evidence TO authenticated;", boundaryError],
  ["authenticated role bypasses RLS", "ALTER ROLE authenticated BYPASSRLS;", boundaryError],
  ["disabled guard", "ALTER TABLE public.partner_media_requests DISABLE TRIGGER partner_media_request_guard;", boundaryError],
  ["extra media trigger", `CREATE TRIGGER a_partner_media_extra BEFORE INSERT ON public.partner_media_requests
    FOR EACH ROW EXECUTE FUNCTION app_private.guard_partner_media_request();`, boundaryError],
  ["owner storage policy widened", `ALTER POLICY "Owners can view own pending partner media"
    ON storage.objects USING (true);`, boundaryError],
  ["public pending bucket", "UPDATE storage.buckets SET public=true WHERE id='partner-media-pending';", boundaryError],
  ["oversized pending bucket", "UPDATE storage.buckets SET file_size_limit=16777216 WHERE id='partner-media-pending';", boundaryError],
  ["SVG pending bucket", `UPDATE storage.buckets SET allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp','image/svg+xml'] WHERE id='partner-media-pending';`, boundaryError],
  ["existing duplicate path", `INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path) SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','synthetic/preflight-duplicate.jpg' FROM generate_series(1,2);`, /Existing active media conflicts/],
  ["existing seventh gallery", `INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path) SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','synthetic/preflight-'||n||'.jpg' FROM generate_series(1,7) n;`, /Existing active media conflicts/],
]) {
  const result = database.result(`BEGIN;\n${setup}\n${migration}`);
  assert.notEqual(result.status, 0, `${label} unexpectedly applied`);
  assert.match(result.stderr, expected);
  const check = database.result(`SELECT
    to_regclass('app_private.partner_media_serialization') IS NULL
    AND to_regclass('public.partner_media_active_storage_path_uq') IS NULL
    AND to_regprocedure('app_private.enforce_partner_media_capacity()') IS NULL
    AND (SELECT count(*) FROM pg_trigger
      WHERE tgrelid='public.partner_media_requests'::regclass AND NOT tgisinternal)=1;`);
  assert.equal(check.status, 0, check.stderr);
  assert.equal(check.stdout.trim(), "t", "failed migration left partial objects");
  console.log(`${label}: rejected atomically`);
}
