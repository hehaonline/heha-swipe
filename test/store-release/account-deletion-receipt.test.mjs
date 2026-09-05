import assert from "node:assert/strict";
import test from "node:test";
import { validateAccountDeletionReceipt } from "../../src/lib/accountDeletionReceipt.js";

const validReceipt = {
  status: "requested",
  request_id: "c21fcbe1-6685-44be-b7fc-c07aac638a8b",
  requested_at: "2026-08-31T12:00:00.000Z",
};

test("deletion receipt validator accepts an explicit complete receipt", () => {
  assert.deepEqual(validateAccountDeletionReceipt([validReceipt]), {
    status: "requested",
    requestId: validReceipt.request_id,
    requestedAt: validReceipt.requested_at,
  });
  assert.equal(
    validateAccountDeletionReceipt({ ...validReceipt, status: "already_requested" }).status,
    "already_requested"
  );
});

test("deletion receipt validator fails closed on malformed responses", () => {
  const malformed = [
    null,
    [],
    [validReceipt, validReceipt],
    {},
    { ...validReceipt, status: undefined },
    { ...validReceipt, status: "complete" },
    { ...validReceipt, request_id: "" },
    { ...validReceipt, requested_at: "not-a-timestamp" },
  ];

  for (const receipt of malformed) {
    assert.throws(
      () => validateAccountDeletionReceipt(receipt),
      /unexpected result/i
    );
  }
});
