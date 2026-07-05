import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import ScoutLeadForm from "./scout/ScoutLeadForm";
import ScoutLeadCard from "./scout/ScoutLeadCard";
import {
  EVENT_TYPES,
  READINESS_STATUS,
  blankForm,
  leadPayload,
} from "./scout/scoutConfig";

export default function ScoutPipeline({ user, lens }) {
  const eventOnly = lens === "events";
  const [leads, setLeads] = useState([]);
  const [contactsByLead, setContactsByLead] = useState({});
  const [form, setForm] = useState(() => blankForm(lens));
  const [expandedLeadId, setExpandedLeadId] = useState(null);
  const [showForm, setShowForm] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  const loadPipeline = useCallback(async () => {
    setLoading(true);
    setError("");

    let query = supabase
      .from("scout_leads")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(200);

    if (eventOnly) query = query.in("lead_type", Array.from(EVENT_TYPES));

    const { data, error: leadError } = await query;
    if (leadError) {
      setError(leadError.message);
      setLoading(false);
      return;
    }

    const nextLeads = data || [];
    setLeads(nextLeads);

    if (!nextLeads.length) {
      setContactsByLead({});
      setLoading(false);
      return;
    }

    const { data: contacts, error: contactError } = await supabase
      .from("scout_contacts")
      .select("*")
      .in("lead_id", nextLeads.map((lead) => lead.id))
      .order("created_at", { ascending: true });

    if (contactError) setError(contactError.message);
    else {
      const grouped = (contacts || []).reduce((acc, contact) => {
        if (!acc[contact.lead_id]) acc[contact.lead_id] = [];
        acc[contact.lead_id].push(contact);
        return acc;
      }, {});
      setContactsByLead(grouped);
    }

    setLoading(false);
  }, [eventOnly]);

  useEffect(() => {
    loadPipeline();
  }, [loadPipeline]);

  useEffect(() => {
    setForm((current) => ({
      ...current,
      lead_type: eventOnly && !EVENT_TYPES.has(current.lead_type)
        ? "event_partner"
        : current.lead_type,
    }));
  }, [eventOnly]);

  const stats = useMemo(() => ({
    total: leads.length,
    newVisits: leads.filter((lead) => lead.pipeline_status === "new_visit").length,
    outreach: leads.filter((lead) => ["contact_ready", "outreach"].includes(lead.pipeline_status)).length,
    onboarding: leads.filter((lead) => ["responded", "onboarding", "partner"].includes(lead.pipeline_status)).length,
  }), [leads]);

  const createFollowupTask = async (leadId) => {
    const { data: lead, error: fetchError } = await supabase
      .from("scout_leads")
      .select("*")
      .eq("id", leadId)
      .single();

    if (fetchError) throw fetchError;
    if (lead.pm_task_id) return;

    const isEvent = EVENT_TYPES.has(lead.lead_type);
    const name = lead.business_name || lead.primary_contact_name || "Untitled scout lead";

    const { data: task, error: taskError } = await supabase
      .from("admin_pm_tasks")
      .insert({
        task_title: isEvent
          ? `Review event lead — ${name}`
          : `Research & establish second contact — ${name}`,
        related_partner_id: lead.partner_id || null,
        related_type: "scout_lead",
        category: isEvent ? "community_events" : "pm_myren",
        priority: "medium",
        status: "todo",
        next_step: isEvent
          ? "Research event fit, verify contact details, and establish a second contact."
          : "Verify the business, identify a second decision-maker or partnership contact, and prepare outreach.",
        approval_needed: false,
        notes: `Created automatically from Scout & Partner Pipeline lead ${lead.id}.`,
        created_by: user.id,
        updated_by: user.id,
      })
      .select("id")
      .single();

    if (taskError) throw taskError;

    const { error: linkError } = await supabase
      .from("scout_leads")
      .update({ pm_task_id: task.id, updated_by: user.id })
      .eq("id", lead.id);

    if (linkError) throw linkError;
  };

  const submitLead = async (event) => {
    event.preventDefault();
    setSaving(true);
    setError("");
    setNotice("");

    const { data, error: insertError } = await supabase
      .from("scout_leads")
      .insert(leadPayload(form, user.id))
      .select("id")
      .single();

    if (insertError) {
      setError(insertError.message);
      setSaving(false);
      return;
    }

    try {
      await createFollowupTask(data.id);
      setNotice("Lead saved. Draft/CRM artifacts were queued and the follow-up task was created.");
    } catch (taskError) {
      setNotice("Lead saved. The scout record is safe, but the follow-up task needs review.");
      setError(taskError.message);
    }

    setForm(blankForm(lens));
    setSaving(false);
    await loadPipeline();
  };

  const updateStatus = async (lead, pipelineStatus) => {
    setError("");

    const { error: leadError } = await supabase
      .from("scout_leads")
      .update({ pipeline_status: pipelineStatus, updated_by: user.id })
      .eq("id", lead.id);

    if (leadError) {
      setError(leadError.message);
      return;
    }

    if (lead.partner_id && READINESS_STATUS[pipelineStatus]) {
      await supabase
        .from("admin_partner_readiness")
        .update({ pipeline_status: READINESS_STATUS[pipelineStatus], updated_by: user.id })
        .eq("partner_id", lead.partner_id);
    }

    setLeads((current) => current.map((item) => (
      item.id === lead.id ? { ...item, pipeline_status: pipelineStatus } : item
    )));
  };

  return (
    <main className="scout-workspace">
      <section className="scout-hero">
        <div>
          <p className="internal-eyebrow">Scout & Partner Pipeline</p>
          <h1>{eventOnly ? "Event discovery pipeline" : "Turn real-world visits into HEHA follow-up."}</h1>
          <p>Add what you know now. Contact details are optional. HEHA keeps the lead internal and never publishes a Swipe listing without Admin approval.</p>
        </div>
        <button className="scout-primary-button" type="button" onClick={() => setShowForm((value) => !value)}>
          {showForm ? "Hide scout form" : "+ Scout a lead"}
        </button>
      </section>

      <section className="scout-stat-grid">
        <article><strong>{stats.total}</strong><span>Visible leads</span></article>
        <article><strong>{stats.newVisits}</strong><span>New visits</span></article>
        <article><strong>{stats.outreach}</strong><span>Contact / outreach</span></article>
        <article><strong>{stats.onboarding}</strong><span>Responded onward</span></article>
      </section>

      {notice && <div className="scout-notice">{notice}</div>}
      {error && <div className="scout-error">{error}</div>}

      {showForm && (
        <ScoutLeadForm
          form={form}
          setForm={setForm}
          eventOnly={eventOnly}
          saving={saving}
          onSubmit={submitLead}
        />
      )}

      <section className="scout-pipeline-section">
        <div className="scout-section-heading">
          <div><p className="internal-eyebrow">Shared CRM view</p><h2>{eventOnly ? "Event leads" : "Partner pipeline"}</h2></div>
          <button className="scout-secondary-button compact" type="button" onClick={loadPipeline}>Refresh</button>
        </div>

        {loading ? <div className="scout-empty">Loading scout leads…</div> : !leads.length ? <div className="scout-empty">No scout leads in this view yet.</div> : (
          <div className="scout-card-list">
            {leads.map((lead) => (
              <ScoutLeadCard
                key={lead.id}
                lead={lead}
                contacts={contactsByLead[lead.id] || []}
                expanded={expandedLeadId === lead.id}
                onToggle={() => setExpandedLeadId(expandedLeadId === lead.id ? null : lead.id)}
                onStatus={updateStatus}
              />
            ))}
          </div>
        )}
      </section>
    </main>
  );
}
