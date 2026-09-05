import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const script = fileURLToPath(
  new URL("../../scripts/require-store-runtime-env.mjs", import.meta.url),
);

function run(overrides = {}) {
  const env = {
    ...process.env,
    VITE_SUPABASE_URL: "https://project-ref.supabase.co",
    VITE_SUPABASE_ANON_KEY: `sb_publishable_${"a".repeat(32)}`,
    ...overrides,
  };

  return spawnSync(process.execPath, [script], {
    encoding: "utf8",
    env,
  });
}

test("accepts a plausible public Supabase runtime configuration", () => {
  const result = run();

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Store runtime environment is valid/);
});

test("fails closed when store runtime values are missing", () => {
  const result = run({
    VITE_SUPABASE_URL: "",
    VITE_SUPABASE_ANON_KEY: "",
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /VITE_SUPABASE_URL is missing/);
  assert.match(result.stderr, /VITE_SUPABASE_ANON_KEY is missing/);
});

test("rejects placeholder values without printing the key", () => {
  const placeholderKey = "replace-me-with-an-anon-key";
  const result = run({
    VITE_SUPABASE_URL: "https://your-project.supabase.co",
    VITE_SUPABASE_ANON_KEY: placeholderKey,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /VITE_SUPABASE_URL is a placeholder/);
  assert.match(result.stderr, /VITE_SUPABASE_ANON_KEY is a placeholder/);
  assert.doesNotMatch(result.stderr, new RegExp(placeholderKey));
});

test("rejects malformed and non-HTTPS URLs", () => {
  for (const url of ["not-a-url", "http://project-ref.supabase.co"]) {
    const result = run({ VITE_SUPABASE_URL: url });

    assert.equal(result.status, 1, `expected ${url} to fail`);
    assert.match(result.stderr, /VITE_SUPABASE_URL/);
  }
});

test("rejects implausible and secret keys without printing them", () => {
  for (const key of ["too-short", `sb_secret_${"s".repeat(32)}`]) {
    const result = run({ VITE_SUPABASE_ANON_KEY: key });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /VITE_SUPABASE_ANON_KEY/);
    assert.doesNotMatch(result.stderr, new RegExp(key));
  }
});

test("release workflow validates runtime configuration before building", async () => {
  const [workflow, packageText] = await Promise.all([
    readFile(
      new URL("../../.github/workflows/store-release-candidate.yml", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../../package.json", import.meta.url), "utf8"),
  ]);
  const validation = workflow.indexOf("npm run env:check:store");
  const build = workflow.indexOf("npm run build:store");
  const scripts = JSON.parse(packageText).scripts;

  assert.notEqual(validation, -1);
  assert.notEqual(build, -1);
  assert.ok(validation < build, "runtime validation must run before the store build");
  assert.match(scripts["build:store"], /^npm run env:check:store && /);
  assert.match(scripts["native:sync"], /npm run build:store/);
  assert.match(scripts["release:verify"], /npm run build:store/);
});
