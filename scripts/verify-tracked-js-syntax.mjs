#!/usr/bin/env node

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, extname, join, resolve, sep } from 'node:path';
import { transformWithEsbuild } from 'vite';

const JAVASCRIPT_MIME_ESSENCES = new Set([
  'application/ecmascript',
  'application/javascript',
  'application/x-ecmascript',
  'application/x-javascript',
  'text/ecmascript',
  'text/javascript',
  'text/javascript1.0',
  'text/javascript1.1',
  'text/javascript1.2',
  'text/javascript1.3',
  'text/javascript1.4',
  'text/javascript1.5',
  'text/jscript',
  'text/livescript',
  'text/x-ecmascript',
  'text/x-javascript'
]);

function inlineScriptKind(rawType) {
  const type = rawType.trim().toLowerCase();
  if (type === '' || JAVASCRIPT_MIME_ESSENCES.has(type.split(';', 1)[0].trimEnd())) {
    return 'classic';
  }
  if (type === 'module') return 'module';

  // HTML parses character references before classifying the type attribute.
  // Without a full HTML tokenizer, fail closed and parse the body as JavaScript
  // whenever a raw character reference could hide a JavaScript MIME essence.
  if (rawType.includes('&')) return 'classic';
  return 'data';
}

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

  const loaders = new Map([
    ['.jsx', 'jsx'],
    ['.ts', 'ts'],
    ['.tsx', 'tsx'],
    ['.mts', 'ts'],
    ['.cts', 'ts']
  ]);
  await transformWithEsbuild(await readFile(path, 'utf8'), path, {
    loader: loaders.get(extension) ?? 'js',
    format: 'esm',
    sourcemap: false
  });
}

async function parseDeployedManifest(path) {
  const parsed = JSON.parse(await readFile(path, 'utf8'));
  assert.equal(typeof parsed, 'object', `${path} must contain a JSON object`);
  assert.notEqual(parsed, null, `${path} must contain a JSON object`);
  assert.equal(Array.isArray(parsed), false, `${path} must contain a JSON object`);

  for (const field of [
    'name', 'short_name', 'start_url', 'scope', 'display',
    'background_color', 'theme_color'
  ]) {
    assert.equal(typeof parsed[field], 'string', `${path} ${field} must be a string`);
    assert.notEqual(parsed[field].trim(), '', `${path} ${field} must not be empty`);
  }
  assert.ok(
    ['browser', 'fullscreen', 'minimal-ui', 'standalone', 'window-controls-overlay'].includes(parsed.display),
    `${path} display is unsupported`
  );
  for (const field of ['background_color', 'theme_color']) {
    assert.match(parsed[field], /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i, `${path} ${field} must be a hex color`);
  }
  for (const field of ['start_url', 'scope']) {
    assert.match(parsed[field], /^\/(?!\/)/, `${path} ${field} must be a local absolute path`);
    assert.equal(parsed[field].includes('\\'), false, `${path} ${field} contains a backslash`);
    assert.equal(parsed[field].split('/').includes('..'), false, `${path} ${field} escapes scope`);
  }

  assert.ok(Array.isArray(parsed.icons) && parsed.icons.length > 0, `${path} icons must be non-empty`);
  const publicRoot = resolve(dirname(path));
  for (const [index, icon] of parsed.icons.entries()) {
    assert.equal(typeof icon, 'object', `${path} icon ${index + 1} must be an object`);
    assert.notEqual(icon, null, `${path} icon ${index + 1} must be an object`);
    assert.equal(typeof icon.src, 'string', `${path} icon ${index + 1} src must be a string`);
    assert.match(icon.src, /^\/(?!\/)[^?#]*$/, `${path} icon ${index + 1} src must be a local asset path`);
    assert.equal(icon.src.includes('\\'), false, `${path} icon ${index + 1} src contains a backslash`);
    assert.equal(icon.src.split('/').includes('..'), false, `${path} icon ${index + 1} src escapes public root`);
    assert.equal(typeof icon.sizes, 'string', `${path} icon ${index + 1} sizes must be a string`);
    assert.match(icon.sizes, /^(?:any|\d+x\d+)(?:\s+(?:any|\d+x\d+))*$/i, `${path} icon ${index + 1} sizes are invalid`);
    assert.match(icon.type ?? '', /^image\/(?:png|svg\+xml|webp)$/i, `${path} icon ${index + 1} type is invalid`);

    const assetPath = resolve(publicRoot, `.${icon.src}`);
    assert.ok(assetPath.startsWith(`${publicRoot}${sep}`), `${path} icon ${index + 1} escapes public root`);
    assert.ok((await stat(assetPath)).isFile(), `${path} icon ${index + 1} asset is missing`);
  }
}

async function parseInlineHtmlScripts(path) {
  const html = await readFile(path, 'utf8');
  const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)];
  let parsed = 0;
  for (const [index, match] of scripts.entries()) {
    const attributes = match[1];
    if (/(?:^|[\t\n\f\r ])src[\t\n\f\r ]*=/i.test(attributes)) continue;
    const typeMatch = attributes.match(/(?:^|[\t\n\f\r ])type[\t\n\f\r ]*=[\t\n\f\r ]*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
    const rawType = typeMatch?.[1] ?? typeMatch?.[2] ?? typeMatch?.[3] ?? '';
    const kind = inlineScriptKind(rawType);
    if (kind === 'data') continue;
    await transformWithEsbuild(match[2], `${path}#inline-script-${index + 1}.js`, {
      loader: 'js',
      format: kind === 'module' ? 'esm' : 'iife',
      sourcemap: false
    });
    parsed += 1;
  }
  if (parsed === 0) throw new Error(`${path} must contain at least one executable inline script`);
  return parsed;
}

async function selfTest() {
  const fixtureRoot = await mkdtemp(join(tmpdir(), 'heha-syntax-'));
  try {
    const safeCjs = join(fixtureRoot, 'safe.cjs');
    const awaitCjs = join(fixtureRoot, 'top-level-await.cjs');
    const importCjs = join(fixtureRoot, 'static-import.cjs');
    const jsx = join(fixtureRoot, 'component.jsx');
    const typescript = join(fixtureRoot, 'edge-function.ts');
    const invalidTypescript = join(fixtureRoot, 'invalid-edge-function.ts');
    const sloppyJs = join(fixtureRoot, 'sloppy-script.js');
    const legacyOctalJsx = join(fixtureRoot, 'legacy-octal.jsx');
    const manifest = join(fixtureRoot, 'manifest.json');
    const invalidManifest = join(fixtureRoot, 'invalid-manifest.json');
    const emptyManifest = join(fixtureRoot, 'empty-manifest.json');
    const missingIconManifest = join(fixtureRoot, 'missing-icon-manifest.json');
    const html = join(fixtureRoot, 'index.html');
    const invalidHtml = join(fixtureRoot, 'invalid-index.html');
    const invalidDataSrcHtml = join(fixtureRoot, 'invalid-data-src-index.html');
    const invalidDataTypeHtml = join(fixtureRoot, 'invalid-data-type-index.html');
    const invalidSpacedTypeHtml = join(fixtureRoot, 'invalid-spaced-type-index.html');
    const invalidEncodedTypeHtml = join(fixtureRoot, 'invalid-encoded-type-index.html');
    await writeFile(safeCjs, "module.exports = { ready: true };\n");
    await writeFile(awaitCjs, "await Promise.resolve();\n");
    await writeFile(importCjs, "import value from './value.js';\n");
    await writeFile(jsx, "export default function Fixture(){ return <div />; }\n");
    await writeFile(typescript, "export const ready: boolean = true;\n");
    await writeFile(invalidTypescript, "export const broken: = true;\n");
    await writeFile(sloppyJs, "with ({ ready: true }) { console.log(ready); }\n");
    await writeFile(legacyOctalJsx, "export default function Fixture(){ const value = 010; return <div>{value}</div>; }\n");
    await mkdir(join(fixtureRoot, 'icons'));
    await writeFile(join(fixtureRoot, 'icons', 'icon-192.png'), 'fixture');
    const validManifest = JSON.stringify({
      name: 'HEHA Swipe', short_name: 'HEHA', start_url: '/', scope: '/',
      display: 'standalone', background_color: '#f5f0e8', theme_color: '#1e4d1e',
      icons: [{ src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' }]
    });
    await writeFile(manifest, `${validManifest}\n`);
    await writeFile(invalidManifest, '{"name":}\n');
    await writeFile(emptyManifest, '{}\n');
    await writeFile(
      missingIconManifest,
      `${validManifest.replace('/icons/icon-192.png', '/icons/missing.png')}\n`
    );
    await writeFile(html, '<script>const ready = true;</script><script type="module" src="/main.js"></script>\n');
    await writeFile(invalidHtml, '<script>const broken = ;</script>\n');
    await writeFile(invalidDataSrcHtml, '<script data-src="/ignored.js">const broken = ;</script>\n');
    await writeFile(invalidDataTypeHtml, '<script data-type="application/json">const broken = ;</script>\n');
    await writeFile(invalidSpacedTypeHtml, '<script type=" text/javascript ">const broken = ;</script>\n');
    await writeFile(invalidEncodedTypeHtml, '<script type="text&#x2f;javascript">const broken = ;</script>\n');

    await parseFile(safeCjs);
    await parseFile(jsx);
    await parseFile(typescript);
    await parseDeployedManifest(manifest);
    await parseInlineHtmlScripts(html);
    await assert.rejects(parseFile(awaitCjs));
    await assert.rejects(parseFile(importCjs));
    await assert.rejects(parseFile(invalidTypescript));
    await assert.rejects(parseFile(sloppyJs));
    await assert.rejects(parseFile(legacyOctalJsx));
    await assert.rejects(parseDeployedManifest(invalidManifest));
    await assert.rejects(parseDeployedManifest(emptyManifest));
    await assert.rejects(parseDeployedManifest(missingIconManifest));
    await assert.rejects(parseInlineHtmlScripts(invalidHtml));
    await assert.rejects(parseInlineHtmlScripts(invalidDataSrcHtml));
    await assert.rejects(parseInlineHtmlScripts(invalidDataTypeHtml));
    await assert.rejects(parseInlineHtmlScripts(invalidSpacedTypeHtml));
    await assert.rejects(parseInlineHtmlScripts(invalidEncodedTypeHtml));
  } finally {
    await rm(fixtureRoot, { recursive: true, force: true });
  }
  console.log('PASS: JS/CJS/JSX/TypeScript and deployed-manifest negative controls.');
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
  ['ls-files', '-z', '--', '*.js', '*.jsx', '*.mjs', '*.cjs', '*.ts', '*.tsx', '*.mts', '*.cts'],
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

await parseDeployedManifest('public/manifest.json');
const inlineScriptCount = await parseInlineHtmlScripts('index.html');

console.log(`PASS: parsed ${tracked.length} tracked JS/JSX/MJS/CJS/TS/TSX/MTS/CTS files, public/manifest.json, and ${inlineScriptCount} inline HTML script(s).`);
