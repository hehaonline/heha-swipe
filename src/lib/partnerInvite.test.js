import test from "node:test";
import assert from "node:assert/strict";
import {
  clearPendingPartnerInviteToken,
  consumePartnerInviteFromLocation,
  pendingPartnerInviteRequestKey,
  pendingPartnerInviteToken,
  partnerInviteUrlRequiresHardStop,
} from "./partnerInvite.js";

function withBrowserState(hash, callback, { historyFails = false, locationReplaceFails = false } = {}) {
  const values = new Map();
  const replaced = [];
  const reloaded = [];
  const previousWindow = globalThis.window;
  const previousSessionStorage = globalThis.sessionStorage;

  globalThis.sessionStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
  globalThis.window = {
    location: {
      pathname: "/",
      search: "?launch=partner_hub",
      hash,
      replace: (url) => {
        if (locationReplaceFails) throw new Error("location replacement denied");
        reloaded.push(url);
      },
    },
    history: {
      replaceState: (_state, _title, url) => {
        if (historyFails) throw new Error("history replacement denied");
        replaced.push(url);
      },
    },
    stop: () => {},
  };

  try {
    callback({ replaced, reloaded, values });
  } finally {
    globalThis.window = previousWindow;
    globalThis.sessionStorage = previousSessionStorage;
  }
}

test("consumes a valid invite fragment into session storage and strips it from the URL", () => {
  const token = "A".repeat(32);
  withBrowserState(`#partner_invite=${token}&launch_source=pure_kitchen`, ({ replaced }) => {
    assert.equal(consumePartnerInviteFromLocation(), token);
    assert.equal(pendingPartnerInviteToken(), token);
    const requestKey = pendingPartnerInviteRequestKey();
    assert.match(requestKey, /^[0-9a-f-]{36}$/i);
    assert.equal(pendingPartnerInviteRequestKey(), requestKey, "retry must reuse the same request key");
    assert.deepEqual(replaced, ["/?launch=partner_hub#launch_source=pure_kitchen"]);
    clearPendingPartnerInviteToken();
    assert.equal(pendingPartnerInviteToken(), null);
    assert.equal(pendingPartnerInviteRequestKey(), null);
  });
});

test("rejects and clears a malformed invite while still removing it from the URL", () => {
  withBrowserState("#partner_invite=not-a-valid-secret", ({ replaced, values }) => {
    values.set("heha_partner_invite_token_v1", "B".repeat(32));
    assert.equal(consumePartnerInviteFromLocation(), null);
    assert.equal(pendingPartnerInviteToken(), null);
    assert.deepEqual(replaced, ["/?launch=partner_hub"]);
  });
});

test("falls back to a sanitized reload when history replacement is denied", () => {
  const token = "C".repeat(32);
  withBrowserState(`#partner_invite=${token}`, ({ reloaded }) => {
    assert.equal(consumePartnerInviteFromLocation(), null);
    assert.deepEqual(reloaded, ["/?launch=partner_hub"]);
    assert.equal(pendingPartnerInviteToken(), null);
    assert.equal(partnerInviteUrlRequiresHardStop(), false);
  }, { historyFails: true });
});

test("hard-stops when neither URL cleanup mechanism is available", () => {
  const token = "D".repeat(32);
  withBrowserState(`#partner_invite=${token}`, () => {
    assert.equal(consumePartnerInviteFromLocation(), null);
    assert.equal(pendingPartnerInviteToken(), null);
    assert.equal(partnerInviteUrlRequiresHardStop(), true);
  }, { historyFails: true, locationReplaceFails: true });
});
