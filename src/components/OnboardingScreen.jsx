import { useState } from "react";
import { supabase } from "../lib/supabase";

const HEHA_INSTAGRAM_URL = import.meta.env.VITE_HEHA_INSTAGRAM_URL || "https://www.instagram.com/heha.online/";
const PRESET_AMOUNTS = [1, 5, 10, 25, 50, 100];

function getInitialRole() {
  return localStorage.getItem("heha_signup_role") || null;
}

function getReturnParams() {
  const params = new URLSearchParams(window.location.search);
  return {
    checkout: params.get("checkout"),
    type: params.get("type"),
    amount: params.get("amount"),
    role: params.get("role"),
  };
}

export default function OnboardingScreen({ user, onComplete }) {
  const returnParams = getReturnParams();
  const [role, setRole] = useState(getInitialRole);
  const [step, setStep] = useState(role ? "access" : "role");
  const [access, setAccess] = useState("free");
  const [supportAmount, setSupportAmount] = useState(10);
  const [instagramStepDone, setInstagramStepDone] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const chooseRole = (nextRole) => {
    localStorage.setItem("heha_signup_role", nextRole);
    setRole(nextRole);
    setStep("access");
  };

  const continueToDiscovery = () => {
    window.history.replaceState(null, "", window.location.pathname);
    onComplete?.(returnParams.role || role || "customer");
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

  const complete = async () => {
    setLoading(true);
    setError(null);

    try {
      await saveProfile("free");
      onComplete?.(role || "customer");
    } catch (completeError) {
      setError(completeError.message || "Could not finish setup yet.");
    } finally {
      setLoading(false);
    }
  };

  const handleInstagramFollowStep = () => {
    setInstagramStepDone(true);
    window.open(HEHA_INSTAGRAM_URL, "_blank", "noopener,noreferrer");
  };

  const startSupporterCheckout = async () => {
    setLoading(true);
    setError(null);

    try {
      await saveProfile("supporter_checkout_started");

      const origin = window.location.origin;
      const { data, error: functionError } = await supabase.functions.invoke("create-supporter-checkout", {
        body: {
          quantity: supportAmount,
          successUrl: `${origin}/?checkout=success&type=supporter_membership&amount=${supportAmount}&role=${role || "customer"}`,
          cancelUrl: `${origin}/?checkout=cancelled&type=supporter_membership&amount=${supportAmount}&role=${role || "customer"}`,
        },
      });

      if (functionError) throw functionError;
      if (!data?.checkoutUrl) {
        throw new Error(data?.error || "Checkout URL was not returned yet.");
      }

      window.location.href = data.checkoutUrl;
    } catch (checkoutError) {
      setError(checkoutError.message || "Could not open checkout yet.");
    } finally {
      setLoading(false);
    }
  };

  if (returnParams.checkout === "success" && returnParams.type === "supporter_membership") {
    return (
      <main className="onboarding-screen">
        <section className="join-card card-like">
          <p className="eyebrow">Supporter checkout complete</p>
          <h1>Thank you for pushing HEHA forward.</h1>
          <p>
            Your supporter checkout completed. Your support helps improve HEHA Swipe discovery, partner onboarding, and the HEHA Local operating system.
          </p>
          <div className="soft-note">
            Next milestone: keep the prototype simple, activate useful local partners, and test support features without turning on live fulfillment too early.
          </div>
          <button className="primary-button" type="button" onClick={continueToDiscovery}>
            Continue to discovery
          </button>
        </section>
      </main>
    );
  }

  if (returnParams.checkout === "cancelled" && returnParams.type === "supporter_membership") {
    return (
      <main className="onboarding-screen">
        <section className="join-card card-like">
          <p className="eyebrow">Checkout cancelled</p>
          <h1>No problem.</h1>
          <p>You can adjust your amount, continue free, or come back to supporter checkout later.</p>
          <button className="primary-button" type="button" onClick={() => window.history.replaceState(null, "", window.location.pathname)}>
            Back to access options
          </button>
        </section>
      </main>
    );
  }

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
  const canStartCheckout = access === "supporter";
  const freeCustomerNeedsInstagram = !isPartner && access === "free";

  return (
    <main className="onboarding-screen">
      <section className="join-card card-like">
        <button className="text-button" onClick={() => setStep("role")}>← Change path</button>
        <p className="eyebrow">Community access</p>
        <h1>{isPartner ? "Choose how your business joins." : "Choose your HEHA Swipe access."}</h1>
        <p>Start free, or choose an optional monthly supporter amount. Support helps grow the local healthy business network.</p>

        <div className="choice-grid plan-choice-grid">
          <button
            className={access === "free" ? "choice-card active-plan" : "choice-card"}
            onClick={() => {
              setAccess("free");
              setInstagramStepDone(false);
            }}
          >
            <span>🌱</span>
            <h2>Free</h2>
            <p>{isPartner ? "Create a starter listing without paying today." : "Follow HEHA on Instagram, then explore and save local businesses for free."}</p>
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
              <span>monthly HEHA Swipe support</span>
            </div>
            <input
              type="range"
              min="1"
              max="100"
              step="1"
              value={supportAmount}
              onChange={(event) => setSupportAmount(Number(event.target.value))}
            />
            <div className="support-preset-grid">
              {PRESET_AMOUNTS.map((amount) => (
                <button
                  key={amount}
                  type="button"
                  className={supportAmount === amount ? "active" : ""}
                  onClick={() => setSupportAmount(amount)}
                >
                  ${amount}
                </button>
              ))}
            </div>
            <p className="soft-mini-note">The selected amount becomes the monthly support amount in checkout.</p>
          </div>
        )}

        {freeCustomerNeedsInstagram && (
          <div className="instagram-follow-card">
            <p className="eyebrow">Free access step</p>
            <h3>Follow HEHA to join free.</h3>
            <p>Tap below to open Instagram. After that, you can continue into HEHA Swipe for free.</p>
            <button className="instagram-button" type="button" onClick={handleInstagramFollowStep}>
              {instagramStepDone ? "Instagram opened ✓" : "Follow @heha.online on Instagram"}
            </button>
            <p className="soft-mini-note">For now, this is a trust-based step. Automatic Instagram follow verification can be added later.</p>
          </div>
        )}

        {canStartCheckout ? (
          <>
            <button className="primary-button" onClick={startSupporterCheckout} disabled={loading}>
              {loading ? "Opening checkout…" : `Start $${supportAmount}/mo supporter checkout`}
            </button>
            <button className="secondary-button" onClick={() => setAccess("free")} disabled={loading}>
              Not now — choose free
            </button>
          </>
        ) : freeCustomerNeedsInstagram ? (
          <button className="primary-button" onClick={complete} disabled={loading || !instagramStepDone}>
            {loading ? "Setting up…" : instagramStepDone ? "Start discovering" : "Follow Instagram to unlock free access"}
          </button>
        ) : (
          <button className="primary-button" onClick={complete} disabled={loading}>
            {loading ? "Setting up…" : isPartner ? "Continue to business listing" : "Start discovering"}
          </button>
        )}

        <div className="soft-note">Monthly support is optional and the free path always stays available.</div>
        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
  );
}
