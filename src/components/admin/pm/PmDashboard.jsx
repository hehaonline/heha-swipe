import AdminWorkspace from "../shared/AdminWorkspace";

const statusVisibility = ["hidden", "draft", "needs_update", "ready", "live", "paused", "error_broken_link", "not_applicable"];

const pmTabs = [
  {
    id: "readiness", label: "Partner Readiness", table: "admin_partner_readiness", primary: "business_name", secondary: "partner_category", status: "pipeline_status", help: "Partner onboarding and profile readiness.",
    initial: { business_name: "", partner_category: "", pipeline_status: "new_lead", profile_status: "draft", next_step: "", blocker: "", due_date: "", approval_needed: false, internal_notes: "" },
    fields: [
      { name: "business_name", label: "Business name", required: true }, { name: "partner_category", label: "Category" },
      { name: "pipeline_status", label: "Pipeline", type: "select", options: ["new_lead", "contacted", "interested", "application_started", "profile_draft", "missing_info", "content_needed", "ready_for_geronimo_review", "approved_to_list", "listed_not_certified", "certification_review_pending", "certified_verified", "paused", "rejected", "archived"] },
      { name: "profile_status", label: "Profile", type: "select", options: ["draft", "missing_required_info", "missing_assets", "needs_content_review", "ready_for_geronimo_review", "approved", "live", "paused", "needs_update"] },
      { name: "next_step", label: "Next step" }, { name: "blocker", label: "Blocker" }, { name: "due_date", label: "Due", type: "date" },
      { name: "approval_needed", label: "Needs Geronimo approval", type: "checkbox" }, { name: "internal_notes", label: "Notes", type: "textarea" },
    ],
  },
  {
    id: "missing", label: "Missing Items", table: "admin_missing_items", primary: "missing_item_type", secondary: "follow_up_method", status: "status", help: "Missing photos, copy, menus, links, or proof points.",
    initial: { missing_item_type: "", status: "open", due_date: "", follow_up_method: "", escalation_needed: false, notes: "" },
    fields: [
      { name: "missing_item_type", label: "Missing item", required: true }, { name: "status", label: "Status", type: "select", options: ["open", "assigned", "waiting_on_business", "waiting_on_content_team", "waiting_on_geronimo", "received", "completed", "paused"] },
      { name: "due_date", label: "Due", type: "date" }, { name: "follow_up_method", label: "Follow-up" }, { name: "escalation_needed", label: "Escalate", type: "checkbox" }, { name: "notes", label: "Notes", type: "textarea" },
    ],
  },
  {
    id: "deals", label: "Deals / Offers", table: "admin_deal_requests", primary: "deal_title", secondary: "deal_type", status: "approval_status", help: "Community Pass, Swoop, SuperSwoop, and event offers.",
    initial: { deal_title: "", deal_type: "general_discount", proposed_discount: "", deal_terms: "", redemption_method: "", start_date: "", end_date: "", content_needed: false, approval_status: "draft", final_status: "draft", risk_notes: "" },
    fields: [
      { name: "deal_title", label: "Deal title", required: true }, { name: "deal_type", label: "Type", type: "select", options: ["community_pass", "swoop", "superswoop", "founding_partner_offer", "general_discount", "event_offer"] },
      { name: "proposed_discount", label: "Discount" }, { name: "redemption_method", label: "Redemption" }, { name: "start_date", label: "Start", type: "date" }, { name: "end_date", label: "End", type: "date" },
      { name: "content_needed", label: "Content needed", type: "checkbox" }, { name: "approval_status", label: "Approval", type: "select", options: ["draft", "needs_geronimo_review", "changes_requested", "rejected", "paused"] },
      { name: "deal_terms", label: "Terms", type: "textarea" }, { name: "risk_notes", label: "Risk notes", type: "textarea" },
    ],
  },
  {
    id: "visibility", label: "Platform Visibility", table: "admin_platform_visibility", primary: "heha_swipe_status", secondary: "heha_local_status", status: "wix_status", help: "Swipe, Local, Wix, HubSpot, Instagram, and newsletter visibility.",
    initial: { heha_swipe_status: "draft", heha_local_status: "draft", wix_status: "draft", hubspot_status: "not_applicable", instagram_status: "not_applicable", newsletter_status: "not_applicable", heha_swipe_url: "", heha_local_url: "", wix_url: "", mismatch_notes: "" },
    fields: [
      { name: "heha_swipe_status", label: "Swipe", type: "select", options: statusVisibility }, { name: "heha_local_status", label: "Local", type: "select", options: statusVisibility }, { name: "wix_status", label: "Wix", type: "select", options: statusVisibility },
      { name: "hubspot_status", label: "HubSpot", type: "select", options: statusVisibility }, { name: "instagram_status", label: "Instagram", type: "select", options: statusVisibility }, { name: "newsletter_status", label: "Newsletter", type: "select", options: statusVisibility },
      { name: "heha_swipe_url", label: "Swipe URL" }, { name: "heha_local_url", label: "Local URL" }, { name: "wix_url", label: "Wix URL" }, { name: "mismatch_notes", label: "Mismatch notes", type: "textarea" },
    ],
  },
  {
    id: "content", label: "Content Requests", table: "admin_content_requests", filter: { type: "eq", column: "dashboard_area", value: "pm" }, defaults: { dashboard_area: "pm" }, primary: "request_title", secondary: "request_type", status: "status", help: "Partner profile copy, images, flyers, listings, and launch assets.",
    initial: { request_title: "", request_type: "partner_profile", priority: "medium", needed_by: "", key_message: "", canva_link: "", notes: "", status: "requested" },
    fields: [
      { name: "request_title", label: "Title", required: true }, { name: "request_type", label: "Type" }, { name: "priority", label: "Priority", type: "select", options: ["low", "medium", "high", "critical"] }, { name: "needed_by", label: "Needed", type: "date" }, { name: "canva_link", label: "Canva" }, { name: "key_message", label: "Message", type: "textarea" }, { name: "notes", label: "Notes", type: "textarea" },
    ],
  },
  {
    id: "tasks", label: "PM Tasks", table: "admin_pm_tasks", primary: "task_title", secondary: "category", status: "status", help: "Team tasks, blockers, next steps, and approval needs.",
    initial: { task_title: "", category: "pm_myren", priority: "medium", due_date: "", status: "todo", blocker: "", next_step: "", approval_needed: false, notes: "" },
    fields: [
      { name: "task_title", label: "Task", required: true }, { name: "category", label: "Category", type: "select", options: ["app_shahid", "wix_raj", "content", "outreach_shakil", "pm_myren", "approval_geronimo", "hubspot", "google_sheets", "qa"] }, { name: "priority", label: "Priority", type: "select", options: ["low", "medium", "high", "critical"] }, { name: "due_date", label: "Due", type: "date" }, { name: "status", label: "Status", type: "select", options: ["todo", "in_progress", "waiting", "blocked", "needs_approval", "completed", "paused"] }, { name: "approval_needed", label: "Needs approval", type: "checkbox" }, { name: "blocker", label: "Blocker", type: "textarea" }, { name: "next_step", label: "Next step", type: "textarea" }, { name: "notes", label: "Notes", type: "textarea" },
    ],
  },
  {
    id: "weekly", label: "Weekly Reports", table: "admin_weekly_reports", primary: "report_week", secondary: "next_week_focus", status: "report_status", help: "Weekly recap for Geronimo: wins, blockers, approvals, next focus.",
    initial: { report_week: "", what_moved_forward: "", blockers: "", geronimo_approval_needed: "", closest_to_live: "", next_week_focus: "", report_status: "draft" },
    fields: [
      { name: "report_week", label: "Week", type: "date", required: true }, { name: "report_status", label: "Status", type: "select", options: ["draft", "ready_for_review", "sent", "archived"] }, { name: "what_moved_forward", label: "Moved forward", type: "textarea" }, { name: "blockers", label: "Blockers", type: "textarea" }, { name: "geronimo_approval_needed", label: "Approvals needed", type: "textarea" }, { name: "closest_to_live", label: "Closest to live", type: "textarea" }, { name: "next_week_focus", label: "Next focus", type: "textarea" },
    ],
  },
];

export default function PmDashboard({ final }) {
  return <AdminWorkspace lane="PM / Partner Operations" title="Myren Project Manager Dashboard" subtitle="Protected internal workspace for partner readiness, missing items, content requests, deals, visibility QA, PM tasks, and weekly reporting. Myren coordinates; Geronimo approves final public decisions." final={final} tabs={pmTabs} overview={[{ eyebrow: "Boundary", title: "Project management, not ownership transfer.", body: "Myren coordinates partner workflow. Final HEHA decisions stay with Geronimo." }]} />;
}
