import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const INTERNAL_ROLES = [
  "super_admin",
  "developer_admin",
  "pm_admin",
  "community_events_admin",
  "som_admin",
];

const PARTNER_TYPES = [
  "instagram",
  "monthly",
  "partner_free",
  "partner_supporter",
  "partner_instagram",
  "partner_monthly",
  "partner",
  "listed",
];

const DOMAINS = [
  { code: "CTRL", number: "01", label: "Control", color: "#49B654" },
  { code: "OPS", number: "02", label: "Operations", color: "#F47C35" },
  { code: "TECH", number: "03", label: "Technology", color: "#3478F6" },
  { code: "GROW", number: "04", label: "Growth", color: "#8B4DE8" },
  { code: "COMM", number: "05", label: "Community", color: "#F5B82E" },
];

function isPartnerType(value) {
  const type = String(value || "");
  return PARTNER_TYPES.some((accepted) => type === accepted || type.startsWith(`${accepted}_`));
}

function clickSwipeTab(label) {
  const button = [...document.querySelectorAll(".bottom-nav button")].find((item) =>
    item.textContent?.toLowerCase().includes(label.toLowerCase())
  );
  button?.click();
}

export default function InternalDashboardShortcut() {
  const [account, setAccount] = useState({ signedIn: false, internalRole: null, isBusiness: false });
  const [open, setOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;

    const checkAccess = async () => {
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData?.session?.user?.id;
      if (!userId) {
        if (!cancelled) setAccount({ signedIn: false, internalRole: null, isBusiness: false });
        return;
      }

      const [roleResult, profileResult, listingResult] = await Promise.all([
        supabase.from("user_roles").select("role").eq("user_id", userId).eq("active", true),
        supabase.from("profiles").select("subscription_type").eq("id", userId).maybeSingle(),
        supabase.from("partners").select("id").eq("owner_id", userId).limit(1),
      ]);
      if (cancelled) return;

      const roles = new Set((roleResult.data || []).map((item) => item.role));
      const internalRole = INTERNAL_ROLES.find((role) => roles.has(role)) || null;
      const isBusiness = isPartnerType(profileResult.data?.subscription_type) || Boolean(listingResult.data?.length);
      setAccount({ signedIn: true, internalRole, isBusiness });
    };

    checkAccess();
    const { data: authListener } = supabase.auth.onAuthStateChange(() => checkAccess());
    return () => {
      cancelled = true;
      authListener?.subscription?.unsubscribe?.();
    };
  }, []);

  const roleLabel = account.internalRole
    ? account.internalRole.replace(/_/g, " ")
    : account.isBusiness
      ? "partner"
      : "customer";

  const actions = useMemo(() => {
    if (account.internalRole) {
      return {
        CTRL: { access: "Operate", detail: "Approvals, routing, governance, and requests.", action: () => window.location.assign("/admin") },
        OPS: { access: "Open Local", detail: "Orders, dispatch, partners, drivers, payouts, and service delivery.", action: () => window.location.assign("https://hehalocal.app/admin") },
        TECH: { access: account.internalRole === "super_admin" || account.internalRole === "developer_admin" ? "Operate" : "Request", detail: "Systems, bugs, releases, security, and architecture.", action: () => window.location.assign(account.internalRole === "super_admin" || account.internalRole === "developer_admin" ? "/admin" : "https://hehalocal.app/request-help?domain=TECH&type=support") },
        GROW: { access: "Operate", detail: "Scout, onboarding, readiness, partnerships, and expansion.", action: () => window.location.assign("/admin/scout") },
        COMM: { access: account.internalRole === "community_events_admin" || account.internalRole === "super_admin" || account.internalRole === "developer_admin" ? "Operate" : "Request", detail: "Content, events, community, media, and partner launch assets.", action: () => window.location.assign(account.internalRole === "community_events_admin" || account.internalRole === "super_admin" || account.internalRole === "developer_admin" ? "/admin/community" : "https://hehalocal.app/request-help?domain=COMM&type=support") },
      };
    }

    if (account.isBusiness) {
      return {
        CTRL: { access: "Request", detail: "Approval, policy, payment review, or account changes.", action: () => window.location.assign("https://hehalocal.app/request-help?domain=CTRL&type=approval") },
        OPS: { access: "Operate", detail: "Orders, menu or products, ingredients, payouts, and fulfillment.", action: () => window.location.assign("https://hehalocal.app/restaurant") },
        TECH: { access: "Request", detail: "Dashboard, menu import, integration, or system support.", action: () => window.location.assign("https://hehalocal.app/request-help?domain=TECH&type=support") },
        GROW: { access: "Participate", detail: "Your Swipe listing, readiness, visibility, and partnership growth.", action: () => { setOpen(false); clickSwipeTab("Profile"); } },
        COMM: { access: "Participate", detail: "Community offers, events, media, and launch updates.", action: () => { setOpen(false); clickSwipeTab("Community"); } },
      };
    }

    return {
      CTRL: { access: "Request", detail: "Account, privacy, dispute, or formal support request.", action: () => window.location.assign("https://hehalocal.app/request-help?domain=CTRL&type=support") },
      OPS: { access: "Operate", detail: "Orders, delivery status, addresses, payments, and reorders.", action: () => window.location.assign("https://hehalocal.app/customer") },
      TECH: { access: "Request", detail: "Report login, checkout, app, notification, or accessibility issues.", action: () => window.location.assign("https://hehalocal.app/request-help?domain=TECH&type=support") },
      GROW: { access: "Discover", detail: "Find local healthy partners and new HEHA neighborhoods.", action: () => { setOpen(false); clickSwipeTab("Discover"); } },
      COMM: { access: "Participate", detail: "Community Pass, events, offers, and local impact.", action: () => { setOpen(false); clickSwipeTab("Community"); } },
    };
  }, [account.internalRole, account.isBusiness]);

  if (!account.signedIn) return null;

  return (
    <>
      <button
        type="button"
        className="one-heha-launcher"
        onClick={() => setOpen(true)}
        aria-label="Open ONE HEHA workspaces"
      >
        <span>ONE HEHA</span>
        <small>Workspaces</small>
      </button>

      {open && (
        <div className="one-heha-overlay" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && setOpen(false)}>
          <section className="one-heha-workspace-panel" role="dialog" aria-modal="true" aria-label="ONE HEHA workspaces">
            <header>
              <div>
                <p>ONE HEHA · ZERO BUREAUCRACY</p>
                <h2>Your connected workspaces</h2>
                <span>{roleLabel}</span>
              </div>
              <button type="button" onClick={() => setOpen(false)} aria-label="Close workspaces">×</button>
            </header>
            <p className="one-heha-workspace-intro">All five pillars stay visible. You operate what your role allows and send one structured request for everything else.</p>
            <div className="one-heha-workspace-grid">
              {DOMAINS.map((domain) => {
                const item = actions[domain.code];
                return (
                  <button key={domain.code} type="button" style={{ "--domain-color": domain.color }} onClick={item.action}>
                    <span className="one-heha-code">{domain.number} {domain.code}</span>
                    <strong>{domain.label}</strong>
                    <p>{item.detail}</p>
                    <small>{item.access} →</small>
                  </button>
                );
              })}
            </div>
            <footer>
              <span>One structure across HEHA Swipe, HEHA Local, and future ops.heha.online.</span>
            </footer>
          </section>
        </div>
      )}
    </>
  );
}
