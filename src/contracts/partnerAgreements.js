const LEGAL_REVIEW_NOTICE =
  "Review draft only. HEHA must obtain category-specific legal approval before this version can be accepted or used for live orders.";

const COMMON_SECTIONS = [
  {
    title: "Parties, authority, and electronic records",
    paragraphs: [
      "The agreement identifies Healthy Habit LLC, the partner's legal entity and DBA, and the person authorized to sign for the partner.",
      "The signer separately consents to electronic records and signatures and may download the complete version before accepting it.",
    ],
  },
  {
    title: "Founding beta and publication",
    paragraphs: [
      "Participation begins as a private founding-beta setup. A signed agreement does not automatically publish, certify, activate payments, or make the partner orderable.",
      "HEHA may publish only after the partner profile, category requirements, test order, and final partner approval are complete.",
    ],
  },
  {
    title: "Data, brand, and customer trust",
    paragraphs: [
      "Each party may use the other party's approved names, logos, menus, products, and photos only to operate and promote the agreed HEHA relationship.",
      "Customer and operational data may be used only for the permitted order, support, safety, accounting, and legal purposes described in the approved agreement and privacy materials.",
    ],
  },
  {
    title: "Suspension, changes, and offboarding",
    paragraphs: [
      "Safety, license, insurance, fraud, privacy, payment, or service-quality concerns may pause new orders while the issue is reviewed.",
      "Material agreement changes require a new version and fresh acceptance. Prior accepted versions and receipts remain retained.",
    ],
  },
];

function agreement({ key, categories, title, summary, categorySections, activationGates }) {
  return {
    key,
    categories,
    title,
    version: `DRAFT-${key.toUpperCase().replaceAll("_", "-")}-2026-08-30`,
    status: "legal_review",
    effectiveDate: null,
    notice: LEGAL_REVIEW_NOTICE,
    summary,
    sections: [...categorySections, ...COMMON_SECTIONS],
    activationGates,
  };
}

export const PARTNER_AGREEMENT_DRAFTS = {
  restaurant: agreement({
    key: "restaurant",
    categories: ["Restaurant"],
    title: "HEHA Restaurant Founding Beta Agreement",
    summary:
      "Restaurant-specific terms for menu accuracy, order handling, delivery coordination, fees, tax responsibilities, disputes, customer contact, and Florida restaurant-delivery requirements.",
    categorySections: [
      {
        title: "Restaurant consent and commercial schedule",
        paragraphs: [
          "HEHA may not take or arrange restaurant orders until the restaurant gives express written or electronic consent through an approved agreement version.",
          "The final agreement must state every restaurant-paid or restaurant-absorbed fee, commission, charge, discount, promotion, payout rule, refund rule, and chargeback rule, and must identify the seller or merchant-of-record model.",
        ],
      },
      {
        title: "Menu, pricing, tax, and prohibited conduct",
        paragraphs: [
          "The final agreement must define menu and price-change permissions, alcohol restrictions, marketing rules, payment rules, prohibited conduct, and which party collects and remits each applicable tax.",
          "HEHA may alter a restaurant price only through the restaurant-consent mechanism approved for the final agreement.",
        ],
      },
      {
        title: "Orders, food safety, and delivery",
        paragraphs: [
          "The restaurant maintains required licenses and accurate hours, capacity, menu, ingredients, major-allergen information, substitutions, preparation timing, packaging, seals, and pickup handoff records.",
          "The final agreement must define delivery-partner insurance requirements and who pays for them, customer contact during preparation and delivery, incident response, recalls, disputes, refunds, and responsibility for restaurant, HEHA, courier, and customer errors.",
        ],
      },
      {
        title: "Florida restaurant-delivery protections",
        paragraphs: [
          "The final agreement may not require the restaurant to indemnify HEHA for harm caused by HEHA or HEHA personnel and may not impose an unreasonable limit on restaurant disputes.",
          "Listing removal, itemized customer checkout, ETA and delivery records, customer concern handling, and restaurant rating-response controls must match the approved Florida-law implementation.",
        ],
      },
    ],
    activationGates: [
      "Florida counsel approval and approval reference recorded",
      "DBPR license and location verified",
      "W-9, tax model, fees, payouts, refunds, and chargebacks approved",
      "Restaurant and delivery insurance requirements verified",
      "Alcohol ordering remains off unless separately approved",
      "Exact authenticated test order passes before publication",
    ],
  }),
  vendor: agreement({
    key: "vendor",
    categories: ["Vendor"],
    title: "HEHA Vendor Founding Beta Agreement",
    summary:
      "Vendor-specific terms for product listings, inventory, pricing, fulfillment, product compliance, returns, recalls, and approved claims.",
    categorySections: [
      {
        title: "Products, inventory, and claims",
        paragraphs: [
          "The vendor is responsible for accurate product names, descriptions, prices, inventory, ingredients, warnings, regulated claims, and availability.",
          "The final agreement defines prohibited products, substantiation for health or sustainability claims, substitutions, recalls, and stop-sale procedures.",
        ],
      },
      {
        title: "Fulfillment and commercial terms",
        paragraphs: [
          "The final agreement states fees, payouts, taxes, discounts, refunds, returns, chargebacks, packaging, pickup or delivery handoff, loss, damage, and fulfillment timeframes.",
        ],
      },
    ],
    activationGates: [
      "Counsel-approved vendor agreement version",
      "W-9 and applicable licenses or permits verified",
      "Product and prohibited-goods review complete",
      "Inventory and fulfillment test passes",
    ],
  }),
  market: agreement({
    key: "market",
    categories: ["Grocery", "FarmersMarket", "Market", "Markets"],
    title: "HEHA Grocery & Farmers Market Founding Beta Agreement",
    summary:
      "Market-specific terms for regulated food sales, vendor responsibility, traceability, weights, substitutions, cold chain, recalls, and pickup or delivery.",
    categorySections: [
      {
        title: "Market operator and seller responsibility",
        paragraphs: [
          "The agreement identifies whether the signer is the seller, market operator, or authorized representative for participating sellers and defines responsibility for every listed product.",
          "Applicable food, agriculture, weights-and-measures, cottage-food, labeling, and tax requirements must be verified before activation.",
        ],
      },
      {
        title: "Traceability, substitutions, and cold chain",
        paragraphs: [
          "The final agreement defines lot or source traceability, inventory changes, substitutions, variable-weight pricing, temperature controls, recalls, refunds, pickup, and delivery handoff.",
        ],
      },
    ],
    activationGates: [
      "Counsel-approved market agreement version",
      "Operator and seller authority verified",
      "Applicable FDACS/local permits and tax records verified",
      "Traceability, variable-price, and cold-chain test passes",
    ],
  }),
  catering: agreement({
    key: "catering",
    categories: ["Catering"],
    title: "HEHA Catering Founding Beta Agreement",
    summary:
      "Caterer-specific master terms plus a separately accepted event statement of work for each booked event.",
    categorySections: [
      {
        title: "Master catering relationship",
        paragraphs: [
          "The master agreement defines licenses, insurance, menus, pricing, deposits, cancellation rules, staffing, equipment, food safety, taxes, payments, refunds, and brand use.",
        ],
      },
      {
        title: "Event statement of work",
        paragraphs: [
          "Each event requires its own accepted statement of work covering date, venue, guest count, menu, allergens, service style, delivery or setup, staffing, equipment, timeline, event insurance, final price, deposit, cancellation, and change deadline.",
        ],
      },
    ],
    activationGates: [
      "Counsel-approved catering master agreement and event SOW",
      "Licenses, W-9, and event-appropriate insurance verified",
      "Deposit, cancellation, staffing, and fulfillment test passes",
      "Alcohol service remains off unless separately approved",
    ],
  }),
  solo_chef: agreement({
    key: "solo_chef",
    categories: ["Private Chef", "PrivateChef", "SoloChef", "MealPrep"],
    title: "HEHA Solo Chef & Meal Prep Founding Beta Agreement",
    summary:
      "Chef-specific terms that separate in-home personal-chef service from licensed meal preparation and delivery.",
    categorySections: [
      {
        title: "Service model and licensing",
        paragraphs: [
          "The onboarding flow must identify whether services are performed in the customer's home, prepared in a licensed facility, delivered as prepared meals, or supplied through another approved model.",
          "The final agreement applies the licenses, insurance, food-safety controls, facility rules, and customer disclosures required for the selected model.",
        ],
      },
      {
        title: "Bookings, menus, and customer premises",
        paragraphs: [
          "The final agreement defines scope, ingredients, allergens, substitutions, shopping, equipment, travel, access to customer premises, scheduling, cancellations, deposits, damages, cleanup, leftovers, and incident reporting.",
        ],
      },
    ],
    activationGates: [
      "Counsel confirms the exact chef/meal-prep operating model",
      "Licenses, W-9, background/safety needs, and insurance verified",
      "Booking, cancellation, and fulfillment test passes",
    ],
  }),
  driver: agreement({
    key: "driver",
    categories: ["Driver"],
    title: "HEHA Driver Services Agreement",
    summary:
      "Driver-specific terms for classification, eligibility, insurance, safety, custody, delivery proof, earnings, expenses, and customer data.",
    categorySections: [
      {
        title: "Classification and compensation",
        paragraphs: [
          "The final agreement may be offered only after counsel approves the worker-classification model and the product, scheduling, control, pay, expense, and tax design match that model.",
          "Pay, tips, reimbursements, deductions, payout timing, availability, acceptance, cancellation, deactivation, and dispute rights must be stated clearly.",
        ],
      },
      {
        title: "Eligibility, safety, and delivery custody",
        paragraphs: [
          "The final flow separately handles driving eligibility, motor-vehicle and background-check consent, vehicle and insurance evidence, food safety, pickup custody, tamper seals, temperature, delivery proof, incidents, accessibility, and customer-data limits.",
        ],
      },
    ],
    activationGates: [
      "Worker-classification review completed and approved",
      "Separate background/MVR consent and required notices approved",
      "License, vehicle, and insurance evidence verified",
      "Driver app pickup-to-delivery smoke test passes",
    ],
  }),
  som: agreement({
    key: "som",
    categories: ["SOM"],
    title: "HEHA SOM Team Agreement",
    summary:
      "Team-member terms for employment or engagement status, role authority, scheduling, pay, expenses, confidentiality, systems access, and customer support.",
    categorySections: [
      {
        title: "Role, employment status, and pay",
        paragraphs: [
          "The default review assumption is a W-2 nonexempt role unless counsel approves another classification. The final documents define duties, manager, schedule, timekeeping, pay, overtime, expenses, benefits, leave, and required policies.",
        ],
      },
      {
        title: "Authority, systems, and community care",
        paragraphs: [
          "The final agreement defines spending, discount, refund, publication, partner, and customer-communication authority; least-privilege system access; confidentiality; device security; incident escalation; and access removal at offboarding.",
        ],
      },
    ],
    activationGates: [
      "Employment/classification and wage-hour review completed",
      "Role description, pay, timekeeping, expenses, and policies approved",
      "Background/authorization needs and least-privilege access verified",
      "Support and escalation smoke test passes",
    ],
  }),
};

export function agreementKeyForListing(listing) {
  const categories = Array.isArray(listing?.categories) && listing.categories.length
    ? listing.categories
    : [listing?.category].filter(Boolean);
  const normalized = categories.map((value) => String(value || "").toLowerCase());
  const businessType = String(listing?.business_type || "").toLowerCase();
  const candidates = new Set();

  if (normalized.includes("restaurant")) candidates.add("restaurant");
  if (normalized.includes("catering")) candidates.add("catering");
  if (normalized.some((value) => ["privatechef", "private chef", "solochef", "solo chef", "mealprep", "meal prep"].includes(value))) candidates.add("solo_chef");
  if (normalized.includes("driver")) candidates.add("driver");
  if (normalized.includes("som")) candidates.add("som");
  if (normalized.some((value) => ["grocery", "farmersmarket", "market", "markets"].includes(value))) candidates.add("market");
  if (normalized.includes("vendor")) {
    candidates.add(/grocery|farmers?\s*market|produce market/.test(businessType) ? "market" : "vendor");
  }
  return candidates.size === 1 ? [...candidates][0] : null;
}

export function agreementDraftForListing(listing) {
  const key = agreementKeyForListing(listing);
  return key ? PARTNER_AGREEMENT_DRAFTS[key] || null : null;
}

export function renderAgreementText(template, partnerName = "Partner") {
  if (!template) return "";
  const lines = [
    template.title,
    `Version: ${template.version}`,
    `Partner: ${partnerName}`,
    "",
    template.notice || "",
    "",
    template.summary || "",
    "",
  ];

  template.sections?.forEach((section, index) => {
    lines.push(`${index + 1}. ${section.title}`);
    section.paragraphs?.forEach((paragraph) => lines.push(paragraph));
    lines.push("");
  });

  lines.push("ACTIVATION GATES");
  template.activationGates?.forEach((gate) => lines.push(`- ${gate}`));
  return lines.join("\n").trim();
}
