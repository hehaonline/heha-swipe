// Tests for the landing entry-gate helpers.
// Runs on Node's built-in test runner -- no extra dependencies:
//   node --test src/lib/entryGate.test.js
import test from "node:test";
import assert from "node:assert/strict";

import {
  sanitizeReturnPath,
  stripEntryParams,
  isLandingEntry,
  shouldShowEntryGate,
  readReturnPath,
  isGuestSession,
  setGuestSession,
  clearGuestSession,
} from "./entryGate.js";

// A minimal in-memory Storage stand-in so guest-session tests do not depend on
// a browser sessionStorage.
function makeStore(initial = {}) {
  const data = { ...initial };
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => {
      data[k] = String(v);
    },
    removeItem: (k) => {
      delete data[k];
    },
  };
}

test("sanitizeReturnPath accepts safe same-origin paths", () => {
  assert.equal(sanitizeReturnPath("/"), "/");
  assert.equal(sanitizeReturnPath("/?tab=faves"), "/?tab=faves");
  assert.equal(sanitizeReturnPath("/support/success"), "/support/success");
  assert.equal(sanitizeReturnPath("/deals#section"), "/deals#section");
  // A colon in a later path segment is harmless once the leading "/" pins origin.
  assert.equal(sanitizeReturnPath("/a:b"), "/a:b");
});

test("sanitizeReturnPath rejects open-redirect / external destinations", () => {
  for (const bad of [
    "//evil.com",
    "/\\evil.com",
    "\\\\evil.com",
    "https://evil.com",
    "http://evil.com/path",
    "//evil.com/@heha",
    "javascript:alert(1)",
    "data:text/html,x",
    "ftp://host",
    "mailto:a@b.c",
    "evil.com",
    "relative/path",
  ]) {
    assert.equal(sanitizeReturnPath(bad), null, `expected null for ${JSON.stringify(bad)}`);
  }
});

test("sanitizeReturnPath rejects whitespace/control smuggling and non-strings", () => {
  assert.equal(sanitizeReturnPath(" /leadingspace"), null);
  assert.equal(sanitizeReturnPath("/tab\ttrick"), null);
  assert.equal(sanitizeReturnPath("/new\nline"), null);
  assert.equal(sanitizeReturnPath("/nul\x00byte"), null);
  assert.equal(sanitizeReturnPath(""), null);
  assert.equal(sanitizeReturnPath(null), null);
  assert.equal(sanitizeReturnPath(undefined), null);
  assert.equal(sanitizeReturnPath(42), null);
  assert.equal(sanitizeReturnPath({}), null);
});

test("stripEntryParams removes entry/return and normalizes, preserving others", () => {
  assert.equal(stripEntryParams("?entry=landing&tab=faves"), "?tab=faves");
  assert.equal(stripEntryParams("?entry=landing"), "");
  assert.equal(stripEntryParams("?return=%2Ffoo&entry=landing"), "");
  assert.equal(stripEntryParams("?tab=deals&entry=landing&x=1"), "?tab=deals&x=1");
  assert.equal(stripEntryParams(""), "");
  assert.equal(stripEntryParams("?foo=bar"), "?foo=bar");
});

test("isLandingEntry detects the landing param exactly", () => {
  assert.equal(isLandingEntry("?entry=landing"), true);
  assert.equal(isLandingEntry("?entry=landing&tab=faves"), true);
  assert.equal(isLandingEntry("?entry=other"), false);
  assert.equal(isLandingEntry("?entry=Landing"), false); // case-sensitive by design
  assert.equal(isLandingEntry(""), false);
  assert.equal(isLandingEntry("?tab=faves"), false);
});

test("shouldShowEntryGate: authenticated users always bypass the gate", () => {
  assert.equal(
    shouldShowEntryGate({ search: "?entry=landing", hasSession: true, isGuest: false }),
    false
  );
  assert.equal(
    shouldShowEntryGate({ search: "?entry=landing", hasSession: true, isGuest: true }),
    false
  );
});

test("shouldShowEntryGate: unauthenticated landing visitor sees the gate", () => {
  assert.equal(
    shouldShowEntryGate({ search: "?entry=landing", hasSession: false, isGuest: false }),
    true
  );
});

test("shouldShowEntryGate: remembered guest does not loop back into the gate", () => {
  assert.equal(
    shouldShowEntryGate({ search: "?entry=landing", hasSession: false, isGuest: true }),
    false
  );
});

test("shouldShowEntryGate: direct visitors keep existing behavior (no gate)", () => {
  assert.equal(
    shouldShowEntryGate({ search: "", hasSession: false, isGuest: false }),
    false
  );
  assert.equal(
    shouldShowEntryGate({ search: "?tab=faves", hasSession: false, isGuest: false }),
    false
  );
});

test("readReturnPath returns a sanitized path or null", () => {
  assert.equal(readReturnPath("?return=%2F%3Ftab%3Dfaves"), "/?tab=faves");
  assert.equal(readReturnPath("?return=https%3A%2F%2Fevil.com"), null);
  assert.equal(readReturnPath("?return=%2F%2Fevil.com"), null);
  assert.equal(readReturnPath("?tab=faves"), null);
  assert.equal(readReturnPath(""), null);
});

test("guest session persistence round-trips and clears", () => {
  const store = makeStore();
  assert.equal(isGuestSession(store), false);
  setGuestSession(store);
  assert.equal(isGuestSession(store), true);
  // Idempotent: setting again keeps it true (no loop / flip-flop).
  setGuestSession(store);
  assert.equal(isGuestSession(store), true);
  clearGuestSession(store);
  assert.equal(isGuestSession(store), false);
});

test("guest session helpers never throw when storage is unavailable/throws", () => {
  const throwing = {
    getItem() {
      throw new Error("blocked");
    },
    setItem() {
      throw new Error("blocked");
    },
    removeItem() {
      throw new Error("blocked");
    },
  };
  assert.equal(isGuestSession(throwing), false);
  assert.doesNotThrow(() => setGuestSession(throwing));
  assert.doesNotThrow(() => clearGuestSession(throwing));
});
