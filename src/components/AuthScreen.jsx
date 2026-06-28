import { useState, useRef } from "react";
import { supabase } from "../lib/supabase";

const redirectTo = window.location.origin;
// Single source of truth for the sign-up intent key so it stays in sync with App.jsx.
const SIGNUP_ROLE_KEY = "heha_signup_role";

export default function AuthScreen() {
  const [role, setRole] = useState(() => localStorage.getItem(SIGNUP_ROLE_KEY) || "");
  const [mode, setMode] = useState("create");
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
          <div className="auth-hero">
            <div className="brand-mark large">✦</div>
            <p className="eyebrow">HEHA Swipe early access</p>
            <h1>Swipe local. Save healthy spots. Support what you love.</h1>
            <p>HEHA Swipe helps you discover local healthy restaurants, wellness spaces, markets, vendors, and community businesses — starting as an early-access web app.</p>
            <p>Swipe local spots. Save favorites. Set your vibe. Businesses can request to get listed.</p>
          </div>

          <div className="choice-grid auth-choice-grid">
            <button type="button" className="choice-card" onClick={() => chooseRole("customer")}>
              <span>🌿</span>
              <h2>Customer</h2>
              <p>Discover, save, and support healthy local businesses around Tampa Bay.</p>
            </button>
            <button type="button" className="choice-card featured" onClick={() => chooseRole("partner")}>
              <span>🏪</span>
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
    ? "HEHA Swipe helps you discover local healthy restaurants, wellness spaces, markets, vendors, and community businesses — starting as an early-access web app. Create a free account to request your business listing."
    : "HEHA Swipe helps you discover local healthy restaurants, wellness spaces, markets, vendors, and community businesses — starting as an early-access web app. Create a free account to explore HEHA Swipe.";

  return (
    <main className="auth-screen">
      <section className="auth-card role-auth-card">
        <button type="button" className="role-switch-pill" onClick={changeRole}>
          {switchLabel}
        </button>

        <div className="auth-hero">
          <div className="brand-mark large">✦</div>
          <p className="eyebrow">{accessLabel}</p>
          <h1>{headline}</h1>
          <p>{helperCopy}</p>
          <p>Swipe local spots. Save favorites. Set your vibe. Businesses can request to get listed.</p>
        </div>

        <div className="auth-tabs">
          <button type="button" className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Create account</button>
          <button type="button" className={mode === "signin" ? "active" : ""} onClick={() => setMode("signin")}>Sign in</button>
        </div>

        <form onSubmit={submitPasswordAuth} className="auth-form">
          <label>Email address</label>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="you@example.com"
            required
          />

          <label>Password</label>
          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="Minimum 8 characters"
            minLength="8"
            required
          />

          <button className="primary-button" disabled={loading}>
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

        <div className="divider"><span>or continue with</span></div>

        <div className="provider-row">
          <button type="button" onClick={() => signInWithProvider("google")} disabled={loading}>Google</button>
          <button type="button" onClick={() => signInWithProvider("apple")} disabled={loading}>Apple</button>
          <button type="button" onClick={() => signInWithProvider("facebook")} disabled={loading}>Facebook</button>
        </div>

        {message && <div className="success-banner">{message}</div>}
        {error && <div className="error-banner">{error}</div>}

        <p className="fine-print">
          Passwords are handled securely by Supabase Auth. HEHA does not store your password inside your public profile.
        </p>
      </section>
    </main>
  );
}
