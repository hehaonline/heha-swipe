import { supabase } from "../../../lib/supabase";

const EVENT_TYPES = ["event_partner", "event_venue", "event_vendor", "sponsor", "artist_musician", "community_organization"];

export async function createScoutFollowupTask(row, userId) {
  const { data: lead, error } = await supabase
    .from("scout_leads")
    .select("id, business_name, lead_type, partner_id, pm_task_id")
    .eq("id", row.id)
    .single();
  if (error) throw error;
  if (lead.pm_task_id) return;

  const eventLead = EVENT_TYPES.includes(lead.lead_type);
  const name = lead.business_name || "Untitled scout lead";
  const { data: task, error: taskError } = await supabase
    .from("admin_pm_tasks")
    .insert({
      task_title: `Review scout lead — ${name}`,
      related_partner_id: lead.partner_id || null,
      related_type: "scout_lead",
      category: eventLead ? "community_events" : "pm_myren",
      priority: "medium",
      status: "todo",
      next_step: eventLead ? "Review event fit and prepare follow-up." : "Research lead and prepare outreach.",
      approval_needed: false,
      notes: "Created from Scout & Partner Pipeline.",
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
}
