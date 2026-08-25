// HEHA launch-readiness QA capture harness — runs against production-preview builds only.
// Node 20 + playwright-core + preinstalled Chromium. No writes to any backend:
// pages are loaded with placeholder Supabase keys (example env), so all network
// data calls fail closed; interactions are limited to same-page UI clicks.
import { chromium } from "playwright-core";
import { mkdirSync, writeFileSync } from "node:fs";

const EXE = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell";
const OUT = new URL("./shots/", import.meta.url).pathname;
mkdirSync(OUT + "local", { recursive: true });
mkdirSync(OUT + "swipe", { recursive: true });

const VP = {
  "320": { width: 320, height: 568 },
  "390": { width: 390, height: 844 },
  "430": { width: 430, height: 932 },
  "768": { width: 768, height: 1024 },
  "1024": { width: 1024, height: 768 },
  "1440": { width: 1440, height: 900 },
  "Z": { width: 720, height: 450 }, // 1440 @ 200% zoom equivalent (WCAG 1.4.10 reflow)
};

const LOCAL = "http://127.0.0.1:4173";
const SWIPE = "http://127.0.0.1:4174";

// expect: text that must be visible for PASS.
// blockedIf: if expect fails but this text IS present, classify BLOCKED (auth wall / empty data).
// actions: sequence of clicks by visible text before screenshot.
const captures = [];
const sweep = (app, base, idp, path, expect, blockedIf, extra = {}) => {
  for (const vp of ["320", "390", "430", "768", "1024", "1440"])
    captures.push({ app, id: `${idp}-${vp}`, url: base + path, vp, expect, blockedIf, ...extra });
};

// ---- HEHA Local (30) ----
sweep("local", LOCAL, "L-home", "/", /HEHA|Local/i, null);
sweep("local", LOCAL, "L-start", "/start", /guest|Log in|Create/i, null);
sweep("local", LOCAL, "L-login", "/login", /Log in|Sign in|password/i, null);
captures.push(
  { app: "local", id: "L-home-zoom", url: LOCAL + "/", vp: "Z", expect: /HEHA|Local/i, checkHScroll: true },
  { app: "local", id: "L-market-zoom", url: LOCAL + "/market", vp: "Z", expect: /market/i, checkHScroll: true },
  { app: "local", id: "L-nutrition-complete-390", url: LOCAL + "/market", vp: "390", expect: /calories|nutrition/i, blockedIf: /unavailable|no products|couldn.t load|error|empty/i, openFirstItem: true },
  { app: "local", id: "L-nutrition-partial-390", url: LOCAL + "/market", vp: "390", expect: /partial|per serving/i, blockedIf: /unavailable|no products|couldn.t load|error|empty/i, openFirstItem: true },
  { app: "local", id: "L-nutrition-missing-390", url: LOCAL + "/market", vp: "390", expect: /not available|missing/i, blockedIf: /unavailable|no products|couldn.t load|error|empty/i, openFirstItem: true },
  { app: "local", id: "L-signup-390", url: LOCAL + "/signup", vp: "390", expect: /Create|Sign up|account/i },
  { app: "local", id: "L-restaurants-390", url: LOCAL + "/restaurants", vp: "390", expect: /restaurant/i },
  { app: "local", id: "L-cart-390", url: LOCAL + "/cart", vp: "390", expect: /cart|empty/i },
  { app: "local", id: "L-profile-guest-390", url: LOCAL + "/profile", vp: "390", expect: /Terms|privacy|profile/i },
  { app: "local", id: "L-chef-390", url: LOCAL + "/chef", vp: "390", expect: /chef/i },
  { app: "local", id: "L-subscribe-1440", url: LOCAL + "/subscribe", vp: "1440", expect: /subscribe|pass/i },
  { app: "local", id: "L-restaurants-1440", url: LOCAL + "/restaurants", vp: "1440", expect: /restaurant/i },
  // Phase-3 manual gate flow evidence (non-matrix, extra):
  { app: "local", id: "X-start-guest-flow", url: LOCAL + "/start?returnTo=%2Fmarket", vp: "390", expect: /market/i, actions: ["Continue as guest"] },
);

// ---- HEHA Swipe (22) ---- (3.4s splash before every screen)
sweep("swipe", SWIPE, "S-gate", "/?entry=landing", /guest|Log in|Create/i, null, { splash: true });
sweep("swipe", SWIPE, "S-auth", "/", /Sign in|Log in|password|email/i, null, { splash: true });
captures.push(
  { app: "swipe", id: "S-gate-zoom", url: SWIPE + "/?entry=landing", vp: "Z", expect: /guest|Log in|Create/i, splash: true, checkHScroll: true },
  { app: "swipe", id: "S-auth-create-390", url: SWIPE + "/?entry=landing", vp: "390", expect: /Create|Sign up/i, splash: true, actions: ["Create an account"] },
  { app: "swipe", id: "S-guest-browse-390", url: SWIPE + "/?entry=landing", vp: "390", expect: /Discover|Saved|Community|Profile/i, splash: true, actions: ["Continue as guest"] },
  { app: "swipe", id: "S-wizard-basics-390", url: SWIPE + "/?becomePartner=1", vp: "390", expect: /Basics|business name/i, blockedIf: /Sign in|Log in|password|email|guest/i, splash: true },
  { app: "swipe", id: "S-wizard-review-390", url: SWIPE + "/?becomePartner=1", vp: "390", expect: /Review/i, blockedIf: /Sign in|Log in|password|email|guest/i, splash: true },
  { app: "swipe", id: "S-discover-390", url: SWIPE + "/?entry=landing", vp: "390", expect: /Discover/i, blockedIf: /Sign in|Log in|no spots|couldn|load/i, splash: true, actions: ["Continue as guest"] },
  { app: "swipe", id: "S-saved-390", url: SWIPE + "/?entry=landing", vp: "390", expect: /Saved|list/i, blockedIf: /Sign in|Log in/i, splash: true, actions: ["Continue as guest", "Saved"] },
  { app: "swipe", id: "S-community-390", url: SWIPE + "/?entry=landing", vp: "390", expect: /Community/i, blockedIf: /Sign in|Log in/i, splash: true, actions: ["Continue as guest", "Community"] },
  { app: "swipe", id: "S-support-success-390", url: SWIPE + "/support/success", vp: "390", expect: /thank|support|confirm/i, splash: true },
  { app: "swipe", id: "S-embed-partners-1440", url: SWIPE + "/embed/partners", vp: "1440", expect: /partner|directory/i },
);

const browser = await chromium.launch({ executablePath: EXE });
const results = [];
for (const c of captures) {
  const ctx = await browser.newContext({ viewport: VP[c.vp] });
  const page = await ctx.newPage();
  let status = "FAIL", note = "";
  try {
    await page.goto(c.url, { waitUntil: "domcontentloaded", timeout: 20000 });
    if (c.splash) await page.waitForTimeout(4200); else await page.waitForTimeout(1200);
    for (const a of c.actions ?? []) {
      try {
        await page.getByText(a, { exact: false }).first().click({ timeout: 5000 });
        await page.waitForTimeout(1000);
      } catch { note += `action "${a}" not clickable; `; }
    }
    if (c.openFirstItem) {
      try {
        await page.locator("[class*=card], [class*=item], article, li button").first().click({ timeout: 5000 });
        await page.waitForTimeout(1000);
      } catch { note += "no item to open; "; }
    }
    const body = (await page.textContent("body")) ?? "";
    if (c.expect && c.expect.test(body)) status = "PASS";
    else if (c.blockedIf && c.blockedIf.test(body)) { status = "BLOCKED"; note += "blocked-marker matched; "; }
    else note += "expected content not found; ";
    if (c.checkHScroll) {
      const h = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
      if (h) { status = "FAIL"; note += "HORIZONTAL SCROLL at this viewport; "; }
    }
  } catch (e) { note += String(e).slice(0, 160); }
  try { await page.screenshot({ path: `${OUT}${c.app}/${c.id}.png`, fullPage: false }); } catch {}
  results.push({ id: c.id, app: c.app, vp: c.vp, url: c.url.replace(/http:\/\/localhost:\d+/, ""), status, note: note.trim() });
  await ctx.close();
}
await browser.close();
writeFileSync(OUT + "results.json", JSON.stringify(results, null, 2));
const counts = results.reduce((m, r) => ((m[r.status] = (m[r.status] ?? 0) + 1), m), {});
console.log(JSON.stringify(counts));
for (const r of results) console.log(`${r.status.padEnd(8)} ${r.id.padEnd(26)} ${r.note}`);
