import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { authenticateForClaim, claimRedirectUrl, claimTokenFromLocation, createPartnerClaimFlow, isVerifiedClaimUser } from "./partnerClaimFlow.js";
import { CLAIM_ERRORS, CLAIM_SUCCESS_KEY, claimSessionStorage, consumeClaimSuccess, friendlyClaimError, readClaimSuccess, saveClaimSuccess } from "./partnerClaimUx.js";

const TOKEN = "a".repeat(64);
const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const PARTNER = "33333333-3333-4333-8333-333333333333";
const VERIFIED = { id: USER, email: "office@example.invalid", email_confirmed_at: "2026-09-14T10:00:00Z", is_anonymous: false };
const PREVIEW = { partner_id: PARTNER, partner_name: "Existing business", expires_at: "2026-09-20T10:00:00Z", claimable: true };
const CLAIMED = { partner_id: PARTNER, partner_name: "Existing business", claimed_at: "2026-09-14T11:00:00Z", claim_status: "claimed" };
const REDIRECT = `https://preview.example.invalid/claim-partner?token=${TOKEN}`;

function fixture({ user = VERIFIED, preview = [PREVIEW], claimed = [CLAIMED], rpcError = null } = {}) {
  const calls = [];
  const state = { user, preview, claimed, rpcError };
  const client = {
    auth: {
      getUser: async () => ({ data: { user: state.user }, error: null }),
      ...Object.fromEntries(["signUp", "signInWithPassword", "signInWithOtp"].map((name) => [name, async (args) => {
        calls.push({ name, args }); return { data: { session: null }, error: null };
      }])),
    },
    rpc: async (name, args) => {
      calls.push({ name, args });
      return { data: name === "preview_partner_claim" ? state.preview : state.claimed, error: state.rpcError };
    },
    from() { throw new Error("No direct table/create/owner operation allowed."); },
  };
  return { client, calls, state, flow: createPartnerClaimFlow(client, TOKEN) };
}

test("accepts only one canonical token on the exact claim route", () => {
  assert.equal(claimTokenFromLocation({ pathname: "/claim-partner", search: `?token=${TOKEN}&code=supabase-callback` }), TOKEN);
  for (const search of ["", "?token=", `?token=${TOKEN}&token=${TOKEN}`, `?token=%20${TOKEN}`, `?token=${TOKEN.toUpperCase()}`, `?token=${"b".repeat(63)}`, "?token=../../secret", `?token=${TOKEN}&other=${"x".repeat(8192)}`]) {
    assert.equal(claimTokenFromLocation({ pathname: "/claim-partner", search }), "");
  }
  for (const pathname of ["/", "/claim-partner/", "/claim-partner-other", "//claim-partner"]) {
    assert.equal(claimTokenFromLocation({ pathname, search: `?token=${TOKEN}` }), "");
  }
});

test("auth return retains only the claim token, not redirect or credential fragments", () => {
  assert.equal(claimRedirectUrl("https://preview.example.invalid", TOKEN), REDIRECT);
  assert.equal(claimRedirectUrl("http://localhost:5173", TOKEN), `http://localhost:5173/claim-partner?token=${TOKEN}`);
  for (const origin of ["javascript:alert(1)", "http://public.example.invalid", "https://user:pass@example.invalid", "https://example.invalid/?redirect=elsewhere", "https://example.invalid/#access_token=secret", "https://example.invalid/other"]) {
    assert.throws(() => claimRedirectUrl(origin, TOKEN));
  }
  assert.throws(() => claimRedirectUrl("https://preview.example.invalid", "bad"));
});

test("only a permanent, confirmed, identified email user is eligible", () => {
  assert.equal(isVerifiedClaimUser(VERIFIED), true);
  for (const user of [null, { ...VERIFIED, id: "bad" }, { ...VERIFIED, email: "" }, { ...VERIFIED, email: "@invalid" }, { ...VERIFIED, is_anonymous: true }, { ...VERIFIED, email_confirmed_at: null }, { ...VERIFIED, email_confirmed_at: "not a date" }, { ...VERIFIED, email: "a".repeat(321) }]) {
    assert.equal(isVerifiedClaimUser(user), false);
  }
});

test("existing verified user previews and claims the exact same partner with token-only RPCs", async () => {
  const { flow, calls } = fixture();
  assert.deepEqual(await flow.preview(USER), PREVIEW);
  assert.deepEqual(await flow.claim(USER, PARTNER), CLAIMED);
  assert.deepEqual(calls, [
    { name: "preview_partner_claim", args: { p_raw_token: TOKEN } },
    { name: "claim_partner_profile", args: { p_raw_token: TOKEN } },
  ]);
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_SUBMISSION_PENDING" });
  assert.equal(calls.length, 2);
});

test("new account cannot preview or claim until its email is verified, then uses the same row", async () => {
  const { flow, calls, state } = fixture({ user: { ...VERIFIED, email_confirmed_at: null } });
  await assert.rejects(flow.preview(USER), { details: "HEHA_CLAIM_RECIPIENT_INELIGIBLE" });
  await assert.rejects(flow.claim(USER, PARTNER));
  assert.equal(calls.length, 0);
  state.user = VERIFIED;
  await flow.preview(USER);
  assert.equal((await flow.claim(USER, PARTNER)).partner_id, PARTNER);
});

test("claim requires a successful preview for the same user and exact business", async () => {
  const { flow, calls } = fixture();
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_INVALID_RESPONSE" });
  await flow.preview(USER);
  await assert.rejects(flow.claim(USER, OTHER), { details: "HEHA_CLAIM_INVALID_RESPONSE" });
  await assert.rejects(flow.claim(OTHER, PARTNER), { details: "HEHA_CLAIM_INVALID_RESPONSE" });
  assert.equal(calls.length, 1);
});

test("rechecks server-confirmed identity immediately before claim", async () => {
  const { flow, calls, state } = fixture();
  await flow.preview(USER);
  state.user = { ...VERIFIED, id: OTHER };
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_SESSION_CHANGED" });
  state.user = { ...VERIFIED, email_confirmed_at: null };
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_RECIPIENT_INELIGIBLE" });
  assert.equal(calls.length, 1);
});

test("session switching during an RPC cannot display/store success for another user", async () => {
  const { client, state, flow } = fixture();
  await flow.preview(USER);
  client.rpc = async () => {
    state.user = { ...VERIFIED, id: OTHER };
    return { data: [CLAIMED], error: null };
  };
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_SESSION_CHANGED" });
  state.user = VERIFIED;
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_SUBMISSION_PENDING" });
});

for (const [details, expected] of [
  ["HEHA_CLAIM_NOT_RECOGNIZED", CLAIM_ERRORS.invalid],
  ["HEHA_CLAIM_EXPIRED", CLAIM_ERRORS.expired],
  ["HEHA_CLAIM_REVOKED", CLAIM_ERRORS.revoked],
  ["HEHA_CLAIM_ALREADY_USED", CLAIM_ERRORS.used],
  ["HEHA_CLAIM_ALREADY_CLAIMED", CLAIM_ERRORS.claimed],
  ["HEHA_CLAIM_PROFILE_UNAVAILABLE", CLAIM_ERRORS.unavailable],
  ["HEHA_CLAIM_RECIPIENT_MISMATCH", CLAIM_ERRORS.recipientMismatch],
  ["HEHA_CLAIM_RECIPIENT_INELIGIBLE", CLAIM_ERRORS.recipientIneligible],
]) {
  test(`server ${details} fails closed with stable, private guidance`, async () => {
    const error = { details, message: "private server diagnostic" };
    const { flow } = fixture({ rpcError: error });
    await assert.rejects(flow.preview(USER), error);
    assert.equal(friendlyClaimError(error), expected);
    const afterPreview = fixture();
    await afterPreview.flow.preview(USER);
    afterPreview.state.rpcError = error;
    await assert.rejects(afterPreview.flow.claim(USER, PARTNER), error);
  });
}

test("unknown error detail does not expose diagnostic text or guess from mutable copy", () => {
  assert.equal(friendlyClaimError({ details: "UNKNOWN", message: "expired private diagnostic" }), CLAIM_ERRORS.generic);
});

test("empty, duplicate, wrong-id and malformed RPC rows cannot produce claim success", async () => {
  for (const preview of [[], [PREVIEW, PREVIEW], null, [{}], [{ ...PREVIEW, claimable: "true" }], [{ ...PREVIEW, expires_at: "bad" }], [{ ...PREVIEW, partner_id: "bad" }]]) {
    await assert.rejects(fixture({ preview }).flow.preview(USER));
  }
  for (const claimed of [[], [CLAIMED, CLAIMED], [{}], [{ ...CLAIMED, partner_id: OTHER }], [{ ...CLAIMED, claim_status: "approved" }], [{ ...CLAIMED, claimed_at: "bad" }]]) {
    const { flow } = fixture({ claimed });
    await flow.preview(USER);
    await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_INVALID_RESPONSE" });
    await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_SUBMISSION_PENDING" });
  }
});

test("double submission issues only one mutation and a successful claim cannot be repeated", async () => {
  const { flow, client, calls } = fixture();
  await flow.preview(USER);
  let finish;
  client.rpc = async (name, args) => {
    calls.push({ name, args });
    return new Promise((resolve) => { finish = resolve; });
  };
  const first = flow.claim(USER, PARTNER);
  await assert.rejects(flow.claim(USER, PARTNER), { details: "HEHA_CLAIM_SUBMISSION_PENDING" });
  finish({ data: [CLAIMED], error: null });
  await first;
  assert.equal(calls.filter((c) => c.name === "claim_partner_profile").length, 1);
});

test("network failures settle and a deliberate retry revalidates the claim", async () => {
  const { flow, client } = fixture();
  const original = client.rpc;
  client.rpc = async () => { throw new Error("network unavailable"); };
  await assert.rejects(flow.preview(USER));
  client.rpc = original;
  await flow.preview(USER);
  client.rpc = async () => { throw new Error("network unavailable"); };
  await assert.rejects(flow.claim(USER, PARTNER));
  client.rpc = original;
  assert.equal((await flow.claim(USER, PARTNER)).partner_id, PARTNER);
});

test("invalid token fails before any auth or RPC call", async () => {
  const client = { auth: { getUser: () => assert.fail("auth called") }, rpc: () => assert.fail("rpc called") };
  await assert.rejects(createPartnerClaimFlow(client, "bad").preview(USER));
});

for (const mode of ["signin", "create"]) {
  for (const method of ["password", "email"]) {
    test(`${mode} ${method} preserves exact return path without owner/role/acceptance metadata`, async () => {
      const { client, calls } = fixture();
      await authenticateForClaim(client, { mode, method, email: " office@example.invalid ", password: "synthetic-pass", redirectTo: REDIRECT });
      const call = calls[0];
      assert.equal(call.name, method === "email" ? "signInWithOtp" : mode === "create" ? "signUp" : "signInWithPassword");
      assert.equal(call.args.email, "office@example.invalid");
      if (method === "email" || mode === "create") assert.equal(call.args.options.emailRedirectTo, REDIRECT);
      if (method === "email") assert.equal(call.args.options.shouldCreateUser, mode === "create");
      assert.equal(call.args.options?.data, undefined);
      assert.doesNotMatch(JSON.stringify(call), /owner_id|partner_id|agreement|signup_role/);
    });
  }
}

test("existing password length is not falsely rejected; invalid new account inputs never call auth", async () => {
  const { client, calls } = fixture();
  await authenticateForClaim(client, { mode: "signin", method: "password", email: VERIFIED.email, password: "older", redirectTo: REDIRECT });
  for (const patch of [{ mode: "create", password: "short" }, { mode: "unknown" }, { email: "" }, { redirectTo: `${REDIRECT}&next=https://elsewhere.invalid` }]) {
    await assert.rejects(authenticateForClaim(client, { mode: "signin", method: "password", email: VERIFIED.email, password: "synthetic-pass", redirectTo: REDIRECT, ...patch }));
  }
  assert.equal(calls.length, 1);
});

function storage() {
  const map = new Map();
  return { getItem: (key) => map.get(key) ?? null, setItem: (key, value) => map.set(key, value), removeItem: (key) => map.delete(key) };
}

test("success receipt is short-lived, exact-business/current-user bound, one-use and token-free", () => {
  const target = storage(), now = 1_000_000;
  assert.equal(saveClaimSuccess(target, PREVIEW.partner_name, false, USER, now, PARTNER), true);
  assert.equal(readClaimSuccess("?claim=success", target, OTHER, now), null);
  assert.equal(readClaimSuccess("?claim=success", target, USER, now + 16 * 60_000), null);
  assert.doesNotMatch(target.getItem(CLAIM_SUCCESS_KEY), /token|email|password/i);
  assert.deepEqual(consumeClaimSuccess("?claim=success", target, USER, now), { userId: USER, partnerId: PARTNER, partnerName: PREVIEW.partner_name, profileSetupPending: false });
  assert.equal(consumeClaimSuccess("?claim=success", target, USER, now), null);
  assert.equal(readClaimSuccess("?claim=success", storage(), USER, now), null);
  assert.equal(saveClaimSuccess(target, "Business", false, USER, now, "bad"), false);
});

test("blocked storage cannot misreport a committed one-time claim as failed", () => {
  const blocked = { setItem() { throw new Error("blocked"); }, getItem() { throw new Error("blocked"); } };
  assert.equal(saveClaimSuccess(blocked, "Business", false, USER, 1_000_000, PARTNER), false);
  assert.equal(readClaimSuccess("?claim=success", blocked, USER), null);
  const host = { get sessionStorage() { throw new Error("SecurityError"); } };
  assert.equal(claimSessionStorage(host), null);
  assert.equal(saveClaimSuccess(claimSessionStorage(host), "Business", false, USER, 1_000_000, PARTNER), false);
});

test("render integration preserves release gates, exact-profile ownership query, and failure retry controls", async () => {
  const [main, app, screen, html] = await Promise.all([
    readFile(new URL("../main.jsx", import.meta.url), "utf8"),
    readFile(new URL("../App.jsx", import.meta.url), "utf8"),
    readFile(new URL("../components/PartnerClaimScreen.jsx", import.meta.url), "utf8"),
    readFile(new URL("../../index.html", import.meta.url), "utf8"),
  ]);
  assert.match(main, /pathname === "\/claim-partner" && releasePolicy\.partnerSelfService/);
  assert.match(main, /revision !== initialRevision/);
  assert.match(main, /if \(signOutError\) throw signOutError/);
  assert.match(app, /\.eq\("owner_id", uid\)/);
  assert.match(app, /ownedQuery = ownedQuery\.eq\("id", returnedClaim\.partnerId\)/);
  assert.match(app, /showPartnerWizard && !myListing && !dataLoading && !appError/);
  assert.match(app, /needsOnboarding && !myListing/);
  assert.match(screen, /if \(authPending\.current\) return/);
  assert.match(screen, /claimPending\.current \|\| completed/);
  assert.match(screen, /setCompleted\(claimed\)/);
  assert.match(screen, /Check link again/);
  assert.match(screen, /Use the invited account/);
  assert.doesNotMatch(screen, /\.from\(|\.insert\(|owner_id:|agreement_accepted|signup_role|localStorage\.setItem/);
  assert.match(html, /<meta name="referrer" content="no-referrer"/);
  assert.ok(html.indexOf('name="referrer"') < html.indexOf("fonts.googleapis.com"));
});

test("server contract used by the UI retains verified-recipient, same-row and independent lifecycle boundaries", async () => {
  const sql = await readFile(new URL("../../supabase/migrations/20260817154927_hybrid_partner_claim_recipient_contract.sql", import.meta.url), "utf8");
  const claim = sql.slice(sql.indexOf("create or replace function public.claim_partner_profile"));
  assert.match(claim, /verified_permanent_claim_email\(actor\)/);
  assert.match(claim, /HEHA_CLAIM_RECIPIENT_MISMATCH/);
  assert.match(claim, /apply_verified_partner_claim\(p\.id,actor,claim_time\)/);
  assert.match(claim, /return query select p\.id,p\.name,'claimed'::text,claim_time/);
  assert.doesNotMatch(claim, /insert into public\.partners|set listing_status|set agreement_status|set operational_status/);
});
