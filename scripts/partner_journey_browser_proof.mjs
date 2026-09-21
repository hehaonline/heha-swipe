// No browser download, remote browser, extra dependency, or hosted credential.
// Control an already-installed Chrome using its documented CDP pipe protocol.
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { EventEmitter } from "node:events";
import { access, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { createServer } from "vite";
import react from "@vitejs/plugin-react";
import { keyEventPayloads } from "../test/browser/cdp-keyboard.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const negativeControl = process.argv[2] === "--negative-control=missing-dialog-focus";
const readinessBaseline = process.argv[2] === "--profile-request-readiness=baseline";
const profileReadiness = readinessBaseline || process.argv[2] === "--profile-request-readiness";
assert.ok(process.argv.length === 2 || (process.argv.length === 3 && (negativeControl || profileReadiness)), "Unsupported browser-proof argument");
const artifacts = resolve(root, "artifacts/partner-journey-browser-proof", profileReadiness ? (readinessBaseline ? "profile-readiness-baseline" : "profile-readiness") : negativeControl ? "negative-missing-dialog-focus" : "positive");
const temporary = await mkdtemp(resolve(tmpdir(), "heha-rendered-proof-"));
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
const receipt = {
  scope: "Rendered production React components with synthetic authenticated props and browser-session mock persistence; NOT hosted auth, email, approval, Storage API, device hardware, or screen-reader proof",
  checkedOutSha: git("rev-parse", "HEAD"), tree: git("rev-parse", "HEAD^{tree}"),
  sourceDirty: Boolean(git("status", "--porcelain", "--untracked-files=no")),
  node: process.version, browserInstalledOnly: true, viewports: [], screenshots: [], status: "running",
  negativeControl: negativeControl ? "missing-dialog-focus" : null,
  profileReadiness, readinessBaseline,
  limitations: ["No full-app login/logout, verification email, hosted persistence, or real account", "No axe dependency or broad WCAG certification; semantic names, keyboard focus, modal containment and scoped focus-ring contrast only", "Mobile viewport emulation, not physical device or assistive-technology testing", "System fonts; remote font import removed by test-only transform"],
};
await mkdir(artifacts, { recursive: true });

class ChromePipe extends EventEmitter {
  constructor(executable) {
    super();
    this.sequence = 0;
    this.pending = new Map();
    this.session = undefined;
    this.buffer = "";
    this.process = spawn(executable, [
      "--headless=new", "--remote-debugging-pipe", `--user-data-dir=${temporary}/chrome`,
      "--no-first-run", "--no-default-browser-check", "--disable-background-networking",
      "--disable-component-update", "--disable-default-apps", "--disable-extensions",
      "--disable-sync", "--disable-dev-shm-usage", "--metrics-recording-only",
      "--no-proxy-server", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1", "about:blank",
    ], { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"],
      env: { PATH: process.env.PATH || "/usr/bin:/bin", HOME: temporary, TMPDIR: temporary, LANG: "C.UTF-8" } });
    this.process.stdio[4].setEncoding("utf8");
    this.process.stdio[4].on("data", (chunk) => {
      this.buffer += chunk;
      for (let end; (end = this.buffer.indexOf("\0")) !== -1;) {
        const message = JSON.parse(this.buffer.slice(0, end));
        this.buffer = this.buffer.slice(end + 1);
        if (message.id) {
          const pending = this.pending.get(message.id);
          if (!pending) continue;
          clearTimeout(pending.timer);
          this.pending.delete(message.id);
          message.error ? pending.reject(new Error(JSON.stringify(message.error))) : pending.resolve(message.result);
        } else this.emit(message.method, message.params);
      }
    });
    const fail = (error) => {
      for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(error); }
      this.pending.clear();
    };
    this.process.on("error", fail);
    this.process.on("exit", (code) => fail(new Error(`Installed browser exited: ${code}`)));
  }
  send(method, params = {}, sessionId = this.session) {
    const id = ++this.sequence;
    return new Promise((resolvePromise, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
      this.pending.set(id, { resolve: resolvePromise, reject, timer });
      this.process.stdio[3].write(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }) + "\0");
    });
  }
  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
    return result.result.value;
  }
  async until(expression, label) {
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      if (await this.evaluate(expression)) return;
      await new Promise((done) => setTimeout(done, 50));
    }
    throw new Error(`Rendered assertion timed out: ${label}`);
  }
  async key(key, modifiers = 0) {
    for (const payload of keyEventPayloads(key, modifiers)) {
      await this.send("Input.dispatchKeyEvent", payload);
    }
  }
  async keyboardFocus(target) {
    for (let tries = 0; tries < 100; tries += 1) {
      if (await this.evaluate(`document.activeElement === (${target})`)) return;
      await this.key("Tab");
    }
    throw new Error(`Not keyboard reachable: ${target}`);
  }
  async activate(target) { await this.keyboardFocus(target); await this.key("Enter"); }
}

const button = (text) => `[...document.querySelectorAll('button')].find(e => (e.getAttribute('aria-label') || e.textContent).trim() === ${JSON.stringify(text)})`;
const input = (label) => `[...document.querySelectorAll('input,textarea')].find(e => [...e.labels || []].some(l => l.textContent.trim() === ${JSON.stringify(label)}))`;
const dialog = "document.querySelector('[role=dialog]')";

// Focused mode reuses the isolated renderer/transport; the old full journey is not rerun.
const readinessFixture = `
import { createElement } from 'react';
import { createRoot } from 'react-dom/client';
import PartnerProfileEditor from '../../src/components/PartnerProfileEditor';
import './synthetic-supabase.js';
import '../../src/index.css';
import '../../src/community-pass.css';
const root = createRoot(document.getElementById('root'));
const users = new Map();
window.__profileReadiness = {
  saved: [],
  render({ ownerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', cardId = '11111111-1111-4111-8111-111111111111', session = 'first' } = {}) {
    const key = ownerId + ':' + session;
    if (!users.has(key)) users.set(key, { id: ownerId, email: 'synthetic-owner@example.invalid' });
    const listing = window.__syntheticProof.snapshot().partners.find(row => row.id === cardId);
    root.render(createElement(PartnerProfileEditor, {
      user: ownerId ? users.get(key) : null,
      listing: listing ? { ...listing, owner_id: ownerId } : null,
      onClose: () => root.render(null),
      onSaved: (card, message) => window.__profileReadiness.saved.push({ id: card.id, message }),
    }));
  },
  close() { root.render(null); },
};
`;

async function runProfileReadiness(chrome, origin) {
  const { browserContextId } = await chrome.send("Target.createBrowserContext", {}, undefined);
  const { targetId } = await chrome.send("Target.createTarget", { url: "about:blank", browserContextId }, undefined);
  const { sessionId } = await chrome.send("Target.attachToTarget", { targetId, flatten: true }, undefined);
  chrome.session = sessionId;
  await chrome.send("Page.enable"); await chrome.send("Runtime.enable"); await chrome.send("Network.enable");
  await chrome.send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  await chrome.send("Page.navigate", { url: `${origin}/test/browser/partner-journey.html` });
  await chrome.until("!!window.__profileReadiness", "focused editor fixture loaded");
  const snapshot = () => chrome.evaluate("window.__syntheticProof.snapshot()");
  const queue = (plan) => chrome.evaluate(`window.__syntheticProof.queueProfileRead(${JSON.stringify(plan)})`);
  const render = async (scope = {}) => {
    await chrome.evaluate(`window.__profileReadiness.render(${JSON.stringify(scope)})`);
    await chrome.until(`!!${dialog}`, "editor mounted");
  };
  const edit = async (value) => {
    await chrome.keyboardFocus(input("Business name"));
    // insertText with native selection works on both installed macOS/Linux Chrome.
    await chrome.evaluate(`${input("Business name")}.select()`);
    await chrome.send("Input.insertText", { text: value });
    assert.equal(await chrome.evaluate(`${input("Business name")}.value`), value);
  };
  const disabled = () => chrome.evaluate("document.querySelector('.preview-actions .primary-button')?.disabled");
  const inserts = async () => (await snapshot()).calls.filter(call => call.table === "partner_profile_change_requests" && call.method === "insert");
  const drain = () => chrome.evaluate("new Promise(resolve => setTimeout(resolve, 50))");
  const reset = async () => {
    await chrome.evaluate("window.__profileReadiness.close()"); await chrome.until(`!${dialog}`, "old editor unmounted");
    await chrome.evaluate("window.__syntheticProof.resetProfileProof(); window.__profileReadiness.saved = []");
  };
  const deferred = async (count) => {
    await chrome.until(`window.__syntheticProof.snapshot().pendingProfileReads.length === ${count}`, "expected deferred scoped reads");
    return (await snapshot()).pendingProfileReads;
  };
  const settle = async (id) => { await chrome.evaluate(`window.__syntheticProof.settleProfileRead(${id})`); await drain(); };
  const check = (name, details = {}) => { (receipt.profileChecks ??= []).push({ name, ...details }); };

  await chrome.evaluate("window.__syntheticProof.seedProfileRequest()");
  await queue({ fail: true }); await render();
  await chrome.until("!!document.querySelector('.error-banner')", "initial lookup error shown");
  await edit("Draft kept after failed pending lookup");
  await chrome.evaluate(`${button("Submit changes for HEHA review")}.click()`); await drain();
  receipt.failedLookup = { inserts: (await inserts()).length, requests: (await snapshot()).profileRequests.length };
  assert.equal(receipt.failedLookup.inserts, 0, "failed pending lookup must not insert");
  assert.equal(await disabled(), true);
  assert.equal(await chrome.evaluate("document.querySelector('.error-banner').textContent.includes('check')"), true, "editing must not erase the lookup gate");
  check("failed initial lookup blocks insert despite an existing pending request");
  await chrome.activate(button("Retry request check"));
  await chrome.until(`${button("Changes already under review")}?.disabled`, "retry finds pending request and stays locked");
  assert.equal(await chrome.evaluate(`${input("Business name")}.value`), "Draft kept after failed pending lookup");
  assert.equal((await inserts()).length, 0); assert.equal((await snapshot()).profileRequests.length, 1);
  check("retry preserves draft and existing pending request locks submission");

  await reset(); await queue({ reject: true }); await render();
  await chrome.until("!!document.querySelector('.error-banner')", "rejected lookup is handled");
  await edit("Retained through repeated lookup errors"); await queue({ fail: true });
  await chrome.activate(button("Retry request check"));
  await chrome.until(`${button("Retry request check")} && !!document.querySelector('.error-banner')`, "second lookup failure allows a truthful retry");
  assert.equal(await disabled(), true); assert.equal((await inserts()).length, 0);
  assert.equal(await chrome.evaluate(`${input("Business name")}.value`), "Retained through repeated lookup errors");
  check("rejected and repeated failed lookups preserve draft and never insert");
  await chrome.activate(button("Retry request check"));
  await chrome.until(`${button("Submit changes for HEHA review")}?.disabled === false`, "successful empty read unlocks submit");
  await chrome.evaluate(`{ const submit = ${button("Submit changes for HEHA review")}; submit.click(); submit.click(); }`);
  await chrome.until("window.__profileReadiness.saved.length === 1", "one verified submission receipt");
  await chrome.until(`${button("Changes already under review")}?.disabled`, "acknowledged submission has rendered its pending lock");
  assert.equal((await inserts()).length, 1); assert.equal((await snapshot()).profileRequests.length, 1);
  assert.equal((await inserts())[0].payload.proposed_changes.name, "Retained through repeated lookup errors");
  assert.equal(await disabled(), true); check("verified empty lookup permits exactly one submission, including duplicate clicks");

  for (const [name, nextScope] of [
    ["card", { cardId: "22222222-2222-4222-8222-222222222222" }],
    ["owner", { ownerId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }],
    ["session", { session: "replacement" }],
  ]) {
    await reset(); await queue({ defer: true }); await render(); const [old] = await deferred(1);
    await edit("Context-scoped unsaved draft");
    await queue({ defer: true, fail: true }); await render(nextScope);
    const ids = await deferred(2); const current = ids.find(id => id !== old);
    assert.equal(await disabled(), true, `${name} change invalidates previous readiness immediately`);
    const expectedName = name === "session" ? "Context-scoped unsaved draft" : name === "card" ? "Newer B" : "Canonical A";
    assert.equal(await chrome.evaluate(`${input("Business name")}.value`), expectedName);
    await settle(old); assert.equal(await disabled(), true, `stale ${name} result cannot unlock current editor`);
    await settle(current); assert.equal(await disabled(), true);
    assert.equal((await inserts()).length, 0);
    const reads = (await snapshot()).calls.filter(call => call.table === "partner_profile_change_requests");
    assert.equal(reads.length, 2);
    assert.deepEqual(reads[1].filters, [["partner_id", nextScope.cardId || "11111111-1111-4111-8111-111111111111"], ["owner_id", nextScope.ownerId || "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]]);
    check(`stale ${name} completion ignored; current failure stays locked; draft isolation respected`);
  }
  await reset(); await render();
  await chrome.until(`${button("Submit changes for HEHA review")}?.disabled === false`, "initial empty check for deferred insert");
  await edit("Draft submitted before session replacement");
  await chrome.evaluate("window.__syntheticProof.queueProfileInsert({ defer: true })");
  await chrome.activate(button("Submit changes for HEHA review"));
  await chrome.until("window.__syntheticProof.snapshot().pendingProfileInserts.length === 1", "first insert remains uncommitted");
  const insertId = (await snapshot()).pendingProfileInserts[0];
  await render({ session: "replacement-during-insert" });
  await chrome.until("window.__syntheticProof.snapshot().calls.filter(call => call.table === 'partner_profile_change_requests' && call.method === 'select').length === 2", "replacement session reads before first insert commits");
  await drain(); assert.equal((await snapshot()).profileRequests.length, 0);
  await chrome.evaluate("document.querySelector('.preview-actions .primary-button').click()"); await drain();
  const attemptedInserts = (await inserts()).length;
  receipt.sessionReplacementInsert = { attemptedInsertsBeforeFirstSettles: attemptedInserts };
  await queue({ defer: true });
  await chrome.evaluate(`window.__syntheticProof.settleProfileInsert(${JSON.stringify(insertId)})`);
  assert.equal(attemptedInserts, 1, "session replacement must preserve the unsettled insert lock");
  const [reconciliation] = await deferred(1);
  assert.equal(await disabled(), true, "settled insert still requires a fresh reconciliation");
  await settle(reconciliation);
  await chrome.until(`${button("Changes already under review")}?.disabled`, "fresh reconciliation finds committed pending request");
  assert.equal((await inserts()).length, 1); assert.equal((await snapshot()).profileRequests.length, 1);
  assert.equal(await chrome.evaluate("window.__profileReadiness.saved.length"), 0, "old-session completion cannot deliver a success callback to replacement session");
  assert.equal(await chrome.evaluate(`${input("Business name")}.value`), "Draft submitted before session replacement");
  check("in-flight insert remains locked through session replacement and fresh post-settlement reconciliation");
  await reset(); await render({ ownerId: null }); await drain();
  assert.equal(await disabled(), true); assert.equal((await snapshot()).calls.length, 0);
  check("missing identity cannot check or submit");
  const { data } = await chrome.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
  const bytes = Buffer.from(data, "base64"); await writeFile(resolve(artifacts, "profile-readiness.png"), bytes);
  receipt.screenshots.push({ path: "profile-readiness.png", sha256: sha256(bytes), syntheticOnly: true });
  await reset();
  chrome.session = undefined; await chrome.send("Target.disposeBrowserContext", { browserContextId });
}
let chrome;
let server;
const network = [];
const runtimeErrors = [];
try {
  // Fixed known locations only: no environment-selected binary or downloaded cache.
  let executable;
  for (const candidate of ["/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/opt/google/chrome/chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]) {
    try { await access(candidate, constants.X_OK); executable = candidate; break; } catch { /* not installed */ }
  }
  if (!executable) throw new Error("NOT RUN: no already-installed supported Chrome found; no download or install is permitted");
  receipt.executable = executable;
  server = await createServer({
    root, configFile: false, envDir: temporary, publicDir: false,
    plugins: [
      { name: "isolated-synthetic-partner-transport", enforce: "pre",
        resolveId(source, importer) {
          const target = importer && source.startsWith(".")
            ? resolve(dirname(importer.split("?")[0]), source).replace(/\.js$/, "")
            : null;
          if (target === resolve(root, "src/lib/supabase")) return resolve(root, "test/browser/synthetic-supabase.js");
        },
        transform(code, id) {
          if (profileReadiness && id === resolve(root, "test/browser/partner-journey.jsx")) return readinessFixture;
          if (readinessBaseline && id === resolve(root, "src/components/PartnerProfileEditor.jsx")) {
            assert.equal(receipt.checkedOutSha, "449c5762c9fe874d16088d44066680e167705dad", "baseline must use the reviewed source");
            return git("show", "HEAD:src/components/PartnerProfileEditor.jsx");
          }
          if (id === resolve(root, "src/index.css")) return code.replace(/^@import url\('https:\/\/fonts\.googleapis\.com[^\n]+\n/, "");
          if (negativeControl && id === resolve(root, "src/components/PartnerProfileEditor.jsx")) {
            assert.ok(code.includes("ref={dialogRef}"), "negative control must remove the real editor focus binding");
            return code.replace("ref={dialogRef}", "");
          }
        },
      }, react(),
    ],
    server: { host: "127.0.0.1", port: 0, hmr: false,
      headers: { "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'" } },
  });
  await server.listen();
  const address = server.httpServer.address();
  assert.equal(address.address, "127.0.0.1");
  const origin = `http://127.0.0.1:${address.port}`;
  const imagePath = resolve(temporary, "synthetic-pixel.png");
  await writeFile(imagePath, Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jE9sAAAAASUVORK5CYII=", "base64"));
  chrome = new ChromePipe(executable);
  receipt.browserVersion = await chrome.send("Browser.getVersion");
  chrome.on("Network.requestWillBeSent", ({ request }) => network.push(request.url));
  chrome.on("Runtime.exceptionThrown", ({ exceptionDetails }) => runtimeErrors.push(exceptionDetails.text));
  if (profileReadiness) await runProfileReadiness(chrome, origin);
  for (const viewport of profileReadiness ? [] : [{ name: "desktop", width: 1280, height: 900, mobile: false }, { name: "mobile", width: 390, height: 844, mobile: true }]) {
    const { browserContextId } = await chrome.send("Target.createBrowserContext", {}, undefined);
    const { targetId } = await chrome.send("Target.createTarget", { url: "about:blank", browserContextId }, undefined);
    const { sessionId } = await chrome.send("Target.attachToTarget", { targetId, flatten: true }, undefined);
    chrome.session = sessionId;
    await chrome.send("Page.enable");
    await chrome.send("Runtime.enable");
    await chrome.send("Network.enable");
    await chrome.send("Emulation.setDeviceMetricsOverride", { width: viewport.width, height: viewport.height, deviceScaleFactor: 1, mobile: viewport.mobile });
    await chrome.send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-reduced-motion", value: "reduce" }] });
    await chrome.send("Page.navigate", { url: `${origin}/test/browser/partner-journey.html` });
    await chrome.until("document.querySelector('.profile-hero h2')?.textContent === 'Canonical A'", "Profile stays on older claimed card A");
    assert.equal(await chrome.evaluate("document.body.textContent.includes('Newer B')"), false);
    await chrome.activate(button("Community Pass"));
    await chrome.until("document.querySelector('.partner-hub-topline h2')?.textContent === 'Canonical A'", "Community Pass stays on A");
    await chrome.activate(button("Edit business profile"));
    await chrome.until(`${dialog}?.getAttribute('aria-label') === 'Edit business profile'`, "editor opens");
    await chrome.until(`document.activeElement === (${button("Close editor")})`, "editor takes keyboard focus");
    assert.equal(await chrome.evaluate(`${input("Business name")}.value`), "Canonical A");
    for (const category of ["Restaurants", "Markets"]) {
      assert.equal(await chrome.evaluate(`[...document.querySelectorAll('.wizard-chip-grid button')].find(e => e.textContent.includes('${category}')).getAttribute('aria-pressed')`), "true");
    }
    assert.equal(await chrome.evaluate("document.querySelector('fieldset legend')?.textContent.startsWith('Categories')"), true);
    await chrome.key("Tab", 8);
    assert.equal(await chrome.evaluate(`document.activeElement === (${button("Cancel")})`), true, "Shift+Tab wraps inside editor");
    await chrome.key("Tab");
    assert.equal(await chrome.evaluate(`document.activeElement === (${button("Close editor")})`), true, "Tab wraps inside editor");
    assert.equal(await chrome.evaluate("document.querySelector('nav').inert || !!document.querySelector('nav').closest('[inert]')"), true, "background is inert");
    await chrome.keyboardFocus(input("Business name"));
    await chrome.key("a", 2);
    await chrome.send("Input.insertText", { text: "Canonical A reviewed edit" });
    const eventsButton = "[...document.querySelectorAll('.wizard-chip-grid button')].find(e => e.textContent.includes('Events'))";
    await chrome.activate(eventsButton);
    assert.equal(await chrome.evaluate(`${eventsButton}.getAttribute('aria-pressed')`), "true");

    const semantic = await chrome.evaluate(`(() => {
      const sheet = document.querySelector('.partner-editor-sheet');
      const visible = e => e.getClientRects().length > 0;
      return {
        unnamedControls: [...sheet.querySelectorAll('input,textarea,button')].filter(visible).filter(e => !(e.getAttribute('aria-label') || (e.labels?.length ? [...e.labels].map(l => l.textContent).join(' ') : e.textContent)).trim()).length,
        overflow: sheet.scrollWidth > sheet.clientWidth + 1 || document.documentElement.scrollWidth > innerWidth + 1,
        focused: getComputedStyle(document.activeElement).outlineStyle,
        focusWidth: getComputedStyle(document.activeElement).outlineWidth,
        focusColor: getComputedStyle(document.activeElement).outlineColor,
        modal: sheet.closest('[role=dialog]').getAttribute('aria-modal')
      };
    })()`);
    assert.equal(semantic.unnamedControls, 0);
    assert.equal(semantic.overflow, false);
    assert.equal(semantic.modal, "true");
    assert.equal(semantic.focused, "solid");
    assert.equal(semantic.focusWidth, "3px");
    assert.equal(semantic.focusColor, "rgb(37, 79, 55)");
    // 3:1 non-text requirement, specifically the dark green ring vs white sheet.
    const luminance = (rgb) => rgb.map(v => { const c = v / 255; return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4; }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
    const focusContrast = 1.05 / (luminance([37, 79, 55]) + .05);
    assert.ok(focusContrast >= 3);
    const capture = async (name) => {
      const path = `${viewport.name}-${name}.png`;
      const { data } = await chrome.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
      const bytes = Buffer.from(data, "base64");
      await writeFile(resolve(artifacts, path), bytes);
      receipt.screenshots.push({ path, sha256: sha256(bytes), viewport: viewport.name, productionComponents: true, syntheticOnly: true });
    };
    await capture("editor-keyboard");
    await chrome.activate(button("Submit changes for HEHA review"));
    await chrome.until(`!${dialog} && document.body.textContent.includes('Profile changes submitted for HEHA review')`, "review request receipt");
    await chrome.until(`document.activeElement === (${button("Edit business profile")})`, "focus returns to editor opener");
    let snapshot = await chrome.evaluate("window.__syntheticProof.snapshot()");
    assert.equal(snapshot.profileRequests.length, 1);
    assert.equal(snapshot.profileRequests[0].partner_id, "11111111-1111-4111-8111-111111111111");
    assert.deepEqual(snapshot.profileRequests[0].proposed_changes, { name: "Canonical A reviewed edit", categories: ["Restaurant", "Vendor", "Events"] });
    assert.equal(snapshot.partners[0].name, "Newer B");
    assert.equal(snapshot.partners[1].name, "Canonical A", "review submission must not update publication");
    await chrome.send("Page.reload");
    await chrome.until("document.querySelector('.profile-hero h2')?.textContent === 'Canonical A'", "reload resumes exact A");
    await chrome.activate(button("Community Pass"));
    await chrome.until("document.querySelector('.partner-hub-topline h2')?.textContent === 'Canonical A'", "resumed hub remains A");
    await chrome.activate(button("Edit business profile"));
    await chrome.until(`${button("Changes already under review")}?.disabled`, "pending request survives reload and blocks duplicate");
    assert.equal(await chrome.evaluate(`${input("Business name")}.value`), "Canonical A", "editor truthfully shows unchanged published value");
    assert.deepEqual((await chrome.evaluate("window.__syntheticProof.snapshot()")).profileRequests[0].proposed_changes, snapshot.profileRequests[0].proposed_changes);
    await chrome.key("Escape");
    await chrome.until(`!${dialog}`, "Escape closes editor");
    await chrome.until(`document.activeElement === (${button("Edit business profile")})`, "Escape restores opener");
    await chrome.activate(button("Add logo / photos"));
    await chrome.until(`document.activeElement === (${button("Close media manager")})`, "media takes keyboard focus");
    await chrome.send("Page.setInterceptFileChooserDialog", { enabled: true });
    const upload = async () => {
      const chooser = new Promise((done, reject) => {
        const timer = setTimeout(() => reject(new Error("File chooser did not open from keyboard activation")), 10000);
        chrome.once("Page.fileChooserOpened", (event) => { clearTimeout(timer); done(event); });
      });
      await chrome.activate(button("Upload logo"));
      const { backendNodeId } = await chooser;
      await chrome.send("DOM.setFileInputFiles", { files: [imagePath], backendNodeId });
    };
    await upload();
    await chrome.until("document.body.textContent.includes('Synthetic upload failed; retry is safe.')", "failed upload is visible");
    snapshot = await chrome.evaluate("window.__syntheticProof.snapshot()");
    assert.equal(snapshot.mediaRequests.length, 0, "failed bytes cannot claim submission");
    await upload();
    await chrome.until("document.body.textContent.includes('Media submitted for HEHA review.')", "retry produces review receipt");
    await chrome.until(`${dialog}?.getAttribute('aria-label') === 'Manage business logo and photos'`, "same-card refresh preserves media dialog");
    snapshot = await chrome.evaluate("window.__syntheticProof.snapshot()");
    assert.equal(snapshot.mediaRequests.length, 1);
    assert.equal(snapshot.uploads.length, 1);
    assert.equal(snapshot.mediaRequests[0].partner_id, "11111111-1111-4111-8111-111111111111");
    assert.ok(snapshot.uploads[0].path.startsWith("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/11111111-1111-4111-8111-111111111111/"));
    assert.equal(snapshot.partners[1].logo_url, undefined, "media review must not publish image");
    const mediaOverflow = await chrome.evaluate("document.querySelector('.partner-media-sheet').scrollWidth > document.querySelector('.partner-media-sheet').clientWidth + 1 || document.documentElement.scrollWidth > innerWidth + 1");
    assert.equal(mediaOverflow, false);
    await capture("media-review");
    await chrome.key("Escape");
    await chrome.until(`document.activeElement === (${button("Add logo / photos")})`, "media restores opener");
    await chrome.activate(button("Profile"));
    await chrome.until("document.querySelector('.profile-hero h2')?.textContent === 'Canonical A'", "return to Profile stays on A");
    assert.equal(await chrome.evaluate("document.documentElement.scrollWidth > innerWidth + 1"), false);
    await capture("profile-resumed");
    for (const call of snapshot.calls.filter(c => c.table === "partners")) {
      assert.deepEqual(call.filters, [["owner_id", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"], ["id", "11111111-1111-4111-8111-111111111111"]]);
    }
    for (const call of snapshot.calls.filter(c => ["partner_profile_change_requests", "partner_media_requests"].includes(c.table) && c.method === "select")) {
      assert.deepEqual(call.filters, [["partner_id", "11111111-1111-4111-8111-111111111111"], ["owner_id", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]]);
    }
    receipt.viewports.push({ ...viewport, exactCard: "A", preservedSecondaryCategory: "Vendor", submittedCategories: ["Restaurant", "Vendor", "Events"], reviewQueueSurvivesReload: true, publishedValuesUnchanged: true, failedUploadHasNoRequest: true, retriedMediaTargetsA: true, keyboardOnlyActions: true, semantic, focusContrast, mediaOverflow });
    chrome.session = undefined;
    await chrome.send("Target.disposeBrowserContext", { browserContextId });
  }
  assert.deepEqual(runtimeErrors, [], "no rendered runtime exceptions");
  assert.ok(network.length > 0, "actual browser loaded rendered source");
  assert.deepEqual(network.filter(url => !url.startsWith(`${origin}/`) && !url.startsWith("data:")), [], "no external browser requests");
  assert.equal(network.some(url => url.includes("/src/lib/supabase.js")), false, "real backend client never loaded");
  receipt.network = { requests: network.length, externalRequests: 0, realBackendClientLoaded: false };
  assert.equal(negativeControl, false, "missing-focus negative control unexpectedly passed");
  assert.equal(readinessBaseline, false, "old-source lookup-failure control unexpectedly passed");
  receipt.status = "pass";
} catch (error) {
  const expectedFailure = (negativeControl && error.message === "Rendered assertion timed out: editor takes keyboard focus") ||
    (readinessBaseline && error.message.startsWith("failed pending lookup must not insert") && receipt.failedLookup?.inserts === 1 && receipt.failedLookup?.requests === 2);
  receipt.status = expectedFailure ? "expected-negative-failure" : "fail";
  receipt.error = error.message;
  receipt.runtimeErrors = runtimeErrors;
  receipt.nonLoopbackRequests = network.filter(url => !/^http:\/\/127\.0\.0\.1:\d+\//.test(url) && !url.startsWith("data:"));
  if (chrome?.session) {
    try {
      receipt.failurePage = await chrome.evaluate("({ title: document.title, body: document.body.innerText.slice(0,5000), url: location.pathname })");
      const { data } = await chrome.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
      await writeFile(resolve(artifacts, "failure.png"), Buffer.from(data, "base64"));
    } catch { /* retain the controlling failure even if the page closed */ }
  }
  if (!expectedFailure) process.exitCode = 1;
} finally {
  receipt.cleanup = { browserExited: !chrome, serverClosed: !server, temporaryRemoved: false };
  if (chrome) {
    chrome.session = undefined;
    try { await chrome.send("Browser.close"); } catch { /* closed transport */ }
    const exited = () => chrome.process.exitCode !== null || chrome.process.signalCode !== null;
    const waitForExit = async (milliseconds) => {
      const deadline = Date.now() + milliseconds;
      while (!exited() && Date.now() < deadline) await new Promise(done => setTimeout(done, 25));
    };
    if (!exited()) { chrome.process.kill("SIGTERM"); await waitForExit(1500); }
    if (!exited()) { chrome.process.kill("SIGKILL"); await waitForExit(1500); }
    receipt.cleanup.browserExited = exited();
    for (const stream of chrome.process.stdio) stream?.destroy();
  }
  if (server) { await server.close(); receipt.cleanup.serverClosed = !server.httpServer?.listening; }
  await rm(temporary, { recursive: true, force: true });
  receipt.cleanup.temporaryRemoved = true;
  if (!Object.values(receipt.cleanup).every(Boolean)) { receipt.status = "fail"; process.exitCode = 1; }
  await writeFile(resolve(artifacts, "receipt.json"), JSON.stringify(receipt, null, 2) + "\n");
  console.log(JSON.stringify(receipt, null, 2));
}
