export const CLAIM_SUCCESS_KEY = "heha_partner_claim_success";

export const CLAIM_ERRORS = {
  invalid: "This claim link isn't recognized. Ask HEHA for a new secure claim link.",
  expired: "This claim link has expired. Ask HEHA for a new secure claim link.",
  revoked: "This claim link is no longer active. Ask HEHA for a new secure claim link.",
  used: "This claim link has already been used. If you completed a claim before, sign in to your HEHA account instead of using this link again.",
  claimed: "This business profile has already been claimed by another account. If that seems wrong, contact HEHA support so we can look into it.",
  unavailable: "This profile currently isn't available to claim. Contact HEHA support for help.",
};

export function friendlyClaimError(error) {
  const message = String(error?.message || "").toLowerCase();
  if (/not recognized|invalid|not found/.test(message)) return CLAIM_ERRORS.invalid;
  if (/expired/.test(message)) return CLAIM_ERRORS.expired;
  if (/revoked|no longer active/.test(message)) return CLAIM_ERRORS.revoked;
  if (/already used|has (already )?been used/.test(message)) return CLAIM_ERRORS.used;
  if (/claimed by another|already been claimed/.test(message)) return CLAIM_ERRORS.claimed;
  if (/no longer claimable|isn't available to claim/.test(message)) return CLAIM_ERRORS.unavailable;
  if (/authentication required/.test(message)) return "Please sign in before claiming this business profile.";
  return "HEHA could not verify this one-time claim link. Ask HEHA for a new secure claim link.";
}

export function friendlyAuthError(error, mode) {
  const message = String(error?.message || "").toLowerCase();
  if (/invalid login credentials|invalid credentials/.test(message)) {
    return "That email and password combination didn't work. Try again, or use “Email me a secure sign-in link” instead.";
  }
  if (/already registered|already exists/.test(message)) {
    return "An account already uses that email. Choose Sign in, or use “Email me a secure sign-in link” instead.";
  }
  if (/password/.test(message) && /short|least|characters/.test(message)) {
    return "Use a password with at least 8 characters.";
  }
  return mode === "create"
    ? "We couldn't create your account. Check your details and try again."
    : "We couldn't sign you in. Try again or use the secure email link.";
}

export function saveClaimSuccess(storage, partnerName, profileSetupPending) {
  storage.setItem(CLAIM_SUCCESS_KEY, JSON.stringify({
    partnerName,
    profileSetupPending: Boolean(profileSetupPending),
  }));
}

export function readClaimSuccess(search, storage) {
  if (new URLSearchParams(search).get("claim") !== "success") return null;
  try {
    const stored = JSON.parse(storage.getItem(CLAIM_SUCCESS_KEY) || "null");
    return stored && typeof stored.partnerName === "string" ? stored : {};
  } catch {
    return {};
  }
}

export function clearClaimSuccess(storage) {
  storage.removeItem(CLAIM_SUCCESS_KEY);
}
