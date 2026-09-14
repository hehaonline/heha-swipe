import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sourcePath = new URL(
  "../../src/components/OnboardingScreen.jsx",
  import.meta.url
);

test("store onboarding clamps every role-changing path to customer", async () => {
  const source = await readFile(sourcePath, "utf8");

  assert.match(
    source,
    /function getAllowedRole\(nextRole\) \{\s*if \(!releasePolicy\.partnerSelfService\) return "customer";/
  );
  assert.match(source, /const allowedRole = getAllowedRole\(nextRole\);/);
  assert.match(
    source,
    /localStorage\.setItem\("heha_signup_role", allowedRole\);/
  );
  assert.match(source, /const isPartner = getAllowedRole\(role\) === "partner";/);
  assert.match(source, /onComplete\?\.\(getAllowedRole\(role\)\);/);
});

test("store onboarding cannot render partner or change-path controls", async () => {
  const source = await readFile(sourcePath, "utf8");

  assert.match(
    source,
    /releasePolicy\.partnerSelfService && \(\s*<button className="choice-card featured"[\s\S]*?>\s*<span>🏪<\/span>/
  );
  assert.match(
    source,
    /releasePolicy\.partnerSelfService && \(\s*<button className="text-button" onClick=\{\(\) => setStep\("role"\)\}>← Change path<\/button>/
  );
});
