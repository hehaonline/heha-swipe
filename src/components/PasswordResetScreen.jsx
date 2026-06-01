import { useState } from "react";
import { supabase } from "../lib/supabase";

export default function PasswordResetScreen({ onComplete }) {
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);

  const updatePassword = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      if (password.length < 8) throw new Error("Please use at least 8 characters.");
      if (password !== confirmPassword) throw new Error("The two passwords do not match.");

      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;

      setMessage("Your password was updated. You can continue to HEHA Swipe now.");
      window.setTimeout(() => onComplete?.(), 900);
    } catch (resetError) {
      setError(resetError.message || "Could not update your password.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="auth-screen">
      <section className="auth-card">
        <div className="auth-hero">
          <div className="brand-mark large">✦</div>
          <p className="eyebrow">Password recovery</p>
          <h1>Create a new HEHA Swipe password.</h1>
          <p>Choose a new password for your account. This keeps your saved businesses and profile secure.</p>
        </div>

        <form onSubmit={updatePassword} className="auth-form">
          <label>New password</label>
          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="Minimum 8 characters"
            minLength="8"
            required
          />

          <label>Confirm new password</label>
          <input
            type="password"
            value={confirmPassword}
            onChange={(event) => setConfirmPassword(event.target.value)}
            placeholder="Repeat your new password"
            minLength="8"
            required
          />

          <button className="primary-button" disabled={loading}>
            {loading ? "Updating…" : "Update password"}
          </button>
        </form>

        {message && <div className="success-banner">{message}</div>}
        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
  );
}
