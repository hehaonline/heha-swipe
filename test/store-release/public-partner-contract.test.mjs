import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  STORE_PUBLIC_PARTNER_FIELDS,
  STORE_PUBLIC_PARTNER_RPC,
  WEB_PUBLIC_ITEM_FIELDS,
  WEB_PUBLIC_PARTNER_FIELDS,
  WEB_PUBLIC_PARTNER_RPC,
  fetchPublicPartners,
  toPublicPartner,
} from "../../src/lib/publicPartner.js";
import {
  hasSpecificHehaLocalDestination,
  hehaLocalProfilePath,
  isHehaLocalPartner,
  partnerOrderLabel,
} from "../../src/lib/hehaLocalRouting.js";

const source = await readFile(new URL("../../src/lib/publicPartner.js", import.meta.url), "utf8");
const directorySource = await readFile(
  new URL("../../src/components/embed/PartnerDirectoryEmbed.jsx", import.meta.url),
  "utf8"
);
const appSource = await readFile(new URL("../../src/App.jsx", import.meta.url), "utf8");
const reviewSql = await readFile(
  new URL("../../supabase/review_only/store_release/002_public_partner_card_projection.sql", import.meta.url),
  "utf8"
);
const closureSql = await readFile(
  new URL("../../supabase/review_only/store_release/003_close_legacy_partner_browser_paths.sql", import.meta.url),
  "utf8"
);

const expectedStoreFields = [
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

const expectedWebOnlyFields = [
  "location",
  "color",
  "items",
  "gallery_urls",
  "website",
  "instagram",
  "price_range",
  "local_eligible",
  "local_lane",
  "primary_cta_destination",
  "primary_cta_path",
];

const expectedWebFields = [...expectedStoreFields, ...expectedWebOnlyFields];
const expectedItemFields = [
  "name",
  "emoji",
  "url",
  "product_url",
  "link",
  "local_product_id",
  "product_id",
];
const expectedItemUrlFields = ["url", "product_url", "link"];

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

const expectedWebCardReturnColumns = [
  ...expectedCardReturnColumns,
  "location text",
  "color text",
  "items jsonb",
  "gallery_urls jsonb",
  "website text",
  "instagram text",
  "price_range text",
  "local_eligible boolean",
  "local_lane text",
  "primary_cta_destination text",
  "primary_cta_path text",
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

test("public partner contracts are explicit and channel-specific", () => {
  assert.deepEqual(STORE_PUBLIC_PARTNER_FIELDS, expectedStoreFields);
  assert.equal(STORE_PUBLIC_PARTNER_FIELDS.length, 13);
  assert.equal(STORE_PUBLIC_PARTNER_RPC, "list_public_swipe_partner_cards");
  assert.deepEqual(WEB_PUBLIC_PARTNER_FIELDS, expectedWebFields);
  assert.equal(WEB_PUBLIC_PARTNER_FIELDS.length, 24);
  assert.equal(WEB_PUBLIC_PARTNER_RPC, "list_public_swipe_partner_details");
  assert.deepEqual(WEB_PUBLIC_ITEM_FIELDS, expectedItemFields);
});

test("store partner sanitizer cannot leak web, private, or operational columns", () => {
  const result = toPublicPartner({
    id: "partner-1",
    name: "Example",
    items: [{ name: "Web-only item" }],
    gallery_urls: ["https://cdn.example/gallery.jpg"],
    website: "https://partner.example",
    local_eligible: true,
    owner_id: "private-owner",
    phone: "private-phone",
    contact: "private-contact",
    routing_notes: "private-notes",
    total_saves: 123,
  }, { channel: "store" });
  assert.deepEqual(Object.keys(result), expectedStoreFields);
  assert.equal(result.id, "partner-1");
  for (const field of [...expectedWebOnlyFields, "owner_id", "phone", "contact", "routing_notes", "total_saves"]) {
    assert.equal(field in result, false, field);
  }
});

test("web sanitizer preserves display and routing behavior without leaking private data", () => {
  const inheritedItem = Object.assign(
    Object.create({ name: "prototype-secret", url: "https://private.example" }),
    { emoji: "✦" },
  );
  const result = toPublicPartner({
    id: "partner-1",
    name: "Example",
    location: "St. Petersburg",
    color: "#123456",
    gallery_urls: ["https://cdn.example/one.jpg", { private_url: "secret" }, ""],
    items: [
      {
        name: "Harvest Bowl",
        emoji: "🥗",
        url: "https://hehalocal.app/items/harvest-bowl",
        product_url: "http://partner.example/harvest-bowl",
        link: "javascript:alert('unsafe')",
        local_product_id: "local-1",
        internal_cost: 4.2,
        supplier_phone: "private-phone",
        routing_notes: "private-notes",
      },
      { owner_id: "private-owner", internal_cost: 7 },
      inheritedItem,
      "not-an-object",
    ],
    website: "https://partner.example",
    instagram: "partner.handle",
    price_range: "$$",
    local_eligible: true,
    local_lane: "meals",
    primary_cta_destination: "local",
    primary_cta_path: "/restaurants/partner-1",
    owner_id: "private-owner",
    phone: "private-phone",
    contact: "private-contact",
    routing_notes: "private-notes",
    pricing_notes: "private-pricing",
    service_fee_amount: 3,
    total_saves: 123,
  }, { channel: "web" });

  assert.deepEqual(Object.keys(result), expectedWebFields);
  assert.deepEqual(result.gallery_urls, ["https://cdn.example/one.jpg"]);
  assert.deepEqual(result.items, [
    {
      name: "Harvest Bowl",
      emoji: "🥗",
      url: "https://hehalocal.app/items/harvest-bowl",
      product_url: "http://partner.example/harvest-bowl",
      local_product_id: "local-1",
    },
    { emoji: "✦" },
  ]);
  assert.equal(result.location, "St. Petersburg");
  assert.equal(result.color, "#123456");
  assert.equal(result.website, "https://partner.example");
  assert.equal(result.instagram, "partner.handle");
  assert.equal(result.price_range, "$$");
  assert.equal(result.local_eligible, true);
  assert.equal(result.local_lane, "meals");
  assert.equal(result.primary_cta_destination, "local");
  assert.equal(result.primary_cta_path, "/restaurants/partner-1");
  assert.equal(isHehaLocalPartner(result), true);
  assert.equal(hehaLocalProfilePath(result), "/restaurants/partner-1");
  assert.equal(partnerOrderLabel(result, result.items[0]), "Open item in HEHA Local");
  for (const field of ["owner_id", "phone", "contact", "routing_notes", "pricing_notes", "service_fee_amount", "total_saves"]) {
    assert.equal(field in result, false, field);
  }
});

test("web item links preserve only absolute HTTP(S) URLs", () => {
  const invalidUrls = [
    "javascript:alert(1)",
    "java\nscript:alert(1)",
    "data:text/html,unsafe",
    "//partner.example/item",
    "https://user:password@partner.example/item",
    "https://partner.example/has space",
    "not-a-url",
    123,
  ];

  for (const value of invalidUrls) {
    const [item] = toPublicPartner({
      items: [{ name: "Safe label", url: value, product_url: value, link: value }],
    }, { channel: "web" }).items;
    assert.deepEqual(item, { name: "Safe label" }, String(value));
  }

  const result = toPublicPartner({
    items: [{
      name: "Safe links",
      url: "https://partner.example/item?ref=heha",
      product_url: "http://partner.example:8080/product/1",
      link: "HTTPS://PARTNER.EXAMPLE/path#details",
    }],
  }, { channel: "web" });
  assert.deepEqual(result.items[0], {
    name: "Safe links",
    url: "https://partner.example/item?ref=heha",
    product_url: "http://partner.example:8080/product/1",
    link: "HTTPS://PARTNER.EXAMPLE/path#details",
  });
});

test("canonical HEHA Local lane roots never masquerade as partner destinations", () => {
  const genericRoots = ["/restaurants", "/market", "/vendors", "/chef", "/group-orders"];
  const genericPaths = [
    "",
    "/",
    "?ref=heha",
    "?partner=11111111-1111-4111-8111-111111111111",
    "#top",
    "/?ref=heha",
    "/#top",
    ...genericRoots.flatMap((root) => [
      root,
      `${root}/`,
      `${root}?ref=heha`,
      `${root}#top`,
      `${root}/.?ref=heha`,
      `${root}/child/..?ref=heha`,
    ]),
  ];

  for (const path of genericPaths) {
    const partner = {
      id: "unmapped-partner",
      local_eligible: true,
      primary_cta_destination: "local",
      primary_cta_path: path,
    };
    assert.equal(hasSpecificHehaLocalDestination(partner), false, path);
    assert.equal(isHehaLocalPartner(partner), false, path);
  }

  assert.equal(hasSpecificHehaLocalDestination({
    id: "unmapped-partner",
    primary_cta_path: "/market/partner-1?ref=heha#details",
  }), true);
  assert.equal(hehaLocalProfilePath({
    id: "unmapped-partner",
    primary_cta_path: "/market/partner-1?ref=heha#details",
  }), "/market/partner-1?ref=heha#details");
  assert.equal(hasSpecificHehaLocalDestination({
    id: "2fbe55b6-f7ba-453d-8923-72f22946fea9",
    primary_cta_path: "/restaurants",
  }), true);

  for (const path of [
    "https://external.example/partner",
    "//external.example/partner",
    "javascript:alert(1)",
    "/market%2fpartner-1",
    "/market\\partner-1",
    "/%72estaurants",
    "/m%61rket",
    "/vend%6frs",
    "/ch%65f",
    "/group-%6frders",
  ]) {
    assert.equal(hasSpecificHehaLocalDestination({
      id: "unmapped-partner",
      primary_cta_path: path,
    }), false, path);
  }
});

test("Swipe client uses the bounded store RPC for an explicit store channel", async () => {
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

  const result = await fetchPublicPartners(client, { channel: "store" });
  assert.deepEqual(calls, [[STORE_PUBLIC_PARTNER_RPC]]);
  assert.deepEqual(Object.keys(result[0]), expectedStoreFields);
  assert.equal("owner_id" in result[0], false);
  assert.doesNotMatch(source, /\.from\s*\(/);
});

test("ordinary web explicitly uses the bounded web-detail RPC", async () => {
  const calls = [];
  const client = {
    rpc: async (...args) => {
      calls.push(args);
      return {
        data: [{
          id: "partner-1",
          name: "Example",
          gallery_urls: ["https://cdn.example/gallery.jpg"],
          items: [{ name: "Harvest Bowl", private_note: "must not pass" }],
          instagram: "partner.handle",
          local_eligible: true,
          primary_cta_destination: "local",
          primary_cta_path: "/restaurants/partner-1",
          owner_id: "private-owner",
        }],
        error: null,
      };
    },
  };

  const result = await fetchPublicPartners(client, { channel: "web" });
  assert.deepEqual(calls, [[WEB_PUBLIC_PARTNER_RPC]]);
  assert.deepEqual(Object.keys(result[0]), expectedWebFields);
  assert.deepEqual(result[0].gallery_urls, ["https://cdn.example/gallery.jpg"]);
  assert.deepEqual(result[0].items, [{ name: "Harvest Bowl" }]);
  assert.equal(result[0].instagram, "partner.handle");
  assert.equal(result[0].local_eligible, true);
  assert.equal(result[0].primary_cta_destination, "local");
  assert.equal(result[0].primary_cta_path, "/restaurants/partner-1");
  assert.equal("owner_id" in result[0], false);
  assert.match(
    appSource,
    /fetchPublicPartners\(supabase,\s*\{\s*channel:\s*releasePolicy\.storeBuild\s*\?\s*"store"\s*:\s*"web",?\s*\}\)/,
  );
});

test("missing or unknown channels fail before RPC I/O", async () => {
  const calls = [];
  const client = {
    rpc: async (...args) => {
      calls.push(args);
      return { data: [], error: null };
    },
  };

  for (const options of [
    undefined,
    null,
    {},
    { channel: "" },
    { channel: "native" },
    { channel: "admin" },
    { channel: "__proto__" },
    { channel: "constructor" },
  ]) {
    await assert.rejects(
      () => fetchPublicPartners(client, options),
      /channel must be exactly 'store' or 'web'/,
    );
  }
  assert.deepEqual(calls, []);
});

test("RPC errors and malformed payloads fail without a fallback", async () => {
  const sentinel = new Error("sentinel RPC failure");
  await assert.rejects(
    () => fetchPublicPartners({
      rpc: async () => ({ data: null, error: sentinel }),
    }, { channel: "store" }),
    (error) => error === sentinel,
  );

  await assert.rejects(
    () => fetchPublicPartners({
      rpc: async () => ({ data: { id: "not-an-array" }, error: null }),
    }, { channel: "web" }),
    /non-array payload/,
  );

  assert.deepEqual(
    await fetchPublicPartners({
      rpc: async () => ({ data: null, error: null }),
    }, { channel: "store" }),
    [],
  );
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
    returnColumnsFor("list_public_swipe_partner_details"),
    expectedWebCardReturnColumns
  );
  assert.deepEqual(
    returnColumnsFor("list_public_partner_directory"),
    expectedDirectoryReturnColumns
  );

  for (const functionName of [
    "list_public_swipe_partner_cards",
    "list_public_swipe_partner_details",
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
    3
  );
  assert.equal((reviewSql.match(/set\s+search_path\s*=\s*''/gi) || []).length, 3);
  assert.equal(
    (reviewSql.match(/status\s*=\s*any\s*\(array\['approved'::text,\s*'live'::text\]\)/gi) || []).length,
    3
  );
  assert.match(reviewSql, /coalesce\(partner\.swipe_eligible,\s*false\)\s*=\s*true/i);
  assert.match(reviewSql, /coalesce\(partner\.website_eligible,\s*false\)\s*=\s*true/i);
  assert.equal(
    (reviewSql.match(/coalesce\(partner\.is_test_record,\s*false\)\s*=\s*false/gi) || []).length,
    3
  );
  assert.doesNotMatch(reviewSql, /select\s+\*/i);
  assert.doesNotMatch(reviewSql, /\bformat\s*\(/i);
  assert.doesNotMatch(
    reviewSql,
    /\b(owner_id|contact|phone|routing_notes|service_fee|pricing_notes|contribution|total_)\b/i
  );

  const webFunction = reviewSql.match(
    /create\s+or\s+replace\s+function\s+public\.list_public_swipe_partner_details\(\)[\s\S]*?as\s+\$\$([\s\S]*?)\$\$;/i,
  );
  assert.ok(webFunction, "bounded web-detail RPC body is required");
  assert.deepEqual(
    [...webFunction[1].matchAll(/^\s*'([a-z_]+)',\s*case\s+when/gm)].map((match) => match[1]),
    expectedItemFields,
  );
  assert.match(webFunction[1], /jsonb_typeof\(image\.value\)\s*=\s*'string'/i);
  for (const field of expectedItemUrlFields) {
    const urlCase = webFunction[1].match(
      new RegExp(`'${field}',\\s*case([\\s\\S]*?)\\n\\s*end,`, "i"),
    );
    assert.ok(urlCase, `bounded ${field} projection is required`);
    assert.match(urlCase[1], new RegExp(`jsonb_typeof\\(item\\.value -> '${field}'\\) = 'string'`, "i"));
    assert.match(urlCase[1], new RegExp(`btrim\\(item\\.value ->> '${field}'\\) ~\\* '\\^https\\?://`, "i"));
    assert.match(urlCase[1], /!~ '\[\[:space:\]\[:cntrl:\]\]'/i);
    assert.match(urlCase[1], new RegExp(`then to_jsonb\\(btrim\\(item\\.value ->> '${field}'\\)\\)`, "i"));
  }
  assert.doesNotMatch(
    webFunction[1],
    /\b(owner_id|contact|phone|routing_notes|routing_status|routing_updated|pricing_notes|service_fee|contribution|total_)\b/i,
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
