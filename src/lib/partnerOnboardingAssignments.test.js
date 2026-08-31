import test from "node:test";
import assert from "node:assert/strict";
import {
  groupPartnerOnboardingAssignments,
  normalizePartnerOnboardingAssignments,
} from "./partnerOnboardingAssignments.js";

const actorId = "00000000-0000-4000-8000-000000000001";
const partnerId = "00000000-0000-4000-8000-000000000002";

function envelope(assignments, overrides = {}) {
  return {
    projection_version: "heha-partner-assignments-v1",
    authorized_actor_id: actorId,
    assignments,
    ...overrides,
  };
}

test("validates and groups deterministic operator/signer assignments without raw partner access", () => {
  const rows = [
    { partner_id: partnerId, role: "authorized_signer", display_name: "Pure Kitchen", private_profile_status: "pending" },
    { partner_id: partnerId, role: "operator", display_name: "Pure Kitchen", private_profile_status: "pending" },
  ];
  const normalized = normalizePartnerOnboardingAssignments(envelope(rows), actorId);
  assert.deepEqual(groupPartnerOnboardingAssignments(normalized.assignments), [{
    partner_id: partnerId,
    display_name: "Pure Kitchen",
    private_profile_status: "pending",
    roles: ["authorized_signer", "operator"],
  }]);
});

test("fails closed on actor mismatch, unauthorized role, duplicate, and conflicting rows", () => {
  const signer = { partner_id: partnerId, role: "authorized_signer", display_name: "Pure Kitchen", private_profile_status: "pending" };
  assert.throws(() => normalizePartnerOnboardingAssignments(
    envelope([signer], { authorized_actor_id: partnerId }),
    actorId,
  ));
  assert.throws(() => normalizePartnerOnboardingAssignments(
    envelope([{ ...signer, role: "admin" }]),
    actorId,
  ));
  assert.throws(() => normalizePartnerOnboardingAssignments(envelope([signer, signer]), actorId));
  assert.throws(() => groupPartnerOnboardingAssignments([
    signer,
    { ...signer, role: "operator", display_name: "Different business" },
  ]));
});
