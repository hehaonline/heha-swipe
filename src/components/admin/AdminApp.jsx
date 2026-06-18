import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import AuthScreen from "../AuthScreen";

const COMMUNITY_ROLES = ["super_admin", "pm_admin", "community_events_admin", "developer_admin"];
const INTERNAL_ROLES = [...COMMUNITY_ROLES, "content_editor", "viewer"];
const FINAL_ROLES = ["super_admin", "developer_admin"];
const DEFAULT_COUNTS = { apps: 0, concepts: 0, invites: 0, content: 0, approvals: 0, recaps: 0 };

export default function AdminApp({ session, loading, onSignOut }) {
  const [role, setRole] = useState(null);
  const [checkingRole, setCheckingRole] = useState(true);
  const [area, setArea] = useState(() => window.location.pathname.includes("/community") ? "community" : window.location.pathname.includes("/pm") ? "pm" : "home");
  const [tab, setTab] = useState("overview");
  const [counts, setCounts] = useState(DEFAULT_COUNTS);
  const [rows, setRows] = useState({ apps: [], concepts: [], invites: [], content: [], approvals: [], recaps: [] });
  const [notice, setNotice] = useState(null);

  const access = useMemo(() => ({
    internal: INTERNAL_ROLES.includes(role),
    community: COMMUNITY_ROLES.includes(role),
    final: FINAL_ROLES.includes(role),
  }), [role]);

  useEffect(() => {
    if (!session?.user?.id) {
      setRole(null);
      setCheckingRole(false);
      return;
    }
    checkRole(session.user.id);
  }, [session?.user?.id]);

  useEffect(() => {
    if (access.community && area === "community") loadCommunity();
  }, [access.community, area]);

  async function checkRole(userId) {
    setCheckingRole(true);
    const { data, error } = await supabase.from("user_roles").select("role").eq("user_id", userId).eq("active", true).limit(1);
    if (!error) setRole(data?.[0]?.role || null);
    setCheckingRole(false);
  }

  function openArea(nextArea) {
    setArea(nextArea);
    window.history.pushState({}, "", nextArea === "community" ? "/admin/community" : nextArea === "pm" ? "/admin/pm" : "/admin");
  }

  function flash(message) {
    setNotice(message);
    window.setTimeout(() => setNotice(null), 2500);
  }

  async function count(table, setup = (q) => q) {
    const { count: result, error } = await setup(supabase.from(table).select("id", { count: "exact", head: true }));
    if (error) throw error;
    return result || 0;
  }

  async function loadCommunity() {
    try {
      const [apps, concepts, invites, content, approvals, recaps] = await Promise.all([
        supabase.from("event_applications").select("*").order("created_at", { ascending: false }).limit(10),
        supabase.from("event_concepts").select("*").order("created_at", { ascending: false }).limit(10),
        supabase.from("invite_list").select("*").order("created_at", { ascending: false }).limit(10),
        supabase.from("admin_content_requests").select("*").eq("dashboard_area", "community_events").order("created_at", { ascending: false }).limit(10),
        supabase.from("admin_approval_requests").select("*").eq("dashboard_area", "community_events").order("created_at", { ascending: false }).limit(10),
        supabase.from("event_recaps").select("*").order("created_at", { ascending: false }).limit(10),
      ]);
      [apps, concepts, invites, content, approvals, recaps].forEach((item) => { if (item.error) throw item.error; });
      setRows({ apps: apps.data || [], concepts: concepts.data || [], invites: invites.data || [], content: content.data || [], approvals: approvals.data || [], recaps: recaps.data || [] });
      const [appsCount, conceptsCount, invitesCount, contentCount, approvalsCount, recapsCount] = await Promise.all([
        count("event_applications"), count("event_concepts"), count("invite_list"),
        count("admin_content_requests", (q) => q.eq("dashboard_area", "community_events")),
        count("admin_approval_requests", (q) => q.eq("dashboard_area", "community_events")),
        count("event_recaps"),
      ]);
      setCounts({ apps: appsCount, concepts: conceptsCount, invites: invitesCount, content: contentCount, approvals: approvalsCount, recaps: recapsCount });
    } catch (error) {
      flash(error.message || "Dashboard data could not load.");
    }
  }

  async function save(table, payload, message) {
    const { error } = await supabase.from(table).insert(payload);
    if (error) return flash(error.message || "Could not save.");
    flash(message);
    loadCommunity();
  }

  if (loading || checkingRole) return <AdminShell title="Checking admin access…" />;
  if (!session) return <AuthScreen />;
  if (!access.internal) return <AdminShell title="Internal only" message="Customers and business accounts cannot access HEHA admin tools, approval queues, invite lists, PM notes, or event operations." action={onSignOut} />;

  return (
    <div className="admin-shell">
      <header className="admin-topbar">
        <div><p className="eyebrow">admin.hehaswipe.app</p><h1>HEHA Swipe Admin</h1></div>
        <div className="admin-actions"><span>{label(role)}</span><button onClick={onSignOut}>Sign out</button></div>
      </header>
      {notice && <div className="admin-toast">{notice}</div>}
      {area === "home" && <AdminHome role={role} openArea={openArea} />}
      {area === "pm" && <PmPlaceholder openArea={openArea} />}
      {area === "community" && access.community && <Community tab={tab} setTab={setTab} counts={counts} rows={rows} save={save} final={access.final} openArea={openArea} refresh={loadCommunity} />}
      {area === "community" && !access.community && <AdminShell title="Community dashboard blocked" message="This role can enter internal admin, but cannot manage Niña’s Community / Events workflow." action={() => openArea("home")} actionLabel="Back" />}
    </div>
  );
}

function AdminShell({ title, message = "Protected HEHA internal dashboard.", action, actionLabel = "Sign out" }) {
  return <div className="admin-loading"><section><p className="eyebrow">HEHA internal</p><h1>{title}</h1><p>{message}</p>{action && <button onClick={action}>{actionLabel}</button>}</section></div>;
}

function AdminHome({ openArea, role }) {
  return <main className="admin-home">
    <section className="admin-card wide"><p className="eyebrow">internal command center</p><h2>Choose your dashboard</h2><p>Two clean lanes: Myren manages PM/partner workflow, and Niña manages Community / Events. Regular users and businesses do not get access.</p></section>
    <button className="admin-card click" onClick={() => openArea("pm")}><span>01</span><strong>PM Dashboard</strong><p>Partner onboarding, readiness, visibility, deals, certification status, blockers, and weekly progress for Myren.</p></button>
    <button className="admin-card click orange" onClick={() => openArea("community")}><span>02</span><strong>COMMUNITY / EVENTS</strong><p>Applications, event concepts, invite lists, outreach, content requests, approval queue, and recaps for Niña.</p></button>
    <section className="admin-card"><p className="eyebrow">role</p><h3>{label(role)}</h3><p>Access is controlled by Supabase RLS, not just by hidden buttons.</p></section>
  </main>;
}

function PmPlaceholder({ openArea }) {
  return <main className="admin-panel"><button className="back-button" onClick={() => openArea("home")}>← Admin home</button><section className="admin-card wide"><p className="eyebrow">PM Dashboard</p><h2>Myren’s lane is protected here.</h2><p>The database already has PM tables for partner readiness, missing items, content, deals, certification, visibility, HubSpot links, tasks, approvals, and weekly reports. This branch keeps the two-button structure ready while we build Niña first.</p></section></main>;
}

function Community({ tab, setTab, counts, rows, save, final, openArea, refresh }) {
  return <main className="admin-panel">
    <button className="back-button" onClick={() => openArea("home")}>← Admin home</button>
    <section className="admin-card wide"><p className="eyebrow">Niña dashboard</p><h2>COMMUNITY / EVENTS</h2><p>Niña can organize, draft, request, track, and recommend. Final public commitments stay with Geronimo.</p><button onClick={refresh}>Refresh</button></section>
    <nav className="admin-tabs">{["overview","applications","concepts","invites","content","approvals","recaps","future"].map((item) => <button key={item} className={tab === item ? "active" : ""} onClick={() => setTab(item)}>{label(item)}</button>)}</nav>
    {tab === "overview" && <Overview counts={counts} rows={rows} final={final} />}
    {tab === "applications" && <Applications rows={rows.apps} save={save} />}
    {tab === "concepts" && <Concepts rows={rows.concepts} save={save} />}
    {tab === "invites" && <Invites rows={rows.invites} save={save} />}
    {tab === "content" && <Content rows={rows.content} save={save} />}
    {tab === "approvals" && <Approvals rows={rows.approvals} save={save} final={final} />}
    {tab === "recaps" && <Recaps rows={rows.recaps} save={save} />}
    {tab === "future" && <Future />}
  </main>;
}

function Overview({ counts, rows, final }) {
  return <section className="admin-grid">
    <Guard final={final} />
    {[["Applications", counts.apps], ["Concepts", counts.concepts], ["Invites", counts.invites], ["Content", counts.content], ["Approvals", counts.approvals], ["Recaps", counts.recaps]].map(([name, value]) => <Metric key={name} name={name} value={value} />)}
    <List title="Recent applications" rows={rows.apps} main="applicant_name" sub="application_type" status="status" />
    <List title="Recent concepts" rows={rows.concepts} main="title" sub="event_type" status="status" />
  </section>;
}

function Applications({ rows, save }) {
  const [f, set] = useForm({ applicant_name: "", brand_or_business_name: "", application_type: "vendor", email: "", phone: "", instagram: "", category: "", event_interest: "", status: "new" });
  return <Module title="Event Applications" rows={rows} main="applicant_name" sub="application_type" status="status"><Form onSubmit={() => save("event_applications", f, "Application added.")}><Input label="Applicant" v={f.applicant_name} set={(v) => set("applicant_name", v)} required /><Input label="Brand" v={f.brand_or_business_name} set={(v) => set("brand_or_business_name", v)} /><Input label="Type" v={f.application_type} set={(v) => set("application_type", v)} /><Input label="Email" v={f.email} set={(v) => set("email", v)} /><Input label="Phone" v={f.phone} set={(v) => set("phone", v)} /><Input label="Instagram" v={f.instagram} set={(v) => set("instagram", v)} /><Text label="Interest" v={f.event_interest} set={(v) => set("event_interest", v)} /></Form></Module>;
}

function Concepts({ rows, save }) {
  const [f, set] = useForm({ title: "", event_type: "soft_launch_mixer", event_goal: "", target_audience: "", proposed_location: "", proposed_date_window: "", status: "draft" });
  return <Module title="Event Concepts" rows={rows} main="title" sub="event_type" status="status"><Form onSubmit={() => save("event_concepts", f, "Event concept saved.")}><Input label="Title" v={f.title} set={(v) => set("title", v)} required /><Input label="Type" v={f.event_type} set={(v) => set("event_type", v)} /><Input label="Goal" v={f.event_goal} set={(v) => set("event_goal", v)} /><Input label="Audience" v={f.target_audience} set={(v) => set("target_audience", v)} /><Input label="Proposed location" v={f.proposed_location} set={(v) => set("proposed_location", v)} /><Input label="Proposed date window" v={f.proposed_date_window} set={(v) => set("proposed_date_window", v)} /></Form></Module>;
}

function Invites({ rows, save }) {
  const [f, set] = useForm({ name: "", contact_method: "instagram", instagram: "", email: "", phone: "", category: "", invite_status: "not_contacted", rsvp_status: "unknown" });
  return <Module title="Invite List" rows={rows} main="name" sub="category" status="invite_status"><Form onSubmit={() => save("invite_list", f, "Invite lead added.")}><Input label="Name" v={f.name} set={(v) => set("name", v)} required /><Input label="Contact method" v={f.contact_method} set={(v) => set("contact_method", v)} /><Input label="Instagram" v={f.instagram} set={(v) => set("instagram", v)} /><Input label="Email" v={f.email} set={(v) => set("email", v)} /><Input label="Phone" v={f.phone} set={(v) => set("phone", v)} /><Input label="Category" v={f.category} set={(v) => set("category", v)} /></Form></Module>;
}

function Content({ rows, save }) {
  const [f, set] = useForm({ dashboard_area: "community_events", request_title: "", request_type: "event_flyer", priority: "medium", key_message: "", approval_needed: true, status: "requested" });
  return <Module title="Content Requests" rows={rows} main="request_title" sub="request_type" status="status"><Form onSubmit={() => save("admin_content_requests", f, "Content request added.")}><Input label="Title" v={f.request_title} set={(v) => set("request_title", v)} required /><Input label="Type" v={f.request_type} set={(v) => set("request_type", v)} /><Input label="Priority" v={f.priority} set={(v) => set("priority", v)} /><Text label="Key message" v={f.key_message} set={(v) => set("key_message", v)} /></Form></Module>;
}

function Approvals({ rows, save, final }) {
  const [f, set] = useForm({ dashboard_area: "community_events", related_type: "event", approval_type: "event_concept_approval", approval_reason: "", risk_level: "medium", status: "needs_geronimo_review" });
  return <Module title="Geronimo Approval Queue" rows={rows} main="approval_type" sub="approval_reason" status="status"><Guard final={final} /><Form onSubmit={() => save("admin_approval_requests", f, "Approval request added.")}><Input label="Approval type" v={f.approval_type} set={(v) => set("approval_type", v)} required /><Input label="Risk" v={f.risk_level} set={(v) => set("risk_level", v)} /><Text label="Reason" v={f.approval_reason} set={(v) => set("approval_reason", v)} /></Form></Module>;
}

function Recaps({ rows, save }) {
  const [f, set] = useForm({ event_name: "", event_date: "", location: "", estimated_attendance: "", new_leads_collected: "", app_signups: "", what_worked: "" });
  const payload = { ...f, estimated_attendance: f.estimated_attendance ? Number(f.estimated_attendance) : null, new_leads_collected: f.new_leads_collected ? Number(f.new_leads_collected) : null, app_signups: f.app_signups ? Number(f.app_signups) : null };
  return <Module title="Event Recaps" rows={rows} main="event_name" sub="location" status="event_date"><Form onSubmit={() => save("event_recaps", payload, "Event recap saved.")}><Input label="Event name" v={f.event_name} set={(v) => set("event_name", v)} required /><Input label="Date" type="date" v={f.event_date} set={(v) => set("event_date", v)} /><Input label="Location" v={f.location} set={(v) => set("location", v)} /><Input label="Attendance" type="number" v={f.estimated_attendance} set={(v) => set("estimated_attendance", v)} /><Text label="What worked" v={f.what_worked} set={(v) => set("what_worked", v)} /></Form></Module>;
}

function Future() {
  return <section className="admin-grid"><section className="admin-card wide"><p className="eyebrow">later</p><h2>Business dashboard split</h2><p><strong>Swipe</strong> becomes the business marketing dashboard: profile, photos, offers, Swipe stats, SuperSwoop/Swoop requests, events, and community visibility.</p><p><strong>Local</strong> becomes the business operational dashboard: orders, bookings, availability, hours, menu/service details, instructions, issue requests, and fulfillment.</p><p>Business users should never see internal PM notes, Niña invite lists, approval queues, or admin-only publishing controls.</p></section></section>;
}

function Module({ title, rows, main, sub, status, children }) { return <section className="admin-crud"><h2>{title}</h2>{children}<List rows={rows} main={main} sub={sub} status={status} /></section>; }
function Form({ children, onSubmit }) { return <form className="admin-form" onSubmit={(e) => { e.preventDefault(); onSubmit(); }}>{children}<button type="submit">Save</button></form>; }
function Input({ label: text, v, set, required, type = "text" }) { return <label><span>{text}</span><input type={type} value={v || ""} onChange={(e) => set(e.target.value)} required={required} /></label>; }
function Text({ label: text, v, set }) { return <label className="wide"><span>{text}</span><textarea value={v || ""} onChange={(e) => set(e.target.value)} /></label>; }
function List({ title, rows, main, sub, status }) { return <section className="admin-list">{title && <h3>{title}</h3>}{!rows?.length ? <p className="empty">No records yet.</p> : rows.map((r) => <article key={r.id}><div><strong>{r[main] || "Untitled"}</strong><p>{r[sub] || "No details yet"}</p></div><span>{label(r[status] || "draft")}</span></article>)}</section>; }
function Metric({ name, value }) { return <section className="metric"><span>{name}</span><strong>{value}</strong></section>; }
function Guard({ final }) { return <section className="guard"><strong>{final ? "Final approval role" : "Approval guardrail active"}</strong><p>{final ? "This role can finalize protected items." : "This role can organize and submit, but cannot approve, publish, schedule, or make final public commitments."}</p></section>; }
function useForm(initial) { const [state, setState] = useState(initial); return [state, (key, value) => setState((current) => ({ ...current, [key]: value }))]; }
function label(value) { return String(value || "").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()); }
