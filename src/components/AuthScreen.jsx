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
  const [cooldown, setCooldown] = useState(0);

  useEffect(() => {
    const hash = window.location.hash;
    if (hash.includes("error=")) {
      const params = new URLSearchParams(hash.substring(1));
      const code = params.get("error_code");
      const desc = params.get("error_description")?.replace(/\+/g, " ");
      setAuthError(code === "otp_expired" ? "Your sign-in link has expired. Request a new one below." : desc || "Sign-in failed.");
      window.history.replaceState(null, "", window.location.pathname);
    }
  }, []);

  useEffect(() => {
    if (cooldown > 0) { const t = setTimeout(() => setCooldown(c => c - 1), 1000); return () => clearTimeout(t); }
  }, [cooldown]);

  const send = async () => {
    setError("");
    if (!value.trim()) { setError(`Enter your ${mode === "email" ? "email" : "phone number"}.`); return; }
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
      setSent(true); setCooldown(60);
    } catch (e) {
      if (e.message?.includes("rate limit") || e.message?.includes("after")) { setError("Please wait before requesting another."); setCooldown(45); }
      else setError(e.message || "Something went wrong.");
    } finally { setLoading(false); }
  };

  const verify = async () => {
    setError("");
    if (!otp.trim()) { setError("Enter the code."); return; }
    setLoading(true);
    try {
      const phone = value.trim().startsWith("+") ? value.trim() : `+1${value.trim().replace(/\D/g, "")}`;
      const { error: e } = await supabase.auth.verifyOtp({ phone, token: otp.trim(), type: "sms" });
      if (e) throw e;
    } catch (e) {
      if (e.message?.includes("expired") || e.message?.includes("invalid")) { setError("Code expired. Request a new one."); setSent(false); setOtp(""); }
      else setError(e.message || "Verification failed.");
    } finally { setLoading(false); }
  };

  const IS = (err) => ({
    width: "100%", padding: "14px 16px", borderRadius: 14, boxSizing: "border-box",
    border: `2px solid ${err ? "#e85d2b" : "#eee"}`, fontSize: 16, outline: "none",
    marginBottom: 8, background: "#fafafa", transition: "border-color 0.2s"
  });

  return (
    <div style={{ minHeight: "100dvh", display: "flex", flexDirection: "column", background: "#fff" }}>

      {/* Dark hero */}
      <div style={{ background: "linear-gradient(160deg, #111 55%, #2a1a0a)", padding: "60px 28px 44px", position: "relative", overflow: "hidden" }}>
        <div style={{ position: "absolute", top: -60, right: -60, width: 220, height: 220, borderRadius: "50%", background: "rgba(232,93,43,0.15)" }} />
        <div style={{ position: "absolute", bottom: 10, left: -30, width: 140, height: 140, borderRadius: "50%", background: "rgba(232,93,43,0.08)" }} />
        <div style={{ marginBottom: 20, position: "relative" }}>
          <div style={{ display: "inline-flex", alignItems: "center", gap: 6, background: "rgba(232,93,43,0.15)", borderRadius: 10, padding: "5px 12px", marginBottom: 18 }}>
            <span style={{ color: "#e85d2b", fontSize: 12 }}>✦</span>
            <span style={{ fontSize: 10, fontWeight: 700, color: "#e85d2b", letterSpacing: 2, textTransform: "uppercase", fontFamily: "Syne, sans-serif" }}>Tampa Bay</span>
          </div>
          <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, color: "#fff", lineHeight: 1, letterSpacing: "-1.5px" }}>
            <div style={{ fontSize: 44 }}>HEHA</div>
            <div style={{ fontSize: 44 }}><span style={{ color: "#e85d2b" }}>·</span>swipe</div>
          </div>
          <div style={{ fontSize: 15, color: "rgba(255,255,255,0.5)", marginTop: 12, lineHeight: 1.6 }}>
            Discover Tampa Bay's healthiest<br />local businesses
          </div>
        </div>
      </div>

      {/* Auth form */}
      <div style={{ flex: 1, padding: "24px 24px 40px", background: "#fff" }}>
        {authError && (
          <div style={{ background: "#fff4f0", border: "1px solid #ffe0d6", borderRadius: 12, padding: "12px 16px", marginBottom: 20, fontSize: 13, color: "#c0392b", lineHeight: 1.5, display: "flex", gap: 10, alignItems: "flex-start" }}>
            <span>⏱</span><div><strong>Link expired.</strong> {authError}</div>
          </div>
        )}

        {/* Toggle */}
        <div style={{ display: "flex", background: "#f5f5f5", borderRadius: 14, padding: 4, marginBottom: 24 }}>
          {["email", "phone"].map(m => (
            <button key={m} onClick={() => { setMode(m); setError(""); setValue(""); setSent(false); setOtp(""); }}
              style={{ flex: 1, padding: "10px 0", borderRadius: 11, border: "none", cursor: "pointer", fontSize: 13, fontWeight: 600, fontFamily: "Syne, sans-serif", background: mode === m ? "#fff" : "transparent", color: mode === m ? "#111" : "#aaa", boxShadow: mode === m ? "0 2px 8px rgba(0,0,0,0.08)" : "none", transition: "all 0.2s" }}>
              {m === "email" ? "📧  Email" : "📱  Phone"}
            </button>
          ))}
        </div>

        {/* Email → link */}
        {mode === "email" && !sent && (<>
          <label style={{ fontSize: 13, fontWeight: 600, color: "#555", display: "block", marginBottom: 8 }}>Email address</label>
          <input type="email" placeholder="you@example.com" value={value} onChange={e => { setValue(e.target.value); setError(""); }} onKeyDown={e => e.key === "Enter" && send()} style={IS(!!error)} autoFocus />
          {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 8 }}>{error}</div>}
          <OrangeBtn onClick={send} loading={loading}>{loading ? "Sending…" : "Send magic link →"}</OrangeBtn>
          <div style={{ fontSize: 12, color: "#bbb", textAlign: "center", marginTop: 12 }}>No password needed. Link expires in 1 hour.</div>
        </>)}

        {mode === "email" && sent && (<>
          <div style={{ textAlign: "center", padding: "16px 0 20px" }}>
            <div style={{ width: 64, height: 64, borderRadius: 20, background: "#fff4f0", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, margin: "0 auto 16px" }}>📬</div>
            <div style={{ fontFamily: "Syne, sans-serif", fontSize: 22, fontWeight: 800, color: "#111", marginBottom: 8 }}>Check your inbox</div>
            <div style={{ fontSize: 14, color: "#777", lineHeight: 1.7 }}>Magic link sent to<br /><strong style={{ color: "#111" }}>{value}</strong></div>
          </div>
          <div style={{ background: "#f9f9f9", borderRadius: 12, padding: "12px 16px", fontSize: 13, color: "#999", marginBottom: 20, lineHeight: 1.5 }}>
            💡 Can't find it? Check your spam folder.
          </div>
          <div style={{ display: "flex", justifyContent: "space-between" }}>
            <button onClick={() => { setSent(false); setError(""); }} style={{ background: "none", border: "none", fontSize: 13, color: "#aaa", cursor: "pointer" }}>← Change email</button>
            <button onClick={send} disabled={cooldown > 0} style={{ background: "none", border: "none", fontSize: 13, color: cooldown > 0 ? "#ccc" : "#e85d2b", cursor: cooldown > 0 ? "not-allowed" : "pointer", fontWeight: 700 }}>
              {cooldown > 0 ? `Resend in ${cooldown}s` : "Resend link"}
            </button>
          </div>
        </>)}

        {/* Phone → code */}
        {mode === "phone" && !sent && (<>
          <label style={{ fontSize: 13, fontWeight: 600, color: "#555", display: "block", marginBottom: 8 }}>Phone number</label>
          <input type="tel" placeholder="+1 (813) 000-0000" value={value} onChange={e => { setValue(e.target.value); setError(""); }} onKeyDown={e => e.key === "Enter" && send()} style={IS(!!error)} autoFocus />
          {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 8 }}>{error}</div>}
          <OrangeBtn onClick={send} loading={loading}>{loading ? "Sending…" : "Send 6-digit code →"}</OrangeBtn>
          <div style={{ fontSize: 12, color: "#bbb", textAlign: "center", marginTop: 12 }}>US numbers only. Standard SMS rates apply.</div>
        </>)}

        {mode === "phone" && sent && (<>
          <div style={{ fontFamily: "Syne, sans-serif", fontSize: 22, fontWeight: 800, color: "#111", marginBottom: 6 }}>Enter your code</div>
          <div style={{ fontSize: 14, color: "#777", marginBottom: 20 }}>Sent to <strong style={{ color: "#111" }}>{value}</strong></div>
          <input type="text" inputMode="numeric" placeholder="· · · · · ·" value={otp}
            onChange={e => { setOtp(e.target.value.replace(/\D/g, "").slice(0, 6)); setError(""); }}
            onKeyDown={e => e.key === "Enter" && verify()}
            style={{ ...IS(!!error), fontSize: 32, fontWeight: 800, letterSpacing: 12, textAlign: "center" }} autoFocus />
          {error && <div style={{ fontSize: 12, color: "#e85d2b", marginBottom: 8 }}>{error}</div>}
          <OrangeBtn onClick={verify} loading={loading} disabled={otp.length < 6}>{loading ? "Verifying…" : "Verify →"}</OrangeBtn>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 16 }}>
            <button onClick={() => { setSent(false); setOtp(""); }} style={{ background: "none", border: "none", fontSize: 13, color: "#aaa", cursor: "pointer" }}>← Change number</button>
            <button onClick={send} disabled={cooldown > 0} style={{ background: "none", border: "none", fontSize: 13, color: cooldown > 0 ? "#ccc" : "#e85d2b", cursor: cooldown > 0 ? "not-allowed" : "pointer", fontWeight: 700 }}>
              {cooldown > 0 ? `Resend in ${cooldown}s` : "Resend code"}
            </button>
          </div>
        </>)}
      </div>
    </div>
  );
}

function OrangeBtn({ onClick, loading, disabled, children }) {
  const off = loading || disabled;
  return (
    <button onClick={onClick} disabled={off}
      style={{ width: "100%", padding: "15px", borderRadius: 14, border: "none", marginTop: 4,
        background: off ? "#f0f0f0" : "linear-gradient(135deg, #e85d2b, #ff7a47)",
        color: off ? "#bbb" : "#fff", fontSize: 15, fontWeight: 700,
        cursor: off ? "not-allowed" : "pointer",
        boxShadow: off ? "none" : "0 6px 20px rgba(232,93,43,0.35)",
        fontFamily: "Syne, sans-serif", transition: "all 0.2s" }}>
      {children}
    </button>
  );
}
