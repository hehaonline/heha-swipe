// src/AdminApp.jsx
// HEHA Swipe — Internal Admin Dashboard
// Read-only MVP shell. No write actions enabled.
// Security: public.user_roles is the ONLY source of truth for admin access.
// app_metadata is NOT used for authorization. Deny by default on any role failure.
// Column names and enum values match Nova's admin_pm_dashboard_foundation_v2 migration exactly.

import { useEffect, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";

// ─── Host gate ──────────────────────────────────────────────────────────────────────────────
const ADMIN_HOSTS = new Set(["admin.hehaswipe.app"]);

function isAllowedAdminHost() {
  const host = window.location.hostname;
  return ADMIN_HOSTS.has(host) || host === "localhost" || host === "127.0.0.1";
}

// ─── Role definitions ─────────────────────────────────────────────────────────────────────
const PM_DASHBOARD_ROLES = new Set(["super_admin", "pm_admin", "developer_admin"]);
const COMMUNITY_EVENT_ROLES = new Set(["super_admin", "community_events_admin", "developer_admin"]);
const INTERNAL_ROLES = new Set([
  "super_admin",
  "pm_admin",
  "developer_admin",
  "content_editor",
  "wix_support",
  "community_events_admin",
  "viewer",
]);

function hasAnyRole(roles, allowedRoles) {
  return roles.some((r) => allowedRoles.has(r));
}
// ─── Overview card definitions ─────────────────────────────────────────────────────────────────────────
// Column names and check-constraint enum values match Nova's migration exactly.
// filterType values:
//   "none"         — no WHERE clause, count all rows
//   "eq"           — single equality: .eq(col, val)
//   "in"           — inclusion list:  .in(col, vals)
//   "notIn"        — exclusion list:  .not(col, 'in', `(a,b,c)`)
//   "visibilityOr" — multi-column OR: .or(orClause) across 4 platform status fields
//
// REMOVED invalid values: new_submission, pending (generic), issue, error (generic), sync_ok, has_issue
const OVERVIEW_CARD_DEFS = [
  {
    label: "Active partner profiles",
    table: "admin_partner_readiness",
    filterType: "notIn",
    col: "pipeline_status",
    vals: ["paused", "rejected", "archived"],
    note: "Partners actively moving through the pipeline (excludes paused, rejected, archived).",
  },
  {
    label: "New submissions",
    table: "admin_partner_readiness",
    filterType: "in",
    col: "pipeline_status",
    vals: ["new_lead", "application_started", "profile_draft"],
    note: "New leads and draft profiles awaiting first review.",
  },
  {
    label: "Profiles missing info",
    table: "admin_partner_readiness",
    filterType: "in",
    col: "profile_status",
    vals: ["missing_required_info", "missing_assets", "needs_content_review"],
    note: "Partners with incomplete profiles that need follow-up.",
  },
  {
    label: "Missing assets",
    table: "admin_missing_items",
    filterType: "in",
    col: "status",
    vals: ["open", "assigned", "waiting_on_business", "waiting_on_content_team"],
    note: "Open missing-info and asset items across all partners.",
  },
  {
    label: "Deal requests",
    table: "admin_deal_requests",
    filterType: "in",
    col: "final_status",
    vals: ["draft", "info_needed", "content_needed", "ready_for_geronimo_review", "changes_requested"],
    note: "Community Pass / Swoop / SuperSwoop deals awaiting action.",
  },
  {
    label: "Certification reviews",
    table: "admin_certification_reviews",
    filterType: "in",
    col: "certification_status",
    vals: ["requested", "missing_info", "in_review", "needs_geronimo_decision"],
    note: "Track only. Geronimo approves all certification decisions.",
  },
  {
    label: "Visibility issues",
    table: "admin_platform_visibility",
    filterType: "visibilityOr",
    orClause: [
      "heha_swipe_status.eq.needs_update",
      "heha_swipe_status.eq.error_broken_link",
      "heha_local_status.eq.needs_update",
      "heha_local_status.eq.error_broken_link",
      "wix_status.eq.needs_update",
      "wix_status.eq.error_broken_link",
      "hubspot_status.eq.needs_update",
      "hubspot_status.eq.error_broken_link",
    ].join(","),
    note: "Swipe, Local, Wix, or HubSpot visibility mismatches needing attention.",
  },
  {
    label: "Needs Geronimo approval",
    table: "admin_approval_requests",
    filterType: "eq",
    col: "status",
    val: "needs_geronimo_review",
    note: "All risky items requiring Geronimo's final sign-off.",
  },
  {
    label: "HubSpot sync issues",
    table: "admin_hubspot_links",
    filterType: "in",
    col: "sync_status",
    vals: ["failed", "needs_review"],
    note: "Backend / Make.com only — no private token in frontend.",
  },
  {
    label: "Weekly report drafts",
    table: "admin_weekly_reports",
    filterType: "in",
    col: "report_status",
    vals: ["draft", "ready_for_review"],
    note: "Drafts staged for Geronimo review and sign-off.",
  },
];
// ─── PM section definitions ──────────────────────────────────────────────────────────────────────────
const PM_SECTIONS = [
  {
    title: "Overview / Today's Priorities",
    description: "High-level counts and the most urgent items needing attention today.",
    status: "MVP",
    items: ["Blocked partners", "Pending approvals", "Overdue tasks", "Flagged items"],
  },
  {
    title: "Partner Pipeline",
    description: "Track each partner from first lead to approved visibility.",
    status: "MVP",
    items: ["Status", "Owner", "Next step", "Due date", "Blocker", "HubSpot link", "Approval needed"],
  },
  {
    title: "Partner Profile Readiness",
    description: "Confirm each partner has the profile data needed for Wix, HEHA Local, and HEHA Swipe.",
    status: "MVP",
    items: ["Descriptions", "Logo / photos", "Menu / products / services", "Links", "Proof point", "Tags"],
  },
  {
    title: "Missing Info + Asset Tracker",
    description: "One queue for missing logos, photos, links, menu info, proof points, and approvals.",
    status: "MVP",
    items: ["Assigned to", "Due date", "Follow-up method", "Escalation needed", "Status"],
  },
  {
    title: "Deals / Discounts / Community Pass / SuperSwoop Queue",
    description: "Track deal requests without auto-approving them. Geronimo approves all deals.",
    status: "MVP",
    items: ["Deal type", "Terms", "Dates", "Redemption", "Content needed", "Geronimo approval"],
  },
  {
    title: "Listed But Not Certified Tracker",
    description: "Make sure listed partners are not confused with HEHA Certified / Verified partners.",
    status: "MVP",
    items: ["Certification status", "Missing review info", "Risk notes", "Badge status", "Geronimo decision"],
  },
  {
    title: "Platform Visibility Tracker",
    description: "Find mismatches across HEHA Swipe, HEHA Local, Wix, HubSpot, Instagram, and newsletter.",
    status: "MVP",
    items: ["Hidden", "Draft", "Needs update", "Ready", "Live", "Paused", "Broken link"],
  },
  {
    title: "HubSpot Sync / CRM Status",
    description: "Surface HubSpot link status. No private token in frontend. Backend / Make.com handles sync.",
    status: "MVP",
    items: ["Linked", "Not linked", "Sync error", "Last synced", "HubSpot owner"],
  },
  {
    title: "Content Request Module",
    description: "Request profile copy, deal cards, Canva graphics, social posts, and listing copy.",
    status: "MVP",
    items: ["Request type", "Assigned person", "Needed by", "Assets provided", "Approval needed"],
  },
  {
    title: "Geronimo Approval Queue",
    description: "All items requiring Geronimo's final approval before any action. Myren routes — Geronimo decides.",
    status: "MVP",
    items: ["Certification decisions", "Final deals", "Pricing changes", "Payment settings", "Public publishing", "Health / quality claims"],
  },
  {
    title: "Team Task + Blocker Tracker",
    description: "Track open tasks and blockers across the team for weekly reporting.",
    status: "MVP",
    items: ["Task owner", "Due date", "Blocker type", "Escalation", "Resolved"],
  },
  {
    title: "Weekly Report Generator",
    description: "Create a concise weekly recap for Geronimo from dashboard-backed items.",
    status: "MVP",
    items: ["Moved forward", "Blocked", "Needs approval", "Closest to live", "Next-week focus"],
  },
];

const QUICK_ACTIONS = [
  "Add Partner",
  "Mark Missing Info",
  "Request Content",
  "Send to Geronimo Approval",
  "Update Visibility Status",
  "Link HubSpot Record",
  "Create Follow-Up Task",
  "Generate Weekly Report",
];
// ─── Main AdminApp ──────────────────────────────────────────────────────────────────────────────
export default function AdminApp() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [roles, setRoles] = useState([]);
  const [roleError, setRoleError] = useState(null);
  const [checkingRoles, setCheckingRoles] = useState(false);
  const [activeDashboard, setActiveDashboard] = useState(null);

  const allowedHost = isAllowedAdminHost();
  const canOpenPmDashboard = useMemo(() => hasAnyRole(roles, PM_DASHBOARD_ROLES), [roles]);
  const canOpenCommunityDashboard = useMemo(() => hasAnyRole(roles, COMMUNITY_EVENT_ROLES), [roles]);
  const hasInternalAccess = useMemo(() => hasAnyRole(roles, INTERNAL_ROLES), [roles]);

  // ── Auth listener ──────────────────────────────────────────────────────────────────────
  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (!mounted) return;
      if (error) setRoleError(error.message);
      setSession(data?.session || null);
      setLoading(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (!nextSession) {
        setRoles([]);
        setRoleError(null);
        setActiveDashboard(null);
      }
    });

    return () => {
      mounted = false;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);

  // ── Load roles — public.user_roles ONLY. Deny by default on any failure. ───
  // app_metadata is NOT consulted. It cannot be used as an authorization source.
  useEffect(() => {
    if (!session?.user?.id || !allowedHost) return;
    loadRoles(session.user.id);
  }, [session?.user?.id, allowedHost]);

  const loadRoles = async (userId) => {
    setCheckingRoles(true);
    setRoleError(null);

    try {
      const { data, error } = await supabase
        .from("user_roles")
        .select("role, active")
        .eq("user_id", userId)
        .eq("active", true);

      if (error) throw error;

      const tableRoles = (data || []).map((r) => r.role).filter(Boolean);

      if (tableRoles.length === 0) {
        // No active internal roles found — deny access. Never fall back.
        setRoles([]);
        setRoleError(
          "No active internal role found for this account. " +
          "Access is denied. Ask Geronimo to assign the correct role in public.user_roles."
        );
      } else {
        setRoles(tableRoles);
      }
    } catch (err) {
      // user_roles unreadable (RLS block, missing table, network error).
      // Deny by default. Do NOT fall back to app_metadata or any other source.
      setRoles([]);
      setRoleError(
        "Admin role table could not be read — access denied by default. " +
        "Verify Supabase RLS allows internal roles to SELECT from public.user_roles. " +
        "Error: " + (err?.message || "unknown")
      );
    } finally {
      setCheckingRoles(false);
    }
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null);
  };

  // ── Render ────────────────────────────────────────────────────────────────────────────────
  if (!allowedHost) return <AdminUnavailable />;
  if (loading) return <AdminLoading message="Opening HEHA admin…" />;
  if (!session) return <AuthScreen />;
  if (checkingRoles) return <AdminLoading message="Checking internal access…" />;
  if (!hasInternalAccess) {
    return (
      <AdminDenied
        email={session.user.email}
        roleError={roleError}
        onSignOut={handleSignOut}
      />
    );
  }

  return (
    <div className="admin-app-shell">
      <header className="admin-topbar">
        <div>
          <p className="eyebrow">admin.hehaswipe.app</p>
          <h1>HEHA Internal Admin</h1>
          <p>Internal workflow tools only. Public users do not have access.</p>
        </div>
        <div className="admin-user-card">
          <span>{session.user.email}</span>
          <small>{roles.join(" · ") || "no role"}</small>
          <button onClick={handleSignOut}>Sign out</button>
        </div>
      </header>

      {roleError && <div className="admin-alert">{roleError}</div>}

      {!activeDashboard && (
        <AdminEntry
          canOpenPmDashboard={canOpenPmDashboard}
          canOpenCommunityDashboard={canOpenCommunityDashboard}
          onOpenPm={() => setActiveDashboard("pm")}
          onOpenCommunity={() => setActiveDashboard("community")}
        />
      )}

      {activeDashboard === "pm" && (
        <PmDashboard onBack={() => setActiveDashboard(null)} canOpen={canOpenPmDashboard} />
      )}

      {activeDashboard === "community" && (
        <CommunityPlaceholder onBack={() => setActiveDashboard(null)} canOpen={canOpenCommunityDashboard} />
      )}
    </div>
  );
}
// ─── Admin Entry Screen ────────────────────────────────────────────────────────────────────
function AdminEntry({ canOpenPmDashboard, canOpenCommunityDashboard, onOpenPm, onOpenCommunity }) {
  return (
    <main className="admin-entry-grid">
      <button
        className="admin-dashboard-button primary"
        onClick={onOpenPm}
        disabled={!canOpenPmDashboard}
      >
        <span>PM Dashboard</span>
        <strong>Myren project-management workflow</strong>
        <small>Partner onboarding · readiness · deals · approvals · weekly reporting</small>
        {!canOpenPmDashboard && (
          <em>Requires pm_admin, developer_admin, or super_admin role</em>
        )}
      </button>

      <button
        className="admin-dashboard-button secondary"
        onClick={onOpenCommunity}
        disabled={!canOpenCommunityDashboard}
      >
        <span>COMMUNITY / EVENTS</span>
        <strong>Niña community activation lane</strong>
        <small>Separate dashboard. Not part of Myren's PM workflow.</small>
        {!canOpenCommunityDashboard && (
          <em>Requires community_events_admin, developer_admin, or super_admin role</em>
        )}
      </button>
    </main>
  );
}

// ─── PM Dashboard ───────────────────────────────────────────────────────────────────────────────
function PmDashboard({ onBack, canOpen }) {
  const [counts, setCounts] = useState({});
  const [countsLoading, setCountsLoading] = useState(true);

  useEffect(() => {
    if (!canOpen) return;
    fetchCounts();
  }, [canOpen]);

  // Builds a read-only count query using the correct Supabase JS filter for each filterType.
  // Supports: none, eq, in, notIn, visibilityOr
  // On any query error or RLS block, the card shows — and the dashboard continues to render.
  const fetchCounts = async () => {
    setCountsLoading(true);
    const results = {};

    await Promise.allSettled(
      OVERVIEW_CARD_DEFS.map(async (card) => {
        try {
          let query = supabase
            .from(card.table)
            .select("*", { count: "exact", head: true });

          if (card.filterType === "eq") {
            query = query.eq(card.col, card.val);
          } else if (card.filterType === "in") {
            query = query.in(card.col, card.vals);
          } else if (card.filterType === "notIn") {
            // Supabase JS: .not(col, 'in', `(a,b,c)`)
            const csvList = `(${card.vals.join(",")})`;
            query = query.not(card.col, "in", csvList);
          } else if (card.filterType === "visibilityOr") {
            // Multi-column OR across 4 platform status fields.
            // orClause is a comma-separated PostgREST filter string, e.g.:
            // "heha_swipe_status.eq.needs_update,heha_local_status.eq.error_broken_link,..."
            query = query.or(card.orClause);
          }
          // filterType === "none": no additional filter, count all rows

          const { count, error } = await query;
          results[card.label] = error ? "—" : (count ?? 0);
        } catch {
          results[card.label] = "—";
        }
      })
    );

    setCounts(results);
    setCountsLoading(false);
  };

  if (!canOpen) {
    return (
      <AdminDenied
        roleError="This account does not have PM Dashboard permission."
        onSignOut={onBack}
      />
    );
  }

  return (
    <main className="pm-dashboard">
      <button className="admin-back-button" onClick={onBack}>
        ← Back to admin home
      </button>

      <section className="admin-section-hero">
        <p className="eyebrow">PM Dashboard · Read-only MVP dashboard</p>
        <h2>Myren manages the workflow. Geronimo approves the final decisions.</h2>
        <p>
          Internal command center for partner onboarding, profile readiness, missing info,
          deal requests, certification tracking, platform visibility, content requests,
          team tasks, and weekly reports. All write actions are disabled until Geronimo
          and Nova approve the full RLS and approval rules.
        </p>
      </section>

      <section className="admin-card-grid overview-grid">
        {OVERVIEW_CARD_DEFS.map((card) => (
          <article className="admin-stat-card" key={card.label}>
            <span>{card.label}</span>
            <strong>{countsLoading ? "…" : (counts[card.label] ?? "—")}</strong>
            <p>{card.note}</p>
          </article>
        ))}
      </section>

      <section className="admin-panel">
        <div className="admin-panel-heading">
          <div>
            <p className="eyebrow">Quick actions</p>
            <h3>Workflow actions for V1</h3>
          </div>
          <small>
            All buttons are intentionally disabled. Write flows require
            Geronimo + Nova approval of RLS policies and approval rules before activation.
          </small>
        </div>
        <div className="admin-action-grid">
          {QUICK_ACTIONS.map((action) => (
            <button key={action} disabled>
              {action}
            </button>
          ))}
        </div>
      </section>

      <section className="pm-section-list">
        {PM_SECTIONS.map((section) => (
          <article className="pm-section-card" key={section.title}>
            <div className="pm-section-card-header">
              <h3>{section.title}</h3>
              <span>{section.status}</span>
            </div>
            <p>{section.description}</p>
            <ul>
              {section.items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </article>
        ))}
      </section>

      <section className="admin-guardrail-box">
        <h3>Guardrails — Myren's Scope</h3>
        <p>
          Myren can track, route, and escalate work. Myren cannot self-approve any of
          the following without Geronimo's explicit final decision:
        </p>
        <ul style={{ color: "rgba(255,255,255,.84)", paddingLeft: "20px", lineHeight: "1.8" }}>
          <li>HEHA Certified / Verified status for any partner</li>
          <li>Final deal terms, discount agreements, or pricing logic</li>
          <li>Payment settings or financial configurations</li>
          <li>Public publishing of sensitive partner profiles</li>
          <li>Legal-sensitive health, quality, or certification claims</li>
          <li>Partner self-publishing or bypassing HEHA review</li>
          <li>Public promises about app features, support, income, or certification timelines</li>
          <li>Sponsor packages or commercial partnership agreements</li>
        </ul>
        <p style={{ marginTop: "14px" }}>
          <strong style={{ color: "white" }}>
            Geronimo keeps final approval on all of the above.
          </strong>
        </p>
      </section>
    </main>
  );
}
// ─── Community Placeholder ─────────────────────────────────────────────────────────────────────
function CommunityPlaceholder({ onBack, canOpen }) {
  if (!canOpen) {
    return (
      <AdminDenied
        roleError="This account does not have Community / Events permission."
        onSignOut={onBack}
      />
    );
  }
  return (
    <main className="pm-dashboard">
      <button className="admin-back-button" onClick={onBack}>
        ← Back to admin home
      </button>
      <section className="admin-section-hero">
        <p className="eyebrow">Community / Events</p>
        <h2>Niña's community activation dashboard — coming soon</h2>
        <p>
          This is a separate dashboard from Myren's PM workflow.
          Niña's community and events lane will be built here independently.
        </p>
      </section>
    </main>
  );
}

// ─── Support components ───────────────────────────────────────────────────────────────────────────
function AdminUnavailable() {
  return (
    <div className="admin-unavailable">
      <div className="admin-gate-card">
        <p className="eyebrow">HEHA Internal Admin</p>
        <h1>Not available on this site.</h1>
        <p>
          Internal admin tools only open from admin.hehaswipe.app
          or a local developer environment.
        </p>
      </div>
    </div>
  );
}

function AdminLoading({ message }) {
  return (
    <div className="admin-unavailable">
      <div className="admin-gate-card">
        <p className="eyebrow">HEHA Internal Admin</p>
        <h1>{message}</h1>
      </div>
    </div>
  );
}

function AdminDenied({ email, roleError, onSignOut }) {
  return (
    <div className="admin-unavailable">
      <div className="admin-gate-card danger">
        <p className="eyebrow">Access denied</p>
        <h1>This account does not have internal admin access.</h1>
        {email && (
          <p>
            Signed in as: <strong>{email}</strong>
          </p>
        )}
        {roleError && <p className="admin-small-warning">{roleError}</p>}
        <p>
          Ask Geronimo or the developer admin to assign the correct role
          in <code>public.user_roles</code> after Supabase RLS is confirmed.
        </p>
        <button onClick={onSignOut}>Sign out</button>
      </div>
    </div>
  );
}
