// Native negative control on the freshly-created synthetic instance only.
import assert from 'node:assert/strict';
import { createDisposableMediaPsql } from './disposable_media_target.mjs';
const database = createDisposableMediaPsql(process.env.DATABASE_URL);
database.verify();
const absent = "SELECT to_regclass('public.heha_media_wrong_target_probe') IS NULL;";
assert.equal(database.sql(absent).trim(), 't');
const wrongNonce = (database.nonce[0] === '0' ? '1' : '0') + database.nonce.slice(1);
const wrong = createDisposableMediaPsql(process.env.DATABASE_URL,
  { ...process.env, HEHA_MEDIA_PROOF_NONCE: wrongNonce });
const result = wrong.result('CREATE TABLE public.heha_media_wrong_target_probe(id integer);');
assert.notEqual(result.status, 0);
assert.match(result.stderr, /Disposable media fixture identity mismatch/);
assert.equal(database.sql(absent).trim(), 't', 'wrong-identity SQL must never execute');
console.log('disposable_media_identity=pass; wrong-run mutation rejected before execution');
