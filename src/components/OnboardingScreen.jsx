import { useState } from "react";
import { supabase } from "../lib/supabase";

const CONTENT = {
  customer: {
    title: "Join the community 🌿",
    subtitle: "Choose how you'd like to support Tampa Bay's healthy businesses.",
    ig: { title: "Follow on Instagram", body: "Follow @heha.online to unlock full access to the HEHA community.", confirm: "I've followed @heha.online ✓" },
    sub: { title: "Monthly Contribution", body: "95¢ of every dollar goes directly to local HEHA businesses. Pay what you can.", breakdown: (amt) => `💚 $${(amt * 0.95).toFixed(2)} to businesses · 🌿 $${(amt * 0.05).toFixed(2)} keeps HEHA running` },
    cta: "Start Exploring →",
  },
  partner: {
    title: "Support the community 🌿",
    subtitle: "To list your business, choose one way to stay connected with HEHA.",
    ig: { title: "Follow on Instagram", body: "Follow @heha.online — stay in the loop with HEHA news, features, and community updates.", confirm: "I've followed @heha.online ✓" },
    sub: { title: "Community Contribution", body: "Support the platform that brings customers to your door. Cancel anytime.", breakdown: (amt) => `💚 $${(amt * 0.95).toFixed(2)} to the community · 🌿 $${(amt * 0.05).toFixed(2)} keeps HEHA running` },
    cta: "Continue to List My Business →",
  },
};

export default function OnboardingScreen({ user, onComplete }) {
  const [step, setStep] = useState("role");
  const [role, setRole] = useState(null);
  const [joinMethod, setJoinMethod] = useState(null);
  const [subAmount, setSubAmount] = useState(5);
  const [loading, setLoading] = useState(false);
  const [igConfirmed, setIgConfirmed] = useState(false);
  const [stripeLoading, setStripeLoading] = useState(false);
  const [stripeError, setStripeError] = useState("");

  const content = role ? CONTENT[role] : null;

  const saveRoleAndGoToJoin = async (r) => {
    setLoading(true);
    setRole(r);
    try {
      await supabase.from("profiles").upsert({
        id: user.id,
        email: user.email || null,
        phone: user.phone || null,
        subscription_type: `pending_${r}`,
      });
    } catch (_) {}
    setLoading(false);
    setStep("join");
  };

  const completeWithIG = async () => {
    setLoading(true);
    try {
      await supabase.from("profiles").upsert({
        id: user.id,
        subscription_type: role === "partner" ? "partner_instagram" : "instagram",
        subscription_active: true,
        subscription_amount: 0,
      });
      await supabase.from("customer_profiles").upsert({ user_id: user.id });
      onComplete(role);
    } catch (e) {
      console.error(e);
      onComplete(role);
    } finally {
      setLoading(false);
    }
  };

  const completeWithStripe = async () => {
    setStripeLoading(true);
    setStripeError("");
    try {
      const { data: { session: authSession } } = await supabase.auth.getSession();
      const res = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/create-checkout-session`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${authSession.access_token}` },
          body: JSON.stringify({
            amount_cents: subAmount * 100,
            user_id: user.id,
            email: user.email || null,
            role,
            success_url: `${window.location.origin}/?checkout=success&role=${role}`,
            cancel_url: `${window.location.origin}/?checkout=cancelled`,
          }),
        }
      );
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Payment setup failed");
      window.location.href = data.url;
    } catch (e) {
      setStripeError(e.message);
      setStripeLoading(false);
    }
  };

  const canProceed = (joinMethod === "ig" && igConfirmed) || (joinMethod === "sub" && subAmount >= 1);

  if (step === "role") return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#f5f0eb", padding: "24px", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ marginBottom: 32, textAlign: "center" }}>
        <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: "-0.5px", color: "#1a1a1a" }}>HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe</div>
        <div style={{ fontSize: 14, color: "#888", marginTop: 6 }}>Welcome! How are you joining?</div>
      </div>
      <div style={{ width: "100%", maxWidth: 360, display: "flex", flexDirection: "column", gap: 16 }}>
        <button onClick={() => saveRoleAndGoToJoin("customer")} disabled={loading}
          style={{ background: "#fff", border: "2px solid #e8e3dc", borderRadius: 18, padding: "24px 20px", cursor: loading ? "wait" : "pointer", textAlign: "left", boxShadow: "0 2px 12px rgba(0,0,0,0.06)", width: "100%" }}>
          <div style={{ fontSize: 36, marginBottom: 10 }}>🛍️</div>
          <div style={{ fontSize: 18, fontWeight: 700, color: "#1a1a1a", marginBottom: 4 }}>I'm a Customer</div>
          <div style={{ fontSize: 14, color: "#888", lineHeight: 1.5 }}>Discover Tampa Bay's best healthy restaurants, coaches, and wellness businesses.</div>
        </button>
        <button onClick={() => saveRoleAndGoToJoin("partner")} disabled={loading}
          style={{ background: "#1a1a1a", border: "2px solid #1a1a1a", borderRadius: 18, padding: "24px 20px", cursor: loading ? "wait" : "pointer", textAlign: "left", boxShadow: "0 2px 12px rgba(0,0,0,0.15)", width: "100%" }}>
          <div style={{ fontSize: 36, marginBottom: 10 }}>🏪</div>
          <div style={{ fontSize: 18, fontWeight: 700, color: "#fff", marginBottom: 4 }}>{loading && role === "partner" ? "Setting up…" : "I'm a Business / Partner"}</div>
          <div style={{ fontSize: 14, color: "rgba(255,255,255,0.7)", lineHeight: 1.5 }}>List your healthy business and get discovered by Tampa locals.</div>
        </button>
      </div>
    </div>
  );

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#f5f0eb", padding: "24px", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ marginBottom: 8, textAlign: "center" }}>
        <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: "-0.5px", color: "#1a1a1a" }}>HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe</div>
      </div>
      <div style={{ width: "100%", maxWidth: 360 }}>
        <h2 style={{ fontSize: 22, fontWeight: 800, color: "#1a1a1a", margin: "0 0 6px" }}>{content.title}</h2>
        <p style={{ fontSize: 14, color: "#888", margin: "0 0 24px", lineHeight: 1.6 }}>{content.subtitle}</p>
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div onClick={() => { setJoinMethod("ig"); setStripeError(""); }}
            style={{ background: joinMethod === "ig" ? "#fff8f0" : "#fff", border: `2px solid ${joinMethod === "ig" ? "#e85d2b" : "#e8e3dc"}`, borderRadius: 16, padding: "18px", cursor: "pointer" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 8 }}>
              <span style={{ fontSize: 28 }}>📸</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700, fontSize: 15, color: "#1a1a1a" }}>{content.ig.title}</div>
                <div style={{ fontSize: 12, color: "#e85d2b", fontWeight: 600 }}>Free</div>
              </div>
              <div style={{ fontSize: 22 }}>{joinMethod === "ig" ? "✅" : "⭕"}</div>
            </div>
            <div style={{ fontSize: 13, color: "#666", lineHeight: 1.5 }}>{content.ig.body}</div>
            {joinMethod === "ig" && (
              <div style={{ marginTop: 14 }} onClick={(e) => e.stopPropagation()}>
                <a href="https://instagram.com/heha.online" target="_blank" rel="noreferrer"
                  style={{ display: "block", textAlign: "center", padding: "11px", background: "linear-gradient(135deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888)", color: "#fff", borderRadius: 10, fontWeight: 700, fontSize: 14, textDecoration: "none", marginBottom: 12 }}>
                  Open @heha.online on Instagram ↗
                </a>
                <label style={{ display: "flex", alignItems: "center", gap: 10, cursor: "pointer", fontSize: 13, color: "#555" }}>
                  <input type="checkbox" checked={igConfirmed} onChange={(e) => setIgConfirmed(e.target.checked)} style={{ width: 18, height: 18, cursor: "pointer" }} />
                  {content.ig.confirm}
                </label>
              </div>
            )}
          </div>

          <div onClick={() => { setJoinMethod("sub"); setStripeError(""); }}
            style={{ background: joinMethod === "sub" ? "#f0f8f2" : "#fff", border: `2px solid ${joinMethod === "sub" ? "#2a7c3f" : "#e8e3dc"}`, borderRadius: 16, padding: "18px", cursor: "pointer" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 8 }}>
              <span style={{ fontSize: 28 }}>💚</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700, fontSize: 15, color: "#1a1a1a" }}>{content.sub.title}</div>
                <div style={{ fontSize: 12, color: "#2a7c3f", fontWeight: 600 }}>From $1/month</div>
              </div>
              <div style={{ fontSize: 22 }}>{joinMethod === "sub" ? "✅" : "⭕"}</div>
            </div>
            <div style={{ fontSize: 13, color: "#666", lineHeight: 1.5, marginBottom: joinMethod === "sub" ? 14 : 0 }}>{content.sub.body}</div>
            {joinMethod === "sub" && (
              <div onClick={(e) => e.stopPropagation()}>
                <div style={{ textAlign: "center", marginBottom: 10 }}>
                  <span style={{ fontSize: 40, fontWeight: 800, color: "#2a7c3f" }}>${subAmount}</span>
                  <span style={{ fontSize: 15, color: "#888" }}>/month</span>
                </div>
                <input type="range" min={1} max={100} step={1} value={subAmount}
                  onChange={(e) => setSubAmount(Number(e.target.value))}
                  style={{ width: "100%", accentColor: "#2a7c3f", cursor: "pointer" }} />
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#aaa", marginTop: 2 }}>
                  <span>$1 min</span><span>$100 max</span>
                </div>
                <div style={{ marginTop: 10, fontSize: 12, color: "#888", textAlign: "center", lineHeight: 1.6 }}>{content.sub.breakdown(subAmount)}</div>
                {stripeError && <div style={{ marginTop: 10, fontSize: 12, color: "#e85d2b", textAlign: "center" }}>{stripeError}</div>}
              </div>
            )}
          </div>
        </div>

        <button onClick={() => { if (joinMethod === "ig" && igConfirmed) completeWithIG(); else if (joinMethod === "sub") completeWithStripe(); }}
          disabled={!canProceed || loading || stripeLoading}
          style={{ width: "100%", padding: "15px", borderRadius: 14, border: "none", background: canProceed && !loading && !stripeLoading ? "#1a1a1a" : "#ccc", color: "#fff", fontSize: 16, fontWeight: 700, cursor: (!canProceed || loading || stripeLoading) ? "not-allowed" : "pointer", marginTop: 20, transition: "background 0.2s" }}>
          {stripeLoading ? "Redirecting to payment…" : loading ? "Setting up…" : joinMethod === "sub" ? `Pay $${subAmount}/month via Stripe →` : content.cta}
        </button>

        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 8, marginTop: 16 }}>
          <button onClick={() => setStep("role")} style={{ background: "none", border: "none", fontSize: 13, color: "#aaa", cursor: "pointer" }}>← Back</button>
          {joinMethod === "sub" && <><span style={{ color: "#ddd" }}>·</span><span style={{ fontSize: 11, color: "#ccc" }}>Secured by</span><span style={{ fontSize: 12, fontWeight: 700, color: "#635bff" }}>stripe</span></>}
        </div>
      </div>
    </div>
  );
}
