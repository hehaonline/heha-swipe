import { EVENT_TYPES, LEAD_TYPES, PIPELINE_STATUSES, labelFor } from "./scoutConfig";
import ScoutLeadDetails from "./ScoutLeadDetails";

export default function ScoutLeadCard({ lead, contacts, expanded, onToggle, onStatus }) {
  const eventLead = EVENT_TYPES.has(lead.lead_type);
  const name = lead.business_name || lead.primary_contact_name || "Unnamed scout lead";
  const location = [lead.business_category, lead.city, lead.state].filter(Boolean).join(" · ");

  return (
    <article className="scout-lead-card">
      <div className="scout-lead-top">
        <div>
          <div className="scout-badge-row">
            <span>{labelFor(LEAD_TYPES, lead.lead_type)}</span>
            {lead.heha_pillar && <span>{lead.heha_pillar}</span>}
            {lead.partner_id && <span>Swipe draft</span>}
            {lead.event_application_id && <span>Event record</span>}
            {lead.pm_task_id && <span>Follow-up task</span>}
            {lead.partner_id && <span>HubSpot queued</span>}
          </div>
          <h3>{name}</h3>
          <p>{location || "Details can be added later."}</p>
        </div>
        <select value={lead.pipeline_status} onChange={(event) => onStatus(lead, event.target.value)}>
          {PIPELINE_STATUSES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
      </div>

      <div className="scout-contact-strip">
        <span>{contacts.length} researched contact{contacts.length === 1 ? "" : "s"}</span>
        {lead.primary_contact_name && <span>Met: {lead.primary_contact_name}{lead.primary_contact_role ? ` · ${lead.primary_contact_role}` : ""}</span>}
        <span>Workflow: {eventLead ? "Niña / Events" : "Myren / PM"}</span>
      </div>

      {expanded && <ScoutLeadDetails lead={lead} contacts={contacts} />}

      <button className="scout-expand-button" type="button" onClick={onToggle}>
        {expanded ? "Close details" : "Open lead"}
      </button>
    </article>
  );
}
