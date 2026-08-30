const SESSION_KEY = "heha_partner_invite_token_v1";
const REQUEST_KEY_SESSION_KEY = "heha_partner_invite_request_key_v1";
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,512}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
let inviteUrlHardStop = false;

function sessionGet(key) {
  try {
    return typeof sessionStorage === "undefined" ? null : sessionStorage.getItem(key);
  } catch {
    return null;
  }
}

function sessionSet(key, value) {
  try {
    if (typeof sessionStorage === "undefined") return false;
    sessionStorage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

function sessionRemove(key) {
  try {
    if (typeof sessionStorage !== "undefined") sessionStorage.removeItem(key);
  } catch {
    // Storage denial keeps the protected flow locked; no token is logged.
  }
}

function clearInviteSession() {
  sessionRemove(SESSION_KEY);
  sessionRemove(REQUEST_KEY_SESSION_KEY);
}

export function consumePartnerInviteFromLocation() {
  if (typeof window === "undefined") return null;
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const candidate = String(params.get("partner_invite") || "").trim();
  if (!candidate) return pendingPartnerInviteToken();

  params.delete("partner_invite");
  const nextHash = params.toString();
  const sanitizedUrl = `${window.location.pathname}${window.location.search}${nextHash ? `#${nextHash}` : ""}`;
  try {
    window.history.replaceState(null, "", sanitizedUrl);
  } catch {
    clearInviteSession();
    try {
      window.location.replace(sanitizedUrl);
    } catch {
      inviteUrlHardStop = true;
      window.stop?.();
    }
    return null;
  }

  if (!TOKEN_PATTERN.test(candidate)) {
    clearInviteSession();
    return null;
  }

  const currentToken = sessionGet(SESSION_KEY);
  if (currentToken !== candidate) sessionRemove(REQUEST_KEY_SESSION_KEY);
  if (!sessionSet(SESSION_KEY, candidate)) {
    clearInviteSession();
    return null;
  }
  return candidate;
}

export function pendingPartnerInviteToken() {
  const token = sessionGet(SESSION_KEY);
  return token && TOKEN_PATTERN.test(token) ? token : null;
}

export function pendingPartnerInviteRequestKey() {
  if (!pendingPartnerInviteToken()) return null;
  const current = sessionGet(REQUEST_KEY_SESSION_KEY);
  if (current && UUID_PATTERN.test(current)) return current;
  const requestKey = crypto.randomUUID();
  return sessionSet(REQUEST_KEY_SESSION_KEY, requestKey) ? requestKey : null;
}

export function clearPendingPartnerInviteToken() {
  clearInviteSession();
}

export function partnerInviteUrlRequiresHardStop() {
  return inviteUrlHardStop;
}
