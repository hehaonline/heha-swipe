import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const swipeCardSource = readFileSync(
  new URL("../components/SwipeCard.jsx", import.meta.url),
  "utf8",
);

test("SwipeCard order CTA has no arbitrary item URL fallback", () => {
  assert.match(swipeCardSource, /const firstOrderUrl = partnerOrderUrl\(partner\);/);
  assert.doesNotMatch(swipeCardSource, /item\?\.(?:url|product_url|link)/);
  assert.doesNotMatch(swipeCardSource, /items\.map\(itemUrl\)/);
  assert.match(swipeCardSource, />Open website</);
});
