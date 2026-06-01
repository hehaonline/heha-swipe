import { useState } from "react";
import { supabase } from "../lib/supabase";

export default function OnboardingScreen({ user, onComplete }) {
  const [step, setStep] = useState("role");
  const [role, setRole] = useState(null);
  const [loading, setLoading] = useState(false);
  const [igConfirmed, setIgConfirmed] = useState(false);

  const saveRole = async (r) => {
    setLoading(true);
    setRole(r);
    try {
      await supabase.from("profiles").upsert({
        id: user.id, email: user.email || null, phone: user.phone || null,
        subscription_type: `pending_${r}`,
      });
    } catch (_) {}
    setLoading(false);
    setStep("join");
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
    <div style={wrap}>
      <Logo />
      <div style={{ width: "100%", maxWidth: 360 }}>
        <h2 style={h2}>Welcome! How are you joining?</h2>
        <p style={sub}>HEHA connects Tampa Bay's healthy community.</p>
        <div style={{ display: "flex", flexDirection: "column", gap: 16, marginTop: 24 }}>
          <button onClick={() => saveRole("customer")} disabled={loading}
            style={{ ...roleCard, background: "#fff", border: "2px solid #e8e3dc" }}>
            <div style={{ fontSize: 36, marginBottom: 10 }}>🛍️</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "#1a1a1a", marginBottom: 4 }}>I'm a Customer</div>
            <div style={{ fontSize: 14, color: "#888", lineHeight: 1.5 }}>Discover Tampa Bay's best healthy restaurants, coaches, and wellness businesses.</div>
          </button>
          <button onClick={() => saveRole("partner")} disabled={loading}
            style={{ ...roleCard, background: "#1a1a1a", border: "2px solid #1a1a1a" }}>
            <div style={{ fontSize: 36, marginBottom: 10 }}>🏪</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "#fff", marginBottom: 4 }}>
              {loading && role === "partner" ? "Setting up…" : "I'm a Business / Partner"}
            </div>
            <div style={{ fontSize: 14, color: "rgba(255,255,255,0.7)", lineHeight: 1.5 }}>List your healthy business and get discovered by Tampa locals.</div>
          </button>
        </div>
      </div>
    </div>
  );

  const isCustomer = role === "customer";
  return (
    <div style={wrap}>
      <Logo />
      <div style={{ width: "100%", maxWidth: 360 }}>
        <h2 style={h2}>{isCustomer ? "Join the community 🌿" : "Stay connected 🌿"}</h2>
        <p style={sub}>
          {isCustomer
            ? "Follow us on Instagram to unlock full access to HEHA Swipe."
            : "Follow us on Instagram to stay connected and list your business."}
        </p>

        <div style={{ background: "#fff", borderRadius: 16, padding: "20px", marginTop: 20, border: "2px solid #e85d2b" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 12 }}>
            <span style={{ fontSize: 32 }}>📸</span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 16, color: "#1a1a1a" }}>Follow on Instagram</div>
              <div style={{ fontSize: 12, color: "#e85d2b", fontWeight: 600 }}>Free — takes 10 seconds</div>
            </div>
          </div>
          <div style={{ fontSize: 14, color: "#666", lineHeight: 1.6, marginBottom: 16 }}>
            {isCustomer
              ? "Follow @heha.online to unlock the full HEHA Swipe experience and stay updated on new local businesses."
              : "Follow @heha.online to join our partner community, get featured in stories, and stay in the loop with HEHA updates."}
          </div>

          <a href="https://instagram.com/heha.online" target="_blank" rel="noreferrer"
            style={{ display: "block", textAlign: "center", padding: "13px", background: "linear-gradient(135deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888)", color: "#fff", borderRadius: 12, fontWeight: 700, fontSize: 15, textDecoration: "none", marginBottom: 14 }}>
            Open @heha.online on Instagram ↗
          </a>

          <label style={{ display: "flex", alignItems: "center", gap: 12, cursor: "pointer", fontSize: 14, color: "#555", fontWeight: 500 }}>
            <input type="checkbox" checked={igConfirmed} onChange={(e) => setIgConfirmed(e.target.checked)}
              style={{ width: 20, height: 20, cursor: "pointer", accentColor: "#e85d2b" }} />
            I've followed @heha.online ✓
          </label>
        </div>

        <button onClick={complete} disabled={!igConfirmed || loading}
          style={{
            width: "100%", padding: "15px", borderRadius: 14, border: "none", marginTop: 20,
            background: igConfirmed && !loading ? "#1a1a1a" : "#ccc",
            color: "#fff", fontSize: 16, fontWeight: 700,
            cursor: igConfirmed && !loading ? "pointer" : "not-allowed",
            transition: "background 0.2s"
          }}>
          {loading ? "Setting up your account…" : isCustomer ? "Start Exploring →" : "Continue to List My Business →"}
        </button>

        <button onClick={() => setStep("role")}
          style={{ background: "none", border: "none", width: "100%", marginTop: 12, fontSize: 13, color: "#aaa", cursor: "pointer" }}>
          ← Back
        </button>

        <div style={{ marginTop: 20, padding: "14px", background: "#f5f0eb", borderRadius: 12, fontSize: 13, color: "#888", textAlign: "center", lineHeight: 1.6 }}>
          💳 Want to support HEHA with a monthly contribution?<br />
          <span style={{ color: "#2a7c3f", fontWeight: 600 }}>Coming soon — from $1/month</span>
        </div>
      </div>
    </div>
  );
}

const wrap = { minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#f5f0eb", padding: "28px 20px", fontFamily: "system-ui, sans-serif" };
const h2 = { fontSize: 22, fontWeight: 800, color: "#1a1a1a", margin: "0 0 6px" };
const sub = { fontSize: 14, color: "#888", margin: 0, lineHeight: 1.6 };
const roleCard = { borderRadius: 18, padding: "22px 20px", cursor: "pointer", textAlign: "left", boxShadow: "0 2px 12px rgba(0,0,0,0.07)", width: "100%" };

function Logo() {
  return (
    <div style={{ textAlign: "center", marginBottom: 28 }}>
      <div style={{ fontSize: 26, fontWeight: 800, letterSpacing: "-0.5px", color: "#1a1a1a" }}>
        HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe
      </div>
    </div>
  );
}
