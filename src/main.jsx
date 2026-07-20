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
import "./location-modal.css";
import "./community-pass.css";
import "./partner-media.css";
import "./partner-offers.css";
import "./embed.css";
import App from "./App.jsx";
import AdminApp from "./components/admin/AdminApp.jsx";
import InternalDashboardShortcut from "./components/InternalDashboardShortcut.jsx";
import BecomePartnerEmbed from "./components/embed/BecomePartnerEmbed.jsx";
import PartnerDirectoryEmbed from "./components/embed/PartnerDirectoryEmbed.jsx";
import { supabase } from "./lib/supabase";

const SIGNUP_ROLE_KEY = "heha_signup_role";

if (new URLSearchParams(window.location.search).get("becomePartner") === "1") {
  localStorage.setItem(SIGNUP_ROLE_KEY, "partner");
}

function shouldRenderAdminApp() {
  const hostIsAdmin = window.location.hostname.startsWith("admin.");
  const buildIsAdmin = import.meta.env.VITE_APP_MODE === "admin";
  const adminRoute = window.location.pathname.startsWith("/admin");
  return hostIsAdmin || buildIsAdmin || adminRoute;
}

function embedFromPath() {
  if (window.location.pathname === "/embed/partners") return "partners";
  if (window.location.pathname === "/embed/become-partner") return "become-partner";
  return null;
}

function Root() {
  const isAdminRoute = shouldRenderAdminApp();
  const embed = embedFromPath();

  if (isAdminRoute) import("./admin-dashboard.css");
  if (isAdminRoute) return <AdminSessionGate />;
  if (embed === "partners") return <PartnerDirectoryEmbed />;
  if (embed === "become-partner") return <BecomePartnerEmbed />;
  return (
    <>
      <App />
      <InternalDashboardShortcut />
    </>
  );
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

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <Root />
  </StrictMode>
);
