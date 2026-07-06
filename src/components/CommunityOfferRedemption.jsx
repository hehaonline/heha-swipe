import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const ACTIVE_STATUSES = new Set(["issued", "confirmed_by_partner"]);

function formatMoney(value) {
  if (value === null || value === undefined || value === "") return null;
  const amount = Number(value);
  if (!Number.isFinite(amount)) return null;
  return `$${amount.toFixed(amount % 1 === 0 ? 0 : 2)}`;
}

function formatDate(value) {
  if (!value) return null;
  const date = new Date(`${value}T12:00:00`);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function formatTime(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
}

function formatCode(code) {
  const digits = String(code || "").replace(/\D/g, "").slice(0, 6);
  return digits.length === 6 ? `${digits.slice(0, 3)} ${digits.slice(3)}` : digits;
}

function todayInTampa() {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    timeZone: "America/New_York",
  }).format(new Date());
}

function latestByDeal(rows = []) {
  const map = new Map();
  rows.forEach((row) => {
    if (!map.has(row.deal_request_id)) map.set(row.deal_request_id, row);
  });
  return map;
}

export default function CommunityOfferRedemption({ user, partner }) {
  const [resolvedUserId, setResolvedUserId] = useState(user?.id || null);
  const [offers, setOffers] = useState([]);
  const [redemptions, setRedemptions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);
  const [problemDrafts, setProblemDrafts] = useState({});

  const redemptionByDeal = useMemo(() => latestByDeal(redemptions), [redemptions]);

  useEffect(() => {
    if (user?.id) {
      setResolvedUserId(user.id);
      return;
    }

    let cancelled = false;
    supabase.auth.getUser().then(({ data }) => {
      if (!cancelled) setResolvedUserId(data?.user?.id || null);
    });
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  const load = useCallback(async () => {
    if (!partner?.id || !resolvedUserId) return;
    setLoading(true);
    setError(null);

    try {
      const [offerResult, redemptionResult] = await Promise.all([
        supabase
          .from("community_offers_public")
          .select("deal_request_id, partner_id, partner_name, partner_category, deal_title, offer_text, deal_terms, available_days, minimum_purchase, first_time_only, max_uses_per_day, verification_preference, start_date, end_date, published_at")
          .eq("partner_id", partner.id)
          .order("published_at", { ascending: false }),
        supabase
          .from("community_offer_redemptions")
          .select("id, deal_request_id, partner_id, redemption_code, status, offer_title_snapshot, offer_text_snapshot, first_time_only_snapshot, issued_at, expires_at, partner_confirmed_at, customer_confirmed_at, customer_outcome, customer_problem_note, created_at")
          .eq("user_id", resolvedUserId)
          .eq("partner_id", partner.id)
          .order("created_at", { ascending: false })
          .limit(20),
      ]);

      if (offerResult.error) throw offerResult.error;
      if (redemptionResult.error) throw redemptionResult.error;
      setOffers(offerResult.data || []);
      setRedemptions(redemptionResult.data || []);
    } catch (loadError) {
      setError(loadError.message || "Could not load Community Offers yet.");
    } finally {
      setLoading(false);
    }
  }, [partner?.id, resolvedUserId]);

  useEffect(() => {
    load();
  }, [load]);

  const issueCode = async (offer) => {
    setBusyId(offer.deal_request_id);
    setError(null);
    setMessage(null);

    try {
      const { data, error: rpcError } = await supabase
        .rpc("issue_community_offer_redemption", { p_deal_id: offer.deal_request_id })
        .single();
      if (rpcError) throw rpcError;
      setMessage(`Your HEHA code for ${data.partner_name} is ready.`);
      await load();
    } catch (issueError) {
      setError(issueError.message || "Could not activate this Community Offer yet.");
    } finally {
      setBusyId(null);
    }
  };

  const confirmOutcome = async (redemption, outcome) => {
    const problemNote = String(problemDrafts[redemption.id] || "").trim();
    setBusyId(redemption.id);
    setError(null);
    setMessage(null);

    try {
      const { error: rpcError } = await supabase.rpc("confirm_community_offer_outcome", {
        p_redemption_id: redemption.id,
        p_outcome: outcome,
        p_problem_note: outcome === "problem" ? problemNote : null,
      });
      if (rpcError) throw rpcError;
      setMessage(outcome === "all_good" ? "Offer confirmed. Thank you for closing the loop." : "Problem reported to HEHA. We saved the issue for follow-up.");
      await load();
    } catch (confirmError) {
      setError(confirmError.message || "Could not confirm this redemption yet.");
    } finally {
      setBusyId(null);
    }
  };

  if (loading) {
    return <div className="community-offer-loading">Checking active HEHA Community Offers…</div>;
  }

  if (!offers.length && !redemptions.some((row) => ACTIVE_STATUSES.has(row.status))) return null;

  const tampaWeekday = todayInTampa();

  return (
    <section className="community-offer-section card-like">
      <div className="community-offer-heading">
        <p className="eyebrow">HEHA Community Offers</p>
        <h3>Local partner perks</h3>
        <p>Use an active offer in HEHA Swipe. The business confirms the six-digit code, then you confirm whether everything worked.</p>
      </div>

      <div className="community-offer-list">
        {offers.map((offer) => {
          const redemption = redemptionByDeal.get(offer.deal_request_id) || null;
          const isIssued = redemption?.status === "issued" && new Date(redemption.expires_at).getTime() > Date.now();
          const partnerConfirmed = redemption?.status === "confirmed_by_partner";
          const availableToday = !offer.available_days?.length || offer.available_days.includes(tampaWeekday);
          const minimum = formatMoney(offer.minimum_purchase);
          const start = formatDate(offer.start_date);
          const end = formatDate(offer.end_date);

          return (
            <article className="community-offer-card" key={offer.deal_request_id}>
              <div className="community-offer-topline">
                <span>Community Offer</span>
                {offer.first_time_only && <strong>First-time only</strong>}
              </div>
              <h4>{offer.deal_title}</h4>
              <div className="community-offer-value">{offer.offer_text}</div>

              <div className="community-offer-meta">
                {offer.available_days?.length > 0 && <span>{offer.available_days.join(" · ")}</span>}
                {minimum && <span>Minimum purchase {minimum}</span>}
                {offer.max_uses_per_day && <span>Limited to {offer.max_uses_per_day} use{offer.max_uses_per_day === 1 ? "" : "s"}/day</span>}
                {(start || end) && <span>{start || "Now"} – {end || "Ongoing"}</span>}
              </div>

              {offer.deal_terms && <p className="community-offer-terms">{offer.deal_terms}</p>}

              {isIssued ? (
                <div className="redemption-code-panel">
                  <span>Show this code to {offer.partner_name}</span>
                  <strong>{formatCode(redemption.redemption_code)}</strong>
                  <small>Valid until {formatTime(redemption.expires_at)}. The business enters the code in its HEHA Partner Hub.</small>
                  <button className="secondary-button" type="button" onClick={load} disabled={loading}>Business confirmed? Refresh status</button>
                </div>
              ) : partnerConfirmed ? (
                <div className="redemption-confirm-panel">
                  <strong>Business confirmed the offer.</strong>
                  <p>Did you receive the Community Offer?</p>
                  <div className="redemption-confirm-actions">
                    <button className="primary-button" type="button" disabled={busyId === redemption.id} onClick={() => confirmOutcome(redemption, "all_good")}>Yes, all good</button>
                    <textarea
                      value={problemDrafts[redemption.id] || ""}
                      onChange={(event) => setProblemDrafts((current) => ({ ...current, [redemption.id]: event.target.value }))}
                      placeholder="Briefly tell HEHA what went wrong"
                    />
                    <button className="secondary-button" type="button" disabled={busyId === redemption.id || !String(problemDrafts[redemption.id] || "").trim()} onClick={() => confirmOutcome(redemption, "problem")}>I had a problem</button>
                  </div>
                </div>
              ) : (
                <button className="primary-button" type="button" disabled={!availableToday || busyId === offer.deal_request_id} onClick={() => issueCode(offer)}>
                  {busyId === offer.deal_request_id ? "Creating code…" : availableToday ? "Use Community Offer" : `Available on ${offer.available_days.join(", ")}`}
                </button>
              )}
            </article>
          );
        })}
      </div>

      {message && <div className="success-banner">{message}</div>}
      {error && <div className="error-banner">{error}</div>}
    </section>
  );
}
