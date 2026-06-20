import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import AuthScreen from "../AuthScreen";
import CommunityDashboard from "./community/CommunityDashboard";
import PmDashboard from "./pm/PmDashboard";
import { AdminCard, roleLabel } from "./shared/AdminPrimitives";

const ALLOWED_ROLES = ["super_admin", "pm_admin", "community_events_admin"];

function areaFromPath() {
  if (window.location.pathname.includes("/community")) return "community";
  if (window.location.pathname.includes("/pm")) return "pm";
  return "home";
}

export default function AdminApp({ session, loading, onSignOut }) {
  const [role, setRole] = useState(null);
  const [checkingRole, setCheckingRole] = useState(true);
  const [area, setArea] = useState(areaFromPath);

  const access = useMemo(() => ({
    internal: ALLOWED_ROLES.includes(role),
    pm: role === "super_admin" || role === "pm_admin",
    community: role === "super_admin" || role === "community_events_admin",
    final: role === "super_admin",
  }), [role]);

  useEffect(() => {
    const handlePopState = () => setArea(areaFromPath());
    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  useEffect(() => {
    if (!session?.user?.id) { setRole(null); setCheckingRole(false); return; }
    checkRole(session.user.id);
  }, [session?.user?.id]);

  async function checkRole(userId) {
    setCheckingRole(true);
    const { data } = await supabase.from("user_roles").select("role").eq("user_id", userId).eq("active", true).limit(1);
    setRole(data?.[0]?.role || null);
    setCheckingRole(false);
  }

  function openArea(nextArea) {
    setArea(nextArea);
    window.history.pushState({}, "", nextArea === "community" ? "/admin/community" : nextArea === "pm" ? "/admin/pm" : "/admin");
  }

  if (loading || checkingRole) return <AdminShell title="Checking access" />;
  if (!session) return <AuthScreen />;
  if (!access.internal) return <AdminShell title="No admin role" message="This area requires an approved HEHA admin role." action={onSignOut} />;

  return <div className="admin-shell"><header className="admin-topbar"><div><p className="eyebrow">admin.hehaswipe.app</p><h1>HEHA Internal Dashboard</h1></div><div className="admin-actions"><span>{roleLabel(role)}</span><button onClick={onSignOut}>Sign out</button></div></header>{area === "home" && <AdminHome role={role} access={access} openArea={openArea} />}{area === "pm" && (access.pm ? <PmDashboard final={access.final} /> : <BlockedArea openArea={openArea} />)}{area === "community" && (access.community ? <CommunityDashboard final={access.final} /> : <BlockedArea openArea={openArea} />)}</div>;
}

function AdminShell({ title, message = "Protected HEHA admin area.", action }) {
  return <div className="admin-loading"><section><p className="eyebrow">HEHA internal</p><h1>{title}</h1><p>{message}</p>{action && <button onClick={action}>Sign out</button>}</section></div>;
}

function AdminHome({ role, access, openArea }) {
  return <main className="admin-home"><AdminCard eyebrow="command center" title="Choose dashboard" wide><p>Access is controlled by Supabase roles.</p></AdminCard>{access.pm && <button className="admin-card click" onClick={() => openArea("pm")}><span>01</span><strong>PM Dashboard</strong><p>Partner readiness, missing items, offers, visibility, tasks, and weekly reports.</p></button>}{access.community && <button className="admin-card click orange" onClick={() => openArea("community")}><span>02</span><strong>Community / Events</strong><p>Applications, concepts, invites, outreach, content requests, approvals, and recaps.</p></button>}<AdminCard eyebrow="role" title={roleLabel(role)}><p>{role === "super_admin" ? "Full internal access." : role === "pm_admin" ? "PM lane access." : "Community lane access."}</p></AdminCard></main>;
}

function BlockedArea({ openArea }) {
  return <main className="admin-panel"><button className="ha-admin-back-button" onClick={() => openArea("home")}>Back</button><AdminCard eyebrow="role boundary" title="Dashboard lane blocked" wide><p>Your role does not include this lane.</p></AdminCard></main>;
}
