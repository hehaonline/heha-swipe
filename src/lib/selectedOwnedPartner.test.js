import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fetchClaimReturnPartner } from "./partnerClaimFlow.js";
import { fetchSelectedOwnedPartner, selectedOwnedPartner } from "./selectedOwnedPartner.js";

const source = (file) => readFileSync(new URL(`../${file}`, import.meta.url), "utf8");
const app = source("App.jsx");
const profile = source("components/ProfileTab.jsx");
const hub = source("components/CommunityPassTab.jsx");
const editor = source("components/PartnerProfileEditor.jsx");
const media = source("components/PartnerMediaManager.jsx");
const owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const older = { id: "11111111-1111-4111-8111-111111111111", owner_id: owner,
  name: "Canonical A", category: "Restaurant", categories: ["Restaurant", "Vendor"], created_at: "2020-01-01" };
const newer = { ...older, id: "22222222-2222-4222-8222-222222222222", name: "Newer B", created_at: "2026-01-01" };

function clientFor(rows = [newer, older]) {
  const calls = [];
  return { calls, from(table) {
    const call = { table, filters: [] }; calls.push(call);
    return {
      select(projection) { call.projection = projection; return this; },
      eq(column, value) { call.filters.push([column, value]); return this; },
      async maybeSingle() {
        const found = rows.filter((row) => call.filters.every(([key, value]) => row[key] === value));
        assert.ok(found.length <= 1, "must not select the newest business by omission");
        return { data: found[0] ? Object.fromEntries(call.projection.split(",").map((key) => [key.trim(), found[0][key.trim()]])) : null, error: null };
      },
    };
  } };
}

// Execute the real query helper with each component's literal projection, not a
// hand-maintained approximation. There is no mounted React harness in this repo.
function projection(component) {
  const match = component.match(/fetchSelectedOwnedPartner\(supabase, user\.id, listing\.id,\s*"([^"]+)"\)/);
  assert.ok(match, "child must use owner + App's exact listing id");
  return match[1];
}

test("claim older A while owning newer B keeps profile/publication/editor/media on A", async () => {
  const client = clientFor();
  const claimed = await fetchClaimReturnPartner(client, owner, { partnerId: older.id });
  const profileRow = await fetchSelectedOwnedPartner(client, owner, claimed.id, projection(profile));
  const editorRow = await fetchSelectedOwnedPartner(client, owner, claimed.id, projection(hub));
  assert.equal(profileRow.id, older.id);
  assert.equal(editorRow.id, older.id);
  assert.equal(profileRow.name, "Canonical A");
  assert.deepEqual(editorRow.categories, ["Restaurant", "Vendor"]);
  for (const call of client.calls) assert.deepEqual(call.filters, [["owner_id", owner], ["id", older.id]]);
  for (const component of ["CommunityPassTab", "ProfileTab"]) {
    assert.match(app, new RegExp(`<${component}[\\s\\S]*?listing=\\{myListing\\}`));
    assert.match(app, new RegExp(`<${component}\\s+key=\\{.*session.user.id.*myListing\\?\\.id`));
  }
  assert.match(profile, /getMyPartnerPublicationStatus\(activeListing\.id\)/);
  assert.match(profile, /partnerId: activeListing\.id/);
  assert.match(hub, /listing=\{activeListing\}/);
  for (const component of ["PartnerProfileEditor", "PartnerMediaManager"]) {
    assert.match(hub, new RegExp(`<${component}[\\s\\S]*?listing=\\{listing\\}`));
  }
  assert.match(editor, /const scope = useMemo\(\(\) => \(\{ user, ownerId: user\?\.id, partnerId: listing\?\.id \}\), \[user, user\?\.id, listing\?\.id\]\)/);
  assert.match(editor, /\.eq\("partner_id", scope\.partnerId\)\s*\.eq\("owner_id", scope\.ownerId\)/);
  assert.match(media, /\.eq\("partner_id", listing\.id\)\s*\.eq\("owner_id", user\.id\)/);
  for (const component of [editor, media]) {
    assert.match(component, /partner_id: listing\.id,\s*owner_id: user\.id/);
  }
  assert.match(media, /\$\{user\.id\}\/\$\{listing\.id\}\//);
});

test("missing selection, missing row and owner switch fail closed without fallback", async () => {
  const client = clientFor();
  assert.equal(await fetchSelectedOwnedPartner(client, owner, null, "id"), null);
  assert.equal(client.calls.length, 0);
  assert.equal(await fetchSelectedOwnedPartner(client, "other-owner", older.id, "id"), null);
  assert.equal(await fetchSelectedOwnedPartner(client, owner, "missing-card", "id"), null);
  assert.equal(selectedOwnedPartner(newer, owner, older.id), null);
  assert.equal(selectedOwnedPartner(older, "other-owner", older.id), null);
  assert.equal(selectedOwnedPartner(older, owner, null), null);
  assert.doesNotMatch(profile, /ownedListing\s*\|\|\s*listing/);
  assert.doesNotMatch(hub.slice(hub.indexOf("export default function CommunityPassTab")), /\.order\("created_at"/);
  assert.match(hub, /request === listingRequest\.current/);
  // A same-card media refresh must not unmount the open manager while fetching.
  // Changed owner/card props are already fail-closed through selectedOwnedPartner.
  assert.doesNotMatch(hub, /const request = \+\+listingRequest\.current;\s*setOwnerListing\(null\)/);
  assert.match(hub, /key=\{`\$\{user\?\.id\}:\$\{listing\?\.id\}`\}/);
});

test("mismatched response and query errors cannot authorize controls", async () => {
  const client = { from: () => ({ select() { return this; }, eq() { return this; }, maybeSingle: async () => ({ data: newer }) }) };
  await assert.rejects(fetchSelectedOwnedPartner(client, owner, older.id, "id"), /could not be verified/);
  const failure = new Error("RLS unavailable");
  client.from = () => ({ select() { return this; }, eq() { return this; }, maybeSingle: async () => ({ error: failure }) });
  await assert.rejects(fetchSelectedOwnedPartner(client, owner, older.id, "id"), failure);
});

const { initialForm, buildChanges } = new Function(
  editor.slice(editor.indexOf("const CATEGORIES"), editor.indexOf("export default function"))
    + "\nreturn { initialForm, buildChanges };"
)();

test("editing one field preserves persisted Restaurant + Vendor", async () => {
  const listing = await fetchSelectedOwnedPartner(clientFor(), owner, older.id, projection(hub));
  const form = initialForm(listing);
  assert.deepEqual(form.categories, ["Restaurant", "Vendor"]);
  assert.deepEqual(buildChanges({ ...form, name: "Updated A" }, listing), { name: "Updated A" });
});

test("adding Events preserves the secondary Vendor category in actual editor changes", async () => {
  const listing = await fetchSelectedOwnedPartner(clientFor(), owner, older.id, projection(hub));
  const form = initialForm(listing);
  const changes = buildChanges({ ...form, categories: [...form.categories, "Events"] }, listing);
  assert.deepEqual(changes, { categories: ["Restaurant", "Vendor", "Events"] });
  assert.deepEqual(listing.categories, ["Restaurant", "Vendor"]);
});
