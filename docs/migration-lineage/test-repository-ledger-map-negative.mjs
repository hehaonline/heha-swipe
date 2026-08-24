#!/usr/bin/env node

import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const SOURCE_ROOT = process.cwd();
const MANIFEST = 'docs/migration-lineage/repository-ledger-map-manifest.sha256';
const LIVE_MAP = 'docs/migration-lineage/live-ledger-compatibility-map-2026-08-24.csv';
const REPOSITORY_MAP =
  'docs/migration-lineage/repository-migration-disposition-map-2026-08-24.csv';

function fail(message) {
  throw new Error(message);
}

function parseCsv(text, label) {
  const records = [];
  let record = [];
  let field = '';
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"') {
        if (text[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        field += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ',') {
      record.push(field);
      field = '';
    } else if (character === '\n') {
      record.push(field);
      field = '';
      if (record.some((value) => value.length > 0)) records.push(record);
      record = [];
    } else if (character !== '\r') {
      field += character;
    }
  }
  if (quoted) fail(`${label}: unterminated quoted field`);
  if (field || record.length) {
    record.push(field);
    records.push(record);
  }
  const header = records.shift();
  return {
    header,
    rows: records.map((values) =>
      Object.fromEntries(header.map((column, index) => [column, values[index]]))
    )
  };
}

function serializeCsv({ header, rows }) {
  const encode = (value) => {
    const text = String(value ?? '');
    return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
  };
  return `${[header, ...rows.map((row) => header.map((column) => row[column]))]
    .map((record) => record.map(encode).join(','))
    .join('\n')}\n`;
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function manifestEntries(root) {
  return readFileSync(join(root, MANIFEST), 'utf8')
    .trim()
    .split('\n')
    .map((line) => {
      const match = line.match(/^([0-9a-f]{64})  (.+)$/);
      if (!match) fail(`invalid manifest line: ${line}`);
      return { digest: match[1], path: match[2] };
    });
}

function refreshManifest(root) {
  const contents = manifestEntries(root)
    .map(({ path }) => `${sha256(join(root, path))}  ${path}`)
    .join('\n');
  writeFileSync(join(root, MANIFEST), `${contents}\n`);
}

function verifyManifest(root) {
  for (const entry of manifestEntries(root)) {
    const actual = sha256(join(root, entry.path));
    if (actual !== entry.digest) {
      fail(`fixture hash mismatch for ${entry.path}`);
    }
  }
}

function copyFixture(root) {
  mkdirSync(root, { recursive: true });
  mkdirSync(join(root, 'supabase/migrations'), { recursive: true });

  for (const entry of manifestEntries(SOURCE_ROOT)) {
    const destination = join(root, entry.path);
    mkdirSync(dirname(destination), { recursive: true });
    copyFileSync(join(SOURCE_ROOT, entry.path), destination);
  }
  mkdirSync(dirname(join(root, MANIFEST)), { recursive: true });
  copyFileSync(join(SOURCE_ROOT, MANIFEST), join(root, MANIFEST));

  for (const relativePath of [
    'docs/migration-lineage/live-ledger-2026-08-19.csv',
    'docs/migration-lineage/repository-inventory.csv'
  ]) {
    const destination = join(root, relativePath);
    mkdirSync(dirname(destination), { recursive: true });
    copyFileSync(join(SOURCE_ROOT, relativePath), destination);
  }

  for (const name of readdirSync(join(SOURCE_ROOT, 'supabase/migrations'))) {
    if (name.endsWith('.sql')) writeFileSync(join(root, 'supabase/migrations', name), '');
  }
}

function mutateCsv(root, relativePath, mutate) {
  const absolutePath = join(root, relativePath);
  const csv = parseCsv(readFileSync(absolutePath, 'utf8'), relativePath);
  mutate(csv.rows);
  writeFileSync(absolutePath, serializeCsv(csv));
}

function rowBy(rows, field, value) {
  const row = rows.find((candidate) => candidate[field] === value);
  if (!row) fail(`fixture row not found: ${field}=${value}`);
  return row;
}

function swapClasses(rows, firstVersion, secondVersion) {
  const first = rowBy(rows, 'live_version', firstVersion);
  const second = rowBy(rows, 'live_version', secondVersion);
  [first.class, second.class] = [second.class, first.class];
}

const fixtures = [
  {
    name: 'aggregate-preserving B/C swap',
    expected: /class C requires a repository candidate/,
    mutate(root) {
      mutateCsv(root, LIVE_MAP, (rows) =>
        swapClasses(rows, '20260531101429', '20260619004758')
      );
    }
  },
  {
    name: 'aggregate-preserving A/C swap',
    expected: /recovered supporter archive contract changed/,
    mutate(root) {
      mutateCsv(root, LIVE_MAP, (rows) =>
        swapClasses(rows, '20260614102924', '20260619004758')
      );
    }
  },
  {
    name: 'aggregate-preserving D/C swap',
    expected: /exact duplicate-name\/version contract changed/,
    mutate(root) {
      mutateCsv(root, LIVE_MAP, (rows) =>
        swapClasses(rows, '20260602213920', '20260619004758')
      );
    }
  },
  {
    name: 'invalid N candidate name',
    expected: /class N candidate must preserve the migration name/,
    mutate(root) {
      mutateCsv(root, LIVE_MAP, (rows) => {
        rowBy(rows, 'live_version', '20260618174049').repository_candidates =
          'supabase/migrations/20260618000200_admin_review_fixes_summary.sql';
      });
    }
  },
  {
    name: 'swapped repository paths',
    expected: /repository map vs inventory: key mismatch/,
    mutate(root) {
      mutateCsv(root, REPOSITORY_MAP, (rows) => {
        [rows[0].repository_path, rows[1].repository_path] = [
          rows[1].repository_path,
          rows[0].repository_path
        ];
      });
    }
  },
  {
    name: 'missing reverse edge',
    expected: /missing reverse edge/,
    mutate(root) {
      mutateCsv(root, REPOSITORY_MAP, (rows) => {
        rowBy(
          rows,
          'repository_path',
          'supabase/migrations/20260618000100_nina_community_events_tables.sql'
        ).live_candidates = '';
      });
    }
  }
];

const results = [];
for (const fixture of fixtures) {
  const root = mkdtempSync(join(tmpdir(), 'swp-016-negative-'));
  try {
    copyFixture(root);
    fixture.mutate(root);
    refreshManifest(root);
    verifyManifest(root);

    const result = spawnSync(
      process.execPath,
      ['docs/migration-lineage/verify-repository-ledger-map.mjs'],
      { cwd: root, encoding: 'utf8' }
    );
    const output = `${result.stdout}\n${result.stderr}`;
    if (result.status === 0) fail(`${fixture.name}: semantic verifier unexpectedly passed`);
    if (!fixture.expected.test(output)) {
      fail(`${fixture.name}: verifier failed for an unexpected reason:\n${output}`);
    }
    results.push(fixture.name);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

console.log(
  JSON.stringify(
    {
      status: 'PASS',
      boundary: 'aggregate-preserving-and-edge-corruption-negative-controls',
      rejected_fixtures: results
    },
    null,
    2
  )
);
