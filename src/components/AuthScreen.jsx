import { useState } from "react";
import { supabase } from "../lib/supabase";

const redirectTo = window.location.origin;

function normalizePhone(value) {
  const trimmed = value.trim();
  if (trimmed.startsWith("+")) return trimmed;
  return `+1${trimmed.replace(/\D/g, "")}`;
}

export default function AuthScreen() {
  const [mode, setMode] = useState("email");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [phoneCodeSent, setPhoneCodeSent] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);

  const resetMode = (nextMode) => {
    setMode(nextMode);
    setMessage(null);
    setError(null);
    setOtp("");
    setPhoneCodeSent(false);
  };

  const signInWithEmail = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      const { error: authError } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        options: { emailRedirectTo: redirectTo, shouldCreateUser: true },
      });
      if (authError) throw authError;
      setMessage("Check your email for the HEHA Swipe sign-in link.");
    } catch (authError) {
      setError(authError.message || "Could not send your sign-in link.");
    } finally {
      setLoading(false);
    }
  };

  const signInWithPhone = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      const normalizedPhone = normalizePhone(phone);
      const { error: authError } = await supabase.auth.signInWithOtp({ phone: normalizedPhone });
      if (authError) throw authError;
      setPhoneCodeSent(true);
      setMessage("We sent a secure sign-in code to your phone.");
    } catch (authError) {
      setError(authError.message || "Could not send the phone code yet.");
    } finally {
      setLoading(false);
    }
  };

  const verifyPhoneCode = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const { error: verifyError } = await supabase.auth.verifyOtp({
        phone: normalizePhone(phone),
        token: otp.trim(),
        type: "sms",
      });
      if (verifyError) throw verifyError;
    } catch (verifyError) {
      setError(verifyError.message || "Could not verify this code.");
    } finally {
      setLoading(false);
    }
  };

  const signInWithProvider = async (provider) => {
    setLoading(true);
    setError(null);
    const { error: authError } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo },
    });
    if (authError) {
      setError(authError.message);
      setLoading(false);
    }
  };

  return (
    <main className="auth-screen">
      <section className="auth-card">
        <div className="auth-hero">
          <div className="brand-mark large">✦</div>
          <p className="eyebrow">HEHA Swipe Tampa Bay</p>
          <h1>Discover the healthy businesses your body wants to know.</h1>
          <p>
            Swipe through local restaurants, wellness partners, markets, coaches, movement spaces, and community offers curated by HEHA.
          </p>
        </div>

        <div className="auth-value-grid">
          <span>🥗 Clean food</span>
          <span>🧘 Wellness</span>
          <span>🛍️ Local vendors</span>
          <span>🕊️ Freebird Fund</span>
        </div>

        <div className="auth-tabs">
          <button className={mode === "email" ? "active" : ""} onClick={() => resetMode("email")}>Email</button>
          <button className={mode === "phone" ? "active" : ""} onClick={() => resetMode("phone")}>Phone</button>
        </div>

        {mode === "email" ? (
          <form onSubmit={signInWithEmail} className="auth-form">
            <label>Email address</label>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="you@example.com"
              required
            />
            <button className="primary-button" disabled={loading}>{loading ? "Sending…" : "Send sign-in link"}</button>
          </form>
        ) : !phoneCodeSent ? (
          <form onSubmit={signInWithPhone} className="auth-form">
            <label>Phone number</label>
            <input
              type="tel"
              value={phone}
              onChange={(event) => setPhone(event.target.value)}
              placeholder="+18135550101"
              required
            />
            <button className="primary-button" disabled={loading}>{loading ? "Sending…" : "Send code"}</button>
          </form>
        ) : (
          <form onSubmit={verifyPhoneCode} className="auth-form">
            <label>Enter your SMS code</label>
            <input
              inputMode="numeric"
              value={otp}
              onChange={(event) => setOtp(event.target.value)}
              placeholder="123456"
              required
            />
            <button className="primary-button" disabled={loading}>{loading ? "Verifying…" : "Verify and continue"}</button>
            <button type="button" className="text-button center" onClick={() => setPhoneCodeSent(false)}>Send a new code</button>
          </form>
        )}

        <div className="divider"><span>or continue with</span></div>

        <div className="provider-row">
          <button onClick={() => signInWithProvider("google")} disabled={loading}>Google</button>
          <button onClick={() => signInWithProvider("apple")} disabled={loading}>Apple</button>
          <button onClick={() => signInWithProvider("facebook")} disabled={loading}>Facebook</button>
        </div>

        {message && <div className="success-banner">{message}</div>}
        {error && <div className="error-banner">{error}</div>}

        <p className="fine-print">
          By joining, you are helping HEHA build a trusted local health discovery network. Marketing messages require separate consent.
        </p>
      </section>
    </main>
  );
}
