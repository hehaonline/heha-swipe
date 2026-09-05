import assert from "node:assert/strict";
import test from "node:test";
import { createReleasePolicy } from "../../src/lib/releasePolicy.js";

const restrictedFeatures = [
  "socialAuth",
  "passwordlessAuth",
  "geolocation",
  "payments",
  "outboundWebhooks",
  "contactRequests",
  "instagram",
  "partnerSelfService",
  "internalAdmin",
  "superSwipe",
  "profileReset",
];

test("store channel fails closed for unfinished or sensitive surfaces", () => {
  const policy = createReleasePolicy({ releaseChannel: "store", isNative: false });
  assert.equal(policy.storeBuild, true);
  assert.equal(policy.passwordAuth, true);
  for (const feature of restrictedFeatures) assert.equal(policy[feature], false, feature);
});

test("native runtime fails closed even if its build channel is absent", () => {
  const policy = createReleasePolicy({ releaseChannel: "web", isNative: true });
  assert.equal(policy.storeBuild, true);
  for (const feature of restrictedFeatures) assert.equal(policy[feature], false, feature);
});

test("ordinary web preview retains the existing web-only surfaces", () => {
  const policy = createReleasePolicy({ releaseChannel: "web", isNative: false });
  assert.equal(policy.storeBuild, false);
  assert.equal(policy.socialAuth, true);
  assert.equal(policy.payments, true);
  assert.equal(policy.contactRequests, true);
});
