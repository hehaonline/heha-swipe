import { supabase } from "../../lib/supabase";
import { EVENT_TYPES, READINESS_STATUS, leadPayload } from "./scoutConfig";
import { createScoutFollowupTask } from "./scoutTaskApi";

export async function loadScoutData(eventOnly) {
  let query = supabase.from("scout_leads").select("*").order("created_at", { ascending: false }).limit(200);
  if (eventOnly) query = query.in("lead_type", Array.from(EVENT_TYPES));

  const { data, error } = await query;
  if (error) throw error;
  const leads = data || [];
  if (!leads.length) return { leads, contactsByLead: {} };

  const { data: contacts, error: contactError } = await supabase
    .from("scout_contacts")
    .select("*")
    .in("lead_id", leads.map((lead) => lead.id))
    .order("created_at", { ascending: true });

  if (contactError) throw contactError;
  const contactsByLead = (contacts || []).reduce((grouped, contact) => {
    (grouped[contact.lead_id] ||= []).push(contact);
    return grouped;
  }, {});

  return { leads, contactsByLead };
}

export async function saveScoutLead(userId, form) {
  const { data, error } = await supabase
    .from("scout_leads")
    .insert(leadPayload(form, userId))
    .select("id")
    .single();

  if (error) throw error;
  await createScoutFollowupTask(userId, data.id);
  return data.id;
}

export async function setScoutStatus(userId, lead, pipelineStatus) {
  const { error } = await supabase
    .from("scout_leads")
    .update({ pipeline_status: pipelineStatus, updated_by: userId })
    .eq("id", lead.id);

  if (error) throw error;

  if (lead.partner_id && READINESS_STATUS[pipelineStatus]) {
    const { error: readinessError } = await supabase
      .from("admin_partner_readiness")
      .update({
        pipeline_status: READINESS_STATUS[pipelineStatus],
        updated_by: userId,
      })
      .eq("partner_id", lead.partner_id);

    if (readinessError) throw readinessError;
  }
}
