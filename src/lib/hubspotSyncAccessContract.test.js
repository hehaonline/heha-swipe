import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const expectedPartnerFields = [
  "name",
  "category",
  "contact",
  "instagram",
  "website",
  "bio",
  "phone",
  "partner_type",
  "neighborhood",
  "hours",
];

test("HubSpot sync uses only the exact service RPC partner projection", async () => {
  const [edgeFunction, migration] = await Promise.all([
    readFile(path.join(repoRoot, "supabase/functions/hubspot-sync/index.ts"), "utf8"),
    readFile(
      path.join(
        repoRoot,
        "supabase/migrations/20260817171238_partner_publication_integration_rc.sql"
      ),
      "utf8"
    ),
  ]);

  assert.doesNotMatch(
    edgeFunction,
    /\.from\(\s*["']partners["']\s*\)/,
    "hubspot-sync must not read raw public.partners"
  );
  assert.match(
    edgeFunction,
    /\.rpc\(\s*["']get_partner_hubspot_sync_source["']\s*,\s*\{\s*p_partner_id:\s*queue\.partner_id\s*\}\s*\)/,
    "hubspot-sync must obtain its partner source through the scoped service RPC"
  );

  const partnerType = edgeFunction.match(/type PartnerRow = \{([\s\S]*?)\n\};/);
  assert.ok(partnerType, "hubspot-sync must keep an explicit PartnerRow contract");
  const partnerFields = [...partnerType[1].matchAll(/^\s+([a-z_]+):/gm)]
    .map((match) => match[1]);
  assert.deepEqual(partnerFields, expectedPartnerFields);

  const rpcDefinition = migration.match(
    /create or replace function public\.get_partner_hubspot_sync_source\([\s\S]*?returns table \(([\s\S]*?)\n\)\nlanguage plpgsql/
  );
  assert.ok(rpcDefinition, "RC migration must define the HubSpot sync source RPC");
  const rpcFields = [...rpcDefinition[1].matchAll(/^\s+([a-z_]+)\s+text,?$/gm)]
    .map((match) => match[1]);
  assert.deepEqual(rpcFields, expectedPartnerFields);

  assert.match(
    migration,
    /create or replace function public\.get_partner_hubspot_sync_source\([\s\S]*?security definer[\s\S]*?set search_path=''[\s\S]*?app_private\.is_service_role_request\(\)/
  );
  assert.match(
    migration,
    /revoke all on function public\.get_partner_hubspot_sync_source\(uuid\)\s+from public,anon,authenticated,service_role;\s*grant execute on function public\.get_partner_hubspot_sync_source\(uuid\)\s+to service_role;/
  );
});
