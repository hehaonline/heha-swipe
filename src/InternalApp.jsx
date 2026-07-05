import { useEffect, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import ScoutPipeline from "./components/ScoutPipeline";

const INTERNAL_ROLES = new Set([
  "super_admin",
  "pm_admin",
  "community_events_admin",
  "som_admin",
  "developer_admin",
]);

const LENS_META = {
  admin: { label: "Admin", eyebrow: "Full pipeline control" },
  pm: { label: "Project Manager", eyebrow: "Partner readiness & follow-up" },
  som: { label: "Sales Operations", eyebrow: "Scout, qualify & hand off" },
  events: { label: "Events", eyebrow: "Venues, vendors & event partners" },
};

function getAvailableLenses(roles) {
  const roleSet = new Set(roles);
  if (roleSet.has("super_admin") || roleSet.has("developer_admin")) {
    return ["admin", "pm", "som", "events"];
  }

  const lenses = [];
  if (roleSet.has("pm_admin")) lenses.push("pm");
  if (roleSet.has("som_admin")) lenses.push("som");
  if (roleSet.has("community_events_admin")) lenses.push("events");
  return lenses;
}

export default function InternalApp() {
  const [session, setSession] = useState(null);
  const [roles, setRoles] = useState([]);
  const [loading, setLoading] = useState(true);
  const [roleLoading, setRoleLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!mounted) return;
      if (sessionError) setError(sessionError.message);
      setSession(data?.session || null);
      setLoading(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (!nextSession) {
        setRoles([]);
        setRoleLoading(false);
      }
    });

    return () => {
      mounted = false;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);

  useEffect(() => {
    const userId = session?.user?.id;
    if (!userId) return;

    let cancelled = false;
    setRoleLoading(true);

    supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", userId)
      .eq("active", true)
      .then(({ data, error: roleError }) => {
        if (cancelled) return;
        if (roleError) {
          setError(roleError.message);
          setRoles([]);
        } else {
          setRoles((data || []).map((item) => item.role));
        }
        setRoleLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [session?.user?.id]);

  const availableLenses = useMemo(() => getAvailableLenses(roles), [roles]);
  const [lens, setLens] = useState("admin");

  useEffect(() => {
    if (!availableLenses.length) return;
    if (!availableLenses.includes(lens)) setLens(availableLenses[0]);
  }, [availableLenses, lens]);

  if (loading) {
    return <div className="internal-loading">Opening HEHA internal workspace…</div>;
  }

  if (!session) return <AuthScreen />;

  if (roleLoading) {
    return <div className="internal-loading">Checking HEHA staff access…</div>;
  }

  const hasAccess = roles.some((role) => INTERNAL_ROLES.has(role));

  if (!hasAccess) {
    return (
      <main className="internal-gate">
        <section className="internal-gate-card">
          <p className="internal-eyebrow">HEHA internal workspace</p>
          <h1>This dashboard is staff-only.</h1>
          <p>Your account is signed in, but it does not have an active HEHA internal role.</p>
          {error && <p className="internal-error">{error}</p>}
          <div className="internal-gate-actions">
            <a className="scout-secondary-button" href="/">Back to HEHA Swipe</a>
            <button className="scout-primary-button" type="button" onClick={() => supabase.auth.signOut()}>
              Sign out
            </button>
          </div>
        </section>
      </main>
    );
  }

  const meta = LENS_META[lens] || LENS_META.admin;

  return (
    <div className="internal-shell">
      <header className="internal-header">
        <div>
          <a className="internal-brand" href="/" aria-label="Back to HEHA Swipe">
            <span className="internal-brand-mark" />
            <strong>HEHA</strong>
            <span>internal</span>
          </a>
          <p>{meta.eyebrow}</p>
        </div>

        <div className="internal-header-actions">
          <a className="scout-secondary-button compact" href="/">Swipe</a>
          <button className="scout-secondary-button compact" type="button" onClick={() => supabase.auth.signOut()}>
            Sign out
          </button>
        </div>
      </header>

      {availableLenses.length > 1 && (
        <nav className="internal-lens-nav" aria-label="Dashboard role view">
          {availableLenses.map((item) => (
            <button
              key={item}
              type="button"
              className={lens === item ? "active" : ""}
              onClick={() => setLens(item)}
            >
              {LENS_META[item].label}
            </button>
          ))}
        </nav>
      )}

      {error && <div className="internal-error-banner">{error}</div>}

      <ScoutPipeline user={session.user} roles={roles} lens={lens} />
    </div>
  );
}
