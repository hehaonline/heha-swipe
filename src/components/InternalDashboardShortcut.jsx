import { useEffect, useState } from "react";
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

  if (!visible) return null;

  return (
    <button
      type="button"
      onClick={() => window.location.assign("/admin")}
      aria-label="Open HEHA internal dashboard"
      style={{
        position: "fixed",
        right: "18px",
        bottom: "92px",
        zIndex: 9999,
        border: "1px solid rgba(255, 126, 26, 0.35)",
        borderRadius: "999px",
        padding: "12px 17px",
        background: "#154d3b",
        color: "#fff",
        fontWeight: 700,
        fontSize: "14px",
        boxShadow: "0 10px 30px rgba(0, 0, 0, 0.18)",
        cursor: "pointer",
      }}
    >
      Open HEHA Dashboard
    </button>
  );
}
