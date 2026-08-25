#!/usr/bin/env node

import {
  chmodSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const ROOT = process.cwd();
const PLAN = 'docs/migration-lineage/deep-metadata-capture-plan-2026-08-24.md';
const plan = readFileSync(join(ROOT, PLAN), 'utf8');
const marker = 'The exact client byte contract';
const markerOffset = plan.indexOf(marker);
const fenceStart = plan.indexOf('```bash\n', markerOffset);
const fenceEnd = plan.indexOf('\n```', fenceStart + 8);

if (markerOffset < 0 || fenceStart < 0 || fenceEnd < 0) {
  throw new Error('capture containment test: exact Bash contract not found');
}

const contract = plan.slice(fenceStart + 8, fenceEnd);
const fixtureRoot = mkdtempSync(join(tmpdir(), 'swp-016-capture-containment-'));
chmodSync(fixtureRoot, 0o700);

function runCapture(parent, fakeMode = 'success') {
  const fakeBin = join(fixtureRoot, 'bin');
  mkdirSync(fakeBin, { recursive: true, mode: 0o700 });
  const fakePsql = join(fakeBin, 'psql');
  writeFileSync(
    fakePsql,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${SWP016_FAKE_MODE:-success}" == "replace-path" ]]; then
  capture_file="$(readlink /proc/self/fd/3)"
  capture_dir="\${capture_file%/*}"
  mv -- "$capture_dir" "$capture_dir.original"
  mkdir -m 700 -- "$capture_dir"
  : >"$capture_dir/deep-structure-manifest.jsonl"
  : >"$capture_dir/deep-structure-manifest.stderr"
  : >"$capture_dir/deep-structure-manifest.receipt"
  chmod 600 -- "$capture_dir"/*
fi
printf '%s\\n' '{"record_class":"test"}'
if [[ "\${SWP016_FAKE_MODE:-success}" == "fail" ]]; then
  printf '%s\\n' 'synthetic psql failure' >&2
  exit 42
fi
`
  );
  chmodSync(fakePsql, 0o700);

  const env = {
    ...process.env,
    PATH: `${fakeBin}:${process.env.PATH ?? ''}`,
    SWP016_FAKE_MODE: fakeMode
  };
  if (parent === undefined) delete env.TMPDIR;
  else env.TMPDIR = parent;
  return spawnSync('bash', ['-c', contract], { cwd: ROOT, env, encoding: 'utf8' });
}

function expectRejected(name, parent, pattern) {
  const result = runCapture(parent);
  if (result.status === 0 || !pattern.test(result.stderr)) {
    throw new Error(`${name}: expected rejection matching ${pattern}, status=${result.status}, stderr=${result.stderr}`);
  }
}

try {
  const conditionalRejections = [];
  expectRejected('unset TMPDIR', undefined, /TMPDIR/);
  expectRejected('relative TMPDIR', 'relative-capture-parent', /absolute path/);

  const broadLeaf = join(fixtureRoot, 'broad-leaf');
  mkdirSync(broadLeaf, { mode: 0o700 });
  chmodSync(broadLeaf, 0o777);
  expectRejected('broad leaf', broadLeaf, /owned by the operator with mode 700/);

  const writableAncestor = join(fixtureRoot, 'writable-ancestor');
  const privateLeaf = join(writableAncestor, 'private-leaf');
  mkdirSync(privateLeaf, { recursive: true, mode: 0o700 });
  chmodSync(writableAncestor, 0o777);
  chmodSync(privateLeaf, 0o700);
  expectRejected(
    'writable non-sticky ancestor',
    privateLeaf,
    /Writable capture-path components must be root-owned sticky directories/
  );

  if (process.getuid?.() !== 0) {
    const operatorStickyAncestor = join(fixtureRoot, 'operator-sticky-ancestor');
    const operatorStickyLeaf = join(operatorStickyAncestor, 'private-leaf');
    mkdirSync(operatorStickyLeaf, { recursive: true, mode: 0o700 });
    chmodSync(operatorStickyAncestor, 0o1777);
    chmodSync(operatorStickyLeaf, 0o700);
    expectRejected(
      'operator-owned sticky ancestor',
      operatorStickyLeaf,
      /Writable capture-path components must be root-owned sticky directories/
    );
    conditionalRejections.push('operator-owned sticky ancestor');
  }

  const symlinkTarget = join(fixtureRoot, 'symlink-target');
  const symlinkParent = join(fixtureRoot, 'symlink-parent');
  mkdirSync(symlinkTarget, { mode: 0o700 });
  symlinkSync(symlinkTarget, symlinkParent);
  expectRejected('symlink path component', symlinkParent, /canonical and contain no symlink/);

  const safeParent = join(fixtureRoot, 'safe-parent');
  mkdirSync(safeParent, { mode: 0o700 });
  expectRejected('noncanonical trailing slash', `${safeParent}/`, /canonical and contain no symlink/);
  const success = runCapture(safeParent);
  if (success.status !== 0) {
    throw new Error(`safe parent: expected success, status=${success.status}, stderr=${success.stderr}`);
  }

  const captureDirs = readdirSync(safeParent).filter((name) =>
    name.startsWith('swp-016-private-capture.')
  );
  if (captureDirs.length !== 1) {
    throw new Error(`safe parent: expected one capture directory, got ${captureDirs.length}`);
  }
  const captureDir = join(safeParent, captureDirs[0]);
  const captureFile = join(captureDir, 'deep-structure-manifest.jsonl');
  const errorFile = join(captureDir, 'deep-structure-manifest.stderr');
  const receiptFile = join(captureDir, 'deep-structure-manifest.receipt');
  if (lstatSync(captureDir).isSymbolicLink() || (statSync(captureDir).mode & 0o777) !== 0o700) {
    throw new Error('safe parent: capture directory is not a real mode-700 directory');
  }
  for (const path of [captureFile, errorFile, receiptFile]) {
    if (lstatSync(path).isSymbolicLink() || !statSync(path).isFile() || (statSync(path).mode & 0o777) !== 0o600) {
      throw new Error(`safe parent: invalid capture output ${path}`);
    }
  }
  if (readFileSync(captureFile, 'utf8') !== '{"record_class":"test"}\n') {
    throw new Error('safe parent: fake psql bytes did not reach the descriptor-pinned capture file');
  }
  if (statSync(errorFile).size !== 0) {
    throw new Error('safe parent: unexpected stderr bytes');
  }
  const expectedCaptureSha = createHash('sha256')
    .update('{"record_class":"test"}\n')
    .digest('hex');
  const expectedErrorSha = createHash('sha256').update('').digest('hex');
  const receiptText = readFileSync(receiptFile, 'utf8');
  for (const receipt of [
    'SWP016_PSQL_STATUS=0',
    'SWP016_PATH_INTEGRITY=true',
    'SWP016_CAPTURE_BYTES=24',
    `SWP016_CAPTURE_SHA256=${expectedCaptureSha}`,
    'SWP016_ERROR_BYTES=0',
    `SWP016_ERROR_SHA256=${expectedErrorSha}`,
    'SWP016_ELIGIBLE=true'
  ]) {
  if (!receiptText.includes(receipt)) {
      throw new Error(`safe parent: missing descriptor-backed receipt ${receipt}`);
    }
  }

  const colonParent = join(fixtureRoot, 'safe:colon-parent');
  mkdirSync(colonParent, { mode: 0o700 });
  const colonSuccess = runCapture(colonParent);
  if (colonSuccess.status !== 0) {
    throw new Error(
      `colon parent: expected success, status=${colonSuccess.status}, stderr=${colonSuccess.stderr}`
    );
  }

  const replacedParent = join(fixtureRoot, 'replace-parent');
  mkdirSync(replacedParent, { mode: 0o700 });
  const replaced = runCapture(replacedParent, 'replace-path');
  if (replaced.status === 0 || !/Capture is ineligible/.test(replaced.stderr)) {
    throw new Error(`path replacement: expected fail-closed result, status=${replaced.status}, stderr=${replaced.stderr}`);
  }
  const originalDirName = readdirSync(replacedParent).find((name) => name.endsWith('.original'));
  if (!originalDirName) throw new Error('path replacement: descriptor-backed original directory not found');
  const originalReceipt = readFileSync(
    join(replacedParent, originalDirName, 'deep-structure-manifest.receipt'),
    'utf8'
  );
  if (!originalReceipt.includes('SWP016_PATH_INTEGRITY=false') ||
      !originalReceipt.includes('SWP016_ELIGIBLE=false')) {
    throw new Error('path replacement: private receipt did not record ineligibility');
  }

  const failedParent = join(fixtureRoot, 'failed-parent');
  mkdirSync(failedParent, { mode: 0o700 });
  const failed = runCapture(failedParent, 'fail');
  if (failed.status === 0 || !/Capture is ineligible/.test(failed.stderr)) {
    throw new Error(`psql failure: expected fail-closed result, status=${failed.status}, stderr=${failed.stderr}`);
  }
  const failedDirName = readdirSync(failedParent).find((name) =>
    name.startsWith('swp-016-private-capture.')
  );
  const failedReceipt = readFileSync(
    join(failedParent, failedDirName, 'deep-structure-manifest.receipt'),
    'utf8'
  );
  if (!failedReceipt.includes('SWP016_PSQL_STATUS=42') ||
      !failedReceipt.includes('SWP016_ELIGIBLE=false')) {
    throw new Error('psql failure: private receipt did not record status 42 and ineligibility');
  }

  console.log(
    JSON.stringify(
      {
        status: 'PASS',
        boundary: 'private-capture-path-containment',
        rejected: [
          'unset TMPDIR',
          'relative TMPDIR',
          'broad leaf',
          'writable non-sticky ancestor',
          ...conditionalRejections,
          'symlink path component',
          'noncanonical trailing slash',
          'post-open pathname replacement',
          'nonzero psql status'
        ],
        accepted: [
          'canonical operator-owned private parent',
          'canonical private parent containing colon'
        ]
      },
      null,
      2
    )
  );
} finally {
  rmSync(fixtureRoot, { recursive: true, force: true });
}
