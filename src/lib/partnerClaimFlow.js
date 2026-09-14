// This client is a fail-closed UI boundary, not an ownership authority. The
// existing RPCs recheck the verified recipient and mutate the same row atomically.
const TOKEN = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function fail(details) {
  return Object.assign(new Error("Claim verification failed."), { details });
}

export function claimTokenFromLocation({ pathname, search = "" }) {
  if (pathname !== "/claim-partner" || search.length > 8192) return "";
  const values = new URLSearchParams(search).getAll("token");
  return values.length === 1 && TOKEN.test(values[0]) ? values[0] : "";
}

export function claimRedirectUrl(origin, token) {
  const url = new URL(origin);
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (!TOKEN.test(token) || (url.protocol !== "https:" && !(local && url.protocol === "http:"))
      || url.username || url.password || url.pathname !== "/" || url.search || url.hash) {
    throw fail("HEHA_CLAIM_NOT_RECOGNIZED");
  }
  return `${url.origin}/claim-partner?token=${token}`;
}

export function isVerifiedClaimUser(user) {
  const email = typeof user?.email === "string" ? user.email.trim() : "";
  return UUID.test(user?.id || "") && user?.is_anonymous !== true
    && Boolean(user?.email_confirmed_at) && Number.isFinite(Date.parse(user.email_confirmed_at))
    && email.length <= 320 && email.indexOf("@") > 0;
}

function oneRow(data) {
  if (!Array.isArray(data) || data.length !== 1 || !data[0] || typeof data[0] !== "object") {
    throw fail("HEHA_CLAIM_INVALID_RESPONSE");
  }
  const row = data[0];
  if (!UUID.test(row.partner_id || "") || typeof row.partner_name !== "string"
      || !row.partner_name.trim() || row.partner_name.length > 200) {
    throw fail("HEHA_CLAIM_INVALID_RESPONSE");
  }
  return row;
}

export async function verifiedClaimUser(client, expectedUserId) {
  const { data, error } = await client.auth.getUser();
  if (error) throw error;
  if (!isVerifiedClaimUser(data?.user)) throw fail("HEHA_CLAIM_RECIPIENT_INELIGIBLE");
  if (data.user.id !== expectedUserId) throw fail("HEHA_CLAIM_SESSION_CHANGED");
  return data.user;
}

export function createPartnerClaimFlow(client, token) {
  let claimPending = false;
  let completed = false;
  let latestPreview = null;
  const checkToken = () => {
    if (!TOKEN.test(token)) throw fail("HEHA_CLAIM_NOT_RECOGNIZED");
  };
  return {
    async preview(expectedUserId) {
      checkToken();
      latestPreview = null;
      await verifiedClaimUser(client, expectedUserId);
      const { data, error } = await client.rpc("preview_partner_claim", { p_raw_token: token });
      if (error) throw error;
      const row = oneRow(data);
      if (row.claimable !== true || !Number.isFinite(Date.parse(row.expires_at))) {
        throw fail("HEHA_CLAIM_PROFILE_UNAVAILABLE");
      }
      await verifiedClaimUser(client, expectedUserId);
      latestPreview = { userId: expectedUserId, partnerId: row.partner_id };
      return row;
    },
    async claim(expectedUserId, expectedPartnerId) {
      checkToken();
      if (claimPending || completed) throw fail("HEHA_CLAIM_SUBMISSION_PENDING");
      if (!latestPreview || latestPreview.userId !== expectedUserId
          || latestPreview.partnerId !== expectedPartnerId) {
        throw fail("HEHA_CLAIM_INVALID_RESPONSE");
      }
      claimPending = true;
      try {
        await verifiedClaimUser(client, expectedUserId);
        const { data, error } = await client.rpc("claim_partner_profile", { p_raw_token: token });
        if (error) throw error;
        // A successful RPC is a committed one-time mutation. Never auto-retry it,
        // even if the response/session validation or browser redirect later fails.
        completed = true;
        const row = oneRow(data);
        if (row.partner_id !== expectedPartnerId || row.claim_status !== "claimed"
            || !Number.isFinite(Date.parse(row.claimed_at))) {
          throw fail("HEHA_CLAIM_INVALID_RESPONSE");
        }
        await verifiedClaimUser(client, expectedUserId);
        return row;
      } finally {
        claimPending = false;
      }
    },
  };
}

export async function authenticateForClaim(client, { mode, method, email, password, redirectTo }) {
  if (!["signin", "create"].includes(mode) || !["password", "email"].includes(method)) {
    throw fail("HEHA_CLAIM_AUTH_INVALID");
  }
  const cleanEmail = typeof email === "string" ? email.trim() : "";
  if (!cleanEmail || cleanEmail.length > 320 || cleanEmail.indexOf("@") <= 0) {
    throw fail("HEHA_CLAIM_AUTH_INVALID");
  }
  const redirect = new URL(redirectTo);
  if (claimRedirectUrl(redirect.origin, claimTokenFromLocation(redirect)) !== redirectTo) {
    throw fail("HEHA_CLAIM_AUTH_INVALID");
  }
  let result;
  if (method === "email") {
    result = await client.auth.signInWithOtp({
      email: cleanEmail,
      options: { emailRedirectTo: redirectTo, shouldCreateUser: mode === "create" },
    });
  } else {
    // Existing passwords may predate the current account-creation minimum.
    if (typeof password !== "string" || !password || (mode === "create" && password.length < 8)) {
      throw new Error("Password must have at least 8 characters for a new account.");
    }
    result = mode === "create"
      ? await client.auth.signUp({ email: cleanEmail, password, options: { emailRedirectTo: redirectTo } })
      : await client.auth.signInWithPassword({ email: cleanEmail, password });
  }
  if (result.error) throw result.error;
  return result.data;
}
