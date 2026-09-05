import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
const sql = await readFile(
  new URL("../../supabase/review_only/store_release/005_fulfill_account_deletion.sql", import.meta.url),
  "utf8",
);
test("fulfillment stays trusted, de-identified, and idempotent", () => {
  assert.match(sql, /security definer[\s\S]*set search_path = ''/i);
  assert.match(sql, /revoke all on function[\s\S]*from public, anon, authenticated, service_role/i);
  assert.match(sql, /grant execute on function[\s\S]*to service_role/i);
  assert.match(sql, /account_deletion_fulfillment_receipts/);
  assert.match(sql, /where receipt\.request_id = p_request_id[\s\S]*true;/i);
  const tableDefinition = sql.slice(
    sql.indexOf("create table if not exists"),
    sql.indexOf(");", sql.indexOf("create table if not exists")),
  );
  assert.doesNotMatch(tableDefinition, /\b(?:email|reason|user_id)\b/i);
  assert.match(
    sql,
    /insert into public\.account_deletion_fulfillment_receipts \(\s*request_id,\s*requested_at,\s*completed_at,\s*deleted_counts\s*\)/i,
  );
});
test("fulfillment refuses retained business data before deleting personal rows", () => {
  const guard = sql.slice(
    sql.indexOf("-- Accounts with partner ownership"),
    sql.indexOf("delete from public.community_offer_redemptions"),
  );
  for (const relation of [
    "public.partners",
    "public.orders",
    "public.contributions",
    "public.supporter_payments",
    "public.supporter_subscriptions",
  ]) {
    assert.match(guard, new RegExp(relation.replace(".", "\\.")));
  }
  assert.match(guard, /retained commercial or partner records require case review/);
});
test("receipt is written before the irreversible Auth deletion", () => {
  const receipt = sql.indexOf("insert into public.account_deletion_fulfillment_receipts");
  const authDelete = sql.indexOf("delete from auth.users");
  assert.ok(receipt > 0);
  assert.ok(authDelete > receipt);
  assert.match(sql, /ON DELETE CASCADE/);
  assert.match(sql, /delete from auth\.users where id = target_user_id/i);
  assert.match(sql, /Auth identity was not deleted/);
});
test("browser roles cannot read completion receipts or invoke fulfillment", () => {
  assert.match(
    sql,
    /revoke all on table public\.account_deletion_fulfillment_receipts[\s\S]*from public, anon, authenticated, service_role/i,
  );
  assert.match(
    sql,
    /grant select on table public\.account_deletion_fulfillment_receipts[\s\S]*to service_role/i,
  );
  assert.doesNotMatch(
    sql,
    /grant (?:select|insert|update|delete|execute)[^;]*to (?:public|anon|authenticated)/i,
  );
});
