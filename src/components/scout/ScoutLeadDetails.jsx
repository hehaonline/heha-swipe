import { EVENT_TYPES } from "./scoutConfig";

export default function ScoutLeadDetails({ lead, contacts }) {
  const eventLead = EVENT_TYPES.has(lead.lead_type);

  return (
    <div className="scout-lead-details">
      <div className="scout-detail-grid">
        {lead.address && <div><strong>Address</strong><p>{[lead.address, lead.city, lead.state, lead.postal_code].filter(Boolean).join(", ")}</p></div>}
        {(lead.phone || lead.email) && <div><strong>Contact</strong><p>{[lead.phone, lead.email].filter(Boolean).join(" · ")}</p></div>}
        {(lead.website || lead.instagram) && <div><strong>Online</strong><p>{[lead.website, lead.instagram].filter(Boolean).join(" · ")}</p></div>}
        {lead.fit_score && <div><strong>HEHA fit</strong><p>{lead.fit_score}/5</p></div>}
        {lead.visit_notes && <div className="wide"><strong>Visit notes</strong><p>{lead.visit_notes}</p></div>}
        {lead.first_impression && <div className="wide"><strong>First impression</strong><p>{lead.first_impression}</p></div>}
        {lead.heha_fit_notes && <div className="wide"><strong>Why HEHA</strong><p>{lead.heha_fit_notes}</p></div>}
        {lead.potential_offer && <div className="wide"><strong>Potential offer</strong><p>{lead.potential_offer}</p></div>}
        {eventLead && (lead.event_capacity || lead.parking_notes || lead.rental_cost_notes) && (
          <div className="wide">
            <strong>Event space notes</strong>
            <p>{[
              lead.event_capacity && `Capacity: ${lead.event_capacity}`,
              lead.parking_notes && `Parking: ${lead.parking_notes}`,
              lead.rental_cost_notes && `Cost: ${lead.rental_cost_notes}`,
            ].filter(Boolean).join(" · ")}</p>
          </div>
        )}
      </div>

      {!!contacts.length && (
        <div className="scout-contact-list">
          {contacts.map((contact, index) => (
            <div key={contact.id}>
              <strong>{contact.contact_name || `Contact ${index + 1}`}</strong>
              <span>{[contact.contact_role, contact.phone, contact.email].filter(Boolean).join(" · ") || contact.notes || "Contact detail saved"}</span>
            </div>
          ))}
        </div>
      )}

      <div className="scout-task-note">
        <strong>Next handoff</strong>
        <p>{eventLead ? "Niña reviews event fit and establishes a second contact." : "Myren researches the business and establishes a second contact before outreach."}</p>
      </div>
    </div>
  );
}
