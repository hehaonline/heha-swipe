#!/usr/bin/env node

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join } from 'node:path';
import { transformWithEsbuild } from 'vite';

async function parseFile(path) {
  const extension = extname(path);
  if (extension === '.cjs') {
    // esbuild's generic JavaScript parser accepts module-only constructs even
    // for .cjs. Node's checker supplies the real CommonJS parse goal.
    execFileSync(process.execPath, ['--check', path], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    });
    return;
  }

  await transformWithEsbuild(await readFile(path, 'utf8'), path, {
    loader: extension === '.jsx' ? 'jsx' : 'js',
    sourcemap: false
  });
}

async function selfTest() {
  const fixtureRoot = await mkdtemp(join(tmpdir(), 'heha-syntax-'));
  try {
    const safeCjs = join(fixtureRoot, 'safe.cjs');
    const awaitCjs = join(fixtureRoot, 'top-level-await.cjs');
    const importCjs = join(fixtureRoot, 'static-import.cjs');
    const jsx = join(fixtureRoot, 'component.jsx');
    await writeFile(safeCjs, "module.exports = { ready: true };\n");
    await writeFile(awaitCjs, "await Promise.resolve();\n");
    await writeFile(importCjs, "import value from './value.js';\n");
    await writeFile(jsx, "export default function Fixture(){ return <div />; }\n");

    await parseFile(safeCjs);
    await parseFile(jsx);
    await assert.rejects(parseFile(awaitCjs));
    await assert.rejects(parseFile(importCjs));
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
  console.log('PASS: syntax verifier CommonJS/JSX negative controls.');
}

if (process.argv[2] === '--self-test') {
  await selfTest();
  process.exit(0);
}

if (process.argv.length > 2) {
  throw new Error(`unknown argument: ${process.argv[2]}`);
}

const tracked = execFileSync(
  'git',
  ['ls-files', '-z', '--', '*.js', '*.jsx', '*.mjs', '*.cjs'],
  { encoding: 'buffer' }
)
  .toString('utf8')
  .split('\0')
  .filter(Boolean)
  .sort();

if (tracked.length === 0) {
  throw new Error('tracked JavaScript syntax check found no files');
}

for (const path of tracked) {
  await parseFile(path);
}

console.log(`PASS: parsed ${tracked.length} tracked JS/JSX/MJS/CJS files.`);
