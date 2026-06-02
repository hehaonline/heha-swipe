import { useState } from "react";
import { supabase } from "../lib/supabase";

const redirectTo = window.location.origin;

export default function AuthScreen() {
  const [role, setRole] = useState(() => localStorage.getItem("heha_signup_role") || "");
  const [mode, setMode] = useState("create");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);

  const chooseRole = (nextRole) => {
    localStorage.setItem("heha_signup_role", nextRole);
    setRole(nextRole);
    setMessage(null);
    setError(null);
  };

  const changeRole = () => {
    const nextRole = role === "partner" ? "customer" : "partner";
    localStorage.setItem("heha_signup_role", nextRole);
    setRole(nextRole);
    setMessage(null);
    setError(null);
  };

  const submitPasswordAuth = async (event) => {
    event.preventDefault();
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
    }
  };

  const sendSignInEmail = async () => {
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      const { error: linkError } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        options: { emailRedirectTo: redirectTo, shouldCreateUser: true },
      });
      if (linkError) throw linkError;
      setMessage("We sent a secure sign-in email. Open the link to continue.");
    } catch (linkError) {
      setError(linkError.message || "Could not send sign-in email.");
    } finally {
      setLoading(false);
    }
  };

  const sendPasswordReset = async () => {
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
    }
  };

  const signInWithProvider = async (provider) => {
    setLoading(true);
    setError(null);
    localStorage.setItem("heha_signup_role", role || "customer");

    const { error: authError } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo },
    });
    if (authError) {
      setError(authError.message);
      setLoading(false);
    }
  };

  if (!role) {
    return (
      <main className="auth-screen">
        <section className="auth-card">
          <div className="auth-hero">
            <div className="brand-mark large">✦</div>
            <p className="eyebrow">HEHA Swipe Tampa Bay</p>
            <h1>How are you joining HEHA Swipe?</h1>
            <p>Choose your path first so your profile opens the right customer or business experience.</p>
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
  const headline = isBusiness
    ? "Sign in or create your business profile."
    : "Sign in or create your HEHA explorer profile.";
  const helperCopy = isBusiness
    ? "Manage your business listing and become visible to local customers looking for healthier options."
    : "Save local restaurants, wellness spaces, markets, and offers you want to remember.";

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
