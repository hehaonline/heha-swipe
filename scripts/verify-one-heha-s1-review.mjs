import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const paths = {
  contract: 'contracts/one-heha-s1-swipe-foundation-v1.json',
  baseline: 'supabase/review_only/one_heha_s1/000_minimal_baseline.sql',
  identity: 'supabase/review_only/one_heha_s1/001_private_identity.sql',
  communityPass: 'supabase/review_only/one_heha_s1/002_community_pass_foundation.sql',
  transitions: 'supabase/review_only/one_heha_s1/003_transition_functions.sql',
  rollback: 'supabase/review_only/one_heha_s1/rollback/001_s1.rollback.sql',
  proof: 'supabase/review_only/one_heha_s1/proof/001_s1.proof.sql',
  concurrency: 'supabase/review_only/one_heha_s1/proof/concurrency_two_client.sh',
  documentation: 'docs/architecture/one-heha-s1-swipe-identity-community-pass-foundation.md',
  workflow: '.github/workflows/one-heha-s1-review-proof.yml',
};

const files = Object.fromEntries(
  Object.entries(paths).map(([key, value]) => [key, read(value)]),
);
const contract = JSON.parse(files.contract);

let checks = 0;
function assert(condition, message) {
  checks += 1;
  if (!condition) throw new Error(`S1 verification failed: ${message}`);
}

function tableBlock(sql, qualifiedName) {
  const escaped = qualifiedName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = sql.match(
    new RegExp(`create table if not exists ${escaped} \\(([\\s\\S]*?)\\n\\);`, 'i'),
  );
  assert(Boolean(match), `missing table block ${qualifiedName}`);
  return match[1];
}

function hasBareUserId(block) {
  return /\n\s*user_id\s+/i.test(`\n${block}`);
}

assert(contract.contract_version === 'one-heha-s1-swipe-foundation-v1', 'contract version');
assert(contract.status === 'review-only', 'review-only status');
assert(contract.production_authorization === false, 'Production authorization must be false');
assert(contract.base_sha === 'a8abb46c4908c9f216c589dd35ab7369a8f6cba9', 'pinned current Swipe base');
assert(contract.authority.canonical_consumer_identity === 'heha_local_auth_user_id', 'Local Auth authority');
assert(contract.authority.canonical_business_identity === 'heha_swipe_partners_id', 'Swipe business authority');
assert(contract.authority.email_is_identity_authority === false, 'email must not be identity authority');
assert(contract.authority.browser_may_submit_canonical_user_id === false, 'browser canonical ID denial');
assert(contract.package.standard_migration_path_allowed === false, 'standard migration path prohibited');
assert(contract.package.application_code_allowed === false, 'application code prohibited');
assert(contract.package.real_accounts_allowed === false, 'real accounts prohibited');
assert(contract.package.provider_calls_allowed === false, 'provider calls prohibited');
assert(contract.package.paid_infrastructure_allowed === false, 'paid infrastructure prohibited');
assert(contract.identity_objects.link_handshakes.max_lifetime_seconds === 300, 'five-minute handshake');
assert(contract.identity_objects.link_handshakes.max_reauthentication_age_seconds === 600, 'ten-minute reauthentication');
assert(contract.identity_objects.link_handshakes.raw_nonce_stored === false, 'raw nonce prohibited');
assert(contract.identity_objects.link_handshakes.raw_assertion_stored === false, 'raw assertion prohibited');
assert(contract.community_pass_objects.account_owner_column === 'canonical_user_id', 'canonical account owner');
assert(contract.community_pass_objects.account_owner_cross_project_fk === false, 'cross-project FK prohibited');
assert(contract.community_pass_objects.child_owner_column === 'account_id', 'child account ownership');
assert(contract.community_pass_objects.duplicated_swipe_user_id_allowed === false, 'child Swipe user ID prohibited');
assert(contract.community_pass_objects.active_benefit_states.length === 3, 'three active benefit states');
assert(contract.community_pass_objects.amount_contract.monthly_min_cents === 200, '$2 minimum');
assert(contract.community_pass_objects.amount_contract.monthly_max_cents === 10000, '$100 maximum');
assert(contract.community_pass_objects.amount_contract.six_month_cents === 1500, '$15 prepaid');
assert(contract.community_pass_objects.amount_contract.twelve_month_cents === 2500, '$25 prepaid');
assert(contract.server_functions.activate_identity_link.same_request_idempotent === true, 'activation idempotency');
assert(contract.server_functions.activate_identity_link.concurrent_conflicts_fail_closed === true, 'conflict fail-close');
assert(contract.server_functions.revoke_identity_for_canonical_user.provider_cancellation_fabricated === false, 'provider cancellation truth');
assert(contract.prohibited.includes('production_apply'), 'Production apply prohibition');
assert(contract.prohibited.includes('live_stripe_action'), 'live Stripe prohibition');
assert(contract.prohibited.includes('member_benefit_activation'), 'benefit activation prohibition');

for (const filePath of Object.values(paths)) {
  assert(!filePath.startsWith('supabase/migrations/'), `${filePath} must remain outside standard migrations`);
}

assert(files.baseline.includes('example.invalid'), 'synthetic-only baseline identities');
assert(files.baseline.includes('create role service_role nologin bypassrls'), 'synthetic service role');
assert(files.baseline.includes('create table if not exists auth.users'), 'synthetic Auth boundary');

for (const schema of ['one_heha_private', 'community_pass_private']) {
  assert(files.identity.includes(`create schema if not exists ${schema}`), `create private schema ${schema}`);
  assert(files.identity.includes(`revoke all on schema ${schema} from anon`), `anon schema denial ${schema}`);
  assert(files.identity.includes(`revoke all on schema ${schema} from authenticated`), `authenticated schema denial ${schema}`);
}

const linkBlock = tableBlock(files.identity, 'one_heha_private.identity_links');
assert(/canonical_user_id uuid/i.test(linkBlock), 'identity link canonical UUID');
assert(/swipe_user_id uuid references auth\.users\(id\)/i.test(linkBlock), 'Swipe Auth source FK');
assert(!/canonical_user_id uuid references/i.test(linkBlock), 'canonical UUID must not have cross-project FK');
assert(files.identity.includes('identity_links_active_canonical_unique'), 'canonical active uniqueness');
assert(files.identity.includes('identity_links_active_swipe_unique'), 'Swipe active uniqueness');
assert(files.identity.includes('identity_events_append_only'), 'identity event append-only trigger');
assert(files.identity.includes('alter table one_heha_private.identity_links force row level security'), 'private forced RLS');

const handshakeBlock = tableBlock(files.identity, 'one_heha_private.link_handshakes');
assert(handshakeBlock.includes("expires_at <= created_at + interval '5 minutes'"), 'maximum handshake lifetime');
assert(handshakeBlock.includes('identity_classification'), 'identity classification field');
assert(!/raw_nonce|raw_assertion|signed_assertion/i.test(handshakeBlock), 'no raw nonce/assertion column');
assert(files.identity.includes('link_handshakes_jti_unique'), 'one-time JTI uniqueness');
assert(files.identity.includes('link_handshakes_pending_swipe_unique'), 'one pending handshake per Swipe user');

const accountBlock = tableBlock(files.communityPass, 'public.community_pass_accounts');
assert(/canonical_user_id uuid/i.test(accountBlock), 'Community Pass canonical owner column');
assert(!hasBareUserId(accountBlock), 'Community Pass account must not contain bare user_id');
assert(!/references auth\.users/i.test(accountBlock), 'Community Pass account must not FK Swipe Auth');
assert(files.communityPass.includes('community_pass_accounts_canonical_unique'), 'canonical account uniqueness');

for (const table of [
  'community_pass_subscriptions',
  'community_pass_purchases',
  'community_pass_entitlements',
  'community_pass_acceptances',
  'community_pass_events',
]) {
  const block = tableBlock(files.communityPass, `public.${table}`);
  assert(/account_id uuid not null references public\.community_pass_accounts\(id\)/i.test(block), `${table} account FK`);
  assert(!hasBareUserId(block), `${table} must not duplicate Swipe user_id`);
}

for (const table of contract.community_pass_objects.tables) {
  assert(files.communityPass.includes(`'${table}'`), `RLS allowlist includes ${table}`);
}
assert(files.communityPass.includes('alter table public.%I force row level security'), 'forced RLS loop');
assert(files.communityPass.includes('revoke all on table public.%I from anon'), 'anon table denial');
assert(files.communityPass.includes('revoke all on table public.%I from authenticated'), 'authenticated table denial');
assert(files.communityPass.includes('community_pass_acceptances_append_only'), 'acceptance append-only trigger');
assert(files.communityPass.includes('community_pass_events_append_only'), 'event append-only trigger');
assert(files.communityPass.includes('community_pass_accounts_trial_used_once'), 'one-time trial trigger');
assert(files.communityPass.includes('selected_amount_cents between 200 and 10000'), 'monthly amount limits');
assert(files.communityPass.includes('selected_amount_cents = 1500'), '$15 clickwrap amount');
assert(files.communityPass.includes('selected_amount_cents = 2500'), '$25 clickwrap amount');

for (const name of [
  'begin_link_handshake',
  'activate_identity_link',
  'resolve_canonical_user_for_swipe',
  'resolve_account_for_swipe_user',
  'create_or_get_account_for_swipe_user',
  'start_trial_for_swipe_user',
  'is_active_for_canonical_user',
  'revoke_identity_for_canonical_user',
]) {
  assert(files.transitions.includes(`function ${name.includes('link') || name.startsWith('revoke') || name.startsWith('resolve_canonical') ? 'one_heha_private' : 'community_pass_private'}.${name}`) || files.transitions.includes(`function one_heha_private.${name}`) || files.transitions.includes(`function community_pass_private.${name}`), `server function ${name}`);
}

assert(!/\bauth\.uid\s*\(/i.test(files.transitions), 'S1 server transitions must not derive Local identity from Swipe auth.uid()');
assert(files.transitions.includes("p_identity_classification is distinct from 'verified_non_sso'"), 'SSO/unverified fail-close');
assert(files.transitions.includes("interval '10 minutes'"), 'recent reauthentication gate');
assert(files.transitions.includes("interval '5 minutes'"), 'five-minute handshake creation');
assert(files.transitions.includes('HEHA_ONE_ASSERTION_REPLAY_DENIED'), 'assertion replay denial');
assert(files.transitions.includes('HEHA_ONE_IDENTITY_LINK_CONFLICT'), 'identity conflict denial');
assert(files.transitions.includes('pg_advisory_xact_lock'), 'transactional concurrency locks');
assert(files.transitions.includes("'one-heha:canonical:'"), 'canonical lock namespace');
assert(files.transitions.includes("'one-heha:swipe:'"), 'Swipe lock namespace');
assert(files.transitions.includes("then 'reconciliation_exception'"), 'provider reconciliation exception');
assert(files.transitions.includes("'provider_reconciliation_required', true"), 'provider liability receipt');
assert(files.transitions.includes("status = 'deleted'"), 'canonical deletion state');
assert(files.transitions.includes('canonical_user_id = null'), 'canonical identity redaction');
assert(files.transitions.includes('grant execute on function %s to service_role'), 'service-only grants');
assert(!/grant\s+execute[\s\S]*\b(?:anon|authenticated)\b/i.test(files.transitions), 'no browser execute grant');

for (const prohibited of [
  /https:\/\/[a-z0-9-]+\.supabase\.co/i,
  /sk_(?:live|test)_[a-z0-9]/i,
  /eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}/,
  /VITE_SUPABASE_/,
  /SUPABASE_SERVICE_ROLE_KEY/,
]) {
  assert(!prohibited.test(files.identity + files.communityPass + files.transitions + files.contract), `prohibited endpoint or credential pattern ${prohibited}`);
}

for (const marker of [
  'sso routes to manual review',
  'unverified email cannot link',
  'dual reauthentication link',
  'different JTI replay denied',
  'expired handshake denied',
  'canonical Community Pass',
  'trial cannot activate twice',
  'deletion and liabilities',
  'account recreation isolation',
]) {
  assert(files.proof.includes(marker), `SQL proof marker ${marker}`);
}
assert(files.proof.includes('Expected 14 S1 proof results'), 'fixed SQL proof result count');
assert(files.proof.includes('rollback;'), 'proof fixture rollback');
assert(files.concurrency.includes('same-request race'), 'same-request two-client race');
assert(files.concurrency.includes('conflicting canonical-link race'), 'conflicting two-client race');
assert(files.concurrency.includes('one stable link ID'), 'stable idempotent result');
assert(files.concurrency.includes('exactly one winner'), 'conflict-safe winner');
assert(files.concurrency.includes('start_canonical_barrier'), 'server-side canonical barrier holder');
assert(files.concurrency.includes('prove_two_clients_waiting'), 'two-client barrier observation');
assert(files.concurrency.includes("l.locktype = 'advisory'"), 'advisory-lock waiter proof');
assert(files.concurrency.includes('and not l.granted'), 'both clients must be blocked before release');
assert(
  (files.concurrency.match(/prove_two_clients_waiting "/g) ?? []).length === 2,
  'both race cases must use the two-client barrier',
);
assert(files.concurrency.startsWith('#!/usr/bin/env bash\nset -euo pipefail'), 'strict concurrency harness');

for (const objectName of [
  'community_pass_stripe_event_inbox',
  'community_pass_events',
  'community_pass_acceptances',
  'community_pass_entitlements',
  'community_pass_purchases',
  'community_pass_subscriptions',
  'community_pass_accounts',
  'identity_events',
  'link_handshakes',
  'identity_links',
]) {
  assert(files.rollback.includes(`drop table if exists ${objectName.startsWith('community_pass_') ? 'public.' : 'one_heha_private.'}${objectName}`), `rollback drops ${objectName}`);
}
assert(files.rollback.includes('drop schema if exists one_heha_private'), 'rollback drops identity schema');
assert(files.rollback.includes('drop schema if exists community_pass_private'), 'rollback drops Community Pass private schema');

assert(files.workflow.includes("postgres: ['15', '17']"), 'PostgreSQL 15/17 matrix');
assert(files.workflow.includes('image: postgres:${{ matrix.postgres }}'), 'matrix-selected PostgreSQL service image');
assert(files.workflow.includes('concurrency_two_client.sh'), 'workflow runs genuine concurrency');
assert(files.workflow.includes('001_s1.rollback.sql'), 'workflow runs rollback');
assert(files.workflow.includes('reapply'), 'workflow proves reapply');
assert(files.workflow.includes('Verify exact review-only scope'), 'workflow file-scope gate');

assert(files.documentation.includes('PR #128 remains donor-only'), 'donor-only Community Pass boundary');
assert(files.documentation.includes('No Production authorization'), 'documentation Production boundary');
assert(files.documentation.includes('S1 does not create a public or authenticated RPC'), 'no browser RPC boundary');
assert(files.documentation.includes('R1 remains a separate approval'), 'hosted rehearsal separate gate');

console.log(`PASS: ONE HEHA S1 review package verified ${checks}/${checks} deterministic source checks.`);
