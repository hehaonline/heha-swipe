import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const forbiddenEnvName = ["VITE", "MAKE", "PARTNER", "APPROVAL", "WEBHOOK"].join("_");

async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return sourceFiles(entryPath);
    if (/\.(?:js|jsx|ts|tsx)$/.test(entry.name)) return [entryPath];
    return [];
  }));
  return files.flat();
}

test("partner submission has no browser webhook credential or request path", async () => {
  const trackedClientFiles = await sourceFiles(path.join(repoRoot, "src"));
  const inspectedFiles = [
    ...trackedClientFiles,
    path.join(repoRoot, ".env.example"),
    path.join(repoRoot, "README.md"),
  ];

  for (const file of inspectedFiles) {
    const contents = await readFile(file, "utf8");
    assert.equal(
      contents.includes(forbiddenEnvName),
      false,
      `${path.relative(repoRoot, file)} exposes the removed partner webhook configuration`
    );
  }

  const wizard = await readFile(path.join(repoRoot, "src/components/PartnerWizard.jsx"), "utf8");
  assert.doesNotMatch(wizard, /\bfetch\s*\(/, "PartnerWizard must not make browser HTTP handoff requests");

  const durableSubmit = wizard.indexOf("await submitPartnerRegistrationWithConsent(");
  const savedStatus = wizard.indexOf("setSubmittedListing(data);", durableSubmit);
  assert.ok(durableSubmit >= 0, "PartnerWizard must keep the durable database submission");
  assert.ok(savedStatus > durableSubmit, "saved status must follow the durable database submission");
});
