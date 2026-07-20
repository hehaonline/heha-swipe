import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import AuthScreen from "../AuthScreen";
import CommunityDashboard from "./community/CommunityDashboard";
import PmDashboard from "./pm/PmDashboard";
import RoutingDashboard from "./routing/RoutingDashboard";
import ScoutDashboard from "./scout/ScoutDashboard";
import { AdminCard, roleLabel } from "./shared/AdminPrimitives";
import { visibleDomains } from "./shared/oneHehaDomains";

const ROLE_ORDER = ["super_admin", "developer_admin", "pm_admin", "community_events_admin", "som_admin"];

function areaFromPath() {
  const path = window.location.pathname;
  if (path.includes("/routing")) return "routing";
  if (path.includes("/scout")) return "scout";
  if (path.includes("/som")) return "som";
  if (path.includes("/community")) return "community";
  if (path.includes("/pm")) return "pm";
  return "home";
}

function pathFor(area) {
  return area === "home" ? "/admin" : `/admin/${area}`;
}

export default function AdminApp({ session, loading, onSignOut }) {
  const [role, setRole] = useState(null);
  const [checkingRole, setCheckingRole] = useState(true);
  const [area, setArea] = useState(areaFromPath);

  const access = useMemo(() => {
    const admin = role === "super_admin" || role === "developer_admin";
    return {
      internal: ROLE_ORDER.includes(role),
      pm: admin || role === "pm_admin",
      routing: admin || role === "pm_admin",
      community: admin || role === "community_events_admin",
      som: admin || role === "som_admin",
      scout: ROLE_ORDER.includes(role),
      final: role === "super_admin",
    };
  }, [role]);

  useEffect(() => {
    const onPop = () => setArea(areaFromPath());
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  useEffect(() => {
    if (!session?.user?.id) {
      setRole(null);
      setCheckingRole(false);
      return;
    }
    checkRole(session.user.id);
  }, [session?.user?.id]);

  async function checkRole(userId) {
    setCheckingRole(true);
    const { data } = await supabase.from("user_roles").select("role").eq("user_id", userId).eq("active", true);
    const roles = new Set((data || []).map((item) => item.role));
    setRole(ROLE_ORDER.find((candidate) => roles.has(candidate)) || null);
    setCheckingRole(false);
  }

  function openArea(nextArea) {
    setArea(nextArea);
    window.history.pushState({}, "", pathFor(nextArea));
  }

  if (loading || checkingRole) return <AdminShell title="Checking access" />;
  if (!session) return <AuthScreen />;
  if (!access.internal) return <AdminShell title="No admin role" message="This area requires an approved HEHA internal role." action={onSignOut} />;

  return (
    <div className="admin-shell">
      <header className="admin-topbar">
        <div><p className="eyebrow">ONE HEHA · ZERO BUREAUCRACY</p><h1>HEHA Internal Dashboard</h1></div>
        <div className="admin-actions">
          <span>{roleLabel(role)}</span>
          {area !== "home" && <button onClick={() => openArea("home")}>Five Domains</button>}
          <button onClick={onSignOut}>Sign out</button>
        </div>
      </header>
      {area === "home" && <AdminHome access={access} openArea={openArea} />}
      {area === "pm" && (access.pm ? <PmDashboard final={access.final} /> : <BlockedArea openArea={openArea} />)}
      {area === "routing" && (access.routing ? <RoutingDashboard final={access.final} /> : <BlockedArea openArea={openArea} />)}
      {area === "community" && (access.community ? <CommunityDashboard final={access.final} /> : <BlockedArea openArea={openArea} />)}
      {area === "som" && (access.som ? <ScoutDashboard role={role} final={access.final} mode="som" /> : <BlockedArea openArea={openArea} />)}
      {area === "scout" && <ScoutDashboard role={role} final={access.final} />}
    </div>
  );
}

function AdminShell({ title, message = "Protected HEHA admin area.", action }) {
  return <div className="admin-loading"><section><p className="eyebrow">HEHA internal</p><h1>{title}</h1><p>{message}</p>{action && <button onClick={action}>Sign out</button>}</section></div>;
}

function AdminHome({ access, openArea }) {
  const domains = visibleDomains(access);

  return (
    <main className="admin-panel">
      <AdminCard eyebrow="ONE HEHA operating system" title="Five domains. One source of truth." wide>
        <p>Every HEHA function has one primary home. Your role determines which modules you can open; cross-app links lead to the canonical workspace instead of duplicating records.</p>
      </AdminCard>
      <section className="admin-grid">
        {domains.map((domain) => (
          <section key={domain.id} className="admin-card wide" style={{ borderLeft: `5px solid ${domain.color}` }}>
            <p className="eyebrow" style={{ color: domain.color }}>{domain.number} ({domain.code})</p>
            <h2>{domain.label}</h2>
            <p>{domain.purpose}</p>
            <div className="admin-home">
              {domain.modules.map((module) => (
                <ModuleCard key={module.id} module={module} color={domain.color} openArea={openArea} />
              ))}
            </div>
          </section>
        ))}
      </section>
    </main>
  );
}

function ModuleCard({ module, color, openArea }) {
  const open = () => {
    if (module.area) return openArea(module.area);
    if (module.href) return window.location.assign(module.href);
    return undefined;
  };
  const interactive = Boolean(module.area || module.href);

  if (!interactive) {
    return (
      <section className="admin-card" style={{ borderTop: `3px solid ${color}` }}>
        <strong>{module.label}</strong>
        <p>{module.description}</p>
        {module.status && <span>{module.status}</span>}
      </section>
    );
  }

  return (
    <button className="admin-card click" onClick={open} style={{ borderTop: `3px solid ${color}` }}>
      <strong>{module.label}</strong>
      <p>{module.description}</p>
      <small>{module.href ? "Open workspace ↗" : "Open module →"}</small>
    </button>
  );
}

function BlockedArea({ openArea }) {
  return <main className="admin-panel"><button className="ha-admin-back-button" onClick={() => openArea("home")}>Back to five domains</button><AdminCard eyebrow="role boundary" title="Dashboard lane blocked" wide><p>Your role does not include this lane.</p></AdminCard></main>;
}
