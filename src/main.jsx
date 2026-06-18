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

const rootComponent = window.location.hostname === "admin.hehaswipe.app" ? AdminApp : App;
const RootComponent = rootComponent;

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <RootComponent />
  </StrictMode>
);
