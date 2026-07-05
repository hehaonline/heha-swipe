export const scoutLeadTypes = ["potential_partner", "heha_swipe_business", "event_partner", "event_venue", "event_vendor", "sponsor", "artist_musician", "community_organization", "app_affiliate_partner"];

export const scoutBusinessFields = [
  { name: "business_name", label: "Business / lead name" },
  { name: "lead_type", label: "Lead type", type: "select", options: scoutLeadTypes },
  { name: "heha_pillar", label: "HEHA pillar", type: "select", options: ["nourish", "educate", "relax", "elevate"] },
  { name: "business_category", label: "Category" },
  { name: "neighborhood", label: "Neighborhood" },
  { name: "tagline", label: "Swipe card headline" },
  { name: "bio", label: "Business bio", type: "textarea" },
  { name: "hours", label: "Hours" },
  { name: "address", label: "Address" },
  { name: "city", label: "City" },
  { name: "state", label: "State" },
  { name: "postal_code", label: "ZIP" },
  { name: "phone", label: "Phone" },
  { name: "email", label: "Email" },
  { name: "website", label: "Website" },
  { name: "instagram", label: "Instagram" },
  { name: "google_maps_url", label: "Google Maps URL" },
];
