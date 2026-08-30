import test from "node:test";
import assert from "node:assert/strict";
import {
  hasSpecificHehaLocalDestination,
  isApprovedHehaLocalInstallConfiguration,
  isHehaLocalPartner,
} from "./hehaLocalRouting.js";

test("generic Local lane pages never count as partner-specific order paths", () => {
  for (const path of [
    "/",
    "/restaurants",
    "/vendors",
    "/market",
    "/chef",
    "/group-orders",
  ]) {
    assert.equal(hasSpecificHehaLocalDestination({ primary_cta_path: path }), false, path);
  }
});

test("Local install configuration fails closed unless the explicit approved HTTPS origin is present", () => {
  assert.equal(isApprovedHehaLocalInstallConfiguration({ enabled: false, configuredUrl: "https://hehalocal.app" }), false);
  assert.equal(isApprovedHehaLocalInstallConfiguration({ enabled: true, configuredUrl: "" }), false);
  assert.equal(isApprovedHehaLocalInstallConfiguration({ enabled: true, configuredUrl: "http://hehalocal.app" }), false);
  assert.equal(isApprovedHehaLocalInstallConfiguration({ enabled: true, configuredUrl: "https://attacker.example" }), false);
  assert.equal(isApprovedHehaLocalInstallConfiguration({ enabled: true, configuredUrl: "https://hehalocal.app/preview" }), false);
  assert.equal(isApprovedHehaLocalInstallConfiguration({ enabled: true, configuredUrl: "https://hehalocal.app" }), true);
});

test("specific Local profile paths remain eligible", () => {
  const partner = {
    id: "synthetic-partner",
    local_eligible: true,
    primary_cta_destination: "local",
    primary_cta_path: "/restaurants/00000000-0000-4000-8000-000000000001",
  };
  assert.equal(hasSpecificHehaLocalDestination(partner), true);
  assert.equal(isHehaLocalPartner(partner), true);
});

test("arbitrary, admin, query-only, and malformed paths never count as a Local profile", () => {
  for (const path of [
    "/?partner=synthetic",
    "/admin",
    "/restaurants?partner=synthetic",
    "/restaurants/not-a-uuid",
    "/restaurants/00000000-0000-4000-8000-000000000001?preview=1",
    "https://attacker.example/restaurants/00000000-0000-4000-8000-000000000001",
  ]) {
    assert.equal(hasSpecificHehaLocalDestination({ primary_cta_path: path }), false, path);
  }
});

test("routing stays fail closed without Local eligibility and destination", () => {
  assert.equal(isHehaLocalPartner({ primary_cta_path: "/restaurants/specific" }), false);
  assert.equal(isHehaLocalPartner({ local_eligible: true, primary_cta_path: "/restaurants/specific" }), false);
});
