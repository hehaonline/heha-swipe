import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const ledgerUrl = new URL(
  "../../docs/store-release/EXTERNAL_CONSUMER_CERTIFICATION.md",
  import.meta.url,
);

test("external consumer ledger is explicit and fail-closed", async () => {
  const ledger = await readFile(ledgerUrl, "utf8");

  for (const heading of [
    "Accountable owner",
    "Current status",
    "Evidence",
    "Last-use evidence",
    "Phase A certification",
    "Phase B certification",
    "Pricing certification",
    "Pricing smoke evidence",
  ]) {
    assert.match(ledger, new RegExp(heading));
  }

  const expectedConsumers = [
    "HEHA Swipe store-card reader",
    "HEHA website partner-directory embed",
    "HEHA Swipe authenticated owner/internal UI",
    "HEHA HubSpot sync edge function",
    "HEHA Local",
    "Wix",
    "Make",
    "Other external or non-code consumers",
  ];

  assert.match(ledger, /no consumer is presumed certified/i);
  assert.match(ledger, /repository-search absence (?:are|is) not evidence of non-use/i);

  const inventoryRows = ledger
    .split("\n")
    .filter((line) => line.startsWith("| "))
    .filter((line) => !line.includes("Consumer / surface"))
    .filter((line) => !line.includes("---"));

  assert.equal(inventoryRows.length, 8);
  const header = ledger
    .split("\n")
    .find((line) => line.startsWith("| Consumer / surface"))
    .split("|")
    .slice(1, -1)
    .map((cell) => cell.trim());
  const phaseBIndex = header.indexOf("Phase B certification");
  const phaseAIndex = header.indexOf("Phase A certification");
  const pricingIndex = header.indexOf("Pricing certification");

  assert.ok(phaseAIndex >= 0);
  assert.ok(phaseBIndex >= 0);
  assert.ok(pricingIndex >= 0);

  const parsedRows = inventoryRows.map((row) =>
    row
      .split("|")
      .slice(1, -1)
      .map((cell) => cell.trim()),
  );

  assert.deepEqual(
    parsedRows.map((cells) => cells[0]),
    expectedConsumers,
  );

  for (const cells of parsedRows) {
    assert.equal(cells.length, header.length);
    assert.match(cells[phaseAIndex], /^(?:NOT CERTIFIED|N\/A)\b/);
    if (cells[phaseAIndex].startsWith("N/A")) {
      assert.match(cells[phaseAIndex], /^N\/A — \S/);
    }
    assert.match(cells[phaseBIndex], /^NOT CERTIFIED\b/);
    assert.match(cells[pricingIndex], /^NOT CERTIFIED\b/);
  }
});
