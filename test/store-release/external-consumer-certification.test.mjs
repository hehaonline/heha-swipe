import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const ledgerUrl = new URL(
  "../../docs/store-release/EXTERNAL_CONSUMER_CERTIFICATION.md",
  import.meta.url,
);

test("external consumer ledger is explicit and fail-closed", async () => {
  const ledger = await readFile(ledgerUrl, "utf8");
  const expectedHeader = [
    "Consumer / surface",
    "Operating entity / account",
    "Environment",
    "Credential class",
    "Accountable owner",
    "Current status",
    "Evidence",
    "Last-use evidence",
    "Phase A certification",
    "Phase B certification",
    "Pricing certification",
    "Pricing smoke evidence",
  ];

  const expectedConsumers = [
    "HEHA Swipe store-card reader",
    "HEHA website directory data caller",
    "HEHA Swipe owner self-service",
    "HEHA Swipe internal routing UI",
    "HEHA HubSpot sync edge function",
    "HEHA Local",
    "Wix site shell and direct integrations",
    "Make scenarios",
    "Other external or non-code consumers",
  ];
  const expectedPhaseAStarts = new Map([
    ["HEHA Swipe store-card reader", "NOT CERTIFIED"],
    ["HEHA website directory data caller", "NOT CERTIFIED"],
    ["HEHA Swipe owner self-service", "N/A"],
    ["HEHA Swipe internal routing UI", "N/A"],
    ["HEHA HubSpot sync edge function", "N/A"],
    ["HEHA Local", "N/A"],
    ["Wix site shell and direct integrations", "N/A"],
    ["Make scenarios", "N/A"],
    ["Other external or non-code consumers", "N/A"],
  ]);

  assert.match(ledger, /no consumer is presumed certified/i);
  assert.match(ledger, /repository-search absence (?:are|is) not evidence of non-use/i);

  const inventoryMarker = "## Inventory\n\n";
  const inventoryParts = ledger.split(inventoryMarker);
  assert.equal(inventoryParts.length, 2);
  const tableBlock = inventoryParts[1].split("\n\n## ")[0];
  const tableLines = tableBlock.trim().split("\n");
  assert.equal(tableLines.length, expectedConsumers.length + 2);

  const parseCanonicalRow = (line) => {
    assert.match(line, /^\| .* \|$/);
    assert.doesNotMatch(line, /\\\|/);
    const cells = line.slice(2, -2).split(" | ");
    assert.equal(cells.length, expectedHeader.length);
    for (const cell of cells) {
      assert.ok(cell.length > 0);
      assert.doesNotMatch(cell, /\|/);
    }
    return cells;
  };

  const header = parseCanonicalRow(tableLines[0]);
  assert.deepEqual(header, expectedHeader);
  assert.equal(
    tableLines[1],
    `| ${expectedHeader.map(() => "---").join(" | ")} |`,
  );

  const parsedRows = tableLines.slice(2).map(parseCanonicalRow);
  const phaseBIndex = header.indexOf("Phase B certification");
  const phaseAIndex = header.indexOf("Phase A certification");
  const pricingIndex = header.indexOf("Pricing certification");
  const entityIndex = header.indexOf("Operating entity / account");

  assert.ok(phaseAIndex >= 0);
  assert.ok(phaseBIndex >= 0);
  assert.ok(pricingIndex >= 0);
  assert.ok(entityIndex >= 0);

  assert.deepEqual(
    parsedRows.map((cells) => cells[0]),
    expectedConsumers,
  );

  for (const cells of parsedRows) {
    const consumer = cells[0];
    const phaseAStart = expectedPhaseAStarts.get(consumer);
    assert.match(cells[entityIndex], /^Healthy Habit LLC\b/);
    assert.match(cells[phaseAIndex], new RegExp(`^${phaseAStart} — \\S`));
    assert.match(cells[phaseBIndex], /^NOT CERTIFIED\b/);
    assert.match(cells[pricingIndex], /^NOT CERTIFIED\b/);
  }
});
