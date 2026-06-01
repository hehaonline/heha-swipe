import { useState } from "react";
import { supabase } from "../lib/supabase";

export default function OnboardingScreen({ user, onComplete }) {
  const [role, setRole] = useState(null);
  const [step, setStep] = useState("role");
  const [igConfirmed, setIgConfirmed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const chooseRole = async (nextRole) => {
    setLoading(true);
    setError(null);
    setRole(nextRole);

    try {
      const { error: upsertError } = await supabase.from("profiles").upsert({
        id: user.id,
        email: user.email || null,
        phone: user.phone || null,
        subscription_type: `pending_${nextRole}`,
      });
      if (upsertError) throw upsertError;
      setStep("join");
    } catch (upsertError) {
      setError(upsertError.message || "Could not save your path yet.");
    } finally {
      setLoading(false);
    }
  };

  const complete = async () => {
    setLoading(true);
    setError(null);

    try {
      const subscriptionType = role === "partner" ? "partner_instagram" : "instagram";
      const { error: profileError } = await supabase.from("profiles").upsert({
        id: user.id,
        email: user.email || null,
        phone: user.phone || null,
        subscription_type: subscriptionType,
        subscription_active: true,
        subscription_amount: 0,
        subscription_status: "active",
      });
      if (profileError) throw profileError;

      await supabase.from("customer_profiles").upsert({ user_id: user.id });
      onComplete?.(role);
    } catch (completeError) {
      setError(completeError.message || "Could not finish setup yet.");
    } finally {
      setLoading(false);
    }
  };

  if (step === "role") {
    return (
      <main className="onboarding-screen">
        <section className="onboarding-hero card-like">
          <p className="eyebrow">Welcome to HEHA Swipe</p>
          <h1>Choose how you want to connect with the healthy local economy.</h1>
          <p>Customers discover. Businesses get seen. HEHA connects the local health community with trust, transparency, and better food options.</p>
        </section>

        <section className="choice-grid">
          <button className="choice-card" onClick={() => chooseRole("customer")} disabled={loading}>
            <span>🌿</span>
            <h2>I’m exploring</h2>
            <p>Find healthy restaurants, markets, wellness partners, coaches, and offers around Tampa Bay.</p>
          </button>
          <button className="choice-card featured" onClick={() => chooseRole("partner")} disabled={loading}>
            <span>🏪</span>
            <h2>I’m a business</h2>
            <p>List your healthy business, get discovered, and join HEHA’s growing local partner network.</p>
          </button>
        </section>
        {error && <div className="error-banner">{error}</div>}
      </main>
    );
  }

  const isPartner = role === "partner";

  return (
    <main className="onboarding-screen">
      <section className="join-card card-like">
        <button className="text-button" onClick={() => setStep("role")}>← Change path</button>
        <p className="eyebrow">One community step</p>
        <h1>{isPartner ? "Stay connected before listing your business." : "Join the local healthy discovery circle."}</h1>
        <p>
          {isPartner
            ? "Follow HEHA so we can feature your business, communicate partner updates, and build social proof around the local healthy movement."
            : "Follow HEHA to unlock Swipe and see new businesses, food drops, partner offers, and community updates."}
        </p>

        <a className="instagram-button" href="https://instagram.com/heha.online" target="_blank" rel="noreferrer">
          Open @heha.online on Instagram ↗
        </a>

        <label className="check-row">
          <input type="checkbox" checked={igConfirmed} onChange={(event) => setIgConfirmed(event.target.checked)} />
          <span>I followed @heha.online</span>
        </label>

        <button className="primary-button" onClick={complete} disabled={!igConfirmed || loading}>
          {loading ? "Setting up…" : isPartner ? "Continue to business listing" : "Start discovering"}
        </button>

        <div className="soft-note">
          Choose-your-own monthly community support is coming later. For now, the app focuses on discovery and partner visibility.
        </div>

        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
  );
}
