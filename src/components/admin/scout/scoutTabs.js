import { scoutBusinessFields } from "./scoutBusinessFields";
import { scoutEventFields, scoutVisitFields } from "./scoutVisitFields";

const partnerTypes = ["potential_partner", "heha_swipe_business", "app_affiliate_partner"];
const eventTypes = ["event_partner", "event_venue", "event_vendor", "sponsor", "artist_musician", "community_organization"];

function scoutTab({ id, label, filter, event = false, leadType }) {
  return {
    id,
    label,
    table: "scout_leads",
    filter,
    defaults: { source: "field_visit", pipeline_status: "new_visit", lead_type: leadType },
    primary: "business_name",
    secondary: "business_category",
    status: "pipeline_status",
    help: event ? "Potential event partners, venues, vendors, and community leads." : "Field visits and potential HEHA partners.",
    description: "Add what you know now. Fields are optional. Partner readiness receives the next-step task and public HEHA Swipe visibility still requires Admin approval.",
    initial: { lead_type: leadType, pipeline_status: "new_visit", heha_pillar: "nourish", photo_emoji: "🏪", card_color: "#ff8a24" },
    fields: event ? [...scoutBusinessFields, ...scoutVisitFields, ...scoutEventFields] : [...scoutBusinessFields, ...scoutVisitFields],
    buttonLabel: "Save Scout Lead",
  };
}

export const partnerScoutTab = scoutTab({ id: "scout", label: "Scout Leads", filter: { type: "in", column: "lead_type", value: partnerTypes }, leadType: "potential_partner" });
export const eventScoutTab = scoutTab({ id: "scout", label: "Scout / Venues", filter: { type: "in", column: "lead_type", value: eventTypes }, event: true, leadType: "event_partner" });
export const allScoutTab = scoutTab({ id: "scout", label: "Scout Pipeline", leadType: "potential_partner" });
