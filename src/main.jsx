import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import "./mobile-fit.css";
import "./account-actions.css";
import "./onboarding-fix.css";
import "./heha-brand-theme.css";
import "./saved-detail-cleanup.css";
import "./super-swoop.css";
import "./preview-and-onboarding-fixes.css";
import "./partner-wizard-clean.css";
import "./placeholder-photo.css";
import "./admin-dashboard.css";
import App from "./App.jsx";
import AdminApp from "./components/admin/AdminApp.jsx";
import { supabase } from "./lib/supabase";

function Root() {
  const isAdminRoute = window.location.pathname.startsWith("/admin") || window.location.hostname.startsWith("admin.");
  return isAdminRoute ? <AdminSessionGate /> : <App />;
}

function AdminSessionGate() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return;
      setSession(data?.session || null);
      setLoading(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setLoading(false);
    });
    return () => {
      mounted = false;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null);
  };

  return <AdminApp session={session} loading={loading} onSignOut={handleSignOut} />;
}

createRoot(document.getElementById("root")).render(<StrictMode><Root /></StrictMode>);
