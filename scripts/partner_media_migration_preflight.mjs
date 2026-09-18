// Fail-closed migration negative controls. No changes survive a failed session.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createDisposableMediaPsql } from "./disposable_media_target.mjs";
const database = createDisposableMediaPsql(process.env.DATABASE_URL);
const migration = readFileSync("supabase/migrations/20260916120000_partner_media_shared_boundary.sql", "utf8");
const policyError = /Unexpected media policy definition or set drift/;
const additionalPolicyError = /Unreviewed additional Storage policy may affect pending media/;
const snapshotSQL = `SELECT jsonb_build_object(
  'serialization',to_regclass('app_private.partner_media_serialization')::text,
  'path_index',to_regclass('public.partner_media_active_storage_path_uq')::text,
  'slot_index',to_regclass('public.partner_media_active_single_slot_uq')::text,
  'capacity',to_regprocedure('app_private.enforce_partner_media_capacity()')::text,
  'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname)
    FROM pg_policies p WHERE (schemaname,tablename) IN
      (('storage','objects'),('public','partner_media_requests'),('public','partner_media_intake_evidence'))),
  'triggers',(SELECT jsonb_agg(jsonb_build_array(tgname,tgenabled,pg_get_triggerdef(oid)) ORDER BY tgname)
    FROM pg_trigger WHERE tgrelid='public.partner_media_requests'::regclass AND NOT tgisinternal),
  'requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM public.partner_media_requests r),
  'evidence',(SELECT jsonb_agg(to_jsonb(e) ORDER BY request_id) FROM public.partner_media_intake_evidence e),
  'partners',(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.partners p),
  'buckets',(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM storage.buckets b)
)::text;`;
const baseline = database.sql(snapshotSQL);
let negativeCount = 0;
const boundaryError = /Unexpected media function\/table\/helper\/schema\/role\/ACL\/trigger\/policy\/bucket drift/;
for (const [label, setup, expected] of [
  ["unknown guard body", `CREATE OR REPLACE FUNCTION app_private.guard_partner_media_request()
    RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path=pg_catalog,public,app_private,auth,pg_temp AS $$ BEGIN RETURN NEW; END $$;`, boundaryError],
  ["guard security invoker", "ALTER FUNCTION app_private.guard_partner_media_request() SECURITY INVOKER;", boundaryError],
  ["guard function ACL widened", "GRANT EXECUTE ON FUNCTION app_private.guard_partner_media_request() TO authenticated;", boundaryError],
  ["assisted function ACL widened", `GRANT EXECUTE ON FUNCTION public.submit_assisted_partner_media(uuid,uuid,text,text,text,text,bigint,text,text) TO service_role;`, boundaryError],
  ["role helper body changed", `CREATE OR REPLACE FUNCTION app_private.has_internal_role(required_roles text[])
    RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path=pg_catalog,public,pg_temp AS $$ SELECT true $$;`, boundaryError],
  ["role helper ACL narrowed", "REVOKE EXECUTE ON FUNCTION app_private.has_internal_role(text[]) FROM authenticated;", boundaryError],
  ["claim email helper ACL widened", "GRANT EXECUTE ON FUNCTION app_private.verified_permanent_claim_email(uuid) TO authenticated;", boundaryError],
  ["private schema exposed", "GRANT USAGE ON SCHEMA app_private TO authenticated;", boundaryError],
  ["media table RLS disabled", "ALTER TABLE public.partner_media_requests DISABLE ROW LEVEL SECURITY;", boundaryError],
  ["media table ACL widened", "GRANT DELETE ON public.partner_media_requests TO authenticated;", boundaryError],
  ["intake evidence ACL widened", "GRANT INSERT ON public.partner_media_intake_evidence TO authenticated;", boundaryError],
  // Supabase rejects this reserved-role mutation before the migration. A native
  // PostgreSQL fixture permits the setup, so its own migration guard must reject.
  ["authenticated role bypass drift", "ALTER ROLE authenticated BYPASSRLS;",
    new RegExp(`reserved role, only superusers can modify it|${boundaryError.source}`)],
  ["disabled guard", "ALTER TABLE public.partner_media_requests DISABLE TRIGGER partner_media_request_guard;", boundaryError],
  ["extra media trigger", `CREATE TRIGGER a_partner_media_extra BEFORE INSERT ON public.partner_media_requests
    FOR EACH ROW EXECUTE FUNCTION app_private.guard_partner_media_request();`, boundaryError],
  ["owner storage policy widened", `ALTER POLICY "Owners can view own pending partner media"
    ON storage.objects USING (true);`, policyError],
  ["evidence policy unrestricted", `ALTER POLICY "Internal staff can read media intake evidence"
    ON public.partner_media_intake_evidence USING (true);`, policyError],
  ["additional evidence policy", `CREATE POLICY unexpected_evidence_read
    ON public.partner_media_intake_evidence FOR SELECT TO authenticated USING (true);`, policyError],
  ["owner storage predicate OR true", `DO $$ DECLARE original text; BEGIN
    SELECT qual INTO STRICT original FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
      AND policyname='Owners can view own pending partner media';
    EXECUTE format('ALTER POLICY %I ON storage.objects USING ((%s) OR true)',
      'Owners can view own pending partner media',original); END $$;`, policyError],
  ["additional unrestricted storage policy", `CREATE POLICY unexpected_storage_read
    ON storage.objects FOR SELECT TO authenticated USING (true);`, additionalPolicyError],
  ["additional public storage policy", `CREATE POLICY unexpected_public_storage_read
    ON storage.objects FOR SELECT TO PUBLIC USING (true);`, additionalPolicyError],
  ["staff storage USING widened", `ALTER POLICY "Internal users can manage pending partner media"
    ON storage.objects USING (true);`, policyError],
  ["staff storage WITH CHECK widened", `ALTER POLICY "Internal users can manage pending partner media"
    ON storage.objects WITH CHECK (true);`, policyError],
  ["owner storage WITH CHECK widened", `ALTER POLICY "Owners can upload own pending partner media"
    ON storage.objects WITH CHECK (true);`, policyError],
  ["evidence policy role changed", `ALTER POLICY "Internal staff can read media intake evidence"
    ON public.partner_media_intake_evidence TO PUBLIC;`, policyError],
  ["owner storage policy missing", `DROP POLICY "Owners can view own pending partner media" ON storage.objects;`, policyError],
  ["staff storage policy command changed", `DROP POLICY "Internal users can view pending partner media" ON storage.objects;
    CREATE POLICY "Internal users can view pending partner media" ON storage.objects FOR ALL TO authenticated
    USING (bucket_id='partner-media-pending' AND app_private.has_internal_role(ARRAY['super_admin','developer_admin','pm_admin']));`, policyError],
  ["evidence policy permissiveness changed", `DROP POLICY "Internal staff can read media intake evidence" ON public.partner_media_intake_evidence;
    CREATE POLICY "Internal staff can read media intake evidence" ON public.partner_media_intake_evidence
    AS RESTRICTIVE FOR SELECT TO authenticated USING (app_private.has_internal_role(ARRAY['super_admin','developer_admin','pm_admin']));`, policyError],
  ["other bucket OR true", `INSERT INTO storage.buckets(id,name,public) VALUES ('synthetic-other','synthetic-other',false);
    CREATE POLICY synthetic_other_bucket ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id='synthetic-other' OR true);`, additionalPolicyError],
  ["other bucket WITH CHECK widened", `INSERT INTO storage.buckets(id,name,public) VALUES ('synthetic-other','synthetic-other',false);
    CREATE POLICY synthetic_other_bucket ON storage.objects FOR ALL TO authenticated
    USING (bucket_id='synthetic-other') WITH CHECK (true);`, additionalPolicyError],
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
  assert.equal(database.sql(snapshotSQL), baseline, `${label} left policy or row changes`);
  negativeCount += 1;
  console.log(`${label}: rejected atomically`);
}

// These positive controls apply only in an outer transaction that is rolled back.
// The accepted definitions cannot match pending media, and must remain unchanged.
assert.equal((migration.match(/\nBEGIN;\n/g) || []).length, 1);
assert.equal((migration.match(/\nCOMMIT;/g) || []).length, 1);
const transactionalBody = migration.replace(/\nBEGIN;\n/, "\n").replace(/\nCOMMIT;/, "\n");
let positiveCount = 0;
for (const [label, policy] of [
  ["other bucket SELECT", "FOR SELECT TO authenticated USING (bucket_id='synthetic-other')"],
  ["other bucket INSERT", "FOR INSERT TO authenticated WITH CHECK (bucket_id='synthetic-other')"],
  ["other bucket ALL fallback", "FOR ALL TO authenticated USING (bucket_id='synthetic-other')"],
  ["additional restrictive policy", "AS RESTRICTIVE FOR SELECT TO authenticated USING (true)"],
]) {
  const result = database.result(`BEGIN;
    INSERT INTO storage.buckets(id,name,public) VALUES ('synthetic-other','synthetic-other',false);
    CREATE POLICY synthetic_other_bucket ON storage.objects ${policy};
    CREATE TEMP TABLE policy_before AS SELECT * FROM pg_policies WHERE schemaname='storage' AND tablename='objects';
    ${transactionalBody}
    DO $$ BEGIN
      IF to_regclass('app_private.partner_media_serialization') IS NULL
        OR to_regprocedure('app_private.enforce_partner_media_capacity()') IS NULL THEN
        RAISE EXCEPTION 'Expected migration objects missing'; END IF;
      IF EXISTS ((SELECT * FROM policy_before EXCEPT SELECT * FROM pg_policies WHERE schemaname='storage' AND tablename='objects')
        UNION ALL (SELECT * FROM pg_policies WHERE schemaname='storage' AND tablename='objects' EXCEPT SELECT * FROM policy_before)) THEN
        RAISE EXCEPTION 'Existing policies changed'; END IF;
    END $$;
    ROLLBACK;`);
  assert.equal(result.status, 0, `${label}: ${result.stderr}`);
  assert.equal(database.sql(snapshotSQL), baseline, `${label} did not roll back`);
  positiveCount += 1;
  console.log(`${label}: accepted unchanged and rolled back`);
}
// Observe real intake/migration overlap. Intake has already touched Storage,
// then must still reach the request queue while migration waits on Storage.
const children = new Set();
function session(name) {
  const child = database.session(); children.add(child);
  let output = "";
  child.stdout.on("data", data => { output += data; });
  child.stderr.on("data", data => { output += data; });
  const done = new Promise(resolve => child.on("close", code => {
    children.delete(child); resolve({code, output});
  }));
  child.stdin.write(`SET application_name='${name}'; BEGIN; SET LOCAL statement_timeout='10s';\n`);
  return {child, done, write: value => child.stdin.write(value + "\n")};
}
async function observed(predicate) {
  for (let attempt=0; attempt<100; attempt += 1) {
    if (database.sql(`SELECT (${predicate});`).trim() === "t") return;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  throw new Error("Expected native lock witness was not observed");
}
const intakeName = `policy_intake_${database.nonce}`;
const migrationName = `policy_migration_${database.nonce}`;
try {
  const intake = session(intakeName);
  const path = "12121212-1212-4212-8212-121212121212/78787878-7878-4787-8787-787878787878/policy-lock-proof.jpg";
  intake.write(`INSERT INTO storage.objects(bucket_id,name) VALUES ('partner-media-pending','${path}');
    SELECT 'storage_ready';`);
  await observed(`EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='${intakeName}'
    AND state='idle in transaction' AND query LIKE '%storage_ready%')`);
  const migrationSession = session(migrationName);
  migrationSession.write(transactionalBody + "ROLLBACK;"); migrationSession.child.stdin.end();
  await observed(`EXISTS(SELECT 1 FROM pg_locks l JOIN pg_stat_activity a USING(pid)
    WHERE a.application_name='${migrationName}' AND l.relation='storage.objects'::regclass
      AND l.mode='AccessExclusiveLock' AND NOT l.granted)`);
  assert.equal(database.sql(`SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid)
    WHERE a.application_name='${migrationName}' AND l.relation='public.partner_media_requests'::regclass
      AND l.mode='AccessExclusiveLock' AND l.granted;`).trim(), "0", "migration locked the queue before Storage");
  intake.write(`SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub','12121212-1212-4212-8212-121212121212',true),
      set_config('request.jwt.claims','{"sub":"12121212-1212-4212-8212-121212121212","role":"authenticated"}',true);
    SELECT public.submit_assisted_partner_media('62626262-6262-4262-8262-626262626262',
      '78787878-7878-4787-8787-787878787878','${path}','gallery','policy-lock-proof.jpg',
      'image/jpeg',64,'synthetic:policy-lock-source','synthetic:policy-lock-rights');
    ROLLBACK;`); intake.child.stdin.end();
  const outcomes = await Promise.all([intake.done, migrationSession.done]);
  for (const result of outcomes) {
    assert.equal(result.code, 0, result.output);
    assert.doesNotMatch(result.output, /40P01|deadlock detected/);
  }
  assert.equal(database.sql(snapshotSQL), baseline, "lock proof did not roll back");
  console.log("intake/migration overlap: observed Storage wait; intake completed; both rolled back");
} finally {
  for (const child of children) child.kill("SIGTERM");
}
console.log(`${negativeCount} atomic negatives and ${positiveCount} policy-preservation positives passed`);
