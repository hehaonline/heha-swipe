#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const EXPECTED_COUNTS = Object.freeze({
  column: 41,
  constraint: 15,
  function: 1,
  index: 12,
  policy: 5,
  rls_state: 3,
  trigger: 3
});

function fail(message) {
  throw new Error(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function assertExactKeys(value, expected, label) {
  if (!isPlainObject(value)) fail(`${label}: expected an object`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    fail(`${label}: unexpected keys ${JSON.stringify(actual)}; expected ${JSON.stringify(wanted)}`);
  }
}

function assertText(value, label) {
  if (typeof value !== 'string' || value.length === 0 || /[\u0000-\u001f]/u.test(value)) {
    fail(`${label}: expected non-empty single-line text`);
  }
}

function parseJsonLines(bytes, label) {
  const text = bytes.toString('utf8');
  if (text.includes('\r')) fail(`${label}: CR bytes are not allowed; preserve LF output`);
  const lines = text.split('\n');
  if (lines.at(-1) === '') lines.pop();
  if (lines.length === 0) fail(`${label}: no rows`);
  return lines.map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      fail(`${label}:${index + 1}: invalid JSON (${error.message})`);
    }
  });
}

function rowKey(row) {
  return [row.record_type, row.object_identity, String(row.ordinal), JSON.stringify(row.metadata)].join('\u0000');
}

function verifyRows(rows, expectedCounts, label) {
  const counts = Object.fromEntries(Object.keys(EXPECTED_COUNTS).map((type) => [type, 0]));
  let previous = null;

  rows.forEach((row, index) => {
    assertExactKeys(row, ['record_type', 'object_identity', 'ordinal', 'metadata'], `${label}:${index + 1}`);
    if (!(row.record_type in EXPECTED_COUNTS)) fail(`${label}:${index + 1}: unsupported record_type`);
    assertText(row.object_identity, `${label}:${index + 1}:object_identity`);
    if (!Number.isInteger(row.ordinal) || row.ordinal < 0) fail(`${label}:${index + 1}: invalid ordinal`);
    if (!isPlainObject(row.metadata)) fail(`${label}:${index + 1}: metadata must be an object`);

    const key = rowKey(row);
    if (previous !== null && previous >= key) {
      fail(`${label}:${index + 1}: rows are not strictly C-order sorted or are duplicated`);
    }
    previous = key;
    counts[row.record_type] += 1;
  });

  if (JSON.stringify(counts) !== JSON.stringify(expectedCounts)) {
    fail(`${label}: count mismatch ${JSON.stringify(counts)}; expected ${JSON.stringify(expectedCounts)}`);
  }
  return counts;
}

function digest(bytes, algorithm) {
  return createHash(algorithm).update(bytes).digest('hex');
}

function syntheticRows() {
  return Object.keys(EXPECTED_COUNTS)
    .map((recordType, index) => ({
      record_type: recordType,
      object_identity: `public.synthetic_${recordType}`,
      ordinal: index,
      metadata: { synthetic: true }
    }))
    .sort((left, right) => (rowKey(left) < rowKey(right) ? -1 : 1));
}

function encodeRows(rows) {
  return Buffer.from(`${rows.map((row) => JSON.stringify(row)).join('\n')}\n`, 'utf8');
}

function compareArtifacts(liveBytes, sourceBytes, expectedCounts) {
  const liveRows = parseJsonLines(liveBytes, 'live-artifact');
  const sourceRows = parseJsonLines(sourceBytes, 'source-artifact');
  const liveCounts = verifyRows(liveRows, expectedCounts, 'live-artifact');
  const sourceCounts = verifyRows(sourceRows, expectedCounts, 'source-artifact');
  if (!liveBytes.equals(sourceBytes)) {
    const firstMismatch = liveRows.findIndex(
      (row, index) => JSON.stringify(row) !== JSON.stringify(sourceRows[index])
    );
    fail(`normalized artifacts differ; first row mismatch index ${firstMismatch}`);
  }
  return {
    counts: liveCounts,
    sourceCounts,
    sha256: digest(liveBytes, 'sha256'),
    md5: digest(liveBytes, 'md5'),
    rows: liveRows.length
  };
}

if (process.argv[2] === '--self-test') {
  const rows = syntheticRows();
  const counts = Object.fromEntries(Object.keys(EXPECTED_COUNTS).map((type) => [type, 1]));
  const bytes = encodeRows(rows);
  const result = compareArtifacts(bytes, Buffer.from(bytes), counts);
  const changedRows = structuredClone(rows);
  changedRows[0].metadata.synthetic = false;
  let mismatchRejected = false;
  try {
    compareArtifacts(bytes, encodeRows(changedRows), counts);
  } catch {
    mismatchRejected = true;
  }
  if (!mismatchRejected) fail('self-test: unequal normalized artifacts were accepted');
  console.log(JSON.stringify({
    status: 'PASS',
    boundary: 'synthetic-comparator-only',
    comparison: 'exact-normalized-row-equality',
    mismatchNegativeControl: 'PASS',
    ...result
  }, null, 2));
} else {
  if (process.argv.length !== 4) {
    fail('usage: node verify-pr69-catalog.mjs <sanitized-live.jsonl> <recovered-source.jsonl> | --self-test');
  }
  const livePath = process.argv[2];
  const sourcePath = process.argv[3];
  const liveBytes = readFileSync(livePath);
  const sourceBytes = readFileSync(sourcePath);
  const result = compareArtifacts(liveBytes, sourceBytes, EXPECTED_COUNTS);
  console.log(JSON.stringify({
    status: 'PASS',
    boundary: 'two-sanitized-catalog-artifacts-only',
    comparison: 'exact-normalized-row-equality',
    liveArtifact: livePath,
    sourceArtifact: sourcePath,
    ...result
  }, null, 2));
}
