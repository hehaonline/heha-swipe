#!/usr/bin/env node

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const EXPECTED_CAPTURE_SHA256 = 'ffbfa95fb33f45dbe67bf0905afbe8424d2f61ef51ea1c073d2cf9ff3aa2d176';

const MUTATING_OR_SIDE_EFFECTING_WORDS = new Set([
  'alter',
  'analyze',
  'call',
  'checkpoint',
  'cluster',
  'comment',
  'copy',
  'create',
  'delete',
  'deallocate',
  'discard',
  'do',
  'drop',
  'execute',
  'grant',
  'insert',
  'lock',
  'listen',
  'load',
  'merge',
  'nextval',
  'notify',
  'refresh',
  'reindex',
  'reset',
  'revoke',
  'set_config',
  'setval',
  'table',
  'truncate',
  'update',
  'unlisten',
  'vacuum'
]);

const ALLOWED_RELATIONS = new Set([
  'catalog_rows',
  'pg_catalog.pg_attrdef',
  'pg_catalog.pg_attribute',
  'pg_catalog.pg_class',
  'pg_catalog.pg_collation',
  'pg_catalog.pg_constraint',
  'pg_catalog.pg_enum',
  'pg_catalog.pg_index',
  'pg_catalog.pg_namespace',
  'pg_catalog.pg_sequence',
  'pg_catalog.pg_type',
  'target_schemas'
]);

const ALLOWED_CALLS = new Set([
  'catalog_rows',
  'pg_catalog.col_description',
  'pg_catalog.format',
  'pg_catalog.format_type',
  'pg_catalog.jsonb_build_object',
  'pg_catalog.obj_description',
  'target_schemas'
]);

const NON_CALL_PAREN_WORDS = new Set([
  'all',
  'any',
  'as',
  'exists',
  'filter',
  'in',
  'over',
  'values',
  'within'
]);

function lineNumber(text, offset) {
  let line = 1;
  for (let index = 0; index < offset; index += 1) {
    if (text[index] === '\n') line += 1;
  }
  return line;
}

function dollarDelimiterAt(text, offset) {
  const match = text.slice(offset).match(/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/);
  return match?.[0] ?? null;
}

function isIdentifierStart(character) {
  return /[A-Za-z_]/.test(character ?? '');
}

function isIdentifierPart(character) {
  return /[A-Za-z0-9_$]/.test(character ?? '');
}

function isEscapeStringPrefix(text, quoteOffset) {
  if (!/[Ee]/.test(text[quoteOffset - 1] ?? '')) return false;
  return !isIdentifierPart(text[quoteOffset - 2]);
}

export function readOnlyProblems(text, path = 'capture.sql') {
  const problems = [];
  const words = [];
  const tokens = [];
  let index = 0;
  let state = 'normal';
  let blockDepth = 0;
  let dollarDelimiter = null;
  let escapeString = false;
  let doubleQuoteStart = 0;
  let doubleQuoteValue = '';

  while (index < text.length) {
    const character = text[index];
    const next = text[index + 1];

    if (state === 'line-comment') {
      if (character === '\n') state = 'normal';
      index += 1;
      continue;
    }

    if (state === 'block-comment') {
      if (character === '/' && next === '*') {
        blockDepth += 1;
        index += 2;
      } else if (character === '*' && next === '/') {
        blockDepth -= 1;
        index += 2;
        if (blockDepth === 0) state = 'normal';
      } else {
        index += 1;
      }
      continue;
    }

    if (state === 'single-quote') {
      if (escapeString && character === '\\') {
        index += Math.min(2, text.length - index);
      } else if (character === "'" && next === "'") {
        index += 2;
      } else if (character === "'") {
        state = 'normal';
        index += 1;
      } else {
        index += 1;
      }
      continue;
    }

    if (state === 'double-quote') {
      if (character === '"' && next === '"') {
        doubleQuoteValue += '"';
        index += 2;
      } else if (character === '"') {
        tokens.push({
          type: 'word',
          value: doubleQuoteValue.toLowerCase(),
          offset: doubleQuoteStart,
          quoted: true
        });
        state = 'normal';
        index += 1;
      } else {
        doubleQuoteValue += character;
        index += 1;
      }
      continue;
    }

    if (state === 'dollar-quote') {
      if (text.startsWith(dollarDelimiter, index)) {
        index += dollarDelimiter.length;
        dollarDelimiter = null;
        state = 'normal';
      } else {
        index += 1;
      }
      continue;
    }

    if (character === '-' && next === '-') {
      state = 'line-comment';
      index += 2;
      continue;
    }
    if (character === '/' && next === '*') {
      state = 'block-comment';
      blockDepth = 1;
      index += 2;
      continue;
    }
    if (character === "'") {
      escapeString = isEscapeStringPrefix(text, index);
      state = 'single-quote';
      index += 1;
      continue;
    }
    if (character === '"') {
      doubleQuoteStart = index;
      doubleQuoteValue = '';
      state = 'double-quote';
      index += 1;
      continue;
    }
    if (character === '$') {
      const delimiter = dollarDelimiterAt(text, index);
      if (delimiter) {
        dollarDelimiter = delimiter;
        state = 'dollar-quote';
        index += delimiter.length;
        continue;
      }
    }
    if (character === '\\') {
      problems.push(
        `${path}:${lineNumber(text, index)}: psql meta-commands are forbidden`
      );
      index += 1;
      continue;
    }
    if (isIdentifierStart(character)) {
      let end = index + 1;
      while (isIdentifierPart(text[end])) end += 1;
      const word = text.slice(index, end).toLowerCase();
      words.push(word);
      tokens.push({ type: 'word', value: word, offset: index });
      if (MUTATING_OR_SIDE_EFFECTING_WORDS.has(word)) {
        problems.push(
          `${path}:${lineNumber(text, index)}: disallowed SQL keyword ${word}`
        );
      }
      index = end;
      continue;
    }
    if (character === ';') {
      tokens.push({ type: 'semicolon', value: ';', offset: index });
    } else if (['.', '(', ')', ','].includes(character)) {
      tokens.push({ type: 'symbol', value: character, offset: index });
    }
    index += 1;
  }

  if (state !== 'normal' && state !== 'line-comment') {
    problems.push(`${path}: unterminated SQL ${state.replaceAll('-', ' ')}`);
  }

  const statements = [[]];
  for (const token of tokens) {
    if (token.type === 'semicolon') {
      if (statements.at(-1).length > 0) statements.push([]);
      continue;
    }
    statements.at(-1).push(token);
  }
  if (statements.at(-1).length === 0) statements.pop();
  const statementWords = statements.map((statement) =>
    statement.map((token) => token.value)
  );

  if (
    statementWords[0]?.join(' ') !== 'begin' ||
    statementWords[1]?.join(' ') !== 'set transaction read only'
  ) {
    problems.push(
      `${path}: first executable statements must begin the read-only transaction`
    );
  }
  if (statementWords.at(-1)?.join(' ') !== 'commit') {
    problems.push(`${path}: final executable statement must be COMMIT`);
  }
  if (
    statements.length !== 5 ||
    statementWords[2]?.join(' ') !== 'set local search_path pg_catalog' ||
    statements[3]?.[0]?.value !== 'with'
  ) {
    problems.push(
      `${path}: capture must contain exactly BEGIN; SET TRANSACTION READ ONLY; SET LOCAL search_path; one WITH/SELECT capture; COMMIT`
    );
  }

  const transactionControl = new Set([
    'abort',
    'begin',
    'commit',
    'end',
    'prepare',
    'release',
    'rollback',
    'savepoint',
    'start'
  ]);
  for (const [statementIndex, statement] of statements.entries()) {
    const allowedOpening = statementIndex === 0 && statementWords[statementIndex].join(' ') === 'begin';
    const allowedReadOnly =
      statementIndex === 1 &&
      statementWords[statementIndex].join(' ') === 'set transaction read only';
    const allowedLocalSearchPath =
      statementWords[statementIndex].join(' ') === 'set local search_path pg_catalog';
    const allowedCommit =
      statementIndex === statements.length - 1 &&
      statementWords[statementIndex].join(' ') === 'commit';
    if (allowedOpening || allowedReadOnly || allowedLocalSearchPath || allowedCommit) continue;

    const first = statement[0];
    if (first && (transactionControl.has(first.value) || first.value === 'set')) {
      problems.push(
        `${path}:${lineNumber(text, first.offset)}: transaction control is forbidden inside the capture`
      );
    }
  }

  function qualifiedNameAt(start) {
    const first = tokens[start];
    if (first?.type !== 'word') return null;
    const parts = [first.value];
    let quoted = first.quoted === true;
    let end = start;
    while (
      tokens[end + 1]?.value === '.' &&
      tokens[end + 2]?.type === 'word'
    ) {
      parts.push(tokens[end + 2].value);
      quoted ||= tokens[end + 2].quoted === true;
      end += 2;
    }
    return { name: parts.join('.'), end, quoted };
  }

  const depthBefore = [];
  let parenthesisDepth = 0;
  for (const [tokenIndex, token] of tokens.entries()) {
    depthBefore[tokenIndex] = parenthesisDepth;
    if (token.value === '(') parenthesisDepth += 1;
    else if (token.value === ')') parenthesisDepth = Math.max(0, parenthesisDepth - 1);
  }

  const fromClauseBoundaries = new Set([
    'cross', 'fetch', 'for', 'full', 'group', 'having', 'inner', 'join',
    'left', 'limit', 'offset', 'on', 'order', 'right', 'union', 'where', 'window'
  ]);

  for (let tokenIndex = 0; tokenIndex < tokens.length; tokenIndex += 1) {
    const token = tokens[tokenIndex];
    if (token.type !== 'word') continue;

    if (token.value === 'from' || token.value === 'join') {
      const relation = qualifiedNameAt(tokenIndex + 1);
      if (!relation || relation.quoted || !ALLOWED_RELATIONS.has(relation.name)) {
        problems.push(
          `${path}:${lineNumber(text, token.offset)}: relation outside the approved catalog/CTE allowlist`
        );
      }
      if (relation) {
        const baseDepth = depthBefore[tokenIndex];
        for (let lookahead = relation.end + 1; lookahead < tokens.length; lookahead += 1) {
          const candidate = tokens[lookahead];
          if (candidate.type === 'semicolon') break;
          if (candidate.value === ')' && depthBefore[lookahead] === baseDepth) break;
          if (
            candidate.type === 'word' &&
            depthBefore[lookahead] === baseDepth &&
            fromClauseBoundaries.has(candidate.value)
          ) break;
          if (candidate.value === ',' && depthBefore[lookahead] === baseDepth) {
            problems.push(
              `${path}:${lineNumber(text, candidate.offset)}: comma-separated relation sources are forbidden`
            );
            break;
          }
        }
      }
    }

    if (tokens[tokenIndex - 1]?.value === '.') continue;
    const call = qualifiedNameAt(tokenIndex);
    if (
      call &&
      tokens[call.end + 1]?.value === '(' &&
      !NON_CALL_PAREN_WORDS.has(call.name) &&
      (call.quoted || !ALLOWED_CALLS.has(call.name))
    ) {
      problems.push(
        `${path}:${lineNumber(text, token.offset)}: callable ${call.name} is outside the approved catalog allowlist`
      );
    }
  }

  return [...new Set(problems)];
}

function selfTest() {
  const safe = String.raw`-- insert update \copy
begin;
set transaction read only;
set local search_path = pg_catalog;
with target_schemas(schema_name) as (values ('public'))
select 'drop', E'\\copy', $$delete$$, "update" from target_schemas;
commit;`;
  assert.deepEqual(readOnlyProblems(safe, 'safe.sql'), []);

  const bad = [
    String.raw`\copy public.example from '/tmp/example'
begin; set transaction read only; select 1; commit;`,
    'begin; set transaction read only; insert into x values (1); commit;',
    'begin; set transaction read only; select 1; \\g /tmp/out; commit;',
    'begin; set transaction read only; commit; begin; set transaction read write; select 1 into created_by_capture; commit;',
    'begin; set transaction read only; select 1; commit; select 2;',
    'begin; set transaction read only; savepoint unsafe; select 1; commit;',
    "begin; set transaction read only; select 1; prepare transaction 'left_behind'; commit;",
    "begin; set transaction read only; select pg_catalog.set_config('search_path', 'public, pg_catalog', false); commit;",
    "begin; set transaction read only; select pg_catalog.nextval('public.some_seq'); commit;",
    "begin; set transaction read only; select pg_catalog.setval('public.some_seq', 1); commit;",
    'begin; set transaction read only; select email from auth.users; commit;',
    'begin; set transaction read only; select email from "auth"."users"; commit;',
    'begin; set transaction read only; select pg_catalog.pg_advisory_lock(1); commit;',
    "begin; set transaction read only; select 'safe\\'; drop table x; commit;",
    'begin; set transaction read only; /* nested /* comment */ update x; commit;',
    'select 1; commit;',
    'begin; set transaction read only; select $$unterminated; commit;'
    ,"begin; set transaction read only; set local search_path = pg_catalog; with target_schemas(schema_name) as (values ('public')) select c.relname from pg_catalog.pg_class c, auth.users u; commit;"
    ,"begin; set transaction read only; set local search_path = pg_catalog; with target_schemas(schema_name) as (values ('public')) table auth.users; commit;"
    ,"begin; set transaction read only; set local search_path = pg_catalog; with target_schemas(schema_name) as (values ('public')) select relname from \"PG_CATALOG\".\"PG_CLASS\"; commit;"
  ];
  for (const [position, fixture] of bad.entries()) {
    assert.notDeepEqual(
      readOnlyProblems(fixture, `bad-${position + 1}.sql`),
      [],
      `negative fixture ${position + 1} unexpectedly passed`
    );
  }
  console.log('PASS: capture query read-only adversarial controls.');
}

if (process.argv[2] === '--self-test') {
  selfTest();
  process.exit(0);
}

if (process.argv.length !== 3) {
  throw new Error(
    'usage: node scripts/verify-capture-query-read-only.mjs <capture.sql>'
  );
}

const path = process.argv[2];
const source = readFileSync(path, 'utf8');
const fingerprint = createHash('sha256').update(source, 'utf8').digest('hex');
if (fingerprint !== EXPECTED_CAPTURE_SHA256) {
  throw new Error(
    `${path}: capture bytes changed; required security review fingerprint does not match`
  );
}
const problems = readOnlyProblems(source, path);
if (problems.length > 0) {
  for (const problem of problems) console.error(problem);
  throw new Error(`capture query read-only verification failed (${problems.length})`);
}
console.log(`PASS: ${path} is structurally read-only and contains no psql meta-command.`);
