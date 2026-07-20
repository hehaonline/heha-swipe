import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";

const LOCAL_URL = "https://hehalocal.app";

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

const DOMAIN_COLORS = {
  CTRL: "#49B654",
  OPS: "#F47C35",
  TECH: "#3478F6",
  GROW: "#8B4DE8",
  COMM: "#F5B82E",
};

function isPartnerType(value) {
  const type = String(value || "");
  return PARTNER_TYPES.some((accepted) => type === accepted || type.startsWith(`${accepted}_`));
}

function clickByText(selector, label) {
  const element = [...document.querySelectorAll(selector)].find((item) =>
    item.textContent?.toLowerCase().includes(label.toLowerCase())
  );
  element?.click();
}

function local(path) {
  window.location.assign(`${LOCAL_URL}${path}`);
}

export default function OneHehaCommandPalette() {
  const [account, setAccount] = useState({ signedIn: false, internalRole: null, isBusiness: false });
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const inputRef = useRef(null);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
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
      setAccount({
        signedIn: true,
        internalRole: INTERNAL_ROLES.find((role) => roles.has(role)) || null,
        isBusiness: isPartnerType(profileResult.data?.subscription_type) || Boolean(listingResult.data?.length),
      });
    };
    load();
    const { data: listener } = supabase.auth.onAuthStateChange(() => load());
    return () => {
      cancelled = true;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);

  useEffect(() => {
    const onKeyDown = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen((current) => !current);
      }
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  useEffect(() => {
    if (!open) return;
    const timer = window.setTimeout(() => inputRef.current?.focus(), 30);
    return () => window.clearTimeout(timer);
  }, [open]);

  const commands = useMemo(() => {
    const swipe = [
      { id: "discover", title: "Discover local partners", description: "Return to the HEHA Swipe discovery deck.", domain: "GROW", keywords: ["discover", "swipe", "partners", "local"], run: () => clickByText(".bottom-nav button", "Discover") },
      { id: "saved", title: "Saved partners", description: "Open businesses and places you saved.", domain: "GROW", keywords: ["saved", "favorites", "faves", "partners"], run: () => clickByText(".bottom-nav button", "Saved") },
      { id: "community", title: "Community and offers", description: "Community Pass, events, offers, and local impact.", domain: "COMM", keywords: ["community", "events", "offers", "pass"], run: () => clickByText(".bottom-nav button", "Community") },
      { id: "profile", title: "Profile and inbox", description: "Account, business listing, messages, and saved settings.", domain: "CTRL", keywords: ["profile", "inbox", "account", "messages"], run: () => clickByText(".bottom-nav button", "Profile") },
      { id: "get-listed", title: "Get listed on HEHA", description: "Start or continue the partner onboarding flow.", domain: "GROW", keywords: ["get listed", "onboarding", "partner", "business"], run: () => clickByText("button", "Get listed") },
    ];

    const requests = [
      { id: "request-ctrl", title: "Request a CTRL decision", description: "Approval, governance, account, finance, or policy support.", domain: "CTRL", keywords: ["approval", "governance", "account", "finance"], run: () => local("/request-help?domain=CTRL&type=approval") },
      { id: "request-ops", title: "Request OPS support", description: "Order, delivery, driver, partner, or fulfillment support.", domain: "OPS", keywords: ["order", "delivery", "driver", "operations"], run: () => local("/request-help?domain=OPS&type=support") },
      { id: "request-tech", title: "Request TECH support", description: "Login, bug, integration, dashboard, or accessibility issue.", domain: "TECH", keywords: ["bug", "login", "integration", "technical"], run: () => local("/request-help?domain=TECH&type=support") },
      { id: "request-grow", title: "Request GROW support", description: "Onboarding, readiness, outreach, visibility, or expansion.", domain: "GROW", keywords: ["growth", "readiness", "outreach", "expansion"], run: () => local("/request-help?domain=GROW&type=question") },
      { id: "request-comm", title: "Request COMM support", description: "Events, offers, photos, content, or community activation.", domain: "COMM", keywords: ["event", "offer", "photo", "content"], run: () => local("/request-help?domain=COMM&type=question") },
    ];

    const localCommands = account.isBusiness
      ? [
          { id: "local-partner", title: "Open partner operations", description: "Orders, menu items, ingredients, payouts, and fulfillment in HEHA Local.", domain: "OPS", keywords: ["local", "restaurant", "menu", "products", "orders"], run: () => local("/restaurant") },
        ]
      : [
          { id: "local-customer", title: "Open customer operations", description: "Orders, delivery status, addresses, payments, and support in HEHA Local.", domain: "OPS", keywords: ["local", "customer", "orders", "delivery"], run: () => local("/customer") },
        ];

    if (!account.internalRole) return [...swipe, ...localCommands, ...requests];

    const internal = [
      { id: "admin-home", title: "Five-domain internal dashboard", description: "Open the ONE HEHA internal command view.", domain: "CTRL", keywords: ["admin", "dashboard", "five domains", "control"], run: () => window.location.assign("/admin") },
      { id: "routing", title: "Partner routing", description: "Approve partner destinations and customer routing.", domain: "CTRL", keywords: ["routing", "partner", "approve"], run: () => window.location.assign("/admin/routing") },
      { id: "scout", title: "Scout and partner pipeline", description: "Field leads, partner discovery, and growth pipeline.", domain: "GROW", keywords: ["scout", "leads", "pipeline", "growth"], run: () => window.location.assign("/admin/scout") },
      { id: "pm", title: "Project Manager workspace", description: "Partner readiness, tasks, visibility, and coordination.", domain: "GROW", keywords: ["myren", "project manager", "readiness", "tasks"], run: () => window.location.assign("/admin/pm") },
      { id: "community-admin", title: "Community and Event workspace", description: "Events, outreach, applications, and recaps.", domain: "COMM", keywords: ["community", "event", "nina", "applications"], run: () => window.location.assign("/admin/community") },
      { id: "som-admin", title: "SOM growth handoff", description: "Partner handoff and sales-operations coordination.", domain: "OPS", keywords: ["som", "sales operations", "handoff"], run: () => window.location.assign("/admin/som") },
      { id: "local-admin", title: "Open HEHA Local Command Center", description: "Canonical orders, dispatch, requests, items, payouts, and service delivery.", domain: "OPS", keywords: ["local", "orders", "dispatch", "requests", "items"], run: () => local("/admin") },
      { id: "local-requests", title: "Open requests and approvals", description: "Shared assignment, escalation, response, and resolution queue.", domain: "CTRL", keywords: ["requests", "approvals", "escalation", "inbox"], run: () => local("/admin/requests") },
    ];

    return [...internal, ...swipe, ...requests];
  }, [account.internalRole, account.isBusiness]);

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return commands;
    return commands.filter((command) => [command.title, command.description, command.domain, ...(command.keywords || [])].join(" ").toLowerCase().includes(normalized));
  }, [commands, query]);

  if (!account.signedIn) return null;

  const run = (command) => {
    setOpen(false);
    setQuery("");
    command.run();
  };

  return (
    <>
      <button type="button" className="one-heha-search-launcher" onClick={() => setOpen(true)} aria-label="Search ONE HEHA">
        <span aria-hidden="true">⌕</span>
        <strong>Search</strong>
        <small>⌘K</small>
      </button>

      {open && (
        <div className="one-heha-command-overlay" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && setOpen(false)}>
          <section className="one-heha-command-panel" role="dialog" aria-modal="true" aria-label="ONE HEHA search">
            <header>
              <span aria-hidden="true">⌕</span>
              <input ref={inputRef} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search partners, dashboards, requests, events…" />
              <button type="button" onClick={() => setOpen(false)} aria-label="Close search">×</button>
            </header>
            <div className="one-heha-command-results">
              {filtered.map((command) => (
                <button key={command.id} type="button" onClick={() => run(command)}>
                  <span className="one-heha-command-dot" style={{ background: DOMAIN_COLORS[command.domain] }} />
                  <span className="one-heha-command-copy"><strong>{command.title}</strong><small>{command.description}</small></span>
                  <span className="one-heha-command-domain">{command.domain}</span>
                </button>
              ))}
              {!filtered.length && <p className="one-heha-command-empty">No matching HEHA destination.</p>}
            </div>
            <footer>Navigation does not replace role checks, approvals, or canonical data ownership.</footer>
          </section>
        </div>
      )}
    </>
  );
}
