const INVALID_RECEIPT_MESSAGE =
  "The deletion service returned an unexpected result. Please contact HEHA support.";

function invalidReceipt() {
  return new Error(INVALID_RECEIPT_MESSAGE);
}

export function validateAccountDeletionReceipt(data) {
  if (Array.isArray(data) && data.length !== 1) throw invalidReceipt();

  const result = Array.isArray(data) ? data[0] : data;
  if (!result || typeof result !== "object" || Array.isArray(result)) throw invalidReceipt();

  const { status, request_id: requestId, requested_at: requestedAt } = result;
  if (status !== "requested" && status !== "already_requested") throw invalidReceipt();
  if (typeof requestId !== "string" || !requestId.trim()) throw invalidReceipt();
  if (
    typeof requestedAt !== "string"
    || !requestedAt.trim()
    || !Number.isFinite(Date.parse(requestedAt))
  ) {
    throw invalidReceipt();
  }

  return {
    status,
    requestId: requestId.trim(),
    requestedAt: requestedAt.trim(),
  };
}
