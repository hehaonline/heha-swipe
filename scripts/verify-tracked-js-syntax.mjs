#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { extname } from 'node:path';
import { transformWithEsbuild } from 'vite';

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
  const extension = extname(path);
  await transformWithEsbuild(await readFile(path, 'utf8'), path, {
    loader: extension === '.jsx' ? 'jsx' : 'js',
    sourcemap: false
  });
}

console.log(`PASS: parsed ${tracked.length} tracked JS/JSX/MJS/CJS files.`);
