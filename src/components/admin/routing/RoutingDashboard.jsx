import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { AdminCard, Guard } from "../shared/AdminPrimitives";

const LANES = ["meals", "market", "vendors", "chef", "group_orders"];
const PILLARS = ["nourish", "educate", "relax", "elevate"];
const DESTINATIONS = ["local", "swipe", "external"];

function laneDefaults(lane, partnerId) {
  const config = {
    meals: ["Order Meals", "/restaurants"],
    market: ["Explore Market", "/market"],
    vendors: ["Shop Local Vendor", "/vendors"],
    chef: ["Explore Chef", "/chef"],
    group_orders: ["Group Orders", "/group-orders"],
  };
  return config[lane] || ["Discover Partner", `/?partner=${partnerId}`];
}

function formFrom(partner) {
  return {
    heha_pillar: partner?.heha_pillar || "",
    website_eligible: Boolean(partner?.website_eligible),
    swipe_eligible: Boolean(partner?.swipe_eligible),
    local_eligible: Boolean(partner?.local_eligible),
    local_lane: partner?.local_lane || "",
    primary_cta_destination: partner?.primary_cta_destination || "swipe",
    primary_cta_label: partner?.primary_cta_label || "Discover Partner",
    primary_cta_path: partner?.primary_cta_path || (partner?.id ? `/?partner=${partner.id}` : ""),
    routing_notes: partner?.routing_notes || "",
  };
}

export default function RoutingDashboard({ final = false }) {
  const [partners, setPartners] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [form, setForm] = useState(formFrom(null));
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("needs_review");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");

  useEffect(() => { loadPartners(); }, []);

  const selected = useMemo(() => partners.find((partner) => partner.id === selectedId) || null, [partners, selectedId]);

  useEffect(() => {
    if (selected) setForm(formFrom(selected));
  }, [selected?.id]);

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return partners.filter((partner) => {
      if (statusFilter !== "all" && partner.routing_status !== statusFilter) return false;
      if (!needle) return true;
      return [partner.name, partner.category, partner.business_type, partner.neighborhood, partner.local_lane]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(needle);
    });
  }, [partners, query, statusFilter]);

  const counts = useMemo(() => ({
    review: partners.filter((partner) => partner.routing_status === "needs_review").length,
    approved: partners.filter((partner) => partner.routing_status === "approved").length,
    local: partners.filter((partner) => partner.local_eligible).length,
  }), [partners]);

  async function loadPartners() {
    setLoading(true);
    const { data, error } = await supabase
      .from("partners")
      .select("id,name,status,category,business_type,neighborhood,website,heha_pillar,website_eligible,swipe_eligible,local_eligible,local_lane,primary_cta_destination,primary_cta_label,primary_cta_path,routing_status,routing_notes,routing_updated_at")
      .order("updated_at", { ascending: false })
      .limit(400);

    if (error) setNotice(error.message);
    else {
      setPartners(data || []);
      setSelectedId((current) => current || data?.[0]?.id || null);
    }
    setLoading(false);
  }

  function update(key, value) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function setLocalEligible(enabled) {
    setForm((current) => {
      if (!enabled) {
        return {
          ...current,
          local_eligible: false,
          local_lane: "",
          primary_cta_destination: current.primary_cta_destination === "local" ? "swipe" : current.primary_cta_destination,
          primary_cta_label: current.primary_cta_destination === "local" ? "Discover Partner" : current.primary_cta_label,
          primary_cta_path: current.primary_cta_destination === "local" ? `/?partner=${selected?.id}` : current.primary_cta_path,
        };
      }
      const lane = current.local_lane || "meals";
      const [label, path] = laneDefaults(lane, selected?.id);
      return { ...current, local_eligible: true, local_lane: lane, primary_cta_destination: "local", primary_cta_label: label, primary_cta_path: path };
    });
  }

  function setLane(lane) {
    const [label, path] = laneDefaults(lane, selected?.id);
    setForm((current) => ({ ...current, local_lane: lane, local_eligible: true, primary_cta_destination: "local", primary_cta_label: label, primary_cta_path: path }));
  }

  function setDestination(destination) {
    setForm((current) => {
      if (destination === "local") {
        const lane = current.local_lane || "meals";
        const [label, path] = laneDefaults(lane, selected?.id);
        return { ...current, local_eligible: true, local_lane: lane, primary_cta_destination: destination, primary_cta_label: label, primary_cta_path: path };
      }
      if (destination === "swipe") {
        return { ...current, primary_cta_destination: destination, primary_cta_label: "Discover Partner", primary_cta_path: `/?partner=${selected?.id}` };
      }
      return { ...current, primary_cta_destination: destination, primary_cta_label: "Learn More", primary_cta_path: selected?.website || "" };
    });
  }

  async function save(finalize = false) {
    if (!selected) return;
    setSaving(true);
    const { error } = await supabase.rpc("review_partner_routing", {
      p_partner_id: selected.id,
      p_heha_pillar: form.heha_pillar || null,
      p_website_eligible: form.website_eligible,
      p_swipe_eligible: form.swipe_eligible,
      p_local_eligible: form.local_eligible,
      p_local_lane: form.local_eligible ? form.local_lane || null : null,
      p_primary_cta_destination: form.primary_cta_destination || null,
      p_primary_cta_label: form.primary_cta_label || null,
      p_primary_cta_path: form.primary_cta_path || null,
      p_routing_notes: form.routing_notes || null,
      p_finalize: finalize,
    });

    setNotice(error ? error.message : finalize ? "Routing finalized by Admin." : "Routing review saved for Admin approval.");
    setSaving(false);
    if (!error) await loadPartners();
  }

  async function resetSuggestion() {
    if (!selected) return;
    setSaving(true);
    const { error } = await supabase.rpc("reset_partner_routing_suggestion", { p_partner_id: selected.id });
    setNotice(error ? error.message : "Routing suggestion regenerated from partner classification.");
    setSaving(false);
    if (!error) await loadPartners();
  }

  return (
    <main className="admin-panel">
      {notice && <div className="admin-toast">{notice}</div>}
      <AdminCard eyebrow="Canonical Partner Routing" title="Website × HEHA Local × HEHA Swipe" wide>
        <p>Website is broad intentional search. HEHA Local is food and ordering utility. HEHA Swipe is discovery. Myren can review routing; only Geronimo can finalize it.</p>
      </AdminCard>
      <Guard final={final} lane="partner routing" />

      <section className="routing-metrics">
        <div><strong>{counts.review}</strong><span>Needs review</span></div>
        <div><strong>{counts.approved}</strong><span>Finalized</span></div>
        <div><strong>{counts.local}</strong><span>Local eligible</span></div>
      </section>

      <section className="routing-layout">
        <aside className="routing-list admin-card">
          <div className="routing-filters">
            <input placeholder="Search partners" value={query} onChange={(event) => setQuery(event.target.value)} />
            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              <option value="needs_review">Needs review</option>
              <option value="approved">Finalized</option>
              <option value="suggested">Suggested</option>
              <option value="paused">Paused</option>
              <option value="all">All</option>
            </select>
          </div>
          {loading ? <p>Loading routing queue…</p> : visible.map((partner) => (
            <button key={partner.id} className={selectedId === partner.id ? "routing-row active" : "routing-row"} onClick={() => setSelectedId(partner.id)}>
              <strong>{partner.name}</strong>
              <span>{[partner.category, partner.business_type, partner.local_lane].filter(Boolean).join(" · ")}</span>
              <small>{partner.routing_status}</small>
            </button>
          ))}
        </aside>

        <section className="routing-editor admin-crud">
          {!selected ? <p>Select a partner.</p> : (
            <>
              <p className="eyebrow">{selected.status} · {selected.routing_status}</p>
              <h2>{selected.name}</h2>
              <p>{[selected.category, selected.business_type, selected.neighborhood].filter(Boolean).join(" · ")}</p>

              <div className="admin-form routing-form">
                <label><span>HEHA pillar</span><select value={form.heha_pillar} onChange={(event) => update("heha_pillar", event.target.value)}><option value="">Not chosen</option>{PILLARS.map((pillar) => <option key={pillar} value={pillar}>{pillar}</option>)}</select></label>

                <label className="admin-checkbox-field"><input type="checkbox" checked={form.website_eligible} onChange={(event) => update("website_eligible", event.target.checked)} /><span>Website Directory</span></label>
                <label className="admin-checkbox-field"><input type="checkbox" checked={form.swipe_eligible} onChange={(event) => update("swipe_eligible", event.target.checked)} /><span>HEHA Swipe</span></label>
                <label className="admin-checkbox-field"><input type="checkbox" checked={form.local_eligible} onChange={(event) => setLocalEligible(event.target.checked)} /><span>HEHA Local</span></label>

                <label><span>HEHA Local lane</span><select disabled={!form.local_eligible} value={form.local_lane} onChange={(event) => setLane(event.target.value)}><option value="">Not applicable</option>{LANES.map((lane) => <option key={lane} value={lane}>{lane}</option>)}</select></label>
                <label><span>Primary CTA destination</span><select value={form.primary_cta_destination} onChange={(event) => setDestination(event.target.value)}>{DESTINATIONS.map((destination) => <option key={destination} value={destination}>{destination}</option>)}</select></label>
                <label><span>CTA label</span><input value={form.primary_cta_label} onChange={(event) => update("primary_cta_label", event.target.value)} /></label>
                <label className="wide"><span>CTA path / URL</span><input value={form.primary_cta_path} onChange={(event) => update("primary_cta_path", event.target.value)} /></label>
                <label className="wide"><span>Routing notes</span><textarea value={form.routing_notes} onChange={(event) => update("routing_notes", event.target.value)} /></label>
              </div>

              <div className="routing-actions">
                <button disabled={saving} onClick={() => save(false)}>Save Review</button>
                {final && <button className="routing-finalize" disabled={saving} onClick={() => save(true)}>Finalize Routing</button>}
                <button disabled={saving} onClick={resetSuggestion}>Regenerate Suggestion</button>
              </div>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
