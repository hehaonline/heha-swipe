import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("store SQL stays in review_only and is not wired into release automation", async () => {
  const workflow = await readFile(
    new URL("../../.github/workflows/store-release-candidate.yml", import.meta.url),
    "utf8"
  );
  assert.doesNotMatch(workflow, /supabase\s+db\s+(push|reset)/i);
  assert.doesNotMatch(workflow, /migration/i);
  assert.match(workflow, /workflow_dispatch/);
});
