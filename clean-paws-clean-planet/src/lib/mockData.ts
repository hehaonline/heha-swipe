/**
 * Mock data for the Clean Paws, Clean Planet prototype.
 *
 * Everything here is demo content for a pitch prototype. No real bookings,
 * no confirmed partnerships, no verified eco claims. Copy intentionally uses
 * "potential partner", "pilot candidate", "demo profile", and
 * "self-reported" language so nothing reads as an official claim.
 */

export type PartnerStatus =
  | "Potential Anchor Partner"
  | "Potential Partner"
  | "Pilot Candidate"
  | "Self-Reported Eco Practices"
  | "HEHA Review Needed";

export type PartnerCategory =
  | "Salon Grooming Anchor"
  | "Mobile Groomer"
  | "Dog Walker"
  | "Pet Sitter"
  | "Eco Pet Product Vendor";

export interface Partner {
  slug: string;
  name: string;
  category: PartnerCategory;
  status: PartnerStatus;
  serviceArea: string;
  tagline: string;
  description: string;
  services: string[];
  ecoNotes: string;
  referralFit: string;
  customerJourney: string[];
  accent: "orange" | "moss" | "peach";
}

export const partners: Partner[] = [
  {
    slug: "barksuds-marina-westshore",
    name: "BarkSuds Marina Westshore District",
    category: "Salon Grooming Anchor",
    status: "Potential Anchor Partner",
    serviceArea: "Westshore / Marina District, Tampa",
    tagline: "A potential trusted salon anchor for in-person grooming.",
    description:
      "A grooming salon can serve as the trusted salon anchor for customers who prefer in-person grooming and recurring care. This is a demo profile illustrating how an established salon could anchor the network while mobile partners extend neighborhood coverage. BarkSuds has not officially joined — this concept page is for discussion only.",
    services: [
      "Full groom",
      "Bath & brush",
      "Nail trims",
      "Deshedding",
      "Ear cleaning",
      "Breed-specific styling",
    ],
    ecoNotes:
      "Partner-submitted practices (demo): low-waste bathing setup, refillable shampoo dispensers, and water-conscious wash stations. Eco details are illustrative and would be HEHA-reviewed before any public claim.",
    referralFit:
      "Strong fit as the in-person anchor. Customers who request salon appointments or recurring full grooms could be routed here first, with mobile partners covering overflow and outer ZIP codes.",
    customerJourney: [
      "Maria requests a full groom for her doodle and prefers a salon visit.",
      "HEHA Local reviews the request and suggests the anchor salon.",
      "The salon confirms a recurring every-4-weeks slot.",
      "Maria opts into a recurring care plan for consistent grooming.",
    ],
    accent: "orange",
  },
  {
    slug: "tampa-mobile-grooming",
    name: "Tampa Mobile Grooming Partner",
    category: "Mobile Groomer",
    status: "Pilot Candidate",
    serviceArea: "South Tampa, Westshore, Hyde Park",
    tagline: "Convenient curbside grooming that comes to the driveway.",
    description:
      "A demo profile for a mobile grooming van that brings full-service grooming to the customer's door. Mobile partners support convenience and neighborhood coverage, especially for anxious pets and busy households. Pilot candidate status means HEHA Local would review before any referrals are sent.",
    services: [
      "Mobile full groom",
      "Bath & tidy",
      "Nail trim",
      "Deshedding",
      "Sanitary trim",
    ],
    ecoNotes:
      "Self-reported eco practices (demo): route-batching by neighborhood to reduce drive time, and biodegradable shampoo options. Self-reported and not yet verified.",
    referralFit:
      "Great fit for route-based opportunities. Requests grouped by ZIP code could be batched into an efficient daily route, lowering mileage and wait times.",
    customerJourney: [
      "Devon requests a mobile bath for a senior dog who dislikes the car.",
      "HEHA Local groups nearby requests into one neighborhood route.",
      "The mobile partner confirms a same-week curbside window.",
      "Devon receives a reminder and a low-stress at-home groom.",
    ],
    accent: "moss",
  },
  {
    slug: "south-tampa-dog-walking",
    name: "South Tampa Dog Walking Partner",
    category: "Dog Walker",
    status: "Potential Partner",
    serviceArea: "South Tampa, Bayshore, Davis Islands",
    tagline: "Reliable midday walks and neighborhood check-ins.",
    description:
      "A demo profile for a local dog-walking service offering scheduled walks and basic visits. Useful as a recurring add-on alongside grooming so customers can handle more of their pet care through one local network.",
    services: [
      "30-minute walks",
      "60-minute walks",
      "Midday check-ins",
      "Puppy potty breaks",
    ],
    ecoNotes:
      "Self-reported eco practices (demo): walk-only routes within the neighborhood and compostable waste bags. Self-reported and not yet verified.",
    referralFit:
      "Natural recurring-revenue fit. Grooming customers often need walks too, so referrals can flow both directions within the local network.",
    customerJourney: [
      "Priya requests weekday midday walks for a high-energy pup.",
      "HEHA Local matches a walker covering her block.",
      "The walker confirms a recurring weekday schedule.",
      "Priya adds an occasional groom through the same network.",
    ],
    accent: "peach",
  },
  {
    slug: "senior-pet-comfort-care",
    name: "Senior Pet Comfort Care Partner",
    category: "Pet Sitter",
    status: "HEHA Review Needed",
    serviceArea: "Greater Tampa (in-home visits)",
    tagline: "Gentle in-home sitting and comfort visits for older pets.",
    description:
      "A demo profile for an in-home pet sitter focused on senior and special-needs pets. Comfort-first visits, medication reminders, and calm companionship. Marked HEHA Review Needed to show how the network flags profiles that require manual review before any public listing.",
    services: [
      "In-home sitting",
      "Daily comfort visits",
      "Medication reminders",
      "Feeding & companionship",
    ],
    ecoNotes:
      "Partner-submitted practices (demo): low-waste supplies and reusable comfort bedding. Details would be HEHA-reviewed before any eco statement is shown publicly.",
    referralFit:
      "Fits households that need gentle, recurring care between grooming visits. A good example of where manual review and trust really matter.",
    customerJourney: [
      "Sam requests calm in-home visits for a 14-year-old dog.",
      "HEHA Local flags the profile for review before matching.",
      "After review, a suitable sitter is suggested.",
      "Sam books recurring comfort visits with clear notes on file.",
    ],
    accent: "moss",
  },
  {
    slug: "eco-paw-balm-vendor",
    name: "Eco Paw Balm Vendor",
    category: "Eco Pet Product Vendor",
    status: "Self-Reported Eco Practices",
    serviceArea: "Ships across Tampa Bay",
    tagline: "Small-batch paw balm and low-waste pet-care add-ons.",
    description:
      "A demo profile for a local maker of paw balm and pet-care basics. Product vendors can offer eco-conscious add-ons at checkout or as a referral bonus. All product and ingredient details are partner-submitted and would be reviewed before any public claim.",
    services: [
      "Paw balm",
      "Low-waste grooming add-ons",
      "Refill program (demo)",
      "Gift bundles",
    ],
    ecoNotes:
      "Self-reported eco practices (demo): refillable tins, plastic-light packaging, and locally sourced ingredients where available. Self-reported and not yet verified.",
    referralFit:
      "An easy add-on for grooming and mobile partners. Eco product bundles can sweeten a recurring care plan without adding operational load.",
    customerJourney: [
      "After a groom, the customer is offered an eco add-on bundle.",
      "HEHA Local includes the vendor as an optional extra.",
      "The customer adds paw balm to a recurring plan.",
      "The vendor gains a recurring, referral-driven customer.",
    ],
    accent: "peach",
  },
  {
    slug: "carrollwood-mobile-spa",
    name: "Carrollwood Mobile Pet Spa Partner",
    category: "Mobile Groomer",
    status: "Pilot Candidate",
    serviceArea: "Carrollwood, Northdale, Citrus Park",
    tagline: "North Tampa mobile grooming for busy neighborhoods.",
    description:
      "A demo profile extending mobile coverage into North Tampa. Helps the network demonstrate route coverage beyond the urban core, which is exactly the kind of gap a referral network can fill.",
    services: ["Mobile full groom", "Bath & brush", "Nail trim", "De-matting"],
    ecoNotes:
      "Self-reported eco practices (demo): batched routes and water-conscious mobile setup. Self-reported and not yet verified.",
    referralFit:
      "Covers ZIP codes the anchor salon and South Tampa mobile partner may not reach, improving overall network availability.",
    customerJourney: [
      "A Carrollwood customer requests a mobile groom.",
      "HEHA Local routes the request to a North Tampa partner.",
      "The partner confirms a route-based window.",
      "The customer joins the network for recurring care.",
    ],
    accent: "orange",
  },
];

export interface ServiceCategory {
  slug: string;
  name: string;
  icon: string;
  blurb: string;
  group: "Grooming" | "Care" | "Eco";
}

export const services: ServiceCategory[] = [
  {
    slug: "salon-grooming",
    name: "Salon grooming",
    icon: "🛁",
    blurb: "Full in-person grooming at a trusted local salon anchor.",
    group: "Grooming",
  },
  {
    slug: "mobile-grooming",
    name: "Mobile grooming",
    icon: "🚐",
    blurb: "Curbside grooming that comes to the driveway.",
    group: "Grooming",
  },
  {
    slug: "nail-trims",
    name: "Nail trims",
    icon: "✂️",
    blurb: "Quick, low-stress nail trims as a standalone or add-on.",
    group: "Grooming",
  },
  {
    slug: "deshedding",
    name: "Deshedding",
    icon: "🪮",
    blurb: "Coat-care and deshedding treatments for heavy shedders.",
    group: "Grooming",
  },
  {
    slug: "dog-walking",
    name: "Dog walking",
    icon: "🦮",
    blurb: "Scheduled neighborhood walks and midday check-ins.",
    group: "Care",
  },
  {
    slug: "pet-sitting",
    name: "Pet sitting",
    icon: "🏠",
    blurb: "In-home sitting and comfort visits, including senior care.",
    group: "Care",
  },
  {
    slug: "eco-products",
    name: "Eco pet-care products",
    icon: "🌿",
    blurb: "Low-waste add-ons and partner-submitted eco product options.",
    group: "Eco",
  },
];

export type BookingStatus =
  | "New request"
  | "Reviewing"
  | "Sent to partner"
  | "Accepted"
  | "Completed"
  | "Follow-up needed";

export const bookingStatuses: BookingStatus[] = [
  "New request",
  "Reviewing",
  "Sent to partner",
  "Accepted",
  "Completed",
  "Follow-up needed",
];

export interface BookingRequest {
  id: string;
  customerName: string;
  petName: string;
  zip: string;
  service: string;
  preference: "Mobile" | "Salon" | "Either";
  suggestedPartner: string;
  status: BookingStatus;
  notes: string;
}

export const bookingRequests: BookingRequest[] = [
  {
    id: "REQ-1042",
    customerName: "Maria G.",
    petName: "Biscuit",
    zip: "33606",
    service: "Full groom",
    preference: "Salon",
    suggestedPartner: "BarkSuds Marina Westshore District",
    status: "New request",
    notes: "Doodle, prefers salon, asked about recurring every 4 weeks.",
  },
  {
    id: "REQ-1043",
    customerName: "Devon P.",
    petName: "Rosie",
    zip: "33611",
    service: "Mobile bath",
    preference: "Mobile",
    suggestedPartner: "Tampa Mobile Grooming Partner",
    status: "Reviewing",
    notes: "Senior dog, dislikes car rides. Wants curbside.",
  },
  {
    id: "REQ-1044",
    customerName: "Priya S.",
    petName: "Mango",
    zip: "33629",
    service: "Dog walking (weekdays)",
    preference: "Either",
    suggestedPartner: "South Tampa Dog Walking Partner",
    status: "Sent to partner",
    notes: "High-energy pup, midday walks Mon–Fri.",
  },
  {
    id: "REQ-1045",
    customerName: "Sam T.",
    petName: "Cooper",
    zip: "33625",
    service: "In-home sitting",
    preference: "Either",
    suggestedPartner: "Senior Pet Comfort Care Partner",
    status: "Reviewing",
    notes: "14yo dog, medication reminders. Profile flagged for review.",
  },
  {
    id: "REQ-1046",
    customerName: "Alex R.",
    petName: "Pepper",
    zip: "33618",
    service: "Mobile full groom",
    preference: "Mobile",
    suggestedPartner: "Carrollwood Mobile Pet Spa Partner",
    status: "Accepted",
    notes: "North Tampa, route-based window confirmed for Thursday.",
  },
  {
    id: "REQ-1047",
    customerName: "Jordan M.",
    petName: "Luna",
    zip: "33609",
    service: "Deshedding + nail trim",
    preference: "Salon",
    suggestedPartner: "BarkSuds Marina Westshore District",
    status: "Completed",
    notes: "Heavy shedder. Interested in eco add-on bundle next time.",
  },
  {
    id: "REQ-1048",
    customerName: "Casey L.",
    petName: "Olive",
    zip: "33607",
    service: "Full groom",
    preference: "Either",
    suggestedPartner: "Unassigned",
    status: "Follow-up needed",
    notes: "Left voicemail. Needs a callback to confirm preferred window.",
  },
];

export interface RoadmapPhase {
  phase: string;
  title: string;
  detail: string;
  state: "Prototype" | "Next" | "Later";
}

export const roadmapPhases: RoadmapPhase[] = [
  {
    phase: "Phase 1",
    title: "Partner interest + landing page",
    detail:
      "This prototype: pitch the concept, collect partner interest, and validate demand with simple intake forms.",
    state: "Prototype",
  },
  {
    phase: "Phase 2",
    title: "Manual referrals + intake forms",
    detail:
      "HEHA Local manually reviews requests and connects customers with approved partners. No automation yet.",
    state: "Next",
  },
  {
    phase: "Phase 3",
    title: "Partner dashboard + booking statuses",
    detail:
      "Partners see incoming referrals and update statuses. Light operational tooling replaces spreadsheets.",
    state: "Later",
  },
  {
    phase: "Phase 4",
    title: "Recurring care plans + Stripe deposits",
    detail:
      "Recurring schedules and deposit handling, added only once trust and demand are proven.",
    state: "Later",
  },
  {
    phase: "Phase 5",
    title: "HEHA Swipe discovery + local pet marketplace",
    detail:
      "Discovery-style browsing and a broader local pet-care marketplace, connected to the wider HEHA Local ecosystem.",
    state: "Later",
  },
];

export interface PartnerBenefit {
  title: string;
  detail: string;
  icon: string;
}

export const partnerBenefits: PartnerBenefit[] = [
  {
    title: "More referral leads",
    detail: "Receive local pet-care requests matched to your services and area.",
    icon: "📈",
  },
  {
    title: "Local visibility",
    detail: "A clean partner profile that highlights your services and coverage.",
    icon: "📍",
  },
  {
    title: "Optional recurring plans",
    detail: "Opt into recurring care leads for steadier, predictable bookings.",
    icon: "🔁",
  },
  {
    title: "Partner profile page",
    detail: "A demo-ready profile you can share and grow as the pilot expands.",
    icon: "🪪",
  },
  {
    title: "Manual approval first",
    detail: "HEHA Local reviews every partner before public listing or referrals.",
    icon: "✅",
  },
  {
    title: "Future HEHA Swipe discovery",
    detail: "Be positioned for discovery as the HEHA Local ecosystem grows.",
    icon: "✨",
  },
];

export interface CustomerBenefit {
  title: string;
  detail: string;
  icon: string;
}

export const customerBenefits: CustomerBenefit[] = [
  {
    title: "Less searching",
    detail: "One local network instead of calling around town.",
    icon: "🔎",
  },
  {
    title: "One simple request",
    detail: "Tell us about your pet once and let HEHA Local coordinate.",
    icon: "📝",
  },
  {
    title: "Salon or mobile",
    detail: "Choose in-person grooming, curbside convenience, or either.",
    icon: "🚐",
  },
  {
    title: "Pet profile notes",
    detail: "Share temperament, coat, and sensitivities so care fits your pet.",
    icon: "🐾",
  },
  {
    title: "Recurring schedules",
    detail: "Set a weekly, bi-weekly, or monthly preference for steady care.",
    icon: "📅",
  },
];

export interface Testimonial {
  quote: string;
  attribution: string;
  role: string;
}

/** Illustrative placeholder quotes — not real endorsements. */
export const testimonials: Testimonial[] = [
  {
    quote:
      "If this fills my slower weekdays with the right local referrals, that's real value — and keeping it community-first matters to us.",
    attribution: "Illustrative quote",
    role: "Grooming salon owner (placeholder)",
  },
  {
    quote:
      "Route-batched requests by neighborhood would cut my drive time and let me serve more pets in a day.",
    attribution: "Illustrative quote",
    role: "Mobile groomer (placeholder)",
  },
  {
    quote:
      "One request, then someone local I can trust reaches out. That's how pet care should feel.",
    attribution: "Illustrative quote",
    role: "Tampa pet owner (placeholder)",
  },
];

export const serviceOptions = [
  "Bath",
  "Full groom",
  "Nail trim",
  "Deshedding",
  "Teeth brushing",
  "Ear cleaning",
  "Dog walking",
  "Pet sitting",
  "Eco product add-ons",
];

export const partnerTypeOptions = [
  "Grooming salon",
  "Mobile groomer",
  "Dog walker",
  "Pet sitter",
  "Pet wellness / product vendor",
  "Referral partner",
];

export function getPartnerBySlug(slug: string): Partner | undefined {
  return partners.find((p) => p.slug === slug);
}
