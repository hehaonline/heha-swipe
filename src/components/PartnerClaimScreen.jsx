import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";
import {
  CLAIM_ERRORS,
  friendlyAuthError,
  friendlyClaimError,
  isClaimRecipientMismatch,
  saveClaimSuccess,
} from "../lib/partnerClaimUx";

const SIGNUP_ROLE_KEY = "heha_signup_role";

function currentClaimRedirect() {
  return `${window.location.origin}${window.location.pathname}${window.location.search}`;
}

function claimTokenFromUrl() {
  return new URLSearchParams(window.location.search).get("token")?.trim() || "";
}

export default function PartnerClaimScreen({ session, authLoading = false, onSignOut }) {
  const token = useMemo(claimTokenFromUrl, []);
  const authPending = useRef(false);
  const [mode, setMode] = useState("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);
  const [preview, setPreview] = useState(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [recipientMismatch, setRecipientMismatch] = useState(false);

  useEffect(() => {
    localStorage.setItem(SIGNUP_ROLE_KEY, "partner");
  }, []);

  useEffect(() => {
    if (!session?.user?.id || !token) return;

    let cancelled = false;
    async function loadPreview() {
      setPreviewLoading(true);
      setError(null);
      setRecipientMismatch(false);
      const { data, error: previewError } = await supabase.rpc("preview_partner_claim", {
        p_raw_token: token,
      });

      if (cancelled) return;
      if (previewError) {
        setPreview(null);
        setRecipientMismatch(isClaimRecipientMismatch(previewError));
        setError(friendlyClaimError(previewError));
      } else {
        setPreview(data?.[0] || null);
        if (!data?.[0]) {
          setError(CLAIM_ERRORS.invalid);
        }
      }
      setPreviewLoading(false);
    }

    loadPreview();
    return () => {
      cancelled = true;
    };
  }, [session?.user?.id, token]);

  const submitPasswordAuth = async (event) => {
    event.preventDefault();
    if (authPending.current) return;
    authPending.current = true;
    setBusy(true);
    setError(null);
    setRecipientMismatch(false);
    setMessage(null);

    try {
      const cleanEmail = email.trim();
      if (!cleanEmail) throw new Error("Enter your business email address.");
      if (password.length < 8) throw new Error("Please use at least 8 characters for your password.");

      if (mode === "create") {
        const { error: signUpError } = await supabase.auth.signUp({
          email: cleanEmail,
          password,
          options: {
            emailRedirectTo: currentClaimRedirect(),
            data: { signup_role: "partner", claim_flow: true },
          },
        });
        if (signUpError) throw signUpError;
        setMessage("Account created. Check your email if confirmation is required, then return to this secure claim link.");
      } else {
        const { error: signInError } = await supabase.auth.signInWithPassword({
          email: cleanEmail,
          password,
        });
        if (signInError) throw signInError;
      }
    } catch (authError) {
      setError(friendlyAuthError(authError, mode));
    } finally {
      setBusy(false);
      authPending.current = false;
    }
  };

  const sendSecureEmail = async () => {
    if (authPending.current) return;
    authPending.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      const cleanEmail = email.trim();
      if (!cleanEmail) throw new Error("Enter your business email address first.");

      const { error: linkError } = await supabase.auth.signInWithOtp({
        email: cleanEmail,
        options: {
          emailRedirectTo: currentClaimRedirect(),
          shouldCreateUser: mode === "create",
          data: { signup_role: "partner", claim_flow: true },
        },
      });
      if (linkError) throw linkError;
      setMessage("We sent a secure email. Open it on this device to return to the business-profile claim.");
    } catch (linkError) {
      setError("We couldn't send the secure sign-in email. Check the address and try again.");
    } finally {
      setBusy(false);
      authPending.current = false;
    }
  };

  const claimProfile = async () => {
    if (!session?.user?.id || !token || busy) return;
    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      const { data, error: claimError } = await supabase.rpc("claim_partner_profile", {
        p_raw_token: token,
      });
      if (claimError) throw claimError;

      const claimed = data?.[0];
      if (!claimed?.partner_id) throw new Error("HEHA did not receive a confirmed profile claim.");

      // Ownership is committed atomically by claim_partner_profile. Account-profile
      // bootstrap is secondary and must never make a successful one-time claim look
      // like it failed (the token is already consumed at this point).
      const [{ error: profileError }, { error: customerProfileError }] = await Promise.all([
        supabase.from("profiles").upsert({
          id: session.user.id,
          email: session.user.email || null,
          phone: session.user.phone || null,
          subscription_type: "partner_free",
        }),
        supabase.from("customer_profiles").upsert({ user_id: session.user.id }),
      ]);
      localStorage.setItem(SIGNUP_ROLE_KEY, "partner");
      saveClaimSuccess(sessionStorage, claimed.partner_name, profileError || customerProfileError, session.user.id);
      setMessage(
        profileError || customerProfileError
          ? `${claimed.partner_name} is connected to your HEHA account. HEHA will finish setting up the account profile.`
          : `${claimed.partner_name} is now connected to your HEHA account.`,
      );

      window.location.replace("/?claim=success");
    } catch (claimError) {
      setRecipientMismatch(isClaimRecipientMismatch(claimError));
      setError(friendlyClaimError(claimError));
    } finally {
      setBusy(false);
    }
  };

  if (authLoading) {
    return (
      <main className="auth-screen">
        <section className="auth-card">
          <p className="eyebrow">Secure business claim</p>
          <h1>Checking your HEHA account…</h1>
        </section>
      </main>
    );
  }

  if (!token) {
    return (
      <main className="auth-screen">
        <section className="auth-card">
          <p className="eyebrow">Secure business claim</p>
          <h1>This claim link is incomplete.</h1>
          <p>Ask HEHA for a new business-profile claim link. For your security, HEHA never asks you to paste a claim token into a public form.</p>
          <p className="claim-support-copy">Need a new link? Contact HEHA support and we'll send one.</p>
          <a className="primary-button" href="/">Return to HEHA Swipe</a>
        </section>
      </main>
    );
  }

  if (!session) {
    return (
      <main className="auth-screen">
        <section className="auth-card role-auth-card claim-auth-card">
          <div className="auth-hero">
            <div className="brand-mark large">✦</div>
            <p className="eyebrow">Secure business claim</p>
            <h1>Connect the profile HEHA already created.</h1>
            <p>Sign in or create a free business account. Claiming keeps the same Partner ID, saves, interest history, and public listing—no duplicate profile is created.</p>
          </div>

          <div className="auth-tabs">
            <button type="button" className={mode === "signin" ? "active" : ""} onClick={() => setMode("signin")}>Sign in</button>
            <button type="button" className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Create account</button>
          </div>

          <form onSubmit={submitPasswordAuth} className="auth-form">
            <label>Business email address</label>
            <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required />

            <label>Password</label>
            <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete={mode === "create" ? "new-password" : "current-password"} required />
            <span className="field-guidance">At least 8 characters.</span>

            <button className="primary-button" type="submit" disabled={busy}>
              {busy ? "Working…" : mode === "create" ? "Create account" : "Sign in and continue"}
            </button>
            {error && <div className="error-banner auth-action-error" role="alert">{error}</div>}
            <button className="secondary-button" type="button" onClick={sendSecureEmail} disabled={busy || !email.trim()}>
              Email me a secure sign-in link
            </button>
          </form>

          <p className="fine-print">A “YES” reply to an outreach message does not verify ownership by itself. The secure claim link and authenticated account complete the claim.</p>
          {message && <div className="success-banner">{message}</div>}
        </section>
      </main>
    );
  }

  return (
    <main className="auth-screen">
      <section className="auth-card role-auth-card claim-auth-card">
        <div className="auth-hero">
          <div className="brand-mark large">🏪</div>
          <p className="eyebrow">Secure business claim</p>
          <h1>{preview?.partner_name || "Review your HEHA profile claim"}</h1>
          <p>Signed in as {session.user.email || session.user.phone || "your HEHA account"}.</p>
        </div>

        {previewLoading ? (
          <div className="soft-note">Checking this one-time claim link…</div>
        ) : preview?.claimable ? (
          <>
            <div className="soft-note">
              Claiming connects this existing profile to your account. It does not automatically approve new products, publish profile edits, create HEHA Certified status, or activate ordering.
            </div>
            <p className="claim-review-gate">Profile edits, products, and offers stay saved as drafts until HEHA reviews them.</p>
            <button className="primary-button" type="button" onClick={claimProfile} disabled={busy}>
              {busy ? "Claiming profile…" : `Claim ${preview.partner_name}`}
            </button>
          </>
        ) : (
          !error && <div className="error-banner">{CLAIM_ERRORS.unavailable}</div>
        )}

        {recipientMismatch ? (
          <div className="claim-mismatch-actions">
            <button className="secondary-button" type="button" onClick={onSignOut} disabled={busy}>Use the invited account</button>
            <a
              className="text-button"
              href="mailto:hello@heha.online?subject=HEHA%20Business%20Claim%20Help"
              aria-label="Get help with this business claim by email"
              title="Email HEHA support about business claims"
            >
              Get help
            </a>
          </div>
        ) : (
          <button className="secondary-button" type="button" onClick={onSignOut} disabled={busy}>Sign out</button>
        )}
        <p className="fine-print">The one-time claim link expires. HEHA stores only a cryptographic hash of the claim token.</p>
        {message && <div className="success-banner">{message}</div>}
        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
  );
}
