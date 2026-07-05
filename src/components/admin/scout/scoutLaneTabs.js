import { scoutBusinessFields } from "./scoutBusinessFields";
import { scoutEventFields, scoutVisitFields } from "./scoutVisitFields";

const partnerTypes = ["potential_partner", "heha_swipe_business", "app_affiliate_partner"];
const eventTypes = ["event_partner", "event_venue", "event_vendor", "sponsor", "artist_musician", "community_organization"];

function makeFields(types, withEvents) {
  const base = scoutBusinessFields.map((field) => field.name === "lead_type" ? { ...field, options: types } : field);
  return withEvents ? [...base, ...scoutVisitFields, ...scoutEventFields] : [...base, ...scoutVisitFields];
}

function makeTab(label, types, leadType, withEvents = false) {
  return {
    id: "scout",
    label,
    table: "scout_leads",
    filter: { type: "in", column: "lead_type", value: types },
    defaults: { source: "field_visit", pipeline_status: "new_visit", lead_type: leadType },
    primary: "business_name",
    secondary: "business_category",
    status: "pipeline_status",
    help: "Field visits and potential HEHA leads.",
    description: "Capture a field visit. Follow-up is routed automatically. Public listings still require Admin approval.",
    initial: { lead_type: leadType, pipeline_status: "new_visit", heha_pillar: "nourish", card_color: "#ff8a24" },
    fields: makeFields(types, withEvents),
    buttonLabel: "Save Scout Lead",
  };
}

export const partnerScoutTab = makeTab("Scout Leads", partnerTypes, "potential_partner");
export const eventScoutTab = makeTab("Scout / Venues", eventTypes, "event_partner", true);
export const allScoutTab = makeTab("Scout Pipeline", [...partnerTypes, ...eventTypes], "potential_partner", true);
