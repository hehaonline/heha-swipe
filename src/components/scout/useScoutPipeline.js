import { useCallback, useEffect, useMemo, useState } from "react";
import { EVENT_TYPES, blankForm } from "./scoutConfig";
import { loadScoutData, saveScoutLead, setScoutStatus } from "./scoutApi";

export default function useScoutPipeline(user, lens) {
  const [leads, setLeads] = useState([]);
  const [contactsByLead, setContactsByLead] = useState({});
  const [form, setForm] = useState(() => blankForm(lens));
  const [expandedLeadId, setExpandedLeadId] = useState(null);
  const [showForm, setShowForm] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  const eventOnly = lens === "events";

  useEffect(() => {
    if (eventOnly) {
      setForm((current) => EVENT_TYPES.has(current.lead_type)
        ? current
        : { ...current, lead_type: "event_partner" });
    }
  }, [eventOnly]);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = await loadScoutData(eventOnly);
      setLeads(data.leads);
      setContactsByLead(data.contactsByLead);
    } catch (loadError) {
      setError(loadError.message);
    } finally {
      setLoading(false);
    }
  }, [eventOnly]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const stats = useMemo(() => ({
    total: leads.length,
    newVisits: leads.filter((lead) => lead.pipeline_status === "new_visit").length,
    outreach: leads.filter((lead) => ["contact_ready", "outreach"].includes(lead.pipeline_status)).length,
    onboarding: leads.filter((lead) => ["responded", "onboarding", "partner"].includes(lead.pipeline_status)).length,
  }), [leads]);

  const submitLead = async (event) => {
    event.preventDefault();
    setSaving(true);
    setError("");
    setNotice("");
    try {
      await saveScoutLead(user.id, form);
      setForm(blankForm(lens));
      setNotice("Scout lead saved. Draft/CRM artifacts were queued and the follow-up task was created.");
      await refresh();
    } catch (saveError) {
      setError(saveError.message);
    } finally {
      setSaving(false);
    }
  };

  const updateStatus = async (lead, status) => {
    setError("");
    try {
      await setScoutStatus(user.id, lead, status);
      setLeads((current) => current.map((item) => (
        item.id === lead.id ? { ...item, pipeline_status: status } : item
      )));
    } catch (statusError) {
      setError(statusError.message);
    }
  };

  return {
    leads,
    contactsByLead,
    form,
    setForm,
    expandedLeadId,
    setExpandedLeadId,
    showForm,
    setShowForm,
    loading,
    saving,
    notice,
    error,
    eventOnly,
    stats,
    refresh,
    submitLead,
    updateStatus,
  };
}
