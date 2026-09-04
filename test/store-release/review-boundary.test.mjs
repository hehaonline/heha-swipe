import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflowPath = (name) =>
  new URL(`../../.github/workflows/${name}`, import.meta.url);

test("store SQL stays in review_only and out of release automation", async () => {
  const workflows = await Promise.all([
    readFile(workflowPath("store-release-candidate.yml"), "utf8"),
    readFile(workflowPath("android-pr-validation.yml"), "utf8"),
  ]);

  for (const workflow of workflows) {
    assert.doesNotMatch(workflow, /supabase\s+db\s+(push|reset)/i);
    assert.doesNotMatch(workflow, /migration/i);
  }
});

test("pull request Android verification is secretless and unsigned", async () => {
  const workflow = await readFile(
    workflowPath("android-pr-validation.yml"),
    "utf8"
  );

  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /contents: read/);
  assert.match(workflow, /testDebugUnitTest/);
  assert.match(workflow, /assembleDebug/);
  assert.doesNotMatch(workflow, /secrets\./);
  assert.doesNotMatch(workflow, /^\s+environment:/m);
  assert.doesNotMatch(workflow, /bundleRelease/);
  assert.doesNotMatch(workflow, /upload-artifact/);
  assert.doesNotMatch(workflow, /workflow_dispatch/);
});

test("signed Android bundle remains a manual environment-gated job", async () => {
  const workflow = await readFile(
    workflowPath("store-release-candidate.yml"),
    "utf8"
  );

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /environment: store-review/);
  assert.match(workflow, /secrets\./);
  assert.match(workflow, /bundleRelease/);
  assert.doesNotMatch(workflow, /pull_request:/);
});
