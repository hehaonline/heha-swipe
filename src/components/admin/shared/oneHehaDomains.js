export const ONE_HEHA_DOMAINS = [
  {
    id: "ctrl",
    number: "01",
    code: "CTRL",
    label: "Control Center",
    color: "#49B654",
    purpose: "Governance, approvals, finance, issues, settings, audit, and source-of-truth controls.",
    modules: [
      { id: "routing", label: "Partner Routing", description: "Approve where partners appear and how customers reach them.", accessKey: "routing", area: "routing" },
      { id: "approvals", label: "Requests & Approvals", description: "Send or review a protected request through the shared HEHA control flow.", href: "https://hehalocal.app/admin/requests", requestHref: "https://hehalocal.app/request-help?domain=CTRL&type=approval" },
      { id: "finance", label: "Finance Governance", description: "HEHA Local remains the operational finance and payout workspace.", href: "https://hehalocal.app/admin" },
      { id: "issues", label: "Issues & Risks", description: "HEHA Local command-center issues, escalations, and launch blockers.", href: "https://hehalocal.app/admin" },
    ],
  },
  {
    id: "ops",
    number: "02",
    code: "OPS",
    label: "Operations & Service Delivery",
    color: "#F47C35",
    purpose: "Orders, dispatch, customers, partners, drivers, catering, payouts, support, and incidents.",
    modules: [
      { id: "local-ops", label: "Open HEHA Local Operations", description: "Canonical home for orders, dispatch, customers, partners, drivers, payouts, and service delivery.", href: "https://hehalocal.app/admin" },
      { id: "som", label: "SOM Growth Handoff", description: "Scout and partner handoff for Sales Operations.", accessKey: "som", area: "som" },
    ],
  },
  {
    id: "tech",
    number: "03",
    code: "TECH",
    label: "Product & Technology",
    color: "#3478F6",
    purpose: "Products, Supabase, integrations, automations, releases, bugs, security, and architecture.",
    modules: [
      { id: "swipe-system", label: "HEHA Swipe System", description: "Current application, roles, routing, realtime dashboards, and release work.", status: "active" },
      { id: "local-system", label: "HEHA Local / Order Hub", description: "Operational product and canonical-backend candidate.", href: "https://hehalocal.app/admin" },
      { id: "architecture", label: "Architecture Decisions", description: "ADR-001 and canonical-backend consolidation remain approval-gated.", status: "gated", requestHref: "https://hehalocal.app/request-help?domain=TECH&type=approval" },
    ],
  },
  {
    id: "grow",
    number: "04",
    code: "GROW",
    label: "Growth & Partnerships",
    color: "#8B4DE8",
    purpose: "Scout pipeline, onboarding, readiness, sales follow-up, partnerships, and expansion.",
    modules: [
      { id: "scout", label: "Scout & Partner Pipeline", description: "Capture field visits and potential HEHA leads once.", accessKey: "scout", area: "scout" },
      { id: "pm", label: "Partner Readiness / PM", description: "Myren workflow, missing items, tasks, deals, visibility, and weekly reports.", accessKey: "pm", area: "pm" },
    ],
  },
  {
    id: "comm",
    number: "05",
    code: "COMM",
    label: "Brand, Content & Community",
    color: "#F5B82E",
    purpose: "Brand, content, HEHA Journal, events, community activation, media, offers, and launch assets.",
    modules: [
      { id: "community", label: "Community / Events", description: "Events, venues, outreach, applications, and recaps.", accessKey: "community", area: "community" },
      { id: "media-review", label: "Items, Ingredients & Media Review", description: "Meals, structured ingredients, estimated macros, photos, and HEHA Reviewed decisions live in HEHA Local.", href: "https://hehalocal.app/admin" },
    ],
  },
];

export function visibleDomains(access) {
  return ONE_HEHA_DOMAINS.map((domain) => ({
    ...domain,
    modules: domain.modules.map((module) => ({
      ...module,
      available: !module.accessKey || Boolean(access[module.accessKey]),
      requestHref:
        module.requestHref ||
        `https://hehalocal.app/request-help?domain=${domain.code}&type=${module.accessKey ? "approval" : "support"}&subject=${encodeURIComponent(module.label)}`,
    })),
  }));
}
