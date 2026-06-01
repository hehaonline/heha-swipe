import { useState } from "react";
import { supabase } from "../lib/supabase";

export default function OnboardingScreen({ user, onComplete }) {
  const [step, setStep] = useState("role");
  const [role, setRole] = useState(null);
  const [loading, setLoading] = useState(false);
  const [igConfirmed, setIgConfirmed] = useState(false);

  const saveRole = async (r) => {
    setLoading(true); setRole(r);
    try {
      await supabase.from("profiles").upsert({
        id: user.id, email: user.email || null, phone: user.phone || null,
        subscription_type: `pending_${r}`
      });
    } catch (_) {}
    setLoading(false); setStep("join");
  };

  const complete = async () => {
    setLoading(true);
    try {
      await supabase.from("profiles").upsert({
        id: user.id,
        subscription_type: role === "partner" ? "partner_instagram" : "instagram",
        subscription_active: true, subscription_amount: 0,
      });
      await supabase.from("customer_profiles").upsert({ user_id: user.id });
      onComplete(role);
    } catch (e) { console.error(e); onComplete(role); }
    finally { setLoading(false); }
  };

  if (step === "role") return (
    <div style={{ minHeight: "100dvh", display: "flex", flexDirection: "column", background: "#fff", fontFamily: "DM Sans, sans-serif" }}>
      <div style={{ background: "linear-gradient(160deg, #111 55%, #2a1a0a)", padding: "56px 28px 44px", position: "relative", overflow: "hidden", flexShrink: 0 }}>
        <div style={{ position: "absolute", top: -60, right: -60, width: 220, height: 220, borderRadius: "50%", background: "rgba(232,93,43,0.15)" }} />
        <div style={{ position: "absolute", bottom: -20, left: -20, width: 150, height: 150, borderRadius: "50%", background: "rgba(232,93,43,0.08)" }} />
        <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, color: "#fff", lineHeight: 1.1, letterSpacing: "-1px", position: "relative" }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: "#e85d2b", letterSpacing: 2, textTransform: "uppercase", marginBottom: 14, display: "flex", alignItems: "center", gap: 6 }}>
            <span>✦</span> Welcome to HEHA Swipe
          </div>
          <div style={{ fontSize: 34 }}>Tampa Bay's</div>
          <div style={{ fontSize: 34 }}>healthy business</div>
          <div style={{ fontSize: 34 }}>discovery app <span style={{ color: "#e85d2b" }}>✦</span></div>
        </div>
        <div style={{ fontSize: 14, color: "rgba(255,255,255,0.5)", marginTop: 14, lineHeight: 1.6, position: "relative" }}>
          Restaurants · Coaches · Vendors · Wellness
        </div>
      </div>

      <div style={{ flex: 1, padding: "28px 20px 40px" }}>
        <div style={{ fontFamily: "Syne, sans-serif", fontSize: 20, fontWeight: 800, color: "#111", marginBottom: 6 }}>How are you joining?</div>
        <div style={{ fontSize: 14, color: "#999", marginBottom: 24, lineHeight: 1.5 }}>Choose your path to get started in Tampa Bay's healthy community.</div>

        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <button onClick={() => saveRole("customer")} disabled={loading}
            style={{ background: "#fff", border: "2px solid #f0f0f0", borderRadius: 20, padding: "20px", cursor: loading ? "wait" : "pointer", textAlign: "left", width: "100%", transition: "all 0.15s" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
              <div style={{ width: 52, height: 52, borderRadius: 16, background: "#fff4f0", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 24, flexShrink: 0 }}>🛍️</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: "Syne, sans-serif", fontSize: 16, fontWeight: 800, color: "#111", marginBottom: 3 }}>I'm a Customer</div>
                <div style={{ fontSize: 13, color: "#999", lineHeight: 1.5 }}>Discover Tampa Bay's best healthy restaurants, coaches, vendors & wellness businesses.</div>
              </div>
              <span style={{ color: "#e85d2b", fontSize: 22, flexShrink: 0 }}>→</span>
            </div>
          </button>

          <button onClick={() => saveRole("partner")} disabled={loading}
            style={{ background: "linear-gradient(135deg, #111, #2a1a0a)", border: "2px solid #111", borderRadius: 20, padding: "20px", cursor: loading ? "wait" : "pointer", textAlign: "left", width: "100%", transition: "all 0.15s" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
              <div style={{ width: 52, height: 52, borderRadius: 16, background: "rgba(232,93,43,0.2)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 24, flexShrink: 0 }}>🏪</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: "Syne, sans-serif", fontSize: 16, fontWeight: 800, color: "#fff", marginBottom: 3 }}>
                  {loading && role === "partner" ? "Setting up…" : "I'm a Business / Partner"}
                </div>
                <div style={{ fontSize: 13, color: "rgba(255,255,255,0.55)", lineHeight: 1.5 }}>List your healthy business and get discovered by Tampa locals.</div>
              </div>
              <span style={{ color: "#e85d2b", fontSize: 22, flexShrink: 0 }}>→</span>
            </div>
          </button>
        </div>
      </div>
    </div>
  );

  const isCustomer = role === "customer";
  return (
    <div style={{ minHeight: "100dvh", display: "flex", flexDirection: "column", background: "#fff", fontFamily: "DM Sans, sans-serif" }}>
      <div style={{ background: "linear-gradient(135deg, #e85d2b, #ff7a47)", padding: "48px 28px 40px", position: "relative", overflow: "hidden", flexShrink: 0 }}>
        <div style={{ position: "absolute", top: -40, right: -40, width: 160, height: 160, borderRadius: "50%", background: "rgba(255,255,255,0.12)" }} />
        <div style={{ position: "absolute", bottom: -30, left: 10, width: 100, height: 100, borderRadius: "50%", background: "rgba(0,0,0,0.08)" }} />
        <button onClick={() => setStep("role")} style={{ background: "rgba(255,255,255,0.2)", border: "none", borderRadius: 20, padding: "7px 14px", fontSize: 13, color: "#fff", cursor: "pointer", marginBottom: 20, fontFamily: "DM Sans, sans-serif", fontWeight: 600 }}>
          ← Back
        </button>
        <div style={{ fontFamily: "Syne, sans-serif", fontSize: 30, fontWeight: 800, color: "#fff", lineHeight: 1.2, position: "relative" }}>
          {isCustomer ? "Join the\ncommunity 🌿" : "Stay\nconnected 🌿"}
        </div>
        <div style={{ fontSize: 14, color: "rgba(255,255,255,0.8)", marginTop: 10, lineHeight: 1.6, position: "relative" }}>
          {isCustomer ? "One quick step to unlock HEHA Swipe." : "One quick step to list your business."}
        </div>
      </div>

      <div style={{ flex: 1, padding: "24px 20px 40px" }}>
        <div style={{ background: "#fff", borderRadius: 20, border: "2px solid #e85d2b", padding: "22px", marginBottom: 20, boxShadow: "0 4px 20px rgba(232,93,43,0.1)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 14 }}>
            <div style={{ width: 50, height: 50, borderRadius: 14, background: "linear-gradient(135deg, #f09433, #e6683c, #dc2743, #bc1888)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22, flexShrink: 0 }}>📸</div>
            <div>
              <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, fontSize: 16, color: "#111" }}>Follow @heha.online</div>
              <div style={{ fontSize: 12, color: "#e85d2b", fontWeight: 700 }}>Free — takes 10 seconds</div>
            </div>
          </div>
          <div style={{ fontSize: 14, color: "#666", lineHeight: 1.7, marginBottom: 16 }}>
            {isCustomer
              ? "Follow us on Instagram to unlock HEHA Swipe and stay updated on the best new local businesses."
              : "Follow us to join our partner network, get featured in our stories, and stay connected with the HEHA community."}
          </div>
          <a href="https://instagram.com/heha.online" target="_blank" rel="noreferrer"
            style={{ display: "block", textAlign: "center", padding: "14px", background: "linear-gradient(135deg, #f09433, #e6683c, #dc2743, #cc2366, #bc1888)", color: "#fff", borderRadius: 14, fontFamily: "Syne, sans-serif", fontWeight: 700, fontSize: 14, textDecoration: "none", marginBottom: 16 }}>
            Open @heha.online on Instagram ↗
          </a>
          <div onClick={() => setIgConfirmed(c => !c)}
            style={{ display: "flex", alignItems: "center", gap: 12, cursor: "pointer", padding: "4px 0" }}>
            <div style={{ width: 26, height: 26, borderRadius: 8, border: `2px solid ${igConfirmed ? "#e85d2b" : "#ddd"}`, background: igConfirmed ? "#e85d2b" : "#fff", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, transition: "all 0.15s" }}>
              {igConfirmed && <span style={{ color: "#fff", fontSize: 15, fontWeight: 700 }}>✓</span>}
            </div>
            <span style={{ fontSize: 14, color: "#555", fontWeight: 500 }}>I've followed @heha.online ✓</span>
          </div>
        </div>

        <button onClick={complete} disabled={!igConfirmed || loading}
          style={{ width: "100%", padding: "16px", borderRadius: 16, border: "none",
            background: igConfirmed && !loading ? "linear-gradient(135deg, #e85d2b, #ff7a47)" : "#f0f0f0",
            color: igConfirmed && !loading ? "#fff" : "#bbb",
            fontSize: 16, fontWeight: 700, cursor: igConfirmed && !loading ? "pointer" : "not-allowed",
            boxShadow: igConfirmed && !loading ? "0 6px 20px rgba(232,93,43,0.35)" : "none",
            fontFamily: "Syne, sans-serif", transition: "all 0.2s" }}>
          {loading ? "Setting up your account…" : isCustomer ? "Start Exploring Tampa Bay →" : "Continue to List My Business →"}
        </button>

        <div style={{ marginTop: 20, background: "#f9f9f9", borderRadius: 14, padding: "14px 18px", fontSize: 13, color: "#aaa", textAlign: "center", lineHeight: 1.6 }}>
          💳 <strong style={{ color: "#e85d2b" }}>Monthly contributions</strong> coming soon — support local businesses from $1/month
        </div>
      </div>
    </div>
  );
}
