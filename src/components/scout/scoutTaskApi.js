import { supabase } from "../../lib/supabase";
import { EVENT_TYPES } from "./scoutConfig";

export async function createScoutFollowupTask(userId, leadId) {
  const { data: lead, error: fetchError } = await supabase
    .from("scout_leads")
    .select("*")
    .eq("id", leadId)
    .single();

  if (fetchError) throw fetchError;
  if (lead.pm_task_id) return lead.pm_task_id;

  const isEvent = EVENT_TYPES.has(lead.lead_type);
  const name = lead.business_name?.trim() || lead.primary_contact_name?.trim() || "Untitled scout lead";

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
      created_by: userId,
      updated_by: userId,
    })
    .select("id")
    .single();

  if (taskError) throw taskError;

  const { error: linkError } = await supabase
    .from("scout_leads")
    .update({ pm_task_id: task.id, updated_by: userId })
    .eq("id", lead.id);

  if (linkError) throw linkError;
  return task.id;
}
