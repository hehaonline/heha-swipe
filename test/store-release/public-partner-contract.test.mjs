import assert from "node:assert/strict";
import test from "node:test";
import {
  PUBLIC_PARTNER_FIELDS,
  PUBLIC_PARTNER_SELECT,
  toPublicPartner,
} from "../../src/lib/publicPartner.js";

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

test("public partner contract is exactly the reviewed 13 fields", () => {
  assert.deepEqual(PUBLIC_PARTNER_FIELDS, expectedFields);
  assert.equal(PUBLIC_PARTNER_FIELDS.length, 13);
  assert.equal(PUBLIC_PARTNER_SELECT, expectedFields.join(","));
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
