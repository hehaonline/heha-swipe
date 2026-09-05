import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(new URL("../../src/lib/accountDeletion.js", import.meta.url), "utf8");
const profileSource = await readFile(new URL("../../src/components/ProfileTab.jsx", import.meta.url), "utf8");
const reviewSql = await readFile(
  new URL("../../supabase/review_only/store_release/001_request_my_account_deletion.sql", import.meta.url),
  "utf8"
);

test("client invokes the authenticated no-argument deletion RPC", () => {
  assert.match(source, /request_my_account_deletion/);
  assert.match(source, /\.rpc\(ACCOUNT_DELETION_RPC\)/);
  assert.match(source, /validateAccountDeletionReceipt\(data\)/);
  assert.doesNotMatch(source, /status[^;\n]*\|\|\s*["']requested["']/);
  assert.doesNotMatch(source, /user_id\s*:/);
});

test("profile does not perform partial client-side deletes or overclaim completion", () => {
  const deletionHandler = profileSource.slice(
    profileSource.indexOf("const requestAccountDeletion"),
    profileSource.indexOf("  return (", profileSource.indexOf("const requestAccountDeletion"))
  );
  assert.doesNotMatch(deletionHandler, /\.from\(/);
  assert.doesNotMatch(deletionHandler, /\.delete\(/);
  assert.doesNotMatch(deletionHandler, /data was cleared/i);
  assert.match(source, /request was submitted/i);
});

test("review-only function derives identity from auth and returns a request receipt", () => {
  assert.match(reviewSql, /auth\.uid\(\)/);
  assert.match(reviewSql, /request_id uuid/);
  assert.match(reviewSql, /status text/);
  assert.match(reviewSql, /requested_at timestamptz/);
  assert.match(reviewSql, /security invoker/i);
  assert.match(reviewSql, /pg_advisory_xact_lock/i);
  assert.match(reviewSql, /create unique index[\s\S]*\(user_id\)/i);
  assert.match(reviewSql, /on conflict \(user_id\) do nothing/i);
  assert.match(reviewSql, /already_requested/);
  assert.match(reviewSql, /returning id, created_at/i);
  assert.doesNotMatch(reviewSql, /clock_timestamp\(\)/i);
  assert.doesNotMatch(reviewSql, /delete\s+from\s+auth\.users/i);
});

test("review-only packet narrows the private request queue by role and column", () => {
  assert.match(
    reviewSql,
    /revoke\s+all\s+on\s+table\s+public\.account_deletion_requests\s+from\s+public,\s*anon,\s*authenticated/i
  );
  assert.match(
    reviewSql,
    /grant\s+select\s*\(id,\s*user_id,\s*status,\s*created_at\)\s+on\s+table\s+public\.account_deletion_requests\s+to\s+authenticated/i
  );
  assert.match(
    reviewSql,
    /grant\s+insert\s*\(user_id,\s*email,\s*reason\)\s+on\s+table\s+public\.account_deletion_requests\s+to\s+authenticated/i
  );
  assert.match(
    reviewSql,
    /alter\s+policy\s+"Users can create own deletion request"[\s\S]*?to\s+authenticated[\s\S]*?with\s+check\s*\(\(select\s+auth\.uid\(\)\)\s*=\s*user_id\)/i
  );
  assert.match(
    reviewSql,
    /alter\s+policy\s+"Users can view own deletion request"[\s\S]*?to\s+authenticated[\s\S]*?using\s*\(\(select\s+auth\.uid\(\)\)\s*=\s*user_id\)/i
  );
  assert.doesNotMatch(
    reviewSql,
    /grant\s+(?:all|select\s*,\s*insert|update|delete|truncate)[^;]*on\s+table\s+public\.account_deletion_requests/i
  );
});
