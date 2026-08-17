import assert from "node:assert/strict";
import test from "node:test";

import { partnerSurfaceVisibility } from "./partnerVisibility.js";

test("raw listing fields never substitute for the authoritative public projection", () => {
  assert.deepEqual(partnerSurfaceVisibility({
    status: "live",
    swipe_eligible: true,
  }), { swipeVisible: false, localVisible: false });

  assert.deepEqual(partnerSurfaceVisibility({
    status: "live",
    swipe_eligible: true,
  }, {
    publication_destinations: ["heha_swipe"],
  }), { swipeVisible: false, localVisible: false });
});

test("owner visibility mirrors the final server-resolved public destinations", () => {
  assert.deepEqual(partnerSurfaceVisibility({}, {
    publication_destinations: ["heha_swipe", "heha_local"],
    staff_review_destinations: ["heha_swipe", "heha_local"],
    public_destinations: ["heha_swipe"],
  }), { swipeVisible: true, localVisible: false });

  assert.deepEqual(partnerSurfaceVisibility({}, {
    public_destinations: ["heha_local"],
  }), { swipeVisible: false, localVisible: true });
});
