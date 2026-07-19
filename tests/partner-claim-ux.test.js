import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  CLAIM_ERRORS,
  CLAIM_SUCCESS_KEY,
  clearClaimSuccess,
  consumeClaimSuccess,
  friendlyAuthError,
  friendlyClaimError,
  readClaimSuccess,
  removeClaimSuccessParam,
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

test("maps recipient mismatch to calm account-switch guidance", () => {
  assert.equal(
    friendlyClaimError({ message: "This one-time claim link belongs to a different account." }),
    CLAIM_ERRORS.recipientMismatch,
  );
});

test("unknown auth and claim errors stay generic", () => {
  assert.equal(friendlyAuthError({ message: "sensitive backend detail" }, "signin").includes("sensitive"), false);
  assert.equal(friendlyClaimError({ message: "sensitive backend detail" }).includes("sensitive"), false);
});

function memoryStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };
}

const USER_A = "11111111-1111-4111-8111-111111111111";
const USER_B = "22222222-2222-4222-8222-222222222222";

test("prevents false claim-success confirmation from query-only navigation", () => {
  assert.equal(readClaimSuccess("?claim=success", memoryStorage(), USER_A, 10_000), null);
});

test("rejects missing, cleared, empty, malformed, and invalid success payloads", () => {
  const now = 1_000_000;
  const invalidPayloads = [
    null,
    "{}",
    "not-json",
    "[]",
    JSON.stringify({ marker: "partner_claim_completed", version: 1, createdAt: now, userId: USER_A, partnerName: "" }),
    JSON.stringify({ marker: "partner_claim_completed", version: 1, createdAt: now, userId: USER_A, partnerName: "   " }),
    JSON.stringify({ marker: "partner_claim_completed", version: 99, createdAt: now, userId: USER_A, partnerName: "Business" }),
    JSON.stringify({ marker: "wrong", version: 1, createdAt: now, userId: USER_A, partnerName: "Business" }),
    JSON.stringify({ marker: "partner_claim_completed", version: 1, createdAt: now - 16 * 60 * 1000, userId: USER_A, partnerName: "Business" }),
  ];

  for (const payload of invalidPayloads) {
    const storage = memoryStorage(payload === null ? {} : { [CLAIM_SUCCESS_KEY]: payload });
    assert.equal(readClaimSuccess("?claim=success", storage, USER_A, now), null);
  }
});

test("genuine claim success survives redirect, renders its exact name, and is consumed once", () => {
  const now = 1_000_000;
  const storage = memoryStorage();
  assert.equal(saveClaimSuccess(storage, "  A Very Long Business Name That Must Wrap Safely  ", true, USER_A, now), true);
  assert.deepEqual(consumeClaimSuccess("?claim=success", storage, USER_A, now + 1_000), {
    partnerName: "A Very Long Business Name That Must Wrap Safely",
    profileSetupPending: true,
  });
  assert.equal(storage.getItem(CLAIM_SUCCESS_KEY), null);
  assert.equal(readClaimSuccess("?claim=success", storage, USER_A, now + 2_000), null);
});

test("claim success persists for the redirect and clears on dismissal", () => {
  const now = 1_000_000;
  const storage = memoryStorage();

  saveClaimSuccess(storage, "A Very Long Business Name That Must Wrap Safely", true, USER_A, now);
  assert.deepEqual(readClaimSuccess("?claim=success", storage, USER_A, now), {
    partnerName: "A Very Long Business Name That Must Wrap Safely",
    profileSetupPending: true,
  });
  assert.equal(readClaimSuccess("", storage, USER_A, now), null);
  clearClaimSuccess(storage);
  assert.equal(storage.getItem(CLAIM_SUCCESS_KEY), null);
  assert.equal(readClaimSuccess("?claim=success", storage, USER_A, now), null);
});

test("copied URL in another session and refresh after consumption show no banner", () => {
  const now = 1_000_000;
  assert.equal(consumeClaimSuccess("?claim=success", memoryStorage(), USER_A, now), null);
  const storage = memoryStorage();
  saveClaimSuccess(storage, "Current Session Business", false, USER_A, now);
  assert.equal(consumeClaimSuccess("?claim=success", storage, USER_B, now), null);
  assert.equal(storage.getItem(CLAIM_SUCCESS_KEY), null);
  assert.equal(consumeClaimSuccess("?claim=success", storage, USER_A, now), null);

  saveClaimSuccess(storage, "Current Session Business", false, USER_A, now);
  assert.ok(consumeClaimSuccess("?claim=success", storage, USER_A, now));
  assert.equal(consumeClaimSuccess("?claim=success", storage, USER_A, now), null);
});

test("query cleanup removes only claim success and preserves unrelated parameters and hash", () => {
  assert.equal(
    removeClaimSuccessParam({ pathname: "/", search: "?claim=success&source=invite&tab=profile", hash: "#details" }),
    "/?source=invite&tab=profile#details",
  );
});

test("claim UI includes persistent, review-gated, non-public confirmation copy", async () => {
  const [app, screen] = await Promise.all([
    readFile(new URL("../src/App.jsx", import.meta.url), "utf8"),
    readFile(new URL("../src/components/PartnerClaimScreen.jsx", import.meta.url), "utf8"),
  ]);
  assert.match(app, /nothing was published or changed publicly yet/);
  assert.match(app, /Review your HEHA account/);
  assert.match(app, /Dismiss claim confirmation/);
  assert.doesNotMatch(app, /claimSuccess\.partnerName \|\||myListing\?\.name \|\||Your business profile.*connected/);
  assert.doesNotMatch(app, /now (an )?Official HEHA Partner|now HEHA Certified|HEHA Local is active/);
  assert.match(screen, /Profile edits, products, and offers stay saved as drafts until HEHA reviews them/);
  assert.match(screen, /At least 8 characters/);
  assert.match(screen, /Use the invited account/);
  assert.match(screen, /Get help/);
});

test("claim admin UI requires a recipient and uses the supported role allowlist", async () => {
  const [adminApp, routing] = await Promise.all([
    readFile(new URL("../src/components/admin/AdminApp.jsx", import.meta.url), "utf8"),
    readFile(new URL("../src/components/admin/routing/RoutingDashboard.jsx", import.meta.url), "utf8"),
  ]);
  assert.match(adminApp, /claimAdmin: \["super_admin", "developer_admin", "pm_admin"\]\.includes\(role\)/);
  assert.match(routing, /Verified recipient email/);
  assert.match(routing, /p_intended_email: intendedEmail/);
  assert.doesNotMatch(routing, /som_admin/);
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
