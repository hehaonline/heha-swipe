import { useState, useEffect } from "react";
import { supabase } from "../lib/supabase";

export default function AuthScreen() {
  const [mode, setMode] = useState("email");
  const [value, setValue] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [authError, setAuthError] = useState("");
  const [resendCooldown, setResendCooldown] = useState(0);

  useEffect(() => {
    const hash = window.location.hash;
    if (hash.includes("error=")) {
      const params = new URLSearchParams(hash.substring(1));
      const errorCode = params.get("error_code");
      const errorDesc = params.get("error_description")?.replace(/\+/g, " ");
      if (errorCode === "otp_expired") {
        setAuthError("Your sign-in link has expired. Links are single-use and valid for 1 hour. Please request a new one.");
      } else {
        setAuthError(errorDesc || "Sign-in failed. Please try again.");
      }
      window.history.replaceState(null, "", window.location.pathname);
    }
  }, []);

  useEffect(() => {
    if (resendCooldown > 0) {
      const t = setTimeout(() => setResendCooldown((c) => c - 1), 1000);
      return () => clearTimeout(t);
    }
  }, [resendCooldown]);

  const sendOtp = async (isResend = false) => {
    setError("");
    if (!value.trim()) { setError(mode === "email" ? "Please enter your email." : "Please enter your phone number."); return; }
    setLoading(true);
    try {
      if (mode === "email") {
        const { error: e } = await supabase.auth.signInWithOtp({ email: value.trim(), options: { shouldCreateUser: true } });
        if (e) throw e;
      } else {
        const phone = value.trim().startsWith("+") ? value.trim() : `+1${value.trim().replace(/\D/g, "")}`;
        const { error: e } = await supabase.auth.signInWithOtp({ phone });
        if (e) throw e;
      }
      setOtpSent(true);
      setResendCooldown(60);
    } catch (e) {
      if (e.message?.includes("rate limit") || e.message?.includes("after")) {
        setError("Please wait a moment before requesting another code.");
        setResendCooldown(45);
      } else {
        setError(e.message || "Something went wrong. Please try again.");
      }
    } finally {
      setLoading(false);
    }
  };

  const verifyOtp = async () => {
    setError("");
    if (!otp.trim()) { setError("Please enter the code."); return; }
    setLoading(true);
    try {
      let result;
      if (mode === "email") {
        result = await supabase.auth.verifyOtp({ email: value.trim(), token: otp.trim(), type: "magiclink" });
      } else {
        const phone = value.trim().startsWith("+") ? value.trim() : `+1${value.trim().replace(/\D/g, "")}`;
        result = await supabase.auth.verifyOtp({ phone, token: otp.trim(), type: "sms" });
      }
      if (result.error) throw result.error;
    } catch (e) {
      if (e.message?.includes("expired") || e.message?.includes("invalid")) {
        setError("Code is invalid or expired. Please request a new one.");
        setOtpSent(false); setOtp("");
      } else {
        setError(e.message || "Verification failed. Please try again.");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#f5f0eb", padding: "24px", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ marginBottom: 32, textAlign: "center" }}>
        <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: "-0.5px", color: "#1a1a1a" }}>HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe</div>
        <div style={{ fontSize: 13, color: "#888", marginTop: 4 }}>Discover local Tampa Bay</div>
      </div>
      <div style={{ background: "#fff", borderRadius: 16, padding: "28px 24px", width: "100%", maxWidth: 360, boxShadow: "0 2px 20px rgba(0,0,0,0.08)" }}>
        {authError && (
          <div style={{ background: "#fff8f0", border: "1px solid #f5c5a0", borderRadius: 10, padding: "12px 14px", marginBottom: 20, fontSize: 13, color: "#8b4513", lineHeight: 1.5 }}>
            <div style={{ fontWeight: 600, marginBottom: 4 }}>⏱ Link expired</div>
            {authError}
          </div>
        )}
        {!otpSent ? (
          <>
            <h2 style={{ margin: "0 0 6px", fontSize: 20, fontWeight: 700, color: "#1a1a1a" }}>{authError ? "Request a new link" : "Sign in or sign up"}</h2>
            <p style={{ margin: "0 0 20px", fontSize: 14, color: "#666" }}>{mode === "email" ? "We'll send a magic link to your email." : "We'll send a 6-digit code to your phone."}</p>
            <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
              {["email", "phone"].map((m) => (
                <button key={m} onClick={() => { setMode(m); setError(""); setValue(""); }}
                  style={{ flex: 1, padding: "8px 0", borderRadius: 8, border: "none", cursor: "pointer", fontSize: 13, fontWeight: 600, background: mode === m ? "#1a1a1a" : "#f0ede8", color: mode === m ? "#fff" : "#555" }}>
                  {m === "email" ? "📧 Email" : "📱 Phone"}
                </button>
              ))}
            </div>
            <input type={mode === "email" ? "email" : "tel"} placeholder={mode === "email" ? "you@example.com" : "+1 (813) 000-0000"} value={value}
              onChange={(e) => { setValue(e.target.value); setError(""); }}
              onKeyDown={(e) => e.key === "Enter" && sendOtp()}
              style={{ width: "100%", padding: "12px 14px", borderRadius: 10, boxSizing: "border-box", border: error ? "1.5px solid #e85d2b" : "1.5px solid #e0dbd4", fontSize: 15, outline: "none", marginBottom: 8, background: "#faf9f7" }} />
            {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 8 }}>{error}</div>}
            <button onClick={() => sendOtp()} disabled={loading}
              style={{ width: "100%", padding: "13px 0", borderRadius: 10, border: "none", background: loading ? "#ccc" : "#1a1a1a", color: "#fff", fontSize: 15, fontWeight: 600, cursor: loading ? "not-allowed" : "pointer" }}>
              {loading ? "Sending…" : mode === "email" ? "Send magic link" : "Send code"}
            </button>
          </>
        ) : (
          <>
            <h2 style={{ margin: "0 0 6px", fontSize: 20, fontWeight: 700, color: "#1a1a1a" }}>{mode === "email" ? "Check your email" : "Enter your code"}</h2>
            <p style={{ margin: "0 0 20px", fontSize: 14, color: "#666" }}>Sent to <strong>{value}</strong>. {mode === "email" ? "Click the link — or enter the OTP code below." : "Enter the 6-digit code below."}</p>
            <input type="text" inputMode="numeric" placeholder="000000" value={otp}
              onChange={(e) => { setOtp(e.target.value.replace(/\D/g, "").slice(0, 6)); setError(""); }}
              onKeyDown={(e) => e.key === "Enter" && verifyOtp()}
              style={{ width: "100%", padding: "12px 14px", borderRadius: 10, boxSizing: "border-box", border: error ? "1.5px solid #e85d2b" : "1.5px solid #e0dbd4", fontSize: 22, fontWeight: 700, letterSpacing: 6, textAlign: "center", outline: "none", marginBottom: 8, background: "#faf9f7" }} />
            {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 8 }}>{error}</div>}
            <button onClick={verifyOtp} disabled={loading || otp.length < 6}
              style={{ width: "100%", padding: "13px 0", borderRadius: 10, border: "none", background: (loading || otp.length < 6) ? "#ccc" : "#1a1a1a", color: "#fff", fontSize: 15, fontWeight: 600, cursor: (loading || otp.length < 6) ? "not-allowed" : "pointer", marginBottom: 12 }}>
              {loading ? "Verifying…" : "Verify code"}
            </button>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <button onClick={() => { setOtpSent(false); setOtp(""); setError(""); }}
                style={{ background: "none", border: "none", fontSize: 13, color: "#888", cursor: "pointer" }}>← Change {mode}</button>
              <button onClick={() => sendOtp(true)} disabled={resendCooldown > 0 || loading}
                style={{ background: "none", border: "none", fontSize: 13, color: resendCooldown > 0 ? "#aaa" : "#e85d2b", cursor: resendCooldown > 0 ? "not-allowed" : "pointer", fontWeight: 600 }}>
                {resendCooldown > 0 ? `Resend in ${resendCooldown}s` : "Resend code"}
              </button>
            </div>
          </>
        )}
      </div>
      <div style={{ marginTop: 20, fontSize: 12, color: "#aaa", textAlign: "center" }}>By signing in, you agree to our Terms & Privacy Policy.</div>
    </div>
  );
}
