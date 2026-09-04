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
const directorySource = await readFile(
  new URL("../../src/components/embed/PartnerDirectoryEmbed.jsx", import.meta.url),
  "utf8"
);
const reviewSql = await readFile(
  new URL("../../supabase/review_only/store_release/002_public_partner_card_projection.sql", import.meta.url),
  "utf8"
);
const closureSql = await readFile(
  new URL("../../supabase/review_only/store_release/003_close_legacy_partner_browser_paths.sql", import.meta.url),
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

const expectedCardReturnColumns = [
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

const expectedDirectoryReturnColumns = [
  "id uuid",
  "name text",
  "category text",
  "business_type text",
  "tagline text",
  "bio text",
  "neighborhood text",
  "location text",
  "tags text[]",
  "offerings text[]",
  "image_url text",
  "photo_emoji text",
  "heha_pillar text",
  "primary_cta_destination text",
  "primary_cta_label text",
  "primary_cta_path text",
  "created_at timestamptz",
];

function returnColumnsFor(functionName) {
  const block = reviewSql.match(
    new RegExp(
      `function\\s+public\\.${functionName}\\(\\)[\\s\\S]*?returns\\s+table\\s*\\(([\\s\\S]*?)\\)\\s*language\\s+sql`,
      "i"
    )
  );
  assert.ok(block, `typed RETURNS TABLE block is required for ${functionName}`);
  return block[1]
    .split(",")
    .map((column) => column.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

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

test("Swipe client uses only the bounded zero-argument partner RPC", async () => {
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

test("directory embed uses the bounded zero-argument directory RPC", () => {
  assert.match(
    directorySource,
    /supabase\.rpc\(\s*"list_public_partner_directory"\s*\)/
  );
  assert.doesNotMatch(directorySource, /\.from\(\s*"public_partner_directory"/);
});

test("review-only RPCs have fixed schemas, paths, and eligibility gates", () => {
  assert.deepEqual(
    returnColumnsFor("list_public_swipe_partner_cards"),
    expectedCardReturnColumns
  );
  assert.deepEqual(
    returnColumnsFor("list_public_partner_directory"),
    expectedDirectoryReturnColumns
  );

  for (const functionName of [
    "list_public_swipe_partner_cards",
    "list_public_partner_directory",
  ]) {
    assert.match(
      reviewSql,
      new RegExp(
        `create\\s+or\\s+replace\\s+function\\s+public\\.${functionName}\\(\\)`,
        "i"
      )
    );
    assert.match(
      reviewSql,
      new RegExp(
        `revoke\\s+all\\s+on\\s+function\\s+public\\.${functionName}\\(\\)\\s+from\\s+public,\\s*anon,\\s*authenticated`,
        "i"
      )
    );
    assert.match(
      reviewSql,
      new RegExp(
        `grant\\s+execute\\s+on\\s+function\\s+public\\.${functionName}\\(\\)\\s+to\\s+anon,\\s*authenticated`,
        "i"
      )
    );
  }

  assert.equal(
    (reviewSql.match(/stable\s+security\s+definer/gi) || []).length,
    2
  );
  assert.equal((reviewSql.match(/set\s+search_path\s*=\s*''/gi) || []).length, 2);
  assert.equal(
    (reviewSql.match(/status\s*=\s*any\s*\(array\['approved'::text,\s*'live'::text\]\)/gi) || []).length,
    2
  );
  assert.match(reviewSql, /coalesce\(partner\.swipe_eligible,\s*false\)\s*=\s*true/i);
  assert.match(reviewSql, /coalesce\(partner\.website_eligible,\s*false\)\s*=\s*true/i);
  assert.equal(
    (reviewSql.match(/coalesce\(partner\.is_test_record,\s*false\)\s*=\s*false/gi) || []).length,
    2
  );
  assert.doesNotMatch(reviewSql, /select\s+\*/i);
  assert.doesNotMatch(reviewSql, /\bformat\s*\(/i);
  assert.doesNotMatch(
    reviewSql,
    /\b(owner_id|contact|phone|routing_notes|service_fee|pricing_notes|contribution|total_)\b/i
  );
});

test("Phase A does not prematurely revoke legacy or base-table access", () => {
  assert.doesNotMatch(reviewSql, /revoke\s+all\s+on\s+table\s+public\.partners/i);
  assert.doesNotMatch(reviewSql, /drop\s+policy/i);
});

test("Phase B packet closes every wide browser path but stays explicitly blocked", () => {
  assert.match(closureSql, /REVIEW ONLY\. DO NOT APPLY YET/i);
  for (const relation of [
    "public_swipe_partners",
    "public_partner_directory",
    "public_local_partners",
  ]) {
    assert.match(
      closureSql,
      new RegExp(`revoke\\s+all[\\s\\S]*public\\.${relation}[\\s\\S]*from\\s+public,\\s*anon,\\s*authenticated`, "i")
    );
  }
  assert.match(
    closureSql,
    /revoke\s+all\s+on\s+table\s+public\.partners\s+from\s+public,\s*anon,\s*authenticated/i
  );
  assert.match(
    closureSql,
    /grant\s+select,\s*insert,\s*update\s+on\s+table\s+public\.partners\s+to\s+authenticated/i
  );
  assert.doesNotMatch(
    closureSql,
    /grant\s+(?:all|delete|truncate|references|trigger)[^;]*on\s+table\s+public\.partners/i
  );
  assert.match(closureSql, /drop\s+policy\s+if\s+exists\s+"Anyone can view approved partners"/i);
  assert.match(closureSql, /drop\s+policy\s+if\s+exists\s+"Saved partners visible to saver"/i);
  assert.match(
    closureSql,
    /alter\s+policy\s+"Owners can view own partner"[\s\S]*?to\s+authenticated[\s\S]*?using\s*\(\(select\s+auth\.uid\(\)\)\s*=\s*owner_id\)/i
  );
});
