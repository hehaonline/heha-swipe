import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_PUBLIC_APP_URL,
  canonicalPublicAppUrl,
} from "../../src/lib/authRedirect.js";

test("store auth redirect defaults to the canonical public HTTPS app URL", () => {
  assert.equal(canonicalPublicAppUrl(), DEFAULT_PUBLIC_APP_URL);
  assert.equal(canonicalPublicAppUrl(""), DEFAULT_PUBLIC_APP_URL);
});

test("store auth redirect accepts HTTPS origins and canonicalizes paths", () => {
  assert.equal(canonicalPublicAppUrl("https://app.example.com/path?source=native#auth"), "https://app.example.com");
});

test("store auth redirect rejects unsafe or malformed configuration", () => {
  for (const value of [
    "http://hehaswipe.app",
    "capacitor://localhost",
    "javascript:alert(1)",
    "https://user:password@hehaswipe.app",
    "not-a-url",
  ]) {
    assert.equal(canonicalPublicAppUrl(value), DEFAULT_PUBLIC_APP_URL, value);
  }
});
