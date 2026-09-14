import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";
import {
  CLAIM_ERRORS,
  claimSessionStorage,
  friendlyAuthError,
  friendlyClaimError,
  isClaimRecipientMismatch,
  saveClaimSuccess,
} from "../lib/partnerClaimUx";
import {
  authenticateForClaim,
  claimRedirectUrl,
  claimTokenFromLocation,
  createPartnerClaimFlow,
} from "../lib/partnerClaimFlow";

export default function PartnerClaimScreen({ session, authLoading = false, sessionError, onSignOut }) {
  const token = useMemo(() => claimTokenFromLocation(window.location), []);
  const flow = useMemo(() => createPartnerClaimFlow(supabase, token), [token]);
  const authPending = useRef(false);
  const claimPending = useRef(false);
  const mounted = useRef(true);
  const [mode, setMode] = useState("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);
  const [preview, setPreview] = useState(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [recipientMismatch, setRecipientMismatch] = useState(false);
  const [previewAttempt, setPreviewAttempt] = useState(0);
  const [completed, setCompleted] = useState(null);

  useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);

  useEffect(() => {
    setPreview(null);
    if (!session?.user?.id || !token || authLoading || sessionError) return;

    let cancelled = false;
    async function loadPreview() {
      setPreviewLoading(true);
      setError(null);
      setRecipientMismatch(false);
      try {
        const nextPreview = await flow.preview(session.user.id);
        if (!cancelled) setPreview(nextPreview);
      } catch (previewError) {
        if (!cancelled) {
          setRecipientMismatch(isClaimRecipientMismatch(previewError));
          setError(friendlyClaimError(previewError));
        }
      } finally {
        if (!cancelled) setPreviewLoading(false);
      }
    }

    loadPreview();
    return () => {
      cancelled = true;
    };
  }, [session?.user?.id, session?.user?.email_confirmed_at, session?.user?.is_anonymous, token, flow, authLoading, sessionError, previewAttempt]);

  const submitPasswordAuth = async (event) => {
    event.preventDefault();
    if (authPending.current) return;
    authPending.current = true;
    setBusy(true);
    setError(null);
    setRecipientMismatch(false);
    setMessage(null);

    try {
      await authenticateForClaim(supabase, {
        mode, method: "password", email, password,
        redirectTo: claimRedirectUrl(window.location.origin, token),
      });
      if (!mounted.current) return;
      setPassword("");
      if (mode === "create") {
        setMessage("Check your designated business inbox to verify your email and return to this claim link. If the account already exists, choose Sign in.");
      }
    } catch (authError) {
      if (mounted.current) setError(friendlyAuthError(authError, mode));
    } finally {
      if (mounted.current) setBusy(false);
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
      await authenticateForClaim(supabase, {
        mode, method: "email", email,
        redirectTo: claimRedirectUrl(window.location.origin, token),
      });
      if (mounted.current) setMessage("Check your inbox for a secure sign-in email. Open it to return to the business-profile claim.");
    } catch {
      if (mounted.current) setError("We couldn't send the secure sign-in email. Check the address and try again.");
    } finally {
      if (mounted.current) setBusy(false);
      authPending.current = false;
    }
  };

  const claimProfile = async () => {
    if (!session?.user?.id || !preview?.claimable || !token || busy || claimPending.current || completed) return;
    claimPending.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      const claimed = await flow.claim(session.user.id, preview.partner_id);
      if (!mounted.current) return;
      setCompleted(claimed);

      // The RPC commits ownership atomically. Do not mutate subscription or
      // entitlement fields from the browser; App detects the owned listing.
      // Storage is only a best-effort redirect confirmation and must not turn a
      // committed, one-time claim into a false failure if storage is blocked.
      saveClaimSuccess(claimSessionStorage(window), claimed.partner_name, false, session.user.id, Date.now(), claimed.partner_id);
      setMessage(`${claimed.partner_name} is now connected to your HEHA account.`);

      // Do not redirect automatically: preserve a visible committed result even
      // if session storage is unavailable. Continuing never repeats the claim.
      window.history.replaceState(null, "", "/claim-partner");
    } catch (claimError) {
      if (mounted.current) {
        setRecipientMismatch(isClaimRecipientMismatch(claimError));
        setError(friendlyClaimError(claimError));
      }
    } finally {
      if (mounted.current) setBusy(false);
      claimPending.current = false;
    }
  };

  const signOut = async () => {
    if (authPending.current || claimPending.current) return;
    authPending.current = true;
    setBusy(true);
    try { await onSignOut(); }
    catch { if (mounted.current) setError("Sign out failed. Try again before using another account."); }
    finally { authPending.current = false; if (mounted.current) setBusy(false); }
  };

  if (authLoading) {
    return (
      <main className="auth-screen">
        <section className="auth-card claim-state-card">
          <p className="eyebrow">Secure business claim</p>
          <h1>Checking your HEHA account…</h1>
        </section>
      </main>
    );
  }

  if (sessionError) {
    return <main className="auth-screen"><section className="auth-card claim-state-card"><h1>Account check unavailable</h1><p role="alert">{sessionError}</p><button className="primary-button" onClick={() => window.location.reload()}>Try again</button></section></main>;
  }

  if (completed) {
    return <main className="auth-screen"><section className="auth-card claim-state-card">
      <h1>{completed.partner_name} is connected to your account.</h1>
      <p role="status">The same business profile was claimed. This did not publish changes, accept a Local agreement, activate offers or ordering, or create another business.</p>
      <a className="primary-button" href="/?claim=success&tab=profile">Review your HEHA account</a>
    </section></main>;
  }

  if (!token) {
    return (
      <main className="auth-screen">
        <section className="auth-card claim-state-card">
          <p className="eyebrow">Secure business claim</p>
          <h1>This claim link is incomplete.</h1>
          <p>Ask HEHA for a new business-profile claim link. For your security, HEHA never asks you to paste a claim token into a public form.</p>
          <p className="claim-support-copy">Need help with a link? Contact HEHA support.</p>
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
            <h1>Connect your existing business profile.</h1>
            <p>Use the designated business inbox to sign in or create a free account and verify your email. Claiming preserves the same profile and history; it does not create another business.</p>
          </div>

          <div className="auth-tabs">
            <button type="button" disabled={busy} aria-pressed={mode === "signin"} className={mode === "signin" ? "active" : ""} onClick={() => setMode("signin")}>Sign in</button>
            <button type="button" disabled={busy} aria-pressed={mode === "create"} className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Create account</button>
          </div>

          <form onSubmit={submitPasswordAuth} className="auth-form">
            <label htmlFor="claim-business-email">Business email address</label>
            <input id="claim-business-email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required />

            <label htmlFor="claim-password">Password</label>
            <input id="claim-password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete={mode === "create" ? "new-password" : "current-password"} required />
            <span className="field-guidance">{mode === "create" ? "At least 8 characters for a new account." : "Use your existing account password."}</span>

            <button className="primary-button" type="submit" disabled={busy}>
              {busy ? "Working…" : mode === "create" ? "Create account" : "Sign in and continue"}
            </button>
            {error && <div className="error-banner auth-action-error" role="alert">{error}</div>}
            <button className="secondary-button" type="button" onClick={sendSecureEmail} disabled={busy || !email.trim()}>
              Email me a secure sign-in link
            </button>
          </form>

          <p className="fine-print">A “YES” reply to an outreach message does not verify ownership by itself. The secure claim link and authenticated account complete the claim.</p>
          <p className="fine-print"><a href="/privacy">Privacy</a> · <a href="/support">Support</a>. Claiming does not accept a commercial or Local agreement.</p>
          {message && <div className="success-banner" role="status" aria-live="polite">{message}</div>}
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

        {previewLoading || (!preview && !error) ? (
          <div className="soft-note" role="status" aria-live="polite">Checking this one-time claim link…</div>
        ) : preview?.claimable ? (
          <>
            <div className="soft-note">
              Claiming connects this existing profile to your account. It does not automatically approve new products, publish profile edits, create HEHA Certified status, or activate ordering.
            </div>
            <p className="claim-review-gate">Community Pass offers and HEHA Local participation are separate opt-ins. Claiming does not change the listing's publication or approval state.</p>
            <button className="primary-button" type="button" onClick={claimProfile} disabled={busy}>
              {busy ? "Claiming profile…" : `Claim ${preview.partner_name}`}
            </button>
          </>
        ) : (
          !error && <div className="error-banner">{CLAIM_ERRORS.unavailable}</div>
        )}

        {recipientMismatch ? (
          <div className="claim-mismatch-actions">
            <button className="secondary-button" type="button" onClick={signOut} disabled={busy}>Use the invited account</button>
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
          <button className="secondary-button" type="button" onClick={signOut} disabled={busy}>Sign out</button>
        )}
        {!preview && error && <button className="secondary-button" type="button" disabled={busy || previewLoading} onClick={() => setPreviewAttempt((attempt) => attempt + 1)}>Check link again</button>}
        <p className="fine-print">The one-time claim link expires. HEHA stores only a cryptographic hash of the claim token.</p>
        {message && <div className="success-banner" role="status" aria-live="polite">{message}</div>}
        {error && <div className="error-banner" role="alert">{error}</div>}
      </section>
    </main>
  );
}
