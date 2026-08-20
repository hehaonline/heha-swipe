#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const lineageDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(lineageDir, '..', '..');

function fail(message) {
  throw new Error(message);
}

function readRepoFile(path) {
  return readFileSync(resolve(repoRoot, path));
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        field += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ',') {
      row.push(field);
      field = '';
    } else if (character === '\n') {
      row.push(field.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += character;
    }
  }

  if (quoted) fail('CSV ended inside a quoted field');
  if (field.length > 0 || row.length > 0) {
    row.push(field.replace(/\r$/, ''));
    rows.push(row);
  }
  return rows;
}

function loadLedger(path, expectedEvidence) {
  const rows = parseCsv(readRepoFile(path).toString('utf8'));
  const header = rows.shift();
  if (JSON.stringify(header) !== JSON.stringify(['version', 'name', 'evidence'])) {
    fail(`${path}: unexpected header ${JSON.stringify(header)}`);
  }
  for (const [index, row] of rows.entries()) {
    if (row.length !== 3) fail(`${path}:${index + 2}: expected 3 fields`);
    if (!/^\d{14}$/.test(row[0])) fail(`${path}:${index + 2}: invalid version`);
    if (!row[1]) fail(`${path}:${index + 2}: empty migration name`);
    if (row[2] !== expectedEvidence) {
      fail(`${path}:${index + 2}: expected evidence ${expectedEvidence}`);
    }
  }
  return rows.map(([version, name, evidence]) => ({ version, name, evidence }));
}

function assertStrictlySorted(rows, label) {
  for (let index = 1; index < rows.length; index += 1) {
    if (rows[index - 1].version >= rows[index].version) {
      fail(`${label}: versions are not strictly sorted at ${rows[index].version}`);
    }
  }
}

function assertManifest() {
  const manifestPath = 'docs/migration-lineage/evidence-manifest.sha256';
  const lines = readRepoFile(manifestPath).toString('utf8').trim().split(/\r?\n/);
  const seen = new Set();
  for (const [index, line] of lines.entries()) {
    const match = /^([a-f0-9]{64})  (.+)$/.exec(line);
    if (!match) fail(`${manifestPath}:${index + 1}: malformed entry`);
    const [, expected, path] = match;
    if (seen.has(path)) fail(`${manifestPath}:${index + 1}: duplicate path ${path}`);
    seen.add(path);
    const actual = sha256(readRepoFile(path));
    if (actual !== expected) fail(`${path}: SHA-256 mismatch (${actual})`);
  }
  return seen.size;
}

const historical = loadLedger(
  'docs/migration-lineage/live-ledger-2026-07-19.csv',
  'U'
);
const current = loadLedger(
  'docs/migration-lineage/live-ledger-2026-08-19.csv',
  'LP'
);

if (historical.length !== 92) fail(`historical ledger: expected 92 rows, got ${historical.length}`);
if (current.length !== 96) fail(`current ledger: expected 96 rows, got ${current.length}`);
if (new Set(historical.map((row) => row.version)).size !== 92) fail('historical ledger: duplicate version');
if (new Set(current.map((row) => row.version)).size !== 96) fail('current ledger: duplicate version');
assertStrictlySorted(historical, 'historical ledger');
assertStrictlySorted(current, 'current ledger');

if (current[0].version !== '20260531101429') fail('current ledger: unexpected first version');
if (current.at(-1).version !== '20260812220624') fail('current ledger: unexpected last version');

const duplicateNames = new Map();
for (const row of current) {
  const versions = duplicateNames.get(row.name) ?? [];
  versions.push(row.version);
  duplicateNames.set(row.name, versions);
}
const duplicates = [...duplicateNames.entries()].filter(([, versions]) => versions.length > 1);
const expectedDuplicate = [
  'analytics_triggers_for_partner_counters',
  ['20260602213920', '20260602220224']
];
if (JSON.stringify(duplicates) !== JSON.stringify([expectedDuplicate])) {
  fail(`current ledger: unexpected duplicate names ${JSON.stringify(duplicates)}`);
}

const historicalVersions = new Set(historical.map((row) => row.version));
const delta = current
  .filter((row) => !historicalVersions.has(row.version))
  .map(({ version, name }) => [version, name]);
const expectedDelta = [
  ['20260720132527', 'partner_multi_categories'],
  ['20260720132617', 'partner_multi_categories_view_security_invoker'],
  ['20260805123842', 'sec002_revoke_public_execute_on_trigger_functions'],
  ['20260812220624', 'update_founding_neighbor_pass_preferences']
];
if (JSON.stringify(delta) !== JSON.stringify(expectedDelta)) {
  fail(`ledger delta: unexpected rows ${JSON.stringify(delta)}`);
}

const manifestEntries = assertManifest();

console.log(JSON.stringify({
  status: 'PASS',
  boundary: 'repository-consistency-only',
  currentLedger: {
    rows: current.length,
    distinctVersions: new Set(current.map((row) => row.version)).size,
    firstVersion: current[0].version,
    lastVersion: current.at(-1).version,
    duplicateNames: Object.fromEntries(duplicates),
    deltaFromHistorical: delta
  },
  historicalLedger: {
    rows: historical.length,
    distinctVersions: new Set(historical.map((row) => row.version)).size
  },
  manifestEntries,
  blocked: [
    'independent live-source provenance until a new authorized capture is committed',
    'PR #69 semantic catalog equality until sanitized live and recovered-source artifacts pass verify-pr69-catalog.mjs'
  ]
}, null, 2));
