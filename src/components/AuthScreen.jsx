import { useState, useEffect } from "react";
import { supabase } from "../lib/supabase";

export default function AuthScreen() {
  const [mode, setMode] = useState("email");
  const [value, setValue] = useState("");
  const [sent, setSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [authError, setAuthError] = useState("");
  const [resendCooldown, setResendCooldown] = useState(0);

  useEffect(() => {
    const hash = window.location.hash;
    if (hash.includes("error=")) {
      const params = new URLSearchParams(hash.substring(1));
      const code = params.get("error_code");
      const desc = params.get("error_description")?.replace(/\+/g, " ");
      setAuthError(code === "otp_expired" ? "Your sign-in link has expired. Please request a new one." : desc || "Sign-in failed. Please try again.");
      window.history.replaceState(null, "", window.location.pathname);
    }
  }, []);

  useEffect(() => {
    if (resendCooldown > 0) { const t = setTimeout(() => setResendCooldown(c => c - 1), 1000); return () => clearTimeout(t); }
  }, [resendCooldown]);

  const send = async () => {
    setError("");
    if (!value.trim()) { setError(`Please enter your ${mode === "email" ? "email" : "phone number"}.`); return; }
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
      setSent(true); setResendCooldown(60);
    } catch (e) {
      if (e.message?.includes("rate limit") || e.message?.includes("after")) { setError("Please wait before requesting another."); setResendCooldown(45); }
      else setError(e.message || "Something went wrong.");
    } finally { setLoading(false); }
  };

  const verify = async () => {
    setError("");
    if (!otp.trim()) { setError("Please enter the code."); return; }
    setLoading(true);
    try {
      const phone = value.trim().startsWith("+") ? value.trim() : `+1${value.trim().replace(/\D/g, "")}`;
      const { error: e } = await supabase.auth.verifyOtp({ phone, token: otp.trim(), type: "sms" });
      if (e) throw e;
    } catch (e) {
      if (e.message?.includes("expired") || e.message?.includes("invalid")) { setError("Code expired or invalid. Request a new one."); setSent(false); setOtp(""); }
      else setError(e.message || "Verification failed.");
    } finally { setLoading(false); }
  };

  const IS = (err) => ({ width: "100%", padding: "13px 14px", borderRadius: 10, boxSizing: "border-box", border: `1.5px solid ${err ? "#e85d2b" : "#e0dbd4"}`, fontSize: 16, outline: "none", marginBottom: 8, background: "#faf9f7", fontFamily: "system-ui" });

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#f5f0eb", padding: "24px", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ marginBottom: 32, textAlign: "center" }}>
        <div style={{ fontSize: 32, fontWeight: 800, letterSpacing: "-1px", color: "#1a1a1a" }}>HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe</div>
        <div style={{ fontSize: 13, color: "#888", marginTop: 4 }}>Discover local Tampa Bay</div>
      </div>
      <div style={{ background: "#fff", borderRadius: 20, padding: "28px 24px", width: "100%", maxWidth: 380, boxShadow: "0 4px 24px rgba(0,0,0,0.08)" }}>
        {authError && <div style={{ background: "#fff8f0", border: "1px solid #f5c5a0", borderRadius: 10, padding: "12px 14px", marginBottom: 20, fontSize: 13, color: "#8b4513", lineHeight: 1.5 }}><strong>⏱ Link expired</strong><br />{authError}</div>}
        <div style={{ display: "flex", gap: 8, marginBottom: 20, background: "#f0ede8", borderRadius: 12, padding: 4 }}>
          {["email", "phone"].map((m) => (
            <button key={m} onClick={() => { setMode(m); setError(""); setValue(""); setSent(false); setOtp(""); }}
              style={{ flex: 1, padding: "9px 0", borderRadius: 9, border: "none", cursor: "pointer", fontSize: 13, fontWeight: 600, background: mode === m ? "#fff" : "transparent", color: mode === m ? "#1a1a1a" : "#888", boxShadow: mode === m ? "0 1px 4px rgba(0,0,0,0.1)" : "none", transition: "all 0.15s" }}>
              {m === "email" ? "📧 Email" : "📱 Phone"}
            </button>
          ))}
        </div>

        {mode === "email" && !sent && (<>
          <h2 style={{ margin: "0 0 6px", fontSize: 20, fontWeight: 700 }}>{authError ? "Request a new link" : "Sign in or sign up"}</h2>
          <p style={{ margin: "0 0 16px", fontSize: 14, color: "#666" }}>We'll email you a magic link — no password needed.</p>
          <input type="email" placeholder="you@example.com" value={value} onChange={(e) => { setValue(e.target.value); setError(""); }} onKeyDown={(e) => e.key === "Enter" && send()} style={IS(!!error)} />
          {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 6 }}>{error}</div>}
          <button onClick={send} disabled={loading} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", marginTop: 4, background: loading ? "#ccc" : "#1a1a1a", color: "#fff", fontSize: 15, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer" }}>{loading ? "Sending…" : "Send magic link →"}</button>
        </>)}

        {mode === "email" && sent && (<>
          <div style={{ textAlign: "center", marginBottom: 20 }}>
            <div style={{ fontSize: 48, marginBottom: 12 }}>📬</div>
            <h2 style={{ margin: "0 0 8px", fontSize: 20, fontWeight: 700 }}>Check your email</h2>
            <p style={{ margin: 0, fontSize: 14, color: "#666", lineHeight: 1.6 }}>We sent a magic link to <strong>{value}</strong>.<br />Click it to sign in — expires in 1 hour.</p>
          </div>
          <div style={{ background: "#f5f0eb", borderRadius: 10, padding: "12px 14px", fontSize: 13, color: "#888", marginBottom: 16, lineHeight: 1.5 }}>💡 Can't find it? Check your spam folder.</div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <button onClick={() => { setSent(false); setError(""); }} style={{ background: "none", border: "none", fontSize: 13, color: "#888", cursor: "pointer" }}>← Change email</button>
            <button onClick={send} disabled={resendCooldown > 0 || loading} style={{ background: "none", border: "none", fontSize: 13, color: resendCooldown > 0 ? "#aaa" : "#e85d2b", cursor: resendCooldown > 0 ? "not-allowed" : "pointer", fontWeight: 600 }}>{resendCooldown > 0 ? `Resend in ${resendCooldown}s` : "Resend link"}</button>
          </div>
        </>)}

        {mode === "phone" && !sent && (<>
          <h2 style={{ margin: "0 0 6px", fontSize: 20, fontWeight: 700 }}>Sign in with phone</h2>
          <p style={{ margin: "0 0 16px", fontSize: 14, color: "#666" }}>We'll text you a 6-digit code.</p>
          <input type="tel" placeholder="+1 (813) 000-0000" value={value} onChange={(e) => { setValue(e.target.value); setError(""); }} onKeyDown={(e) => e.key === "Enter" && send()} style={IS(!!error)} />
          {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 6 }}>{error}</div>}
          <button onClick={send} disabled={loading} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", marginTop: 4, background: loading ? "#ccc" : "#1a1a1a", color: "#fff", fontSize: 15, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer" }}>{loading ? "Sending…" : "Send 6-digit code →"}</button>
        </>)}

        {mode === "phone" && sent && (<>
          <h2 style={{ margin: "0 0 6px", fontSize: 20, fontWeight: 700 }}>Enter your code</h2>
          <p style={{ margin: "0 0 16px", fontSize: 14, color: "#666" }}>Sent to <strong>{value}</strong></p>
          <input type="text" inputMode="numeric" placeholder="000000" value={otp} onChange={(e) => { setOtp(e.target.value.replace(/\D/g, "").slice(0, 6)); setError(""); }} onKeyDown={(e) => e.key === "Enter" && verify()} style={{ ...IS(!!error), fontSize: 28, fontWeight: 700, letterSpacing: 10, textAlign: "center" }} />
          {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 6 }}>{error}</div>}
          <button onClick={verify} disabled={loading || otp.length < 6} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", marginTop: 4, background: (loading || otp.length < 6) ? "#ccc" : "#1a1a1a", color: "#fff", fontSize: 15, fontWeight: 700, cursor: (loading || otp.length < 6) ? "not-allowed" : "pointer" }}>{loading ? "Verifying…" : "Verify code →"}</button>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 12 }}>
            <button onClick={() => { setSent(false); setOtp(""); setError(""); }} style={{ background: "none", border: "none", fontSize: 13, color: "#888", cursor: "pointer" }}>← Change number</button>
            <button onClick={send} disabled={resendCooldown > 0 || loading} style={{ background: "none", border: "none", fontSize: 13, color: resendCooldown > 0 ? "#aaa" : "#e85d2b", cursor: resendCooldown > 0 ? "not-allowed" : "pointer", fontWeight: 600 }}>{resendCooldown > 0 ? `Resend in ${resendCooldown}s` : "Resend code"}</button>
          </div>
        </>)}
      </div>
      <div style={{ marginTop: 20, fontSize: 12, color: "#aaa", textAlign: "center" }}>By signing in, you agree to our Terms & Privacy Policy.</div>
    </div>
  );
}
