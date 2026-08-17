import assert from "node:assert/strict";
import test from "node:test";

import {
  hasSpecificHehaLocalDestination,
  partnerLocalRequestCopy,
  partnerOrderLabel,
} from "./hehaLocalRouting.js";

const partnerId = "9d21cdb5-8f85-4c0b-a98a-cc835eac20f2";

test("generic chef and catering routes are not partner-specific", () => {
  assert.equal(hasSpecificHehaLocalDestination({ primary_cta_path: "/chef" }), false);
  assert.equal(hasSpecificHehaLocalDestination({ primary_cta_path: "/chef/match" }), false);
  assert.equal(hasSpecificHehaLocalDestination({ primary_cta_path: "/group-orders" }), false);
});

test("a direct Local profile route is partner-specific", () => {
  assert.equal(hasSpecificHehaLocalDestination({
    id: partnerId,
    local_lane: "chef",
    primary_cta_path: `/chef/${partnerId}`,
  }), true);
});

test("an attributable chef request route carries Swipe identity and service", () => {
  assert.equal(hasSpecificHehaLocalDestination({
    id: partnerId,
    local_lane: "chef",
    primary_cta_path: `/chef/match?swipePartnerId=${partnerId}&service=private_chef`,
  }), true);
  assert.equal(hasSpecificHehaLocalDestination({
    id: partnerId,
    local_lane: "group_orders",
    primary_cta_path: `/chef/match?swipePartnerId=${partnerId}&service=catering`,
  }), true);
  assert.equal(hasSpecificHehaLocalDestination({
    primary_cta_path: "/chef/match?service=catering",
  }), false);
});

test("chef and catering routes fail closed for the wrong partner or lane", () => {
  const otherId = "06d8be43-f907-4ced-a683-57814cc8ccbf";
  assert.equal(hasSpecificHehaLocalDestination({
    id: partnerId,
    local_lane: "chef",
    primary_cta_path: `/chef/${otherId}`,
  }), false);
  assert.equal(hasSpecificHehaLocalDestination({
    id: partnerId,
    local_lane: "chef",
    primary_cta_path: `/chef/match?swipePartnerId=${partnerId}&service=catering`,
  }), false);
  assert.equal(hasSpecificHehaLocalDestination({
    id: partnerId,
    local_lane: "group_orders",
    primary_cta_path: `/group-orders/${partnerId}`,
  }), true);
});

test("attributable chef and catering routes use request-specific conversion copy", () => {
  const chef = {
    id: partnerId,
    local_eligible: true,
    local_lane: "chef",
    primary_cta_destination: "local",
    primary_cta_path: `/chef/match?swipePartnerId=${partnerId}&service=private_chef`,
  };
  const caterer = {
    ...chef,
    local_lane: "group_orders",
    primary_cta_path: `/chef/match?swipePartnerId=${partnerId}&service=catering`,
  };

  assert.equal(partnerOrderLabel(chef), "Request this chef");
  assert.equal(partnerOrderLabel(caterer), "Request catering quote");
  assert.equal(partnerLocalRequestCopy(chef)?.heading, "Request this chef");
  assert.equal(partnerLocalRequestCopy(caterer)?.heading, "Request catering quote");
});
