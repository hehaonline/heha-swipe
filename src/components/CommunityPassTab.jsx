import { useEffect, useState } from "react";
import { startSupporterCheckout } from "../lib/supporterCheckout";
import { fetchActiveSupporterSubscription } from "../lib/supporterStatus";

// Community Pass & Local Deals dashboard.
// Reads supporter/profile state; for "Become a Supporter" it routes to the shared,
// already-deployed supporter checkout (PR #26) via lib/supporterCheckout — no
// duplicated Stripe logic and no new checkout function.

const REMINDER_COPY =
  "HEHA Swipe grows through the people using it. If this community helps you discover better local options, even $1/month helps us keep building.";

const BENEFITS = [
  { icon: "✨", title: "Early access to HEHA Swipe features" },
  { icon: "🎟️", title: "Supporter-only local deal drops" },
  { icon: "🗳️", title: "Vote on future HEHA partners" },
  { icon: "🔎", title: "First look at new restaurants, wellness spaces, and markets" },
  { icon: "📣", title: "HEHA community updates" },
  { icon: "🕊️", title: "Freebird / community mission updates" },
  { icon: "🎉", title: "Event invites and local partner announcements" },
];

const SUPPORTER_TYPES = ["supporter_membership", "customer_supporter", "partner_supporter"];

function isActiveSupporter(profile) {
  if (!profile) return false;
  const type = profile.subscription_type || "";
  return profile.subscription_active === true && SUPPORTER_TYPES.includes(type);
}

function statusLabel(profile) {
  const s = (profile?.subscription_status || "").toLowerCase();
  if (s === "active") return "Active";
  if (s === "trialing") return "Trialing";
  if (s === "past_due") return "Payment past due";
  if (s === "canceled" || s === "cancelled") return "Canceled";
  return profile?.subscription_active ? "Active" : "—";
}

function ManageSupportModal({ portalUrl, onClose }) {
  const [billingNote, setBillingNote] = useState(null);

  const goToBilling = () => {
    if (portalUrl) {
      window.open(portalUrl, "_blank", "noopener,noreferrer");
    } else {
      setBillingNote(
        "Billing management is almost ready. For now, contact HEHA support or manage your subscription through Stripe."
      );
    }
  };

  return (
    <div className="cp-modal-backdrop" role="dialog" aria-modal="true" aria-label="Manage support" onClick={onClose}>
      <section className="cp-modal card-like" onClick={(e) => e.stopPropagation()}>
        <button className="cp-modal-close" type="button" aria-label="Close" onClick={onClose}>×</button>
        <p className="eyebrow">Manage support</p>
        <h2>Before you cancel…</h2>
        <p className="cp-modal-copy">
          Your support helps HEHA Swipe grow the local healthy discovery network, highlight small
          businesses, and keep early-access features moving forward. Even $1/month helps.
        </p>

        <div className="cp-modal-actions">
          <button className="primary-button" type="button" onClick={onClose}>
            Keep my support
          </button>

          {/* Quantity-change (lower amount) is not wired yet — shown as coming soon, never a dead end. */}
          <button className="secondary-button" type="button" disabled title="Coming soon">
            Lower to $1/month · Coming soon
          </button>

          <button className="secondary-button" type="button" onClick={goToBilling}>
            Pause support
          </button>

          {/* Always-visible, never blocked: the path out stays open. */}
          <button className="text-button center" type="button" onClick={goToBilling}>
            Continue to billing
          </button>
        </div>

        {billingNote && <div className="cp-billing-note">{billingNote}</div>}
      </section>
    </div>
  );
}

export default function CommunityPassTab({ user, profile }) {
  const [showManage, setShowManage] = useState(false);
  const [amount, setAmount] = useState(5);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  // Fallback: if the profile hasn't been flipped by the webhook yet, an active
  // supporter_subscriptions row still counts (covers post-payment lag).
  const [subRow, setSubRow] = useState(null);

  const profileSupporter = isActiveSupporter(profile);

  useEffect(() => {
    if (profileSupporter || !user?.id) {
      setSubRow(null);
      return;
    }
    let cancelled = false;
    fetchActiveSupporterSubscription(user.id)
      .then((row) => {
        if (!cancelled) setSubRow(row);
      })
      .catch(() => {
        if (!cancelled) setSubRow(null);
      });
    return () => {
      cancelled = true;
    };
  }, [profileSupporter, user?.id]);

  const supporter = profileSupporter || !!subRow;
  const currentAmount = profileSupporter
    ? Number(profile?.subscription_amount || 0)
    : subRow
    ? Number(subRow.amount_cents || 0) / 100
    : 0;
  const supporterStatus = profileSupporter
    ? statusLabel(profile)
    : subRow
    ? (subRow.status === "trialing" ? "Trialing" : "Active")
    : statusLabel(profile);
  const portalUrl = import.meta.env.VITE_STRIPE_CUSTOMER_PORTAL_URL || null;

  const goToCheckout = async (qty) => {
    setBusy(true);
    setError(null);
    try {
      await startSupporterCheckout(qty); // redirects to Stripe on success
    } catch (e) {
      setError(e.message || "Supporter checkout is not available yet. Please try again later.");
      setBusy(false);
    }
  };

  return (
    <section className="community-pass-screen">
      <header className="cp-hero">
        <p className="eyebrow">Community-supported</p>
        <h1>Community Pass &amp; Local Deals</h1>
        <p className="cp-sub">
          HEHA Swipe is community-supported. Supporters help us grow Tampa Bay’s local healthy
          discovery network and unlock early features and local deal drops.
        </p>
      </header>

      {supporter ? (
        <>
          <div className="cp-status-card card-like">
            <span className="cp-badge">✓ Active supporter</span>
            <div className="cp-status-grid">
              <div>
                <span className="cp-status-label">Monthly support</span>
                <strong className="cp-status-value">{currentAmount > 0 ? `$${currentAmount}/month` : "Active"}</strong>
              </div>
              <div>
                <span className="cp-status-label">Status</span>
                <strong className="cp-status-value">{supporterStatus}</strong>
              </div>
            </div>
            <p className="cp-thanks">
              Thank you for helping HEHA Swipe grow Tampa Bay’s local healthy discovery network.
            </p>
          </div>

          <h2 className="cp-section-title">Benefits unlocked</h2>
          <div className="cp-benefits-grid">
            {BENEFITS.map((b) => (
              <div className="cp-benefit-card" key={b.title}>
                <span className="cp-benefit-icon">{b.icon}</span>
                <span>{b.title}</span>
              </div>
            ))}
          </div>

          <h2 className="cp-section-title">Local deals &amp; partner offers</h2>
          <div className="cp-panel card-like">
            <p>Supporter local deal drops are on the way. New partner offers will appear here as HEHA activates them — no fake deals until they’re real.</p>
          </div>

          <h2 className="cp-section-title">HEHA updates</h2>
          <div className="cp-panel card-like">
            <p>Community and Freebird mission updates, new partner announcements, and event invites will show up here.</p>
          </div>

          <h2 className="cp-section-title">Community impact</h2>
          <div className="cp-panel card-like">
            <p>Your monthly support helps highlight small local businesses and keeps early-access features moving forward for the whole HEHA Swipe community.</p>
          </div>

          <button className="secondary-button cp-manage-btn" type="button" onClick={() => setShowManage(true)}>
            Manage support
          </button>

          {showManage && <ManageSupportModal portalUrl={portalUrl} onClose={() => setShowManage(false)} />}
        </>
      ) : (
        <>
          <div className="cp-panel card-like">
            <p className="cp-explainer">
              HEHA Swipe grows through the people using it. Supporters get early access, supporter-only
              local deal drops, and a say in which local businesses HEHA highlights next.
            </p>
          </div>

          <h2 className="cp-section-title">What supporters get</h2>
          <div className="cp-benefits-grid">
            {BENEFITS.map((b) => (
              <div className="cp-benefit-card cp-benefit-preview" key={b.title}>
                <span className="cp-benefit-icon">{b.icon}</span>
                <span>{b.title}</span>
              </div>
            ))}
          </div>

          <div className="cp-cta-card card-like">
            <div className="cp-amount-row">
              <div>
                <span className="cp-status-label">Choose your monthly support</span>
                <span className="cp-amount-hint">$1 to $100/month</span>
              </div>
              <strong className="cp-status-value">${amount}/month</strong>
            </div>
            <input
              type="range"
              min="1"
              max="100"
              step="1"
              value={amount}
              onChange={(e) => setAmount(Number(e.target.value))}
              aria-label="Monthly support amount"
              disabled={busy}
            />

            <button className="primary-button" type="button" onClick={() => goToCheckout(amount)} disabled={busy}>
              {busy ? "Opening checkout…" : `Become a Supporter · $${amount}/month`}
            </button>
            <button className="secondary-button" type="button" onClick={() => goToCheckout(1)} disabled={busy}>
              Start at $1/month
            </button>

            {error && <div className="cp-billing-note">{error}</div>}
            <p className="cp-reminder">{REMINDER_COPY}</p>
          </div>
        </>
      )}
    </section>
  );
}
