// Select one exact, real predecessor body inside the disposable full-chain DB.
// The hosted fixture is read-only evidence translated into a local-only replay;
// this script never accepts a hosted database target.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createDisposableMediaPsql } from "./disposable_media_target.mjs";

const variants = Object.freeze({
  repository: "ff6a09e7cd7be3aa64544af7e79724e7",
  hosted: "ee900bcda5fdabd3e5400358ed09158d",
});
const variant = process.env.HEHA_MEDIA_PREDECESSOR;
assert.ok(Object.hasOwn(variants, variant), "Expected repository or hosted predecessor variant");

const database = createDisposableMediaPsql(process.env.DATABASE_URL);
if (variant === "hosted") {
  database.sql(readFileSync(
    "supabase/tests/fixtures/partner_media_hosted_guard_predecessor.sql",
    "utf8",
  ));
}

const result = database.sql(`
SELECT jsonb_build_object(
  'body_md5',md5(p.prosrc),
  'owner',pg_get_userbyid(p.proowner),
  'language',l.lanname,
  'security_definer',p.prosecdef,
  'volatility',p.provolatile,
  'strict',p.proisstrict,
  'leakproof',p.proleakproof,
  'parallel',p.proparallel,
  'kind',p.prokind,
  'returns',p.prorettype::regtype::text,
  'config',p.proconfig,
  'acl',p.proacl::text,
  'claim_helper',to_regprocedure('app_private.verified_permanent_claim_email(uuid)') IS NOT NULL,
  'claim_invites',to_regclass('public.partner_claim_invites') IS NOT NULL,
  'claim_events',to_regclass('public.partner_lifecycle_events') IS NOT NULL,
  'publication_review',to_regclass('public.partner_publication_review_events') IS NOT NULL,
  'app_private_locked',NOT has_schema_privilege('authenticated','app_private','USAGE')
)::text
FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
WHERE p.oid='app_private.guard_partner_media_request()'::regprocedure;
`);
const observed = JSON.parse(result.trim());
assert.deepEqual(observed, {
  body_md5: variants[variant],
  owner: "postgres",
  language: "plpgsql",
  security_definer: true,
  volatility: "v",
  strict: false,
  leakproof: false,
  parallel: "u",
  kind: "f",
  returns: "trigger",
  config: ["search_path=pg_catalog, public, app_private, auth, pg_temp"],
  acl: "{postgres=X/postgres}",
  claim_helper: true,
  claim_invites: true,
  claim_events: true,
  publication_review: true,
  app_private_locked: true,
});
process.stdout.write(JSON.stringify({
  predecessor_variant: variant,
  predecessor_body_md5: observed.body_md5,
  prerequisite_order: "publication/claim chain before owner-path, assisted-intake and shared-boundary",
  result: "pass",
}) + "\n");
