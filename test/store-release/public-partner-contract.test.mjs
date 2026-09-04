import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  PUBLIC_PARTNER_FIELDS,
  PUBLIC_PARTNER_RPC,
  PUBLIC_PARTNER_SELECT,
  fetchPublicPartners,
  toPublicPartner,
} from "../../src/lib/publicPartner.js";

const source = await readFile(new URL("../../src/lib/publicPartner.js", import.meta.url), "utf8");
const reviewSql = await readFile(
  new URL("../../supabase/review_only/store_release/002_public_partner_card_projection.sql", import.meta.url),
  "utf8"
);

const expectedFields = [
  "id",
  "name",
  "category",
  "categories",
  "tagline",
  "bio",
  "neighborhood",
  "tags",
  "offerings",
  "image_url",
  "photo_emoji",
  "heha_partner",
  "created_at",
];

const expectedReturnColumns = [
  "id uuid",
  "name text",
  "category text",
  "categories text[]",
  "tagline text",
  "bio text",
  "neighborhood text",
  "tags text[]",
  "offerings text[]",
  "image_url text",
  "photo_emoji text",
  "heha_partner boolean",
  "created_at timestamptz",
];

test("public partner contract is exactly the reviewed 13 fields", () => {
  assert.deepEqual(PUBLIC_PARTNER_FIELDS, expectedFields);
  assert.equal(PUBLIC_PARTNER_FIELDS.length, 13);
  assert.equal(PUBLIC_PARTNER_SELECT, expectedFields.join(","));
  assert.equal(PUBLIC_PARTNER_RPC, "list_public_swipe_partner_cards");
});

test("public partner sanitizer cannot leak private or internal columns", () => {
  const result = toPublicPartner({
    id: "partner-1",
    name: "Example",
    owner_id: "private-owner",
    phone: "private-phone",
    contact: "private-contact",
    routing_notes: "private-notes",
  });
  assert.deepEqual(Object.keys(result), expectedFields);
  assert.equal(result.id, "partner-1");
  assert.equal("owner_id" in result, false);
  assert.equal("phone" in result, false);
  assert.equal("routing_notes" in result, false);
});

test("client uses only the bounded zero-argument partner RPC", async () => {
  const calls = [];
  const client = {
    rpc: async (...args) => {
      calls.push(args);
      return {
        data: [{ id: "partner-1", name: "Example", owner_id: "private-owner" }],
        error: null,
      };
    },
  };

  const result = await fetchPublicPartners(client);
  assert.deepEqual(calls, [[PUBLIC_PARTNER_RPC]]);
  assert.deepEqual(Object.keys(result[0]), expectedFields);
  assert.equal("owner_id" in result[0], false);
  assert.doesNotMatch(source, /\.from\s*\(/);
});

test("review-only RPC has a fixed schema, search path, and eligibility gate", () => {
  assert.match(
    reviewSql,
    /create\s+or\s+replace\s+function\s+public\.list_public_swipe_partner_cards\(\)/i
  );
  const returnBlock = reviewSql.match(/returns\s+table\s*\(([\s\S]*?)\)\s*language\s+sql/i);
  assert.ok(returnBlock, "typed RETURNS TABLE block is required");
  const actualReturnColumns = returnBlock[1]
    .split(",")
    .map((column) => column.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  assert.deepEqual(actualReturnColumns, expectedReturnColumns);
  assert.match(reviewSql, /stable\s+security\s+definer/i);
  assert.match(reviewSql, /set\s+search_path\s*=\s*''/i);
  assert.match(reviewSql, /status\s*=\s*any\s*\(array\['approved'::text,\s*'live'::text\]\)/i);
  assert.match(reviewSql, /coalesce\(partner\.swipe_eligible,\s*false\)\s*=\s*true/i);
  assert.match(reviewSql, /coalesce\(partner\.is_test_record,\s*false\)\s*=\s*false/i);
  assert.doesNotMatch(reviewSql, /select\s+\*/i);
  assert.doesNotMatch(reviewSql, /\bformat\s*\(/i);
});

test("review-only packet closes every wide browser read path", () => {
  for (const relation of [
    "public_swipe_partners",
    "public_partner_directory",
    "public_local_partners",
  ]) {
    assert.match(
      reviewSql,
      new RegExp(`revoke\\s+all[\\s\\S]*public\\.${relation}[\\s\\S]*from\\s+public,\\s*anon,\\s*authenticated`, "i")
    );
  }
  assert.match(
    reviewSql,
    /revoke\s+all\s+on\s+table\s+public\.partners\s+from\s+public,\s*anon,\s*authenticated/i
  );
  assert.match(
    reviewSql,
    /grant\s+select,\s*insert,\s*update\s+on\s+table\s+public\.partners\s+to\s+authenticated/i
  );
  assert.doesNotMatch(
    reviewSql,
    /grant\s+(?:all|delete|truncate|references|trigger)[^;]*on\s+table\s+public\.partners/i
  );
  assert.match(reviewSql, /drop\s+policy\s+if\s+exists\s+"Anyone can view approved partners"/i);
  assert.match(reviewSql, /drop\s+policy\s+if\s+exists\s+"Saved partners visible to saver"/i);
  assert.match(
    reviewSql,
    /alter\s+policy\s+"Owners can view own partner"[\s\S]*?to\s+authenticated[\s\S]*?using\s*\(\(select\s+auth\.uid\(\)\)\s*=\s*owner_id\)/i
  );
  assert.match(
    reviewSql,
    /revoke\s+all\s+on\s+function\s+public\.list_public_swipe_partner_cards\(\)\s+from\s+public,\s*anon,\s*authenticated/i
  );
  assert.match(
    reviewSql,
    /grant\s+execute\s+on\s+function\s+public\.list_public_swipe_partner_cards\(\)\s+to\s+anon,\s*authenticated/i
  );
});
