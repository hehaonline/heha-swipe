import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import AuthScreen from "../AuthScreen";
import CommunityDashboard from "./community/CommunityDashboard";
import PmDashboard from "./pm/PmDashboard";
import ScoutDashboard from "./scout/ScoutDashboard";
import { AdminCard, roleLabel } from "./shared/AdminPrimitives";

const ROLE_ORDER = ["super_admin", "developer_admin", "pm_admin", "community_events_admin", "som_admin"];

function areaFromPath() {
  const path = window.location.pathname;
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
        <div><p className="eyebrow">admin.hehaswipe.app</p><h1>HEHA Internal Dashboard</h1></div>
        <div className="admin-actions">
          <span>{roleLabel(role)}</span>
          {area !== "scout" && <button onClick={() => openArea("scout")}>Scout Pipeline</button>}
          {area !== "home" && <button onClick={() => openArea("home")}>Home</button>}
          <button onClick={onSignOut}>Sign out</button>
        </div>
      </header>
      {area === "home" && <AdminHome access={access} openArea={openArea} />}
      {area === "pm" && (access.pm ? <PmDashboard final={access.final} /> : <BlockedArea openArea={openArea} />)}
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
  return <main className="admin-home"><AdminCard eyebrow="command center" title="Choose dashboard" wide><p>One internal system with role-specific lanes.</p></AdminCard>{access.pm && <Dash title="PM Dashboard" text="Partner readiness and project management." onClick={() => openArea("pm")} />}{access.community && <Dash title="Community / Events" text="Events, venues, outreach, and recaps." onClick={() => openArea("community")} />}{access.som && <Dash title="Sales Operations" text="Scout and route potential partners." onClick={() => openArea("som")} />}{access.scout && <Dash title="Scout & Partner Pipeline" text="Shared field visit and lead intake." onClick={() => openArea("scout")} />}</main>;
}

function Dash({ title, text, onClick }) {
  return <button className="admin-card click" onClick={onClick}><strong>{title}</strong><p>{text}</p></button>;
}

function BlockedArea({ openArea }) {
  return <main className="admin-panel"><button className="ha-admin-back-button" onClick={() => openArea("home")}>Back</button><AdminCard eyebrow="role boundary" title="Dashboard lane blocked" wide><p>Your role does not include this lane.</p></AdminCard></main>;
}
