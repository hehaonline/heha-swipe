import { useEffect, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";

const ADMIN_HOSTS = new Set(["admin.hehaswipe.app"]);
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

const OVERVIEW_CARDS = [
  { label: "Active partner profiles", value: "Setup", note: "Connect after RLS + tables are approved." },
  { label: "New submissions", value: "Setup", note: "Phase 2: business forms flow into review." },
  { label: "Profiles missing info", value: "Setup", note: "Missing fields/assets tracker." },
  { label: "Deal requests", value: "Setup", note: "Community Pass / Swoop / SuperSwoop queue." },
  { label: "Certification reviews", value: "Setup", note: "Track only. Geronimo approves." },
  { label: "Visibility issues", value: "Setup", note: "Wix / Local / Swipe / HubSpot mismatches." },
  { label: "Needs Geronimo approval", value: "Setup", note: "All risky items flow here." },
  { label: "HubSpot sync issues", value: "Setup", note: "Backend or Make.com only; no frontend token." },
];

const PM_SECTIONS = [
  {
    title: "Partner Pipeline",
    description: "Track each partner from first lead to approved visibility.",
    status: "MVP",
    items: ["Status", "Owner", "Next step", "Due date", "Blocker", "HubSpot link", "Approval needed"],
  },
  {
    title: "Profile Readiness",
    description: "Confirm each partner has the profile data needed for Wix, HEHA Local, and HEHA Swipe.",
    status: "MVP",
    items: ["Descriptions", "Logo/photos", "Menu/products/services", "Links", "Proof point", "Tags"],
  },
  {
    title: "Missing Info + Assets",
    description: "One queue for missing logos, photos, links, menu info, proof points, and approvals.",
    status: "MVP",
    items: ["Assigned to", "Due date", "Follow-up method", "Escalation needed", "Status"],
  },
  {
    title: "Deals / Discounts Queue",
    description: "Track Community Pass, Swoop, SuperSwoop, and local discount requests without auto-approving them.",
    status: "MVP",
    items: ["Deal type", "Terms", "Dates", "Redemption", "Content needed", "Geronimo approval"],
  },
  {
    title: "Listed But Not Certified",
    description: "Make sure listed partners are not confused with HEHA Certified / Verified partners.",
    status: "MVP",
    items: ["Certification status", "Missing review info", "Risk notes", "Badge status", "Geronimo decision"],
  },
  {
    title: "Platform Visibility",
    description: "Find mismatches between HEHA Swipe, HEHA Local, Wix, HubSpot, Instagram, and newsletter visibility.",
    status: "MVP",
    items: ["Hidden", "Draft", "Needs update", "Ready", "Live", "Paused", "Broken link"],
  },
  {
    title: "Content Requests",
    description: "Request profile copy, deal cards, Canva graphics, social posts, and listing copy from the content team.",
    status: "MVP",
    items: ["Request type", "Assigned person", "Needed by", "Assets provided", "Approval needed"],
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

function isAllowedAdminHost() {
  const host = window.location.hostname;
  return ADMIN_HOSTS.has(host) || host === "localhost" || host === "127.0.0.1";
}

function getAppMetadataRoles(user) {
  const appRole = user?.app_metadata?.role;
  const appRoles = user?.app_metadata?.roles;
  const normalized = [];
  if (typeof appRole === "string") normalized.push(appRole);
  if (Array.isArray(appRoles)) normalized.push(...appRoles.filter(Boolean));
  return normalized;
}

function hasAnyRole(roles, allowedRoles) {
  return roles.some((role) => allowedRoles.has(role));
}

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

  useEffect(() => {
    if (!session?.user?.id || !allowedHost) return;
    loadRoles(session.user);
  }, [session?.user?.id, allowedHost]);

  const loadRoles = async (user) => {
    setCheckingRoles(true);
    setRoleError(null);

    const appMetadataRoles = getAppMetadataRoles(user);

    try {
      const { data, error } = await supabase
        .from("user_roles")
        .select("role, active")
        .eq("user_id", user.id)
        .eq("active", true);

      if (error) throw error;

      const tableRoles = (data || []).map((record) => record.role).filter(Boolean);
      setRoles(Array.from(new Set([...tableRoles, ...appMetadataRoles])));
    } catch (error) {
      // Deny by default if the role table is missing or not readable.
      setRoles(Array.from(new Set(appMetadataRoles)));
      setRoleError(
        "Admin role table is not connected yet. Access is denied unless a trusted app_metadata admin role exists."
      );
    } finally {
      setCheckingRoles(false);
    }
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null);
  };

  if (!allowedHost) {
    return <AdminUnavailable />;
  }

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

function AdminEntry({ canOpenPmDashboard, canOpenCommunityDashboard, onOpenPm, onOpenCommunity }) {
  return (
    <main className="admin-entry-grid">
      <button className="admin-dashboard-button primary" onClick={onOpenPm} disabled={!canOpenPmDashboard}>
        <span>PM Dashboard</span>
        <strong>Myren project-management workflow</strong>
        <small>Partner onboarding · readiness · deals · approvals · weekly reporting</small>
        {!canOpenPmDashboard && <em>Requires PM Admin or Super Admin role</em>}
      </button>

      <button className="admin-dashboard-button secondary" onClick={onOpenCommunity} disabled={!canOpenCommunityDashboard}>
        <span>COMMUNITY / EVENTS</span>
        <strong>Niña community activation lane</strong>
        <small>Separate dashboard. Not part of Myren’s PM workflow.</small>
        {!canOpenCommunityDashboard && <em>Requires Community/Event Admin or Super Admin role</em>}
      </button>
    </main>
  );
}

function PmDashboard({ onBack, canOpen }) {
  if (!canOpen) {
    return <AdminDenied roleError="This account does not have PM Dashboard permission." onSignOut={onBack} />;
  }

  return (
    <main className="pm-dashboard">
      <button className="admin-back-button" onClick={onBack}>← Back to admin home</button>

      <section className="admin-section-hero">
        <p className="eyebrow">PM Dashboard</p>
        <h2>Myren manages the workflow. Geronimo approves the final decisions.</h2>
        <p>
          This dashboard is the internal command center for partner onboarding, profile readiness, missing info,
          deal requests, certification tracking, platform visibility, content requests, blockers, and weekly reports.
        </p>
      </section>

      <section className="admin-card-grid overview-grid">
        {OVERVIEW_CARDS.map((card) => (
          <article className="admin-stat-card" key={card.label}>
            <span>{card.label}</span>
            <strong>{card.value}</strong>
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
          <small>Buttons are intentionally disabled until tables, RLS, and approval rules are approved.</small>
        </div>
        <div className="admin-action-grid">
          {QUICK_ACTIONS.map((action) => (
            <button key={action} disabled>{action}</button>
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
              {section.items.map((item) => <li key={item}>{item}</li>)}
            </ul>
          </article>
        ))}
      </section>

      <section className="admin-guardrail-box">
        <h3>Guardrails</h3>
        <p>
          Myren can track and route work, but cannot self-approve HEHA Certified / Verified status, final deals,
          pricing logic, payment settings, public publishing of sensitive profiles, or legal-sensitive health/quality claims.
        </p>
      </section>
    </main>
  );
}

function CommunityPlaceholder({ onBack, canOpen }) {
  if (!canOpen) return <AdminDenied roleError="This account does not have Community / Events permission." onSignOut={onBack} />;

  return (
    <main className="pm-dashboard">
      <button className="admin-back-button" onClick={onBack}>← Back to admin home</button>
      <section className="admin-section-hero">
        <p className="eyebrow">Community / Events</p>
        <h2>Separate dashboard placeholder</h2>
        <p>This keeps Niña’s event/community activation lane separate from Myren’s PM Dashboard.</p>
      </section>
    </main>
  );
}

function AdminUnavailable() {
  return (
    <div className="admin-unavailable">
      <div className="admin-gate-card">
        <p className="eyebrow">HEHA Internal Admin</p>
        <h1>Not available on this site.</h1>
        <p>Internal admin tools only open from admin.hehaswipe.app or a local developer environment.</p>
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
        {email && <p>Signed in as: <strong>{email}</strong></p>}
        {roleError && <p className="admin-small-warning">{roleError}</p>}
        <p>Ask Geronimo or the developer admin to assign the correct role after Supabase RLS is approved.</p>
        <button onClick={onSignOut}>Sign out</button>
      </div>
    </div>
  );
}
