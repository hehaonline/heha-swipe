import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const ACTIVE_STATUSES = new Set(["issued", "confirmed_by_partner"]);

function formatCode(code) {
  const digits = String(code || "").replace(/\D/g, "").slice(0, 6);
  return digits.length === 6 ? `${digits.slice(0, 3)} ${digits.slice(3)}` : digits;
}

function formatTime(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
}

export default function CustomerOfferActivity({ user }) {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);
  const [problemDrafts, setProblemDrafts] = useState({});

  const activeRows = useMemo(
    () => rows.filter((row) => ACTIVE_STATUSES.has(row.status)),
    [rows]
  );

  const load = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    setError(null);

    try {
      const { data, error: queryError } = await supabase
        .from("community_offer_redemptions")
        .select("id, deal_request_id, partner_id, redemption_code, status, offer_title_snapshot, offer_text_snapshot, first_time_only_snapshot, issued_at, expires_at, partner_confirmed_at, customer_confirmed_at, customer_outcome, customer_problem_note, created_at")
        .eq("user_id", user.id)
        .in("status", ["issued", "confirmed_by_partner"])
        .order("created_at", { ascending: false })
        .limit(10);
      if (queryError) throw queryError;
      setRows(data || []);
    } catch (loadError) {
      setError(loadError.message || "Could not load your active Community Offers.");
    } finally {
      setLoading(false);
    }
  }, [user?.id]);

  useEffect(() => {
    load();
  }, [load]);

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
      setMessage(outcome === "all_good" ? "Offer confirmed. Thank you." : "Problem saved for HEHA follow-up.");
      await load();
    } catch (confirmError) {
      setError(confirmError.message || "Could not confirm this offer experience yet.");
    } finally {
      setBusyId(null);
    }
  };

  if (loading || (!activeRows.length && !error)) return null;

  return (
    <section className="customer-offer-activity card-like">
      <div className="customer-offer-activity-heading">
        <p className="eyebrow">Your active offers</p>
        <h2>Community Offer activity</h2>
        <p>Keep this screen handy while using a HEHA Community Offer.</p>
      </div>

      <div className="customer-offer-activity-list">
        {activeRows.map((row) => {
          const expired = row.status === "issued" && new Date(row.expires_at).getTime() <= Date.now();
          return (
            <article className="customer-offer-activity-card" key={row.id}>
              <h3>{row.offer_title_snapshot}</h3>
              <strong>{row.offer_text_snapshot}</strong>

              {row.status === "issued" && !expired && (
                <div className="redemption-code-panel compact">
                  <span>Show this code to the business</span>
                  <strong>{formatCode(row.redemption_code)}</strong>
                  <small>Valid until {formatTime(row.expires_at)}</small>
                </div>
              )}

              {row.status === "issued" && expired && (
                <div className="cp-billing-note">This code expired. Return to the saved business detail to activate the offer again.</div>
              )}

              {row.status === "confirmed_by_partner" && (
                <div className="redemption-confirm-panel compact">
                  <strong>Business confirmed the offer.</strong>
                  <p>Did you receive the Community Offer?</p>
                  <div className="redemption-confirm-actions">
                    <button className="primary-button" type="button" disabled={busyId === row.id} onClick={() => confirmOutcome(row, "all_good")}>Yes, all good</button>
                    <textarea
                      value={problemDrafts[row.id] || ""}
                      onChange={(event) => setProblemDrafts((current) => ({ ...current, [row.id]: event.target.value }))}
                      placeholder="Briefly tell HEHA what went wrong"
                    />
                    <button className="secondary-button" type="button" disabled={busyId === row.id || !String(problemDrafts[row.id] || "").trim()} onClick={() => confirmOutcome(row, "problem")}>I had a problem</button>
                  </div>
                </div>
              )}
            </article>
          );
        })}
      </div>

      <button className="secondary-button" type="button" onClick={load} disabled={loading}>Refresh offer activity</button>
      {message && <div className="success-banner">{message}</div>}
      {error && <div className="error-banner">{error}</div>}
    </section>
  );
}
