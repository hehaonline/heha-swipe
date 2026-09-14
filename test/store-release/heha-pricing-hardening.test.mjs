import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const reviewSql = await readFile(
  new URL("../../supabase/review_only/store_release/004_harden_heha_pricing_access.sql", import.meta.url),
  "utf8"
);

test("pricing hardening changes only view security mode and privileges", () => {
  assert.match(
    reviewSql,
    /alter\s+view\s+public\.heha_pricing\s+set\s*\(security_invoker\s*=\s*true\)/i
  );
  assert.match(
    reviewSql,
    /revoke\s+all\s+on\s+table\s+public\.heha_pricing\s+from\s+public,\s*anon,\s*authenticated,\s*service_role/i
  );
  assert.match(
    reviewSql,
    /grant\s+select\s+on\s+table\s+public\.heha_pricing\s+to\s+service_role/i
  );
  assert.doesNotMatch(reviewSql, /create\s+(?:or\s+replace\s+)?view/i);
  assert.doesNotMatch(reviewSql, /drop\s+view/i);
  assert.doesNotMatch(
    reviewSql,
    /\b(?:heha_fee|driver_pay_per_portion|min_order|max_order|freebird_fund_pct|heha_operations_pct|google_review_discount_pct|partner_launch_suggested)\b/i
  );
  assert.doesNotMatch(
    reviewSql,
    /grant\s+(?:all|insert|update|delete|truncate|references|trigger)[^;]*heha_pricing/i
  );
});

test("pricing packet remains review-only and externally gated", () => {
  assert.match(reviewSql, /REVIEW ONLY/i);
  assert.match(reviewSql, /Wix, Make, HEHA Local/i);
  assert.match(reviewSql, /pg_get_viewdef/i);
  assert.match(reviewSql, /security_definer_view advisor error disappears/i);
});
