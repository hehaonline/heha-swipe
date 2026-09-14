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
import LegalPage, { isPublicInfoPath } from "./components/LegalPage.jsx";
import { releasePolicy } from "./lib/releasePolicy";
import PartnerClaimScreen from "./components/PartnerClaimScreen.jsx";

const SIGNUP_ROLE_KEY = "heha_signup_role";

if (releasePolicy.partnerSelfService && new URLSearchParams(window.location.search).get("becomePartner") === "1") {
  localStorage.setItem(SIGNUP_ROLE_KEY, "partner");
}

function shouldRenderAdminApp() {
  if (!releasePolicy.internalAdmin) return false;
  const hostIsAdmin = window.location.hostname.startsWith("admin.");
  const buildIsAdmin = import.meta.env.VITE_APP_MODE === "admin";
  const adminRoute = window.location.pathname.startsWith("/admin");
  return hostIsAdmin || buildIsAdmin || adminRoute;
}

function embedFromPath() {
  if (releasePolicy.storeBuild) return null;
  if (window.location.pathname === "/embed/partners") return "partners";
  if (window.location.pathname === "/embed/become-partner") return "become-partner";
  return null;
}

function Root() {
  if (isPublicInfoPath(window.location.pathname)) {
    return <LegalPage pathname={window.location.pathname} />;
  }
  const isAdminRoute = shouldRenderAdminApp();
  const embed = embedFromPath();

  if (isAdminRoute) import("./admin-dashboard.css");
  if (isAdminRoute) return <AdminSessionGate />;
  if (window.location.pathname === "/claim-partner" && releasePolicy.partnerSelfService) {
    return <PartnerClaimSessionGate />;
  }
  if (embed === "partners") return <PartnerDirectoryEmbed />;
  if (embed === "become-partner") return <BecomePartnerEmbed />;
  return (
    <>
      <App />
      {releasePolicy.internalAdmin && <InternalDashboardShortcut />}
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

function PartnerClaimSessionGate() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  useEffect(() => {
    let mounted = true;
    let revision = 0;
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      revision += 1;
      if (!mounted) return;
      setSession(nextSession);
      setError(null);
      setLoading(false);
    });
    const initialRevision = revision;
    supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!mounted || revision !== initialRevision) return;
      if (sessionError) throw sessionError;
      setSession(data?.session || null);
      setLoading(false);
    }).catch(() => {
      if (!mounted || revision !== initialRevision) return;
      setError("We could not check your account. Reload this page to try again.");
      setLoading(false);
    });
    return () => {
      mounted = false;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);
  return <PartnerClaimScreen
    key={session?.user?.id || "signed-out"}
    session={session}
    authLoading={loading}
    sessionError={error}
    onSignOut={async () => {
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) throw signOutError;
      setSession(null);
    }}
  />;
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <Root />
  </StrictMode>
);
