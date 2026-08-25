#!/usr/bin/env node

import { readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import { createHash } from 'node:crypto';

const ROOT = process.cwd();

function fail(message) {
  throw new Error(message);
}

function readText(relativePath) {
  return readFileSync(join(ROOT, relativePath), 'utf8');
}

function sha256(relativePath) {
  return createHash('sha256').update(readFileSync(join(ROOT, relativePath))).digest('hex');
}

function parseCsv(text, label) {
  if (text.includes('\r')) fail(`${label}: CR bytes are not allowed`);
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];

    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') {
      if (field.length !== 0) fail(`${label}: unexpected quote`);
      quoted = true;
    } else if (char === ',') {
      row.push(field);
      field = '';
    } else if (char === '\n') {
      row.push(field);
      field = '';
      if (!(row.length === 1 && row[0] === '')) rows.push(row);
      row = [];
    } else {
      field += char;
    }
  }

  if (quoted) fail(`${label}: unterminated quoted field`);
  if (field.length || row.length) {
    row.push(field);
    rows.push(row);
  }
  if (rows.length < 2) fail(`${label}: expected header and data`);

  const header = rows[0];
  if (new Set(header).size !== header.length) fail(`${label}: duplicate header`);
  return rows.slice(1).map((values, index) => {
    if (values.length !== header.length) {
      fail(`${label}:${index + 2}: expected ${header.length} fields, got ${values.length}`);
    }
    return Object.fromEntries(header.map((name, column) => [name, values[column]]));
  });
}

function assertExactKeys(actualRows, expectedRows, keyFn, label) {
  const actual = actualRows.map(keyFn).sort();
  const expected = expectedRows.map(keyFn).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    const actualSet = new Set(actual);
    const expectedSet = new Set(expected);
    const missing = expected.filter((key) => !actualSet.has(key));
    const extra = actual.filter((key) => !expectedSet.has(key));
    fail(`${label}: key mismatch; missing=${JSON.stringify(missing)} extra=${JSON.stringify(extra)}`);
  }
}

function countBy(rows, key) {
  const counts = {};
  for (const row of rows) counts[row[key]] = (counts[row[key]] ?? 0) + 1;
  return counts;
}

function splitCandidates(value, label) {
  if (!value) return [];
  const candidates = value.split(';');
  if (candidates.some((candidate) => candidate.length === 0)) {
    fail(`${label}: empty candidate segment`);
  }
  if (new Set(candidates).size !== candidates.length) {
    fail(`${label}: duplicate candidate`);
  }
  return candidates;
}

function repositoryPath(version, name) {
  return `supabase/migrations/${version}_${name}.sql`;
}

function repositoryNameFromPath(path) {
  const match = basename(path).match(/^\d{14}_(.+)\.sql$/);
  if (!match) fail(`repository path has non-canonical migration filename: ${path}`);
  return match[1];
}

function liveKey(row) {
  return `${row.live_version ?? row.version}:${row.live_name ?? row.name}`;
}

const ledger = parseCsv(
  readText('docs/migration-lineage/live-ledger-2026-08-19.csv'),
  'live ledger'
);
const inventory = parseCsv(
  readText('docs/migration-lineage/repository-inventory.csv'),
  'repository inventory'
);
const liveMap = parseCsv(
  readText('docs/migration-lineage/live-ledger-compatibility-map-2026-08-24.csv'),
  'live compatibility map'
);
const repoMap = parseCsv(
  readText('docs/migration-lineage/repository-migration-disposition-map-2026-08-24.csv'),
  'repository disposition map'
);
const repositoryExpectations = parseCsv(
  readText('docs/migration-lineage/repository-disposition-expectations-2026-08-24.csv'),
  'reviewed repository expectations'
);

if (ledger.length !== 96) fail(`live ledger: expected 96 rows, got ${ledger.length}`);
if (new Set(ledger.map((row) => row.version)).size !== 96) fail('live ledger: versions are not unique');
if (inventory.length !== 35) fail(`repository inventory: expected 35 rows, got ${inventory.length}`);
if (liveMap.length !== 96) fail(`live compatibility map: expected 96 rows, got ${liveMap.length}`);
if (repoMap.length !== 35) fail(`repository disposition map: expected 35 rows, got ${repoMap.length}`);
if (repositoryExpectations.length !== 35) {
  fail(`reviewed repository expectations: expected 35 rows, got ${repositoryExpectations.length}`);
}
for (const row of repositoryExpectations) {
  if (!/^[0-9a-f]{64}$/.test(row.sha256)) {
    fail(`reviewed repository expectations ${row.repository_path}: invalid SHA-256`);
  }
  const actual = sha256(row.repository_path);
  if (actual !== row.sha256) {
    fail(
      `reviewed repository expectations ${row.repository_path}: SHA-256 mismatch; expected=${row.sha256} actual=${actual}`
    );
  }
}

assertExactKeys(
  liveMap,
  ledger,
  (row) => `${row.live_version ?? row.version}\u0000${row.live_name ?? row.name}\u0000${row.evidence}`,
  'live map vs ledger'
);
assertExactKeys(
  repoMap,
  inventory,
  (row) => {
    const version = row.repository_version ?? row.version;
    const name = row.repository_name ?? row.name;
    const path = row.repository_path ?? repositoryPath(version, name);
    return `${version}\u0000${name}\u0000${path}\u0000${row.evidence}`;
  },
  'repository map vs inventory'
);
assertExactKeys(
  repoMap,
  repositoryExpectations,
  (row) => `${row.repository_path}\u0000${row.class}\u0000${row.live_candidates}`,
  'repository map vs reviewed expectations'
);

const liveVersions = new Set(ledger.map((row) => row.version));
const repositoryVersions = new Set(inventory.map((row) => row.version));
const exactVersionOverlap = [...liveVersions].filter((version) => repositoryVersions.has(version));
if (exactVersionOverlap.length !== 0) {
  fail(`expected zero exact live/repository version matches, got ${JSON.stringify(exactVersionOverlap)}`);
}

const allowedLiveClassifications = new Set(['A', 'N', 'C', 'B', 'D']);
for (const row of liveMap) {
  if (!allowedLiveClassifications.has(row.class)) {
    fail(`live map ${row.live_version}: invalid class ${row.class}`);
  }
}

const expectedLiveCounts = { A: 1, B: 15, C: 60, D: 2, N: 18 };
const actualLiveCounts = countBy(liveMap, 'class');
for (const [classification, expected] of Object.entries(expectedLiveCounts)) {
  if (actualLiveCounts[classification] !== expected) {
    fail(`live map: ${classification} expected ${expected}, got ${actualLiveCounts[classification] ?? 0}`);
  }
}
if (Object.keys(actualLiveCounts).length !== Object.keys(expectedLiveCounts).length) {
  fail(`live map: unexpected classification set ${JSON.stringify(actualLiveCounts)}`);
}

const archiveRows = liveMap.filter((row) => row.class === 'A');
if (
  archiveRows.length !== 1 ||
  archiveRows[0].live_version !== '20260614102924' ||
  archiveRows[0].repository_candidates !==
    'docs/migration-lineage/historical-sql/20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql'
) {
  fail('live map: recovered supporter archive contract changed');
}

const ledgerRowsByName = new Map();
for (const row of ledger) {
  const rows = ledgerRowsByName.get(row.name) ?? [];
  rows.push(row);
  ledgerRowsByName.set(row.name, rows);
}
const ledgerDuplicateNames = [...ledgerRowsByName.entries()].filter(([, rows]) => rows.length > 1);
if (
  ledgerDuplicateNames.length !== 1 ||
  ledgerDuplicateNames[0][0] !== 'analytics_triggers_for_partner_counters' ||
  JSON.stringify(ledgerDuplicateNames[0][1].map((row) => row.version).sort()) !==
    JSON.stringify(['20260602213920', '20260602220224'])
) {
  fail('live ledger: exact duplicate-name/version contract changed');
}

const duplicateRows = liveMap.filter((row) => row.class === 'D');
if (
  duplicateRows.length !== 2 ||
  duplicateRows.some(
    (row) =>
      row.live_name !== 'analytics_triggers_for_partner_counters' ||
      !['20260602213920', '20260602220224'].includes(row.live_version)
  )
) {
  fail('live map: exact duplicate-name/version contract changed');
}

for (const row of liveMap) {
  const candidates = splitCandidates(row.repository_candidates, `live map ${row.live_version}`);
  if (row.class === 'A') {
    if (candidates.length !== 1 || candidates[0] !== archiveRows[0].repository_candidates) {
      fail(`live map ${row.live_version}: class A requires the frozen archive path`);
    }
  } else if (row.class === 'B' || row.class === 'D') {
    if (candidates.length !== 0) {
      fail(`live map ${row.live_version}: class ${row.class} must not have repository candidates`);
    }
  } else if (row.class === 'C' || row.class === 'N') {
    if (candidates.length === 0) {
      fail(`live map ${row.live_version}: class ${row.class} requires a repository candidate`);
    }
  }

  if (row.class === 'N') {
    for (const candidate of candidates) {
      if (repositoryNameFromPath(candidate) !== row.live_name) {
        fail(`live map ${row.live_version}: class N candidate must preserve the migration name`);
      }
    }
  }
}

const allowedRepoClassifications = new Set(['BC', 'BS', 'AN', 'AR', 'AS']);
for (const row of repoMap) {
  if (!allowedRepoClassifications.has(row.class)) {
    fail(`repository map ${row.repository_path}: invalid class ${row.class}`);
  }
}

const expectedRepoCounts = { AN: 1, AR: 1, AS: 1, BC: 26, BS: 6 };
const actualRepoCounts = countBy(repoMap, 'class');
for (const [classification, expected] of Object.entries(expectedRepoCounts)) {
  if (actualRepoCounts[classification] !== expected) {
    fail(`repository map: ${classification} expected ${expected}, got ${actualRepoCounts[classification] ?? 0}`);
  }
}
if (Object.keys(actualRepoCounts).length !== Object.keys(expectedRepoCounts).length) {
  fail(`repository map: unexpected classification set ${JSON.stringify(actualRepoCounts)}`);
}

const mappedPaths = repoMap.map((row) => row.repository_path).sort();
if (new Set(mappedPaths).size !== mappedPaths.length) fail('repository map: duplicate repository_path');

for (const row of repoMap) {
  const expectedPath = repositoryPath(row.repository_version, row.repository_name);
  if (row.repository_path !== expectedPath) {
    fail(`repository map ${row.repository_version}:${row.repository_name}: expected path ${expectedPath}, got ${row.repository_path}`);
  }
  if (repositoryNameFromPath(row.repository_path) !== row.repository_name) {
    fail(`repository map ${row.repository_path}: filename/name mismatch`);
  }
  splitCandidates(row.live_candidates, `repository map ${row.repository_path}`);
}

const repositoryRowsByVersion = new Map();
for (const row of repoMap) {
  const rows = repositoryRowsByVersion.get(row.repository_version) ?? [];
  rows.push(row);
  repositoryRowsByVersion.set(row.repository_version, rows);
}
for (const [version, rows] of repositoryRowsByVersion) {
  if (rows.length === 1) {
    if (['BS', 'AR', 'AS'].includes(rows[0].class)) {
      fail(`repository map ${version}: collision-only class ${rows[0].class} used for a unique version`);
    }
    continue;
  }
  if (!rows.some((row) => row.class === 'BS')) {
    fail(`repository map ${version}: shared version requires at least one BS row`);
  }
  for (const row of rows) {
    if (!['BS', 'AR', 'AS'].includes(row.class)) {
      fail(`repository map ${row.repository_path}: shared version requires a collision class`);
    }
    if (row.repository_name.endsWith('.rollback') !== (row.class === 'AR')) {
      fail(`repository map ${row.repository_path}: rollback/collision class mismatch`);
    }
  }
}

const actualPaths = readdirSync(join(ROOT, 'supabase/migrations'))
  .filter((name) => name.endsWith('.sql'))
  .map((name) => `supabase/migrations/${name}`)
  .sort();

if (JSON.stringify(actualPaths) !== JSON.stringify(mappedPaths)) {
  const actualSet = new Set(actualPaths);
  const mappedSet = new Set(mappedPaths);
  const missing = mappedPaths.filter((path) => !actualSet.has(path));
  const extra = actualPaths.filter((path) => !mappedSet.has(path));
  fail(`repository map vs current migration directory mismatch; missing=${JSON.stringify(missing)} extra=${JSON.stringify(extra)}`);
}

const mappedPathSet = new Set(mappedPaths);
const repoByPath = new Map(repoMap.map((row) => [row.repository_path, row]));
const liveByKey = new Map(liveMap.map((row) => [liveKey(row), row]));
const archivePath =
  'docs/migration-lineage/historical-sql/20260614102924_add_supporter_payments_subscriptions_vibe_settings.sql';
for (const row of liveMap) {
  const candidates = splitCandidates(row.repository_candidates, `live map ${row.live_version}`);
  for (const candidate of candidates) {
    if (candidate !== archivePath && !mappedPathSet.has(candidate)) {
      fail(`live map ${row.live_version}: unknown repository candidate ${candidate}`);
    }
    if (candidate !== archivePath) {
      const reverseCandidates = splitCandidates(
        repoByPath.get(candidate).live_candidates,
        `repository map ${candidate}`
      );
      if (!reverseCandidates.includes(liveKey(row))) {
        fail(`live map ${row.live_version}: missing reverse edge from ${candidate}`);
      }
    }
  }
}

const liveKeySet = new Set(ledger.map((row) => `${row.version}:${row.name}`));
for (const row of repoMap) {
  const candidates = splitCandidates(row.live_candidates, `repository map ${row.repository_path}`);
  for (const candidate of candidates) {
    if (!liveKeySet.has(candidate)) {
      fail(`repository map ${row.repository_path}: unknown live candidate ${candidate}`);
    }
    const reverseCandidates = splitCandidates(
      liveByKey.get(candidate).repository_candidates,
      `live map ${candidate}`
    );
    if (!reverseCandidates.includes(row.repository_path)) {
      fail(`repository map ${row.repository_path}: missing reverse edge from ${candidate}`);
    }
  }
}

if (actualPaths.some((path) => path.includes('20260614102924_add_supporter_payments_subscriptions_vibe_settings'))) {
  fail('historical supporter SQL re-entered the executable migration directory');
}

console.log(
  JSON.stringify(
    {
      status: 'PASS',
      boundary: 'repository-and-ledger-compatibility-documentation-only',
      live_rows: ledger.length,
      repository_files: inventory.length,
      unique_repository_versions: repositoryVersions.size,
      exact_version_matches: exactVersionOverlap.length,
      live_classes: countBy(liveMap, 'class'),
      repository_classes: countBy(repoMap, 'class')
    },
    null,
    2
  )
);
