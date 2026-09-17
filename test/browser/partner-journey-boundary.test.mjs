import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { keyEventPayloads } from "./cdp-keyboard.mjs";

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

test("Enter includes native activation text and a matching code/key-up", () => {
  assert.deepEqual(keyEventPayloads("Enter"), [
    { key: "Enter", code: "Enter", modifiers: 0, windowsVirtualKeyCode: 13, type: "keyDown", text: "\r", unmodifiedText: "\r" },
    { key: "Enter", code: "Enter", modifiers: 0, windowsVirtualKeyCode: 13, type: "keyUp" },
  ]);
});

test("Tab and Shift+Tab are raw navigation events without inserted text", () => {
  for (const modifiers of [0, 8]) {
    const [down, up] = keyEventPayloads("Tab", modifiers);
    assert.equal(down.type, "rawKeyDown");
    assert.equal(down.text, "");
    assert.equal(down.modifiers, modifiers);
    assert.equal(down.code, "Tab");
    assert.equal(up.type, "keyUp");
  }
});

test("Ctrl+A is a native editing shortcut; Escape has no character payload", () => {
  const [selectAll] = keyEventPayloads("a", 2);
  assert.equal(selectAll.type, "rawKeyDown");
  assert.equal(selectAll.code, "KeyA");
  assert.equal(selectAll.text, "");
  assert.equal(selectAll.windowsVirtualKeyCode, 65);
  assert.equal(keyEventPayloads("Escape")[0].type, "rawKeyDown");
  assert.equal(keyEventPayloads("Escape")[0].text, "");
});

test("unsupported keys/modifiers fail before a CDP event", () => {
  for (const [key, modifiers] of [["Unknown", 0], ["Enter", -1], ["Enter", 16], ["Enter", 1.5], ["Enter", "2"], ["Enter", NaN]]) {
    assert.throws(() => keyEventPayloads(key, modifiers), /Unsupported proof keyboard input/);
  }
});

test("Space aliases deliver one character with matching physical code and release", () => {
  for (const key of ["Space", " "]) {
    assert.deepEqual(keyEventPayloads(key), [
      { key: " ", code: "Space", modifiers: 0, windowsVirtualKeyCode: 32, type: "keyDown", text: " ", unmodifiedText: " " },
      { key: " ", code: "Space", modifiers: 0, windowsVirtualKeyCode: 32, type: "keyUp" },
    ]);
  }
});

test("literal character and activation text are suppressed only by non-Shift modifiers", () => {
  for (const [key, character] of [["a", "a"], ["Enter", "\r"], ["Space", " "]]) {
    for (let modifiers = 0; modifiers < 16; modifiers += 1) {
      const [down, up] = keyEventPayloads(key, modifiers);
      const text = modifiers & 7 ? "" : character;
      assert.equal(down.text, text);
      assert.equal(down.unmodifiedText, text);
      assert.equal(down.type, text ? "keyDown" : "rawKeyDown");
      assert.equal(up.type, "keyUp");
      assert.equal(up.key, down.key);
      assert.equal(up.code, down.code);
      assert.equal(up.modifiers, modifiers);
      assert.equal(Object.hasOwn(up, "text"), false);
    }
  }
});

test("prototype names and non-string keys fail without coercion", () => {
  const coercible = { toString() { throw new Error("key must not be coerced"); } };
  for (const key of ["constructor", "toString", "__proto__", "hasOwnProperty", null, undefined, 13, ["Enter"], coercible]) {
    assert.throws(() => keyEventPayloads(key), /Unsupported proof keyboard input/);
  }
});
