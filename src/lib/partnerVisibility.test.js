import assert from "node:assert/strict";
import test from "node:test";

import { partnerSurfaceVisibility } from "./partnerVisibility.js";

const partnerId = "9d21cdb5-8f85-4c0b-a98a-cc835eac20f2";

test("only approved/live and Swipe-eligible partners are described as Swipe-visible", () => {
  assert.deepEqual(partnerSurfaceVisibility({
    status: "listed",
    category: "Wellness",
    swipe_eligible: true,
  }), { swipeVisible: false, localVisible: false });

  assert.deepEqual(partnerSurfaceVisibility({
    status: "approved",
    category: "Wellness",
    swipe_eligible: false,
  }), { swipeVisible: false, localVisible: false });

  assert.equal(partnerSurfaceVisibility({
    status: "live",
    category: "Wellness",
    swipe_eligible: true,
  }).swipeVisible, true);
});

test("Wave 1 visibility requires destination consent and attributable Local routing", () => {
  const partner = {
    id: partnerId,
    status: "live",
    category: "PrivateChef",
    categories: ["PrivateChef"],
    swipe_eligible: true,
    local_eligible: true,
    local_lane: "chef",
    primary_cta_destination: "local",
    primary_cta_path: `/chef/match?swipePartnerId=${partnerId}&service=private_chef`,
  };

  assert.deepEqual(partnerSurfaceVisibility(partner, {
    publication_destinations: [],
  }), { swipeVisible: false, localVisible: false });

  assert.deepEqual(partnerSurfaceVisibility(partner, {
    publication_destinations: ["heha_swipe", "heha_local"],
  }), { swipeVisible: true, localVisible: true });

  assert.equal(partnerSurfaceVisibility({
    ...partner,
    primary_cta_path: "/chef/match",
  }, {
    publication_destinations: ["heha_local"],
  }).localVisible, false);
});
