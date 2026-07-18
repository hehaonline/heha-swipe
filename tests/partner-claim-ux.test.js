import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  CLAIM_ERRORS,
  CLAIM_SUCCESS_KEY,
  clearClaimSuccess,
  friendlyAuthError,
  friendlyClaimError,
  readClaimSuccess,
  saveClaimSuccess,
} from "../src/lib/partnerClaimUx.js";

const claimCases = [
  ["not recognized", "This claim link is not recognized.", CLAIM_ERRORS.invalid],
  ["expired", "This claim link has expired.", CLAIM_ERRORS.expired],
  ["revoked", "This claim link is revoked.", CLAIM_ERRORS.revoked],
  ["already used", "This claim link has already been used.", CLAIM_ERRORS.used],
  ["already claimed", "This business profile has already been claimed by another account.", CLAIM_ERRORS.claimed],
  ["not claimable", "This profile is no longer claimable.", CLAIM_ERRORS.unavailable],
];

for (const [name, serverMessage, expected] of claimCases) {
  test(`maps ${name} claim state`, () => {
    assert.equal(friendlyClaimError({ message: serverMessage }), expected);
  });
}

test("maps invalid credentials without rendering the raw Supabase message", () => {
  const raw = "Invalid login credentials: internal request 784";
  const friendly = friendlyAuthError({ message: raw }, "signin");
  assert.equal(friendly, "That email and password combination didn't work. Try again, or use “Email me a secure sign-in link” instead.");
  assert.equal(friendly.includes("internal request 784"), false);
});

test("unknown auth and claim errors stay generic", () => {
  assert.equal(friendlyAuthError({ message: "sensitive backend detail" }, "signin").includes("sensitive"), false);
  assert.equal(friendlyClaimError({ message: "sensitive backend detail" }).includes("sensitive"), false);
});

test("claim success persists for the redirect and clears on dismissal", () => {
  const values = new Map();
  const storage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };

  saveClaimSuccess(storage, "A Very Long Business Name That Must Wrap Safely", true);
  assert.deepEqual(readClaimSuccess("?claim=success", storage), {
    partnerName: "A Very Long Business Name That Must Wrap Safely",
    profileSetupPending: true,
  });
  assert.equal(readClaimSuccess("", storage), null);
  clearClaimSuccess(storage);
  assert.equal(storage.getItem(CLAIM_SUCCESS_KEY), null);
  assert.deepEqual(readClaimSuccess("?claim=success", storage), {});
});

test("claim UI includes persistent, review-gated, non-public confirmation copy", async () => {
  const [app, screen] = await Promise.all([
    readFile(new URL("../src/App.jsx", import.meta.url), "utf8"),
    readFile(new URL("../src/components/PartnerClaimScreen.jsx", import.meta.url), "utf8"),
  ]);
  assert.match(app, /nothing was published or changed publicly yet/);
  assert.match(app, /Review your HEHA account/);
  assert.match(app, /Dismiss claim confirmation/);
  assert.doesNotMatch(app, /now (an )?Official HEHA Partner|now HEHA Certified|HEHA Local is active/);
  assert.match(screen, /Profile edits, products, and offers stay saved as drafts until HEHA reviews them/);
  assert.match(screen, /At least 8 characters/);
});

test("claim styles cover focus, inactive-tab contrast, and long-name wrapping", async () => {
  const css = await readFile(new URL("../src/account-actions.css", import.meta.url), "utf8");
  assert.match(css, /#4f493f on #fffaf2 = 8\.57:1 contrast/);
  assert.match(css, /\.auth-tabs button:focus-visible/);
  assert.match(css, /input:focus-visible/);
  assert.match(css, /\.primary-button:focus-visible/);
  assert.match(css, /\.secondary-button:focus-visible/);
  assert.match(css, /overflow-wrap: anywhere/);
});
