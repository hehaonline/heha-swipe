import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import PartnerRedemptionConfirm from "./PartnerRedemptionConfirm";

const DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

const OFFER_SUGGESTIONS = {
  Restaurant: [
    "10% off",
    "15% off one item",
    "Free add-on",
    "Free drink with qualifying purchase",
    "$5 off $25+",
    "Second item 50% off",
    "First visit special",
  ],
  Vendor: [
    "10% off",
    "$5 off $30+",
    "Free sample",
    "Free add-on",
    "Bundle discount",
    "First purchase special",
  ],
  Wellness: [
    "First class free",
    "50% off first class",
    "$10 off first visit",
    "Free 15-minute add-on",
    "Free consultation",
    "Bring a friend special",
  ],
  Coach: [
    "Free intro call",
    "Free assessment",
    "$15 off first session",
    "20% off first package",
    "Complimentary resource or session add-on",
  ],
  Catering: [
    "Free consultation",
    "Complimentary add-on",
    "$25 off first qualifying booking",
    "First group booking special",
    "Free tasting where applicable",
  ],
  PrivateChef: [
    "Free consultation",
    "Complimentary add-on",
    "$25 off first qualifying booking",
    "First group booking special",
    "Free tasting where applicable",
  ],
  Service: [
    "$10 off first visit",
    "10% off",
    "Free consultation",
    "Complimentary add-on",
    "First-time customer special",
  ],
  Events: [
    "Early access special",
    "10% off ticket",
    "Bring a friend special",
    "Free add-on",
    "Local community special",
  ],
};

const DEFAULT_SUGGESTIONS = [
  "10% off",
  "First visit special",
  "Free consultation",
  "Complimentary add-on",
  "Local community special",
];

const VERIFICATION_OPTIONS = [
  { value: "in_app_code", label: "HEHA in-app redemption code · recommended" },
  { value: "show_swipe_app", label: "Customer shows active offer in HEHA Swipe" },
  { value: "weekly_partner_code", label: "Weekly rotating partner code · redemption step" },
  { value: "heha_help_decide", label: "Let HEHA help me choose" },
];

function formatStatus(value) {
  return String(value || "submitted")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function requestStatus(request) {
  if (!request) return "";
  if (request.final_status && request.final_status !== "draft") return formatStatus(request.final_status);
  if (request.approval_status && request.approval_status !== "draft") return formatStatus(request.approval_status);
  return "Submitted";
}

export default function PartnerCommunityOfferBuilder({ user, listing, onClose, onChanged }) {
  const suggestions = useMemo(
    () => OFFER_SUGGESTIONS[listing?.category] || DEFAULT_SUGGESTIONS,
    [listing?.category]
  );

  const [title, setTitle] = useState(`${listing?.name || "My business"} Community Offer`);
  const [selectedOffer, setSelectedOffer] = useState(suggestions[0] || "");
  const [customMode, setCustomMode] = useState(false);
  const [customOffer, setCustomOffer] = useState("");
  const [availableDays, setAvailableDays] = useState([]);
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [minimumPurchase, setMinimumPurchase] = useState("");
  const [firstTimeOnly, setFirstTimeOnly] = useState(false);
  const [maxUsesPerDay, setMaxUsesPerDay] = useState("");
  const [verificationPreference, setVerificationPreference] = useState("in_app_code");
  const [terms, setTerms] = useState("");
  const [partnerNote, setPartnerNote] = useState("");
  const [latestRequest, setLatestRequest] = useState(null);
  const [showRedemption, setShowRedemption] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);

  const loadLatestRequest = useCallback(async () => {
    if (!user?.id || !listing?.id) return;
    setLoading(true);
    setError(null);
    try {
      const { data, error: requestError } = await supabase
        .from("admin_deal_requests")
        .select("id, deal_title, proposed_discount, custom_offer, available_days, start_date, end_date, approval_status, final_status, verification_preference, created_at, updated_at")
        .eq("partner_id", listing.id)
        .eq("owner_id", user.id)
        .eq("source", "partner")
        .eq("deal_type", "community_pass")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (requestError) throw requestError;
      setLatestRequest(data || null);
    } catch (loadError) {
      setError(loadError.message || "Could not load your latest Community Offer request.");
    } finally {
      setLoading(false);
    }
  }, [listing?.id, user?.id]);

  useEffect(() => {
    loadLatestRequest();
  }, [loadLatestRequest]);

  const activeRequest = Boolean(
    latestRequest && !["rejected", "expired"].includes(String(latestRequest.final_status || "").toLowerCase())
  );

  const toggleDay = (day) => {
    setAvailableDays((current) =>
      current.includes(day) ? current.filter((item) => item !== day) : [...current, day]
    );
  };

  const submitOffer = async () => {
    const offerText = customMode ? customOffer.trim() : selectedOffer.trim();
    if (!title.trim()) {
      setError("Add a short title for your Community Offer.");
      return;
    }
    if (!offerText) {
      setError("Choose a suggested offer or write a custom Community Offer.");
      return;
    }
    if (startDate && endDate && endDate < startDate) {
      setError("End date cannot be before the start date.");
      return;
    }

    setBusy(true);
    setError(null);
    setMessage(null);

    try {
      const verificationLabel = VERIFICATION_OPTIONS.find((option) => option.value === verificationPreference)?.label || verificationPreference;
      const { error: insertError } = await supabase
        .from("admin_deal_requests")
        .insert({
          partner_id: listing.id,
          owner_id: user.id,
          deal_title: title.trim(),
          deal_type: "community_pass",
          proposed_discount: offerText,
          suggested_offer_key: customMode ? null : selectedOffer,
          custom_offer: customMode ? customOffer.trim() : null,
          deal_terms: terms.trim() || null,
          redemption_method: verificationLabel,
          start_date: startDate || null,
          end_date: endDate || null,
          available_days: availableDays,
          minimum_purchase: minimumPurchase === "" ? null : Number(minimumPurchase),
          first_time_only: firstTimeOnly,
          max_uses_per_day: maxUsesPerDay === "" ? null : Number(maxUsesPerDay),
          verification_preference: verificationPreference,
          partner_note: partnerNote.trim() || null,
        });

      if (insertError) throw insertError;
      setMessage("Community Offer submitted for HEHA review. Nothing is active or public yet.");
      await loadLatestRequest();
      await onChanged?.();
    } catch (submitError) {
      setError(submitError.message || "Could not submit this Community Offer yet.");
    } finally {
      setBusy(false);
    }
  };

  if (showRedemption) {
    return <PartnerRedemptionConfirm listing={listing} onClose={() => setShowRedemption(false)} />;
  }

  return (
    <div className="preview-backdrop" role="dialog" aria-modal="true" aria-label="Create Community Offer" onClick={onClose}>
      <section className="partner-preview-sheet partner-offer-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close Community Offer builder">×</button>

        <div className="preview-body partner-offer-body">
          <p className="eyebrow">Optional partner benefit</p>
          <h2>Community Offer</h2>
          <p className="preview-tagline">
            Offer something special to the HEHA community. You control the idea and availability; HEHA reviews every offer before activation.
          </p>

          <button className="secondary-button partner-confirm-code-launch" type="button" onClick={() => setShowRedemption(true)}>
            Confirm a customer HEHA code
          </button>
          <p className="partner-confirm-code-copy">A customer using an active Community Offer will show you a six-digit code. Enter it here to confirm the offer.</p>

          {loading ? (
            <div className="cp-billing-note">Checking your current Community Offer status…</div>
          ) : activeRequest ? (
            <section className="partner-offer-current">
              <span className="cp-status-label">Current request</span>
              <h3>{latestRequest.deal_title}</h3>
              <strong>{latestRequest.proposed_discount || latestRequest.custom_offer}</strong>
              <p>Status: {requestStatus(latestRequest)} · Submitted {formatDate(latestRequest.created_at)}</p>
              <div className="partner-cert-note">
                HEHA is reviewing this offer. It is not active until HEHA approves and activates the redemption flow.
              </div>
              <button className="secondary-button" type="button" onClick={loadLatestRequest}>Refresh offer status</button>
            </section>
          ) : (
            <>
              <div className="profile-form partner-offer-form">
                <label className="field-block">
                  <span>Offer title</span>
                  <input value={title} onChange={(event) => setTitle(event.target.value)} maxLength={90} />
                </label>

                <div className="field-block">
                  <span>Choose a suggested offer for {listing?.category || "your business"}</span>
                  <select value={customMode ? "custom" : selectedOffer} onChange={(event) => {
                    if (event.target.value === "custom") {
                      setCustomMode(true);
                    } else {
                      setCustomMode(false);
                      setSelectedOffer(event.target.value);
                    }
                  }}>
                    {suggestions.map((suggestion) => <option key={suggestion} value={suggestion}>{suggestion}</option>)}
                    <option value="custom">Write my own offer</option>
                  </select>
                </div>

                {customMode && (
                  <label className="field-block">
                    <span>Custom Community Offer</span>
                    <textarea value={customOffer} onChange={(event) => setCustomOffer(event.target.value)} placeholder="Describe the exact offer customers can receive." />
                  </label>
                )}

                <div className="field-block">
                  <span>Available days · optional</span>
                  <div className="partner-offer-days">
                    {DAYS.map((day) => (
                      <button
                        key={day}
                        className={availableDays.includes(day) ? "selected" : ""}
                        type="button"
                        onClick={() => toggleDay(day)}
                      >
                        {day.slice(0, 3)}
                      </button>
                    ))}
                  </div>
                  <small>Leave all days unselected if the offer can be available any day HEHA activates it.</small>
                </div>

                <div className="partner-offer-date-grid">
                  <label className="field-block">
                    <span>Start date · optional</span>
                    <input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} />
                  </label>
                  <label className="field-block">
                    <span>End date · optional</span>
                    <input type="date" value={endDate} onChange={(event) => setEndDate(event.target.value)} />
                  </label>
                </div>

                <div className="partner-offer-date-grid">
                  <label className="field-block">
                    <span>Minimum purchase · optional</span>
                    <input type="number" min="0" step="0.01" value={minimumPurchase} onChange={(event) => setMinimumPurchase(event.target.value)} placeholder="25.00" />
                  </label>
                  <label className="field-block">
                    <span>Max uses per day · optional</span>
                    <input type="number" min="1" step="1" value={maxUsesPerDay} onChange={(event) => setMaxUsesPerDay(event.target.value)} placeholder="10" />
                  </label>
                </div>

                <label className="partner-offer-check">
                  <input type="checkbox" checked={firstTimeOnly} onChange={(event) => setFirstTimeOnly(event.target.checked)} />
                  <span>First-time customers only</span>
                </label>

                <label className="field-block">
                  <span>Preferred offer verification</span>
                  <select value={verificationPreference} onChange={(event) => setVerificationPreference(event.target.value)}>
                    {VERIFICATION_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                  </select>
                </label>

                {verificationPreference === "weekly_partner_code" && (
                  <div className="cp-billing-note">
                    Weekly rotating codes will be activated in the HEHA redemption step. You are choosing the verification preference now; no public code is created yet.
                  </div>
                )}

                <label className="field-block">
                  <span>Offer terms · optional</span>
                  <textarea value={terms} onChange={(event) => setTerms(event.target.value)} placeholder="Example: one use per customer, cannot be combined with another promotion." />
                </label>

                <label className="field-block">
                  <span>Note for HEHA · optional</span>
                  <textarea value={partnerNote} onChange={(event) => setPartnerNote(event.target.value)} placeholder="Anything Myren or the HEHA team should know while reviewing this offer?" />
                </label>
              </div>

              <div className="partner-cert-note">
                Community Offers are optional. Submitting an offer does not activate it, publish a discount, or create a redemption code automatically.
              </div>

              {message && <div className="success-banner">{message}</div>}
              {error && <div className="error-banner">{error}</div>}

              <div className="preview-actions">
                <button className="primary-button" type="button" onClick={submitOffer} disabled={busy}>
                  {busy ? "Submitting…" : "Submit Community Offer for HEHA review"}
                </button>
                <button className="secondary-button" type="button" onClick={onClose} disabled={busy}>Cancel</button>
              </div>
            </>
          )}

          {activeRequest && (
            <div className="preview-actions">
              <button className="primary-button" type="button" onClick={onClose}>Back to Partner Hub</button>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
