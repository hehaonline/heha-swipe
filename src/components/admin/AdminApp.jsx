import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import AuthScreen from "../AuthScreen";
import CommunityDashboard from "./community/CommunityDashboard";
import PmDashboard from "./pm/PmDashboard";
import RoutingDashboard from "./routing/RoutingDashboard";
import ScoutDashboard from "./scout/ScoutDashboard";
import { AdminCard, roleLabel } from "./shared/AdminPrimitives";
import { ONE_HEHA_DOMAINS, visibleDomains } from "./shared/oneHehaDomains";

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

function domainForArea(area) {
  if (area === "som") return "ops";
  if (area === "pm" || area === "scout") return "grow";
  if (area === "community") return "comm";
  return "ctrl";
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

  function openDomain(domain) {
    if (domain.id === "ctrl") return openArea("home");
    if (domain.id === "ops") return window.location.assign("https://hehalocal.app/admin");
    if (domain.id === "tech") {
      if (role === "super_admin" || role === "developer_admin") return openArea("home");
      return window.location.assign("https://hehalocal.app/request-help?domain=TECH&type=support");
    }
    if (domain.id === "grow") return openArea(access.scout ? "scout" : "home");
    if (domain.id === "comm") {
      if (access.community) return openArea("community");
      return window.location.assign("https://hehalocal.app/request-help?domain=COMM&type=support");
    }
    return openArea("home");
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

      <AdminDomainStrip activeDomain={domainForArea(area)} onOpen={openDomain} />

      {area === "home" && <AdminHome access={access} openArea={openArea} />}
      {area === "pm" && (access.pm ? <PmDashboard final={access.final} /> : <BlockedArea openArea={openArea} domain="GROW" />)}
      {area === "routing" && (access.routing ? <RoutingDashboard final={access.final} /> : <BlockedArea openArea={openArea} domain="CTRL" />)}
      {area === "community" && (access.community ? <CommunityDashboard final={access.final} /> : <BlockedArea openArea={openArea} domain="COMM" />)}
      {area === "som" && (access.som ? <ScoutDashboard role={role} final={access.final} mode="som" /> : <BlockedArea openArea={openArea} domain="OPS" />)}
      {area === "scout" && <ScoutDashboard role={role} final={access.final} />}
    </div>
  );
}

function AdminShell({ title, message = "Protected HEHA admin area.", action }) {
  return <div className="admin-loading"><section><p className="eyebrow">HEHA internal</p><h1>{title}</h1><p>{message}</p>{action && <button onClick={action}>Sign out</button>}</section></div>;
}

function AdminDomainStrip({ activeDomain, onOpen }) {
  return (
    <nav className="one-heha-admin-strip" aria-label="ONE HEHA domains">
      {ONE_HEHA_DOMAINS.map((domain) => (
        <button
          key={domain.id}
          type="button"
          className={activeDomain === domain.id ? "active" : ""}
          style={{ "--domain-color": domain.color }}
          onClick={() => onOpen(domain)}
        >
          <span>{domain.number} {domain.code}</span>
          <strong>{domain.label}</strong>
        </button>
      ))}
    </nav>
  );
}

function AdminHome({ access, openArea }) {
  const domains = visibleDomains(access);

  return (
    <main className="admin-panel">
      <AdminCard eyebrow="ONE HEHA operating system" title="Five domains. One source of truth." wide>
        <p>Every domain stays visible. Your role determines what you can operate; restricted work becomes one structured request instead of a hidden or duplicated process.</p>
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
  const available = module.available !== false;
  const open = () => {
    if (!available) return window.location.assign(module.requestHref);
    if (module.area) return openArea(module.area);
    if (module.href) return window.location.assign(module.href);
    if (module.requestHref && module.status === "gated") return window.location.assign(module.requestHref);
    return undefined;
  };
  const interactive = Boolean(module.area || module.href || (!available && module.requestHref) || (module.status === "gated" && module.requestHref));

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
    <button className={`admin-card click ${available ? "" : "restricted"}`} onClick={open} style={{ borderTop: `3px solid ${color}` }}>
      <strong>{module.label}</strong>
      <p>{module.description}</p>
      <small>{!available ? "Send request →" : module.href ? "Open workspace ↗" : "Open module →"}</small>
    </button>
  );
}

function BlockedArea({ openArea, domain }) {
  const requestHref = `https://hehalocal.app/request-help?domain=${domain}&type=approval`;
  return (
    <main className="admin-panel">
      <button className="ha-admin-back-button" onClick={() => openArea("home")}>Back to five domains</button>
      <AdminCard eyebrow="role boundary" title="This lane is read-only for your role" wide>
        <p>You can still see where the function belongs and send one structured request to the responsible administrator.</p>
        <button className="ha-admin-back-button" onClick={() => window.location.assign(requestHref)}>Send request</button>
      </AdminCard>
    </main>
  );
}
