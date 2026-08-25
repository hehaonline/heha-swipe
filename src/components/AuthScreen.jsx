import { useState, useRef } from "react";
import { supabase } from "../lib/supabase";

const redirectTo = window.location.origin;
// Single source of truth for the sign-up intent key so it stays in sync with App.jsx.
const SIGNUP_ROLE_KEY = "heha_signup_role";

function CustomerIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M19.5 4.5c-6.8.1-11.2 2.6-13.1 7.4-1.1 2.8-.2 5.5 2.2 6.7 2.5 1.3 5.4.2 6.8-2.4 1.1-2.1 1.2-5.3 4.1-11.7Z" />
      <path d="M5 20c2.2-4.1 5.3-7.1 9.3-9" />
    </svg>
  );
}

function BusinessIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M4 9.5V20h16V9.5" />
      <path d="M3 9.5 5.2 4h13.6L21 9.5" />
      <path d="M3 9.5c0 1.4 1 2.5 2.3 2.5s2.4-1.1 2.4-2.5c0 1.4 1 2.5 2.3 2.5s2-1.1 2-2.5c0 1.4.9 2.5 2 2.5s2.3-1.1 2.3-2.5c0 1.4 1.1 2.5 2.4 2.5S21 10.9 21 9.5" />
      <path d="M9 20v-5h6v5" />
    </svg>
  );
}

export default function AuthScreen({ initialMode = null, onBack } = {}) {
  // When arriving from the landing entry gate we already know the intent
  // (sign in vs create) and can skip straight to the consumer form, while the
  // role pill still lets business users switch. Direct visitors keep the
  // original role-first experience.
  const [role, setRole] = useState(
    () => localStorage.getItem(SIGNUP_ROLE_KEY) || (initialMode ? "customer" : "")
  );
  const [mode, setMode] = useState(initialMode === "signin" ? "signin" : "create");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);
  // Guards against a second auth call firing before `loading` disables the button
  // on the next render (rapid double-click / double-submit). One click => one call.
  const authPending = useRef(false);

  // Persist the chosen customer/partner intent right before an auth call so it
  // survives the OAuth/magic-link round trip and can be read after login.
  const persistIntent = () => {
    localStorage.setItem(SIGNUP_ROLE_KEY, role || "customer");
  };

  const chooseRole = (nextRole) => {
    localStorage.setItem(SIGNUP_ROLE_KEY, nextRole);
    setRole(nextRole);
    setMessage(null);
    setError(null);
  };

  const changeRole = () => {
    const nextRole = role === "partner" ? "customer" : "partner";
    localStorage.setItem(SIGNUP_ROLE_KEY, nextRole);
    setRole(nextRole);
    setMessage(null);
    setError(null);
  };

  const submitPasswordAuth = async (event) => {
    event.preventDefault();
    if (authPending.current) return;
    authPending.current = true;
    persistIntent();
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      if (password.length < 8) {
        throw new Error("Please use at least 8 characters for your password.");
      }

      if (mode === "create") {
        const { error: signUpError } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            emailRedirectTo: redirectTo,
            data: { signup_role: role || "customer" },
          },
        });
        if (signUpError) throw signUpError;
        setMessage("Account created. Check your email if confirmation is required, then sign in with your password.");
      } else {
        const { error: signInError } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });
        if (signInError) throw signInError;
      }
    } catch (authError) {
      setError(authError.message || "Could not complete authentication.");
    } finally {
      setLoading(false);
      authPending.current = false;
    }
  };

  const sendSignInEmail = async () => {
    if (authPending.current) return;
    authPending.current = true;
    persistIntent();
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      const { error: linkError } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        // On the Sign in tab, do NOT create a new user: that path can trigger a
        // second (signup confirmation) email on top of the magic link. New accounts
        // are still created intentionally from the Create account tab.
        options: { emailRedirectTo: redirectTo, shouldCreateUser: mode === "create" },
      });
      if (linkError) throw linkError;
      setMessage("We sent a secure sign-in email. Open the link to continue.");
    } catch (linkError) {
      setError(linkError.message || "Could not send sign-in email.");
    } finally {
      setLoading(false);
      authPending.current = false;
    }
  };

  const sendPasswordReset = async () => {
    if (authPending.current) return;
    authPending.current = true;
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      if (!email.trim()) throw new Error("Enter your email address first, then tap Forgot password.");
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo,
      });
      if (resetError) throw resetError;
      setMessage("Password reset email sent. Open the link and create a new password.");
    } catch (resetError) {
      setError(resetError.message || "Could not send password reset email.");
    } finally {
      setLoading(false);
      authPending.current = false;
    }
  };

  const signInWithProvider = async (provider) => {
    if (authPending.current) return;
    authPending.current = true;
    setLoading(true);
    setError(null);
    persistIntent();

    const { error: authError } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo },
    });
    // On success the browser redirects to the provider, so we intentionally do not
    // reset here. Only clear the guard if the call failed before navigating away.
    if (authError) {
      setError(authError.message);
      setLoading(false);
      authPending.current = false;
    }
  };

  if (!role) {
    return (
      <main className="auth-screen">
        <section className="auth-card">
          {onBack && (
            <button type="button" className="auth-back-link" onClick={onBack}>
              ← Explore as guest
            </button>
          )}
          <div className="auth-hero">
            <div className="brand-mark large" role="img" aria-label="HEHA Swipe">H</div>
            <p className="eyebrow">HEHA Swipe early access</p>
            <h1>Swipe local. Save healthy spots. Support what you love.</h1>
            <p>HEHA Swipe helps you discover local healthy restaurants, wellness spaces, markets, vendors, and community businesses — starting as an early-access web app.</p>
          </div>

          <div className="choice-grid auth-choice-grid">
            <button type="button" className="choice-card" onClick={() => chooseRole("customer")}>
              <span className="choice-icon"><CustomerIcon /></span>
              <h2>Customer</h2>
              <p>Discover, save, and support healthy local businesses around Tampa Bay.</p>
            </button>
            <button type="button" className="choice-card featured" onClick={() => chooseRole("partner")}>
              <span className="choice-icon"><BusinessIcon /></span>
              <h2>Business</h2>
              <p>Create a listing and become visible inside the HEHA Swipe discovery feed.</p>
            </button>
          </div>
        </section>
      </main>
    );
  }

  const isBusiness = role === "partner";
  const accessLabel = isBusiness ? "Business access" : "Customer access";
  const switchLabel = isBusiness ? "Customer access" : "Business access";
  const headline = "Swipe local. Save healthy spots. Support what you love.";
  const helperCopy = isBusiness
    ? mode === "create"
      ? "Create an account to request your business listing and join the HEHA Swipe discovery feed."
      : "Sign in to continue managing your HEHA Swipe business access."
    : mode === "create"
      ? "Create an account to discover, save, and support healthy local places."
      : "Sign in to continue discovering and saving healthy local places.";

  return (
    <main className="auth-screen">
      <section className="auth-card role-auth-card">
        {onBack && (
          <button type="button" className="auth-back-link" onClick={onBack}>
            ← Explore as guest
          </button>
        )}
        <button type="button" className="role-switch-pill" onClick={changeRole}>
          {switchLabel}
        </button>

        <div className="auth-hero">
          <div className="brand-mark large" role="img" aria-label="HEHA Swipe">H</div>
          <p className="eyebrow">{accessLabel}</p>
          <h1>{headline}</h1>
          <p>{helperCopy}</p>
        </div>

        <div className="auth-tabs">
          <button type="button" aria-pressed={mode === "create"} className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Create account</button>
          <button type="button" aria-pressed={mode === "signin"} className={mode === "signin" ? "active" : ""} onClick={() => setMode("signin")}>Sign in</button>
        </div>

        <form onSubmit={submitPasswordAuth} className="auth-form">
          <label htmlFor="auth-email">Email address</label>
          <input
            id="auth-email"
            name="email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="you@example.com"
            required
          />

          <label htmlFor="auth-password">Password</label>
          <input
            id="auth-password"
            name="password"
            type="password"
            autoComplete={mode === "create" ? "new-password" : "current-password"}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="Minimum 8 characters"
            minLength="8"
            required
          />

          <button type="submit" className="primary-button" disabled={loading}>
            {loading ? "Working…" : mode === "create" ? "Create secure account" : "Sign in with password"}
          </button>
        </form>

        {mode === "signin" && (
          <button type="button" className="text-button center" onClick={sendPasswordReset} disabled={loading}>
            Forgot password?
          </button>
        )}

        <button type="button" className="text-button center" onClick={sendSignInEmail} disabled={!email || loading}>
          Send secure sign-in email instead
        </button>

        <div className="divider"><span>or</span></div>

        <div className="provider-row">
          <button type="button" onClick={() => signInWithProvider("google")} disabled={loading}>
            <span className="provider-mark" aria-hidden="true">G</span>
            <span>Continue with Google</span>
          </button>
          <button type="button" onClick={() => signInWithProvider("apple")} disabled={loading}>
            <span className="provider-mark" aria-hidden="true">A</span>
            <span>Continue with Apple</span>
          </button>
          <button type="button" onClick={() => signInWithProvider("facebook")} disabled={loading}>
            <span className="provider-mark" aria-hidden="true">f</span>
            <span>Continue with Facebook</span>
          </button>
        </div>

        {message && <div className="success-banner" role="status" aria-live="polite">{message}</div>}
        {error && <div className="error-banner" role="alert">{error}</div>}

        <p className="fine-print">
          Your sign-in is protected. HEHA never displays your password or shares it with local partners.
        </p>
      </section>
    </main>
  );
}
