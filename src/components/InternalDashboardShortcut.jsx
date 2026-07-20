import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { supabase } from "../lib/supabase";

const INTERNAL_ROLES = new Set([
  "super_admin",
  "developer_admin",
  "pm_admin",
  "community_events_admin",
  "som_admin",
]);

export default function InternalDashboardShortcut() {
  const [visible, setVisible] = useState(false);
  const [profileHost, setProfileHost] = useState(null);

  useEffect(() => {
    let cancelled = false;

    const checkAccess = async () => {
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData?.session?.user?.id;

      if (!userId) {
        if (!cancelled) setVisible(false);
        return;
      }

      const { data, error } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", userId)
        .eq("active", true);

      if (cancelled) return;
      if (error) {
        setVisible(false);
        return;
      }

      setVisible((data || []).some((item) => INTERNAL_ROLES.has(item.role)));
    };

    checkAccess();

    const { data: authListener } = supabase.auth.onAuthStateChange(() => {
      checkAccess();
    });

    return () => {
      cancelled = true;
      authListener?.subscription?.unsubscribe?.();
    };
  }, []);

  useEffect(() => {
    const locateProfile = () => {
      setProfileHost(document.querySelector(".profile-screen"));
    };

    locateProfile();
    const observer = new MutationObserver(locateProfile);
    observer.observe(document.body, { childList: true, subtree: true });

    return () => observer.disconnect();
  }, []);

  if (!visible || !profileHost) return null;

  return createPortal(
    <div className="profile-card card-like" aria-label="HEHA internal dashboard access">
      <p className="eyebrow">HEHA team access</p>
      <h3>Internal dashboard</h3>
      <p>Open the dashboard assigned to your active HEHA role.</p>
      <button
        type="button"
        className="primary-button"
        onClick={() => window.location.assign("/admin")}
        aria-label="Open HEHA internal dashboard"
      >
        Open HEHA Dashboard
      </button>
    </div>,
    profileHost
  );
}
