import assert from 'node:assert/strict';
import test from 'node:test';
import childProcess from 'node:child_process';
import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { requireDisposableMediaTarget, createDisposableMediaPsql, verifyDisposableMediaApi } from './disposable_media_target.mjs';

const databaseUrl = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const apiUrl = 'http://127.0.0.1:54321';
const nonce = '1234567890abcdef1234567890abcdef';
const cleanEnv = { PATH: '/usr/bin:/bin', HEHA_MEDIA_PROOF_NONCE: nonce };
const scripts = ['partner_media_concurrency_proof.mjs', 'partner_media_migration_preflight.mjs',
  'partner_media_api_proof.mjs', 'partner_media_sql.mjs', 'partner_media_target_proof.mjs'];
let sequence = 0;

// Only the Node module under test is entered. Every child-process/fetch function
// is replaced before import, so these negative controls never connect or run SQL.
async function probe(script, { db = databaseUrl, api = apiUrl, env = {}, positive = false } = {}) {
  const oldEnv = process.env;
  const oldArgs = process.argv;
  const oldRead = fs.readFileSync;
  const oldFetch = globalThis.fetch;
  const oldChild = Object.fromEntries(['spawn', 'spawnSync', 'execFileSync'].map((key) => [key, childProcess[key]]));
  const calls = [];
  const stop = (...args) => { calls.push(args); throw new Error('PROBE_CHILD_STOP'); };
  try {
    process.env = { ...cleanEnv, DATABASE_URL: db, ...env };
    process.argv = [oldArgs[0], script, 'supabase/tests/partner_media_access_proof.sql'];
    for (const key of Object.keys(oldChild)) childProcess[key] = stop;
    globalThis.fetch = stop;
    fs.readFileSync = (file, ...args) => file === 0
      ? JSON.stringify({ DB_URL: db, API_URL: api, ANON_KEY: 'synthetic', SERVICE_ROLE_KEY: 'synthetic' })
      : oldRead(file, ...args);
    syncBuiltinESMExports();
    await assert.rejects(import(`./${script}?probe=${sequence++}`), positive ? /PROBE_CHILD_STOP/ : /Disposable media proof/);
    assert.equal(calls.length, positive ? 1 : 0, 'invalid target must fail before every subprocess/fetch');
    if (positive) {
      const [command, args, options] = calls[0];
      assert.equal(command, 'psql');
      assert.ok(args.includes('-X') && args.includes('-w'));
      assert.ok(args.indexOf('-c') < args.indexOf('-f'));
      assert.match(args[args.indexOf('-c') + 1], /public\.heha_media_proof_identity/);
      assert.deepEqual(options.env, { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' });
    }
  } finally {
    process.env = oldEnv;
    process.argv = oldArgs;
    fs.readFileSync = oldRead;
    globalThis.fetch = oldFetch;
    Object.assign(childProcess, oldChild);
    syncBuiltinESMExports();
  }
}

const invalidUrls = [
  null, 42, '', 'host=127.0.0.1 port=54322 dbname=postgres',
  databaseUrl + '?', databaseUrl + '#', databaseUrl + '#host=proof-target.invalid',
  ...['host=proof-target.invalid', 'hostaddr=192.0.2.1', 'port=6543', 'dbname=other',
    'user=other', 'service=other', 'servicefile=/tmp/other', 'passfile=/tmp/other',
    'options=-csearch_path=other', 'sslmode=require', '%68ost=proof-target.invalid',
    'host=127.0.0.1&host=proof-target.invalid'].map((query) => databaseUrl + '?' + query),
  databaseUrl.replace('127.0.0.1', 'localhost'), databaseUrl.replace('127.0.0.1', '[::1]'),
  databaseUrl.replace('127.0.0.1', '2130706433'), databaseUrl.replace('127.0.0.1', '127.1'),
  databaseUrl.replace('127.0.0.1', '0x7f000001'), databaseUrl.replace('127.0.0.1', '127.000.000.001'),
  databaseUrl.replace('127.0.0.1', '%31%32%37.0.0.1'), databaseUrl.replace('54322', '054322'),
  databaseUrl.replace('54322', '5432'), databaseUrl.replace(':54322', ''),
  databaseUrl.replace('127.0.0.1', '127.0.0.1,proof-target.invalid'),
  databaseUrl.replace('@', '@proof-target.invalid@'), databaseUrl.replace('@', '%40'),
  databaseUrl.replace('postgres:postgres@', 'postgres:@'),
  databaseUrl.replace('postgres:postgres@', 'postgres@'),
  databaseUrl.replace('postgres:postgres@', 'other:postgres@'),
  databaseUrl.replace('postgres:postgres@', 'postgres:%00@'),
  databaseUrl.replace('postgres:postgres@', 'postgres:%zz@'),
  databaseUrl.replace('postgres:postgres@', 'postgres:p%40ss@'),
  databaseUrl.replace('postgresql:', 'postgres:'), databaseUrl.replace('postgresql:', 'POSTGRESQL:'),
  databaseUrl.replace('/postgres', '/other'), databaseUrl.replace('/postgres', '/postgre%73'),
  databaseUrl.replace('/postgres', '/'), databaseUrl + '/', databaseUrl + '/other',
  databaseUrl.replace('/postgres', '/a/../postgres'), databaseUrl.replace('/postgres', '/%2fpostgres'),
  databaseUrl.replace('/postgres', '/host=proof-target.invalid'),
  ' ' + databaseUrl, databaseUrl + '\n', databaseUrl + '\0', databaseUrl.replace('@', '\\@'),
];
for (const script of scripts) {
  test(`${script}: exact target reaches only the guarded first subprocess`, () => probe(script, { positive: true }));
  invalidUrls.forEach((db, index) => test(`${script}: invalid raw URI ${index} has zero side effects`, () => probe(script, { db })));
  for (const name of ['PGHOST', 'PGHOSTADDR', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD',
    'PGSERVICE', 'PGSERVICEFILE', 'PGPASSFILE', 'PGSYSCONFDIR', 'PGOPTIONS', 'PGAPPNAME',
    'PGTARGETSESSIONATTRS', 'PGLOADBALANCEHOSTS', 'PGCONNECT_TIMEOUT', 'PGCLIENTENCODING',
    'PGSSLMODE', 'PGSSLCERT', 'PGSSLKEY', 'PGSSLROOTCERT', 'PGREQUIREAUTH', 'PGGSSENCMODE',
    'PGKRBSRVNAME', 'PGTZ', 'pgHost', 'PgFutureConnectionOverride',
    'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NODE_USE_ENV_PROXY']) {
    for (const value of ['', 'synthetic-override']) {
      test(`${script}: rejects ${name} ${value ? 'set' : 'empty'} before child`, () => probe(script, { env: { [name]: value } }));
    }
  }
  for (const value of [undefined, '', 'not-a-nonce', nonce + "'", nonce.toUpperCase()]) {
    test(`${script}: missing/malformed fixture identity ${String(value)} has zero side effects`, () => probe(script, { env: { HEHA_MEDIA_PROOF_NONCE: value } }));
  }
}

for (const api of [null, '', 'https://127.0.0.1:54321', 'http://localhost:54321', 'http://127.0.0.1:54322',
  apiUrl + '/', apiUrl + '?', apiUrl + '#', 'http://127.0.0.1:54321@proof-target.invalid',
  'http://127.1:54321', 'http://%31%32%37.0.0.1:54321']) {
  test(`API proof: ambiguous API target ${api} has zero side effects`, () => probe('partner_media_api_proof.mjs', { api }));
}

test('boundary child environment excludes ambient credentials, config and loaders', () => {
  const target = requireDisposableMediaTarget(databaseUrl, {
    ...cleanEnv, HOME: '/sensitive', PSQLRC: '/sensitive', NODE_OPTIONS: '--import=bad',
    LD_PRELOAD: 'bad', SSLKEYLOGFILE: 'bad', SUPABASE_ACCESS_TOKEN: 'secret',
  });
  assert.deepEqual(target.childEnv, { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' });
  assert.equal(target.databaseUrl, databaseUrl);
  assert.match(target.guard, /session_user <> 'postgres'/);
  assert.match(target.guard, /current_database\(\) <> 'postgres'/);
  assert.match(target.guard, /server_version_num/);
  assert.match(target.guard, /count\(\*\)/);
});

test('every SQL entrypoint puts identity guard before caller input, including cleanup and race sessions', () => {
  const original = Object.fromEntries(['execFileSync', 'spawnSync', 'spawn'].map((name) => [name, childProcess[name]]));
  const calls = [];
  try {
    for (const name of Object.keys(original)) childProcess[name] = (...args) => { calls.push(args); return ''; };
    syncBuiltinESMExports();
    const db = createDisposableMediaPsql(databaseUrl, cleanEnv);
    db.verify(); db.sql('DELETE FROM synthetic'); db.result('ALTER TABLE synthetic'); db.session();
    assert.equal(calls.length, 4);
    for (const [command, args, options] of calls) {
      assert.equal(command, 'psql');
      assert.deepEqual(args.slice(-4), ['-c', requireDisposableMediaTarget(databaseUrl, cleanEnv).guard, '-f', '-']);
      assert.ok(args.includes('ON_ERROR_STOP=1'));
      assert.deepEqual(options.env, { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' });
    }
  } finally { Object.assign(childProcess, original); syncBuiltinESMExports(); }
});

test('API identity uses only a nonredirecting GET and accepts exactly one matching row', async () => {
  let calls = 0;
  await verifyDisposableMediaApi(apiUrl, 'synthetic', 'synthetic', nonce, async (url, init) => {
    calls += 1;
    assert.equal(url, apiUrl + '/rest/v1/heha_media_proof_identity?select=nonce');
    assert.equal(init.method, 'GET'); assert.equal(init.redirect, 'error');
    return { ok: true, json: async () => [{ nonce }] };
  });
  assert.equal(calls, 1);
  for (const rows of [[], [{ nonce: 'other' }], [{ nonce }, { nonce }], null, {}, [{ nonce: null }]]) {
    await assert.rejects(verifyDisposableMediaApi(apiUrl, 'synthetic', 'synthetic', nonce,
      async () => ({ ok: true, json: async () => rows })), /fixture identity mismatch/);
  }
  await assert.rejects(verifyDisposableMediaApi(apiUrl, 'synthetic', 'synthetic', nonce,
    async () => ({ ok: false })), /fixture identity mismatch/);
});

test('API entrypoint stops before Auth/Storage mutation when database or API identity fails', async () => {
  const oldEnv = process.env, oldRead = fs.readFileSync, oldExec = childProcess.execFileSync, oldFetch = globalThis.fetch;
  try {
    process.env = cleanEnv;
    fs.readFileSync = (file, ...args) => file === 0 ? JSON.stringify({ DB_URL: databaseUrl, API_URL: apiUrl,
      ANON_KEY: 'synthetic', SERVICE_ROLE_KEY: 'synthetic' }) : oldRead(file, ...args);
    let requests = 0;
    globalThis.fetch = async (_url, init) => {
      requests += 1;
      assert.equal(init.method, 'GET');
      return { ok: true, json: async () => [{ nonce: 'wrong-instance' }] };
    };
    childProcess.execFileSync = () => { throw new Error('fixture identity mismatch'); };
    syncBuiltinESMExports();
    await assert.rejects(import(`./partner_media_api_proof.mjs?probe=${sequence++}`), /fixture identity mismatch/);
    assert.equal(requests, 0);
    childProcess.execFileSync = () => '';
    syncBuiltinESMExports();
    await assert.rejects(import(`./partner_media_api_proof.mjs?probe=${sequence++}`), /fixture identity mismatch/);
    assert.equal(requests, 1);
  } finally {
    process.env = oldEnv; fs.readFileSync = oldRead; childProcess.execFileSync = oldExec; globalThis.fetch = oldFetch;
    syncBuiltinESMExports();
  }
});
