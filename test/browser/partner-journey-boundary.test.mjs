import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const script = readFileSync(resolve(root, "scripts/partner_journey_browser_proof.mjs"), "utf8");
const body = script.match(/resolveId\(source, importer\) \{([\s\S]*?)\n        \},/)[1];
const resolveId = new Function("root", "resolve", "dirname", `return function(source, importer) {${body}}`)(root, resolve, dirname);
const mock = resolve(root, "test/browser/synthetic-supabase.js");

test("actual browser resolver replaces every current relative Supabase import", () => {
  let imports = 0;
  for (const path of readdirSync(resolve(root, "src"), { recursive: true }).filter(path => /\.[jt]sx?$/.test(path))) {
    const file = resolve(root, "src", path);
    for (const match of readFileSync(file, "utf8").matchAll(/from\s+["']([^"']*supabase(?:\.js)?)["']/g)) {
      imports += 1;
      assert.equal(resolveId(match[1], file), mock, `${path}: ${match[1]}`);
    }
  }
  assert.ok(imports > 10, "test must inspect the real import graph, not only fixture imports");
});

test("same-directory and component imports resolve to the identical isolated transport", () => {
  assert.equal(resolveId("./supabase", resolve(root, "src/lib/accountDeletion.js")), mock);
  assert.equal(resolveId("../lib/supabase", resolve(root, "src/components/ProfileTab.jsx")), mock);
  assert.equal(resolveId("./supabase.js", resolve(root, "src/lib/accountDeletion.js") + "?v=123"), mock);
});

test("unrelated files and packages are not aliased", () => {
  assert.equal(resolveId("@supabase/supabase-js", resolve(root, "src/lib/supabase.js")), undefined);
  assert.equal(resolveId("./supabase", resolve(root, "test/browser/unrelated.js")), undefined);
});
