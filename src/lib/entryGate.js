// HEHA Swipe landing entry gate -- pure helpers.
//
// These functions carry the security-sensitive redirect handling and the
// gate/guest decision logic. They are intentionally free of React and of any
// direct DOM/window access so they can be unit tested in isolation and reused
// from anywhere. Callers pass in the raw values (search string, session flag)
// and receive plain data back.

// sessionStorage key remembering that a visitor explicitly chose to browse as a
// guest for the current browser session. Session-scoped (not localStorage) so a
// guest choice never silently persists across browser sessions.
export const GUEST_SESSION_KEY = "heha_guest_session";

// Query param the HEHA Wix landing page appends: https://hehaswipe.app/?entry=landing
export const ENTRY_PARAM = "entry";
export const ENTRY_LANDING_VALUE = "landing";

// Optional return destination param. Sanitized before ever being used.
export const RETURN_PARAM = "return";

// True if the string contains any ASCII control character, space, or other
// whitespace. Such characters in a return path only ever serve to smuggle a
// scheme or host past a naive validator, so we reject the whole value. Written
// as an explicit code-point scan to avoid brittle regex-escape handling.
function hasUnsafeWhitespace(str) {
  for (let i = 0; i < str.length; i += 1) {
    const code = str.charCodeAt(i);
    // Control chars and space (0x00..0x20), plus common Unicode whitespace.
    if (code <= 0x20) return true;
    if (code === 0x85 || code === 0xa0 || code === 0x2028 || code === 0x2029) return true;
    if (code >= 0x2000 && code <= 0x200a) return true;
  }
  return false;
}

/**
 * Sanitize a caller-supplied return destination into a safe, internal-only path.
 *
 * Open-redirect defense: we accept ONLY same-origin absolute paths and reject
 * anything that could navigate off-site or execute script. The result is always
 * either a clean path beginning with a single "/" or null.
 *
 * Rejected: external URLs, protocol-relative "//host", "http:"/"https:"/"javascript:"
 * schemes, backslash tricks ("/\\evil.com"), whitespace/control smuggling, and
 * anything not starting with a single forward slash.
 *
 * @param {unknown} raw
 * @returns {string|null} safe internal path (e.g. "/?tab=faves") or null
 */
export function sanitizeReturnPath(raw) {
  if (typeof raw !== "string") return null;
  if (raw === "") return null;

  // Reject any whitespace/control smuggling before further parsing.
  if (hasUnsafeWhitespace(raw)) return null;

  const value = raw;

  // Must be an absolute internal path: exactly one leading slash.
  if (value[0] !== "/") return null;
  // "//host" and "/\host" are protocol-relative / backslash redirects off-origin.
  if (value[1] === "/" || value[1] === "\\") return null;

  // Backslashes anywhere are never valid in a normal internal path and are a
  // common browser normalization trick -- reject them.
  if (value.includes("\\")) return null;

  // A scheme (e.g. "javascript:", "http:") cannot legitimately appear before the
  // first "/", "?", or "#" of a valid path. Reject any ":" in that first segment.
  const firstSegmentEnd = value.search(/[/?#]/);
  const firstSegment = firstSegmentEnd === -1 ? value : value.slice(0, firstSegmentEnd);
  if (firstSegment.includes(":")) return null;

  return value;
}

/**
 * Remove the entry-gate params from a location.search string and return a
 * normalized search string ("" or "?a=1&b=2"). Preserves any other params.
 * Used to clean "?entry=landing" out of the URL after a choice so the gate does
 * not re-trigger on refresh.
 *
 * @param {string} search location.search, e.g. "?entry=landing&tab=faves"
 * @returns {string} normalized search string, "" when empty
 */
export function stripEntryParams(search) {
  const params = new URLSearchParams(typeof search === "string" ? search : "");
  params.delete(ENTRY_PARAM);
  params.delete(RETURN_PARAM);
  const next = params.toString();
  return next ? `?${next}` : "";
}

/**
 * Did this visitor arrive from the HEHA landing page (?entry=landing)?
 * @param {string} search location.search
 * @returns {boolean}
 */
export function isLandingEntry(search) {
  const params = new URLSearchParams(typeof search === "string" ? search : "");
  return params.get(ENTRY_PARAM) === ENTRY_LANDING_VALUE;
}

/**
 * Decide whether the first-party entry gate should be shown.
 *
 * Rules:
 *  - Authenticated users always bypass the gate (they continue to their
 *    destination) regardless of the param.
 *  - A visitor who already chose "continue as guest" this session bypasses the
 *    gate so it never loops.
 *  - Otherwise, only visitors who explicitly arrived with ?entry=landing see it.
 *    Direct visitors keep the existing (auth screen) behavior.
 *
 * @param {{ search: string, hasSession: boolean, isGuest: boolean }} input
 * @returns {boolean}
 */
export function shouldShowEntryGate({ search, hasSession, isGuest }) {
  if (hasSession) return false;
  if (isGuest) return false;
  return isLandingEntry(search);
}

/**
 * Read the safe return destination out of a search string (already validated).
 * @param {string} search location.search
 * @returns {string|null}
 */
export function readReturnPath(search) {
  const params = new URLSearchParams(typeof search === "string" ? search : "");
  return sanitizeReturnPath(params.get(RETURN_PARAM));
}

// --- Guest session persistence (thin sessionStorage wrappers) --------------
// Wrapped in try/catch because sessionStorage can throw in private-mode or
// sandboxed contexts; a storage failure must never break browsing.

function resolveStore(storage) {
  if (storage) return storage;
  if (typeof sessionStorage !== "undefined") return sessionStorage;
  return null;
}

/** @returns {boolean} whether the guest choice is remembered for this session */
export function isGuestSession(storage) {
  try {
    return resolveStore(storage)?.getItem(GUEST_SESSION_KEY) === "1";
  } catch {
    return false;
  }
}

/** Remember the guest choice for the current browser session. */
export function setGuestSession(storage) {
  try {
    resolveStore(storage)?.setItem(GUEST_SESSION_KEY, "1");
  } catch {
    // Non-fatal: guest can still browse this render; the gate may reappear on a
    // hard refresh, which is safe (never a security downgrade).
  }
}

/** Clear any remembered guest choice (e.g. after a successful sign-in). */
export function clearGuestSession(storage) {
  try {
    resolveStore(storage)?.removeItem(GUEST_SESSION_KEY);
  } catch {
    // Non-fatal.
  }
}
