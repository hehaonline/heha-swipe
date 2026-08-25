import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  PUBLIC_PARTNER_DIRECTORY_FIELDS,
  PUBLIC_PARTNER_DIRECTORY_FIELD_LIST,
} from "./publicPartnerDirectoryContract.js";

test("the public directory field contract excludes private location data", () => {
  assert.equal(PUBLIC_PARTNER_DIRECTORY_FIELDS.includes("location"), false);
  assert.equal(PUBLIC_PARTNER_DIRECTORY_FIELDS.includes("neighborhood"), true);
  assert.deepEqual(
    PUBLIC_PARTNER_DIRECTORY_FIELD_LIST.split(","),
    [...PUBLIC_PARTNER_DIRECTORY_FIELDS]
  );
});

test("PartnerDirectoryEmbed uses the shared field contract and no location fallback", async () => {
  const source = await readFile(
    new URL("../components/embed/PartnerDirectoryEmbed.jsx", import.meta.url),
    "utf8"
  );

  assert.match(source, /\.select\(PUBLIC_PARTNER_DIRECTORY_FIELD_LIST\)/);
  assert.doesNotMatch(source, /partner\.location/);
  assert.doesNotMatch(source, /["']location["']/);
});
