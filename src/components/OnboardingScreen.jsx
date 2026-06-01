import { useState } from "react";
import { supabase } from "../lib/supabase";

function getInitialRole() {
  return localStorage.getItem("heha_signup_role") || null;
}

export default function OnboardingScreen({ user, onComplete }) {
  const [role, setRole] = useState(getInitialRole);
  const [step, setStep] = useState(role ? "access" : "role");
  const [access, setAccess] = useState("free");
  const [supportAmount, setSupportAmount] = useState(10);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const chooseRole = (nextRole) => {
    localStorage.setItem("heha_signup_role", nextRole);
    setRole(nextRole);
    setStep("access");
  };

  const saveProfile = async (statusOverride) => {
    const isPartner = role === "partner";
    const subscriptionType = isPartner
      ? access === "supporter" ? "partner_supporter" : "partner_free"
      : access === "supporter" ? "customer_supporter" : "customer_free";

    const { error: profileError } = await supabase.from("profiles").upsert({
      id: user.id,
      email: user.email || null,
      phone: user.phone || null,
      subscription_type: subscriptionType,
      subscription_active: access === "free" || statusOverride === "active",
      subscription_amount: access === "supporter" ? supportAmount : 0,
      subscription_status: statusOverride || access,
    });
    if (profileError) throw profileError;

    await supabase.from("customer_profiles").upsert({ user_id: user.id });
  };

  const complete = async ({ forceFree = false } = {}) => {
    setLoading(true);
    setError(null);

    try {
      if (forceFree) setAccess("free");
      await saveProfile(forceFree ? "free" : undefined);
      onComplete?.(role || "customer");
    } catch (completeError) {
      setError(completeError.message || "Could not finish setup yet.");
    } finally {
      setLoading(false);
    }
  };

  const startSupporterCheckout = async () => {
    setLoading(true);
    setError(null);

    try {
      await saveProfile("supporter_checkout_started");
      const stripeLink = import.meta.env.VITE_STRIPE_SUPPORTER_CHECKOUT_URL;
      if (!stripeLink) {
        throw new Error("Stripe checkout is not connected yet. Add VITE_STRIPE_SUPPORTER_CHECKOUT_URL in Vercel when your Stripe payment link is ready.");
      }
      const url = new URL(stripeLink);
      url.searchParams.set("client_reference_id", user.id);
      url.searchParams.set("prefilled_email", user.email || "");
      url.searchParams.set("heha_amount", String(supportAmount));
      window.location.href = url.toString();
    } catch (checkoutError) {
      setError(checkoutError.message || "Could not open Stripe checkout yet.");
    } finally {
      setLoading(false);
    }
  };

  if (step === "role") {
    return (
      <main className="onboarding-screen">
        <section className="onboarding-hero card-like">
          <p className="eyebrow">Welcome to HEHA Swipe</p>
          <h1>How are you joining?</h1>
          <p>Choose your path first. Customers discover. Businesses get listed and become visible to the HEHA community.</p>
        </section>

        <section className="choice-grid">
          <button className="choice-card" onClick={() => chooseRole("customer")} disabled={loading}>
            <span>🌿</span>
            <h2>I’m a customer</h2>
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
  const canStartStripe = access === "supporter";

  return (
    <main className="onboarding-screen">
      <section className="join-card card-like">
        <button className="text-button" onClick={() => setStep("role")}>← Change path</button>
        <p className="eyebrow">Community access</p>
        <h1>{isPartner ? "Choose how your business joins." : "Choose your HEHA Swipe access."}</h1>
        <p>Start free, or choose an optional monthly supporter amount. Support helps grow the local healthy business network.</p>

        <div className="choice-grid plan-choice-grid">
          <button className={access === "free" ? "choice-card active-plan" : "choice-card"} onClick={() => setAccess("free")}>
            <span>🌱</span>
            <h2>Free</h2>
            <p>Explore HEHA Swipe and save local businesses without paying today.</p>
          </button>
          <button className={access === "supporter" ? "choice-card featured active-plan" : "choice-card featured"} onClick={() => setAccess("supporter")}>
            <span>🕊️</span>
            <h2>Supporter</h2>
            <p>Choose a monthly amount to support HEHA’s community work.</p>
          </button>
        </div>

        {access === "supporter" && (
          <div className="slider-card">
            <div className="slider-header">
              <strong>${supportAmount}/mo</strong>
              <span>optional support</span>
            </div>
            <input
              type="range"
              min="1"
              max="100"
              step="1"
              value={supportAmount}
              onChange={(event) => setSupportAmount(Number(event.target.value))}
            />
          </div>
        )}

        {canStartStripe ? (
          <>
            <button className="primary-button" onClick={startSupporterCheckout} disabled={loading}>
              {loading ? "Opening Stripe…" : "Start supporter checkout"}
            </button>
            <button className="secondary-button" onClick={() => complete({ forceFree: true })} disabled={loading}>
              Continue free for testing
            </button>
          </>
        ) : (
          <button className="primary-button" onClick={() => complete()} disabled={loading}>
            {loading ? "Setting up…" : isPartner ? "Continue to business listing" : "Start discovering"}
          </button>
        )}

        <div className="soft-note">Stripe checkout needs your Stripe payment link in Vercel. Until then, use Free or Continue free for testing.</div>
        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
  );
}
