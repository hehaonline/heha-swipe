import { useEffect, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import MyrenFullDashboard from "./admin/MyrenFullDashboard";

const ADMIN_HOSTS = new Set(["admin.hehaswipe.app"]);
const ALLOWED_ROLES = new Set(["super_admin", "pm_admin"]);

function isAllowedAdminHost() {
  const host = window.location.hostname;
  return ADMIN_HOSTS.has(host) || host === "localhost" || host === "127.0.0.1";
}

function hasAllowedRole(roles) {
  return roles.some((role) => ALLOWED_ROLES.has(role));
}

export default function AdminApp() {
  const [session, setSession] = useState(null);
  const [roles, setRoles] = useState([]);
  const [loading, setLoading] = useState(true);
  const [checkingRoles, setCheckingRoles] = useState(false);
  const [roleError, setRoleError] = useState(null);
  const [showDashboard, setShowDashboard] = useState(false);

  const allowedHost = isAllowedAdminHost();
  const hasAccess = useMemo(() => hasAllowedRole(roles), [roles]);

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
        setShowDashboard(false);
      }
    });

    return () => {
      mounted = false;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);

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
        .select("role")
        .eq("user_id", userId)
        .eq("active", true);

      if (error) throw error;

      const nextRoles = (data || []).map((item) => item.role).filter((role) => ALLOWED_ROLES.has(role));
      setRoles(nextRoles);

      if (!nextRoles.length) {
        setRoleError("No Geronimo/Myren admin role found for this account. Access denied.");
      }
    } catch (error) {
      setRoles([]);
      setRoleError(`Admin role check failed. Access denied by default. ${error?.message || ""}`);
    } finally {
      setCheckingRoles(false);
    }
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null);
  };

  if (!allowedHost) return <AdminUnavailable />;
  if (loading) return <AdminLoading message="Opening HEHA admin…" />;
  if (!session) return <AuthScreen />;
  if (checkingRoles) return <AdminLoading message="Checking Geronimo/Myren access…" />;
  if (!hasAccess) {
    return <AdminDenied email={session.user.email} roleError={roleError} onSignOut={handleSignOut} />;
  }

  return (
    <div className="admin-app-shell">
      <header className="admin-topbar">
        <div>
          <p className="eyebrow">admin.hehaswipe.app</p>
          <h1>HEHA Internal Admin</h1>
          <p>Private dashboard access only for Geronimo and Myren.</p>
        </div>
        <div className="admin-user-card">
          <span>{session.user.email}</span>
          <small>{roles.join(" · ")}</small>
          <button onClick={handleSignOut}>Sign out</button>
        </div>
      </header>

      {roleError && <div className="admin-alert">{roleError}</div>}

      {!showDashboard ? (
        <main className="admin-entry-grid">
          <button className="admin-dashboard-button primary" onClick={() => setShowDashboard(true)}>
            <span>PM Dashboard</span>
            <strong>Myren + Geronimo control center</strong>
            <small>Partner readiness · missing assets · deals · certification · visibility · approvals · weekly reports</small>
          </button>
          <button className="admin-dashboard-button secondary" disabled>
            <span>COMMUNITY / EVENTS</span>
            <strong>Locked for later</strong>
            <small>Niña’s event dashboard is intentionally not active in this build.</small>
            <em>Not accessible from this Myren/Geronimo dashboard yet</em>
          </button>
        </main>
      ) : (
        <MyrenFullDashboard user={session.user} roles={roles} onBack={() => setShowDashboard(false)} />
      )}
    </div>
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
        <h1>This account does not have Geronimo/Myren dashboard access.</h1>
        {email && <p>Signed in as: <strong>{email}</strong></p>}
        {roleError && <p className="admin-small-warning">{roleError}</p>}
        <p>This dashboard is limited to <code>super_admin</code> and <code>pm_admin</code> roles in <code>public.user_roles</code>.</p>
        <button onClick={onSignOut}>Sign out</button>
      </div>
    </div>
  );
}
