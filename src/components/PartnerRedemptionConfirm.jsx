import { useState } from "react";
import { supabase } from "../lib/supabase";

function formatCode(value) {
  const digits = String(value || "").replace(/\D/g, "").slice(0, 6);
  return digits.length === 6 ? `${digits.slice(0, 3)} ${digits.slice(3)}` : digits;
}

export default function PartnerRedemptionConfirm({ listing, onClose }) {
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [confirmed, setConfirmed] = useState(null);

  const digits = String(code || "").replace(/\D/g, "").slice(0, 6);

  const confirmCode = async () => {
    if (digits.length !== 6) {
      setError("Enter the six-digit HEHA redemption code.");
      return;
    }

    setBusy(true);
    setError(null);
    setConfirmed(null);

    try {
      const { data, error: rpcError } = await supabase
        .rpc("confirm_community_offer_code", {
          p_partner_id: listing.id,
          p_code: digits,
        })
        .single();
      if (rpcError) throw rpcError;
      setConfirmed(data);
      setCode("");
    } catch (confirmError) {
      setError(confirmError.message || "Could not confirm this HEHA code.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="preview-backdrop" role="dialog" aria-modal="true" aria-label="Confirm Community Offer code" onClick={onClose}>
      <section className="partner-preview-sheet redemption-confirm-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close redemption confirmation">×</button>

        <div className="preview-body redemption-confirm-body">
          <p className="eyebrow">Partner confirmation</p>
          <h2>Confirm HEHA Offer</h2>
          <p className="preview-tagline">
            Ask the customer for the six-digit code shown in HEHA Swipe. Confirming records the offer redemption for {listing?.name || "your business"}.
          </p>

          <label className="field-block redemption-code-input">
            <span>Six-digit HEHA code</span>
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              value={formatCode(code)}
              onChange={(event) => setCode(event.target.value)}
              placeholder="123 456"
              aria-label="Six-digit HEHA redemption code"
            />
          </label>

          <button className="primary-button" type="button" disabled={busy || digits.length !== 6} onClick={confirmCode}>
            {busy ? "Confirming…" : "Confirm Community Offer"}
          </button>

          {confirmed && (
            <div className="redemption-success-card">
              <span>✓ Offer confirmed</span>
              <h3>{confirmed.offer_title}</h3>
              <strong>{confirmed.offer_text}</strong>
              {confirmed.first_time_only && <p>Partner reminder: this offer was marked first-time customers only.</p>}
              <p>The customer can now confirm “all good” or report a problem in HEHA Swipe.</p>
            </div>
          )}

          {error && <div className="error-banner">{error}</div>}

          <div className="partner-cert-note">
            Early access uses HEHA in-app six-digit codes. A code is short-lived and can only be confirmed for your own business listing.
          </div>

          <div className="preview-actions">
            <button className="secondary-button" type="button" onClick={onClose} disabled={busy}>Back to Partner Hub</button>
          </div>
        </div>
      </section>
    </div>
  );
}
