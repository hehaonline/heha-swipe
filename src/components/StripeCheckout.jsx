import { useState } from "react";
import { supabase } from "../lib/supabase";

export default function StripeCheckout({ user, amount, onSuccess, onCancel }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleCheckout = async () => {
    setLoading(true);
    setError("");
    try {
      const { data: { session: supaSession } } = await supabase.auth.getSession();
      const res = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/create-checkout-session`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${supaSession.access_token}`,
          },
          body: JSON.stringify({
            amount_cents: amount * 100,
            user_id: user.id,
            email: user.email || null,
            success_url: `${window.location.origin}/?checkout=success`,
            cancel_url: `${window.location.origin}/?checkout=cancelled`,
          }),
        }
      );
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Failed to create checkout session");
      window.location.href = data.url;
    } catch (e) {
      setError(e.message);
      setLoading(false);
    }
  };

  return (
    <div style={{
      background: "#fff", borderRadius: 16, padding: "24px",
      boxShadow: "0 4px 20px rgba(0,0,0,0.1)", maxWidth: 360, width: "100%"
    }}>
      <div style={{ textAlign: "center", marginBottom: 20 }}>
        <div style={{ fontSize: 40, marginBottom: 8 }}>💚</div>
        <div style={{ fontSize: 20, fontWeight: 800, color: "#1a1a1a" }}>${amount}/month</div>
        <div style={{ fontSize: 13, color: "#888", marginTop: 4 }}>Supporting Tampa Bay's healthy community</div>
      </div>
      <div style={{ background: "#f0f8f2", borderRadius: 10, padding: "14px", marginBottom: 20 }}>
        <div style={{ fontSize: 13, color: "#2a7c3f", lineHeight: 1.6 }}>
          <div>💚 <strong>${(amount * 0.95).toFixed(2)}</strong> goes to local businesses</div>
          <div>🌿 <strong>${(amount * 0.05).toFixed(2)}</strong> keeps HEHA running</div>
          <div style={{ marginTop: 8, fontSize: 12, color: "#888" }}>Cancel anytime · Secure payment via Stripe</div>
        </div>
      </div>
      {error && (
        <div style={{ background: "#fff0f0", border: "1px solid #fcc", borderRadius: 8, padding: "10px 12px", fontSize: 13, color: "#c00", marginBottom: 16 }}>{error}</div>
      )}
      <button onClick={handleCheckout} disabled={loading}
        style={{
          width: "100%", padding: "14px", borderRadius: 12, border: "none",
          background: loading ? "#ccc" : "#2a7c3f", color: "#fff",
          fontSize: 16, fontWeight: 700, cursor: loading ? "wait" : "pointer", marginBottom: 12
        }}>
        {loading ? "Redirecting to payment…" : `Subscribe for $${amount}/month →`}
      </button>
      <button onClick={onCancel}
        style={{ background: "none", border: "none", width: "100%", fontSize: 13, color: "#aaa", cursor: "pointer" }}>
        Cancel
      </button>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 6, marginTop: 16 }}>
        <span style={{ fontSize: 11, color: "#ccc" }}>Secured by</span>
        <span style={{ fontSize: 13, fontWeight: 700, color: "#635bff" }}>stripe</span>
      </div>
    </div>
  );
}
