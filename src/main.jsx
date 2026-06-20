import { StrictMode } from "react";
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
import AdminApp from "./AdminApp.jsx";

// Route to AdminApp on admin subdomain or local dev (localhost / 127.0.0.1).
// The public HEHA Swipe app loads on all other hostnames — it is completely unaffected.
// AdminApp does its own isAllowedAdminHost() check internally for additional safety.
const ADMIN_HOSTS = new Set(["admin.hehaswipe.app"]);
const host = window.location.hostname;
const isAdminHost = ADMIN_HOSTS.has(host) || host === "localhost" || host === "127.0.0.1";

const RootComponent = isAdminHost ? AdminApp : App;

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <RootComponent />
  </StrictMode>
);
