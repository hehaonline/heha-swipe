import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function source(path) {
  return readFile(new URL(`../../${path}`, import.meta.url), "utf8");
}

test("store contact requests are gated at both UI and persistence handler layers", async () => {
  const [app, faves] = await Promise.all([
    source("src/App.jsx"),
    source("src/components/FavesTab.jsx"),
  ]);

  assert.match(app, /if \(!releasePolicy\.contactRequests\) return;/);
  assert.match(app, /allowContactRequests=\{releasePolicy\.contactRequests\}/);
  assert.match(faves, /if \(!allowContactRequests \|\| !selectedPartner\) return;/);
  assert.match(faves, /allowContactRequests && !partner\.heha_partner/);
});

test("store auth uses the configured canonical redirect while web keeps its origin", async () => {
  const auth = await source("src/components/AuthScreen.jsx");
  assert.match(auth, /releasePolicy\.storeBuild/);
  assert.match(auth, /canonicalPublicAppUrl\(import\.meta\.env\.VITE_PUBLIC_APP_URL\)/);
  assert.match(auth, /: window\.location\.origin/);
});

test("public legal pages are effective copy and do not show review-draft labels", async () => {
  const legal = await source("src/components/LegalPage.jsx");
  assert.doesNotMatch(legal, /Draft for store review/i);
  assert.match(legal, /Effective September 3, 2026/);
  assert.match(legal, /provided by Healthy Habit LLC/i);
  assert.match(legal, /Supabase for authentication and database services/i);
  assert.match(legal, /Vercel for web hosting/i);
  assert.match(legal, /We do not sell personal information/i);
  assert.match(legal, /We use HTTPS/i);
  assert.match(legal, /backup and security-log copies expire through normal retention cycles/i);
  assert.match(legal, /does not request precise device location/i);
  assert.match(legal, /discount requests/i);
  assert.match(legal, /Request account deletion by email/i);
});
