import { useState } from "react";
import { supabase } from "../lib/supabase";

const PRESET_AMOUNTS = [1, 5, 10, 25, 50, 100];

function getCheckoutStatus() {
  return new URLSearchParams(window.location.search).get("checkout");
}

export default function SupporterSliderScreen({ user, onBack }) {
  const [supportAmount, setSupportAmount] = useState(5);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const checkoutStatus = getCheckoutStatus();

  const startCheckout = async () => {
    setLoading(true);
    setError(null);

    try {
      const origin = window.location.origin;
      const { data, error: functionError } = await supabase.functions.invoke("create-supporter-checkout", {
        body: {
          quantity: supportAmount,
          successUrl: `${origin}/subscribe?checkout=success&amount=${supportAmount}`,
          cancelUrl: `${origin}/subscribe?checkout=cancelled&amount=${supportAmount}`,
        },
      });

      if (functionError) throw functionError;
      if (!data?.checkoutUrl) {
        throw new Error(data?.error || "Stripe checkout did not return a checkout URL yet.");
      }

      window.location.href = data.checkoutUrl;
    } catch (checkoutError) {
      setError(checkoutError.message || "Could not open Stripe checkout yet.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="onboarding-screen supporter-slider-screen">
      <section className="join-card card-like">
        <button className="text-button" type="button" onClick={onBack}>← Back to HEHA Swipe</button>

        <p className="eyebrow">HEHA Swipe supporter membership</p>
        <h1>Choose your monthly support.</h1>
        <p>
          Pick a monthly amount from $1 to $100. Stripe handles the secure checkout, and HEHA stores only the supporter status and payment reference.
        </p>

        {checkoutStatus === "success" && (
          <div className="success-banner">Thank you — the monthly supporter checkout completed. Stripe webhook confirmation may take a moment.</div>
        )}

        {checkoutStatus === "cancelled" && (
          <div className="soft-note">Checkout was cancelled. You can adjust the amount and try again whenever you are ready.</div>
        )}

        <div className="slider-card supporter-slider-card">
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
            aria-label="Monthly support amount"
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

          <p className="soft-mini-note">
            Technical test: ${supportAmount}/month is sent as Stripe quantity {supportAmount} on the $1/month supporter price.
          </p>
        </div>

        <button className="primary-button" type="button" onClick={startCheckout} disabled={loading || !user?.id}>
          {loading ? "Opening Stripe…" : `Start $${supportAmount}/month Stripe checkout`}
        </button>

        <p className="soft-note">
          Signed in as {user?.email || "HEHA tester"}. This is still sandbox/test-mode until Geronimo approves live payments.
        </p>

        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
  );
}
