// Fail-closed migration negative controls. No changes survive a failed session.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
const url = process.env.DATABASE_URL;
assert.ok(url && new URL(url).hostname === "127.0.0.1" && new URL(url).port === "54322", "Disposable local database required");
const migration = readFileSync("supabase/migrations/20260916120000_partner_media_shared_boundary.sql", "utf8");
const args = ["-X", url, "-v", "ON_ERROR_STOP=1", "-qAt"];
for (const [label, setup, expected] of [
  ["disabled guard", "ALTER TABLE public.partner_media_requests DISABLE TRIGGER partner_media_request_guard;", /Unexpected media boundary/],
  ["public pending bucket", "UPDATE storage.buckets SET public=true WHERE id='partner-media-pending';", /Unexpected media boundary/],
  ["existing duplicate path", `INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path) SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','synthetic/preflight-duplicate.jpg' FROM generate_series(1,2);`, /Existing active media conflicts/],
  ["existing seventh gallery", `INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path) SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','synthetic/preflight-'||n||'.jpg' FROM generate_series(1,7) n;`, /Existing active media conflicts/],
]) {
  const result = spawnSync("psql", args, { input: `BEGIN;\n${setup}\n${migration}`, encoding: "utf8" });
  assert.notEqual(result.status, 0, `${label} unexpectedly applied`);
  assert.match(result.stderr, expected);
  const check = spawnSync("psql", args, { input: "SELECT to_regclass('app_private.partner_media_serialization') IS NULL AND to_regclass('public.partner_media_active_storage_path_uq') IS NULL;", encoding: "utf8" });
  assert.equal(check.status, 0, check.stderr);
  assert.equal(check.stdout.trim(), "t", "failed migration left partial objects");
  console.log(`${label}: rejected atomically`);
}
