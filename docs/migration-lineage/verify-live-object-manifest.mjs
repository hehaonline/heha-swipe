#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const EXPECTED = Object.freeze({
  counts: Object.freeze({
    extension: 6,
    function: 39,
    policy: 133,
    table: 45,
    trigger: 46,
    view: 5
  }),
  rlsEnabled: 45,
  rlsForced: 0,
  materializedViews: 0
});

const METADATA_KEYS = Object.freeze({
  extension: ['version'],
  function: ['language', 'owner', 'parallel', 'return_type', 'security_definer', 'volatility'],
  policy: ['command', 'permissive', 'roles'],
  table: ['owner', 'relation_kind', 'rls_enabled', 'rls_forced'],
  trigger: ['constraint', 'enabled', 'function_identity', 'trigger_type'],
  view: ['owner', 'relation_kind']
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

function parseJsonLines(bytes) {
  const text = bytes.toString('utf8');
  if (text.includes('\r')) fail('artifact: CR bytes are not allowed; preserve LF output');
  const lines = text.split('\n');
  if (lines.at(-1) === '') lines.pop();
  if (lines.length === 0) fail('artifact: no rows');
  return lines.map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      fail(`artifact:${index + 1}: invalid JSON (${error.message})`);
    }
  });
}

function validateMetadata(row, index) {
  const label = `artifact:${index + 1}:${row.record_type}`;
  assertExactKeys(row.metadata, METADATA_KEYS[row.record_type], `${label}:metadata`);

  switch (row.record_type) {
    case 'table':
      assertText(row.metadata.owner, `${label}:owner`);
      if (!['ordinary', 'partitioned'].includes(row.metadata.relation_kind)) {
        fail(`${label}: invalid relation_kind`);
      }
      if (typeof row.metadata.rls_enabled !== 'boolean' || typeof row.metadata.rls_forced !== 'boolean') {
        fail(`${label}: RLS fields must be boolean`);
      }
      break;
    case 'view':
      assertText(row.metadata.owner, `${label}:owner`);
      if (!['view', 'materialized_view'].includes(row.metadata.relation_kind)) {
        fail(`${label}: invalid relation_kind`);
      }
      break;
    case 'function':
      for (const key of ['owner', 'language', 'volatility', 'parallel', 'return_type']) {
        assertText(row.metadata[key], `${label}:${key}`);
      }
      if (typeof row.metadata.security_definer !== 'boolean') {
        fail(`${label}: security_definer must be boolean`);
      }
      break;
    case 'trigger':
      assertText(row.metadata.enabled, `${label}:enabled`);
      assertText(row.metadata.function_identity, `${label}:function_identity`);
      if (!Number.isInteger(row.metadata.trigger_type) || row.metadata.trigger_type < 0) {
        fail(`${label}: trigger_type must be a non-negative integer`);
      }
      if (typeof row.metadata.constraint !== 'boolean') fail(`${label}: constraint must be boolean`);
      break;
    case 'policy':
      assertText(row.metadata.command, `${label}:command`);
      assertText(row.metadata.permissive, `${label}:permissive`);
      if (!Array.isArray(row.metadata.roles) || row.metadata.roles.some((role) => typeof role !== 'string')) {
        fail(`${label}: roles must be a text array`);
      }
      break;
    case 'extension':
      assertText(row.metadata.version, `${label}:version`);
      break;
    default:
      fail(`${label}: unsupported record type`);
  }
}

function rowSortKey(row) {
  return [row.record_type, row.schema, row.identity, JSON.stringify(row.metadata)].join('\u0000');
}

function verifyRows(rows, expected) {
  const counts = Object.fromEntries(Object.keys(METADATA_KEYS).map((type) => [type, 0]));
  const identities = new Set();
  let previousKey = null;

  rows.forEach((row, index) => {
    assertExactKeys(row, ['record_type', 'schema', 'name', 'identity', 'metadata'], `artifact:${index + 1}`);
    if (!(row.record_type in METADATA_KEYS)) fail(`artifact:${index + 1}: unknown record_type`);
    for (const key of ['schema', 'name', 'identity']) assertText(row[key], `artifact:${index + 1}:${key}`);
    validateMetadata(row, index);

    const sortKey = rowSortKey(row);
    if (previousKey !== null && previousKey >= sortKey) {
      fail(`artifact:${index + 1}: rows are not strictly C-order sorted or identity is duplicated`);
    }
    previousKey = sortKey;

    const identityKey = `${row.record_type}\u0000${row.identity}`;
    if (identities.has(identityKey)) fail(`artifact:${index + 1}: duplicate identity ${row.identity}`);
    identities.add(identityKey);
    counts[row.record_type] += 1;
  });

  if (JSON.stringify(counts) !== JSON.stringify(expected.counts)) {
    fail(`artifact: count mismatch ${JSON.stringify(counts)}; expected ${JSON.stringify(expected.counts)}`);
  }

  const tables = rows.filter((row) => row.record_type === 'table');
  const rlsEnabled = tables.filter((row) => row.metadata.rls_enabled).length;
  const rlsForced = tables.filter((row) => row.metadata.rls_forced).length;
  const materializedViews = rows.filter(
    (row) => row.record_type === 'view' && row.metadata.relation_kind === 'materialized_view'
  ).length;

  if (rlsEnabled !== expected.rlsEnabled) fail(`artifact: expected ${expected.rlsEnabled} RLS-enabled tables, got ${rlsEnabled}`);
  if (rlsForced !== expected.rlsForced) fail(`artifact: expected ${expected.rlsForced} FORCE-RLS tables, got ${rlsForced}`);
  if (materializedViews !== expected.materializedViews) {
    fail(`artifact: expected ${expected.materializedViews} materialized views, got ${materializedViews}`);
  }

  return { counts, rlsEnabled, rlsForced, materializedViews };
}

function syntheticRows() {
  const rows = [
    { record_type: 'extension', schema: 'extensions', name: 'example', identity: 'example', metadata: { version: '1.0' } },
    { record_type: 'function', schema: 'public', name: 'example', identity: 'public.example()', metadata: { language: 'sql', owner: 'postgres', parallel: 'u', return_type: 'integer', security_definer: false, volatility: 'v' } },
    { record_type: 'policy', schema: 'public', name: 'example', identity: 'public.example.example', metadata: { command: 'SELECT', permissive: 'PERMISSIVE', roles: ['authenticated'] } },
    { record_type: 'table', schema: 'public', name: 'example', identity: 'public.example', metadata: { owner: 'postgres', relation_kind: 'ordinary', rls_enabled: true, rls_forced: false } },
    { record_type: 'trigger', schema: 'public', name: 'example', identity: 'public.example.example', metadata: { constraint: false, enabled: 'O', function_identity: 'public.example()', trigger_type: 5 } },
    { record_type: 'view', schema: 'public', name: 'example', identity: 'public.example', metadata: { owner: 'postgres', relation_kind: 'view' } }
  ];
  return rows.sort((left, right) => (rowSortKey(left) < rowSortKey(right) ? -1 : 1));
}

if (process.argv[2] === '--self-test') {
  const counts = Object.fromEntries(Object.keys(METADATA_KEYS).map((type) => [type, 1]));
  const bytes = Buffer.from(`${syntheticRows().map((row) => JSON.stringify(row)).join('\n')}\n`, 'utf8');
  const result = verifyRows(parseJsonLines(bytes), { counts, rlsEnabled: 1, rlsForced: 0, materializedViews: 0 });
  console.log(JSON.stringify({ status: 'PASS', boundary: 'synthetic-verifier-only', ...result }, null, 2));
} else {
  const artifactPath = process.argv[2];
  if (!artifactPath || process.argv.length !== 3) {
    fail('usage: node verify-live-object-manifest.mjs <sanitized.jsonl> | --self-test');
  }
  const bytes = readFileSync(artifactPath);
  const rows = parseJsonLines(bytes);
  const result = verifyRows(rows, EXPECTED);
  console.log(JSON.stringify({
    status: 'PASS',
    boundary: 'sanitized-catalog-artifact-only',
    artifact: artifactPath,
    sha256: createHash('sha256').update(bytes).digest('hex'),
    ...result
  }, null, 2));
}
