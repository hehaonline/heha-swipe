// Proof-only boundary, not a general PostgreSQL connection-string parser.
// The raw-URI approach follows Local PR263's reviewed safeguard at 4748c8d4
// (disposable-postgres-target.mjs, blob cfa6638d396034cae8c3d8990982e0c6e61e4032).
// Swipe intentionally narrows that contract to its fixed disposable CI ports,
// rejects every inherited PG* setting, and checks a per-run fixture identity.
import { execFileSync, spawn, spawnSync } from 'node:child_process';

export function requireDisposableMediaApiTarget(apiUrl) {
  if (apiUrl !== 'http://127.0.0.1:54321') {
    throw new Error('Disposable media proof requires the exact local API target');
  }
}

export function requireDisposableMediaTarget(databaseUrl, env = process.env, apiUrl) {
  if (Object.keys(env).some((name) => /^PG/i.test(name))) {
    throw new Error('Disposable media proof rejects inherited libpq PG* settings');
  }
  if (Object.keys(env).some((name) => /^(?:HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NODE_USE_ENV_PROXY)$/i.test(name))) {
    throw new Error('Disposable media proof rejects inherited API proxy settings');
  }
  // Do not parse/normalize first: libpq and WHATWG URL have different grammars.
  // Only an explicit password in the unreserved ASCII subset is supported.
  if (typeof databaseUrl !== 'string' ||
      !/^postgresql:\/\/postgres:[A-Za-z0-9._~-]+@127\.0\.0\.1:54322\/postgres$/.test(databaseUrl)) {
    throw new Error('Disposable media proof requires the exact local PostgreSQL target; no URI overrides');
  }
  const nonce = env.HEHA_MEDIA_PROOF_NONCE;
  if (typeof nonce !== 'string' || !/^[a-f0-9]{32}$/.test(nonce)) {
    throw new Error('Disposable media proof requires a per-run synthetic fixture identity');
  }
  if (apiUrl !== undefined) requireDisposableMediaApiTarget(apiUrl);
  // Deliberately omit HOME, PG*, PSQL*, loader, proxy and credential variables.
  // -X also forbids psql startup files; -w forbids interactive password fallback.
  const childEnv = Object.freeze({ PATH: env.PATH || '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' });
  const guard = `DO $media_target$ BEGIN
    IF current_database() <> 'postgres' OR session_user <> 'postgres'
       OR current_setting('server_version_num')::integer / 10000 <> 17
       OR pg_is_in_recovery()
       OR (SELECT count(*) FROM public.heha_media_proof_identity) <> 1
       OR (SELECT nonce FROM public.heha_media_proof_identity WHERE singleton) IS DISTINCT FROM '${nonce}'
    THEN RAISE EXCEPTION 'Disposable media fixture identity mismatch'; END IF;
  END $media_target$;`;
  return Object.freeze({ databaseUrl, nonce, childEnv, guard });
}

export function createDisposableMediaPsql(databaseUrl, env = process.env, apiUrl) {
  const target = requireDisposableMediaTarget(databaseUrl, env, apiUrl);
  // Every session (including cleanup and asynchronous race sessions) checks the
  // marker before consuming any caller SQL. ON_ERROR_STOP prevents continuation.
  const args = Object.freeze(['-X', '-w', '--dbname=' + target.databaseUrl,
    '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-qAt', '-c', target.guard, '-f', '-']);
  const options = { encoding: 'utf8', env: target.childEnv, stdio: ['pipe', 'pipe', 'pipe'] };
  return Object.freeze({
    nonce: target.nonce,
    verify: () => execFileSync('psql', args, { ...options, input: '' }),
    sql: (input) => execFileSync('psql', args, { ...options, input }),
    result: (input) => spawnSync('psql', args, { ...options, input }),
    session: () => spawn('psql', args, { env: target.childEnv, stdio: ['pipe', 'pipe', 'pipe'] }),
  });
}

export async function verifyDisposableMediaApi(apiUrl, key, service, nonce, request = fetch) {
  requireDisposableMediaApiTarget(apiUrl);
  const response = await request(apiUrl + '/rest/v1/heha_media_proof_identity?select=nonce', {
    method: 'GET', redirect: 'error',
    headers: { apikey: key, Authorization: 'Bearer ' + service },
  });
  const rows = response.ok ? await response.json() : null;
  if (!Array.isArray(rows) || rows.length !== 1 || rows[0].nonce !== nonce) {
    throw new Error('Disposable API/database fixture identity mismatch');
  }
}
