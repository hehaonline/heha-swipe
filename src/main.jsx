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
import "./app-install-guide.css";
import "./partner-agreement.css";
import "./partner-onboarding-checklist.css";
import "./lib/pwaInstall";
import App from "./App.jsx";
import AdminApp from "./components/admin/AdminApp.jsx";
import InternalDashboardShortcut from "./components/InternalDashboardShortcut.jsx";
import BecomePartnerEmbed from "./components/embed/BecomePartnerEmbed.jsx";
import PartnerDirectoryEmbed from "./components/embed/PartnerDirectoryEmbed.jsx";
import { supabase } from "./lib/supabase";
import { partnerInviteUrlRequiresHardStop } from "./lib/partnerInvite";

const partnerPwaEnabled = import.meta.env.VITE_ENABLE_HEHA_SWIPE_PWA === "true";
const LEGACY_HEHA_PWA_CACHES = new Set(["heha-v1"]);

function enableInstallMetadata() {
  const addMeta = (name, content) => {
    const meta = document.createElement("meta");
    meta.name = name;
    meta.content = content;
    document.head.appendChild(meta);
  };
  const addLink = (rel, href, sizes = null) => {
    const link = document.createElement("link");
    link.rel = rel;
    link.href = href;
    if (sizes) link.sizes = sizes;
    document.head.appendChild(link);
  };

  addMeta("apple-mobile-web-app-capable", "yes");
  addMeta("apple-mobile-web-app-title", "HEHA Swipe");
  addMeta("apple-mobile-web-app-status-bar-style", "default");
  addLink("manifest", "/manifest.json");
  addLink("apple-touch-icon", "/icons/icon-180.png", "180x180");
}

if (partnerPwaEnabled) enableInstallMetadata();

if (import.meta.env.PROD && "serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    if (partnerPwaEnabled) {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // The application remains usable online if PWA registration is unavailable.
      });
      return;
    }

    // A disabled/rolled-back release must also retire an older HEHA Swipe
    // worker and its private shell caches. This does not touch other origins or
    // unrelated cache namespaces.
    navigator.serviceWorker.getRegistrations()
      .then((registrations) => Promise.all(registrations
        .filter((registration) => {
          const scriptUrl = registration.active?.scriptURL
            || registration.waiting?.scriptURL
            || registration.installing?.scriptURL
            || "";
          return new URL(scriptUrl || "/", window.location.origin).pathname === "/sw.js";
        })
        .map((registration) => registration.unregister())))
      .catch(() => {});

    if ("caches" in window) {
      caches.keys()
        .then((keys) => Promise.all(keys
          .filter((key) => key.startsWith("heha-swipe-shell-") || LEGACY_HEHA_PWA_CACHES.has(key))
          .map((key) => caches.delete(key))))
        .catch(() => {});
    }
  });
}

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
  if (partnerInviteUrlRequiresHardStop()) return <InviteUrlSafetyStop />;
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

function InviteUrlSafetyStop() {
  return (
    <main className="partner-wizard-screen">
      <section className="partner-wizard-shell">
        <div className="wizard-note" role="alert">
          HEHA could not safely remove the private invitation from this browser's address bar. Close this tab and ask HEHA for a new protected link. Do not copy or share the current URL.
        </div>
      </section>
    </main>
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
