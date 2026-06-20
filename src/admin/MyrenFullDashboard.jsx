import { useMemo, useState } from "react";
import { DASHBOARD_TABS, OVERVIEW_CARD_DEFS, TABLES, STATUS_OPTIONS } from "./dashboardSchema";
import { useMyrenDashboard } from "./useMyrenDashboard";

function formatValue(value) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if (typeof value === "string" && value.includes("T")) return value.slice(0, 10);
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function statusClass(value) {
  const text = String(value || "").toLowerCase();
  if (text.includes("approved") || text === "live" || text === "success" || text === "completed") return "good";
  if (text.includes("blocked") || text.includes("error") || text.includes("missing") || text.includes("failed")) return "risk";
  if (text.includes("review") || text.includes("waiting") || text.includes("needed") || text.includes("draft")) return "watch";
  return "neutral";
}

export default function MyrenFullDashboard({ user, roles = [], onBack }) {
  const [activeTab, setActiveTab] = useState("overview");
  const [search, setSearch] = useState("");
  const { counts, records, loading, error, lastLoadedAt, refresh } = useMyrenDashboard();

  const isGeronimo = roles.includes("super_admin");
  const isMyren = roles.includes("pm_admin") && !isGeronimo;
  const currentConfig = TABLES[activeTab];
  const currentRows = records?.[activeTab]?.rows || [];
  const currentError = records?.[activeTab]?.error;

  const filteredRows = useMemo(() => {
    if (!search.trim()) return currentRows;
    const term = search.trim().toLowerCase();
    return currentRows.filter((row) => JSON.stringify(row).toLowerCase().includes(term));
  }, [currentRows, search]);

  return (
    <main className="full-admin-dashboard">
      <div className="dashboard-toolbar">
        <button className="admin-back-button" onClick={onBack}>← Back to admin home</button>
        <button className="secondary-mini-button" onClick={refresh} disabled={loading}>{loading ? "Refreshing…" : "Refresh data"}</button>
      </div>

      <section className="admin-section-hero full-dashboard-hero">
        <p className="eyebrow">Myren PM Dashboard · Full read-only control center</p>
        <h2>Partner readiness, deals, certification, visibility, approvals, tasks, and weekly reports.</h2>
        <p>
          This dashboard is limited to Geronimo and Myren role access. Myren manages the workflow;
          Geronimo keeps final approval over certification, final deals, pricing, payment settings, sensitive publishing,
          health or quality claims, sponsor packages, and public promises.
        </p>
        <div className="role-scope-row">
          <span>Signed in: {user?.email || "internal user"}</span>
          <span>Roles: {roles.join(" · ") || "none"}</span>
          <span>{isGeronimo ? "Geronimo final approval mode" : isMyren ? "Myren workflow mode" : "Internal viewer"}</span>
          {lastLoadedAt && <span>Loaded: {new Date(lastLoadedAt).toLocaleString()}</span>}
        </div>
      </section>

      {error && <div className="admin-alert">{error}</div>}

      <section className="admin-card-grid overview-grid full-count-grid">
        {OVERVIEW_CARD_DEFS.map((card) => (
          <article className="admin-stat-card" key={card.key}>
            <span>{card.label}</span>
            <strong>{loading ? "…" : counts[card.key] ?? "—"}</strong>
            <p>{card.note}</p>
          </article>
        ))}
      </section>

      <section className="dashboard-mode-warning">
        <h3>Current safety mode</h3>
        <p>
          Full dashboard visibility is built here, but live editing controls are intentionally not activated in this screen.
          This keeps the dashboard safe while Muhammad verifies build behavior, RLS, and role access. Write workflows can be
          activated later behind Geronimo approval rules and audit logging.
        </p>
      </section>

      <nav className="admin-tab-rail" aria-label="Myren dashboard sections">
        {DASHBOARD_TABS.map((tab) => (
          <button key={tab.id} className={activeTab === tab.id ? "active" : ""} onClick={() => setActiveTab(tab.id)}>
            {tab.label}
          </button>
        ))}
      </nav>

      {activeTab === "overview" ? (
        <OverviewPanel isGeronimo={isGeronimo} isMyren={isMyren} />
      ) : (
        <section className="admin-data-panel">
          <div className="data-panel-heading">
            <div>
              <p className="eyebrow">{currentConfig?.table}</p>
              <h3>{currentConfig?.title || "Dashboard section"}</h3>
              <p>{sectionDescription(activeTab)}</p>
            </div>
            <div className="data-tools">
              <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search visible records…" />
              <span>{filteredRows.length} records</span>
            </div>
          </div>

          {currentError && <div className="admin-alert">{currentError}</div>}

          <RecordsTable config={currentConfig} rows={filteredRows} />
          <FieldGuide config={currentConfig} />
        </section>
      )}
    </main>
  );
}

function OverviewPanel({ isGeronimo, isMyren }) {
  return (
    <section className="overview-command-grid">
      <article className="command-card">
        <h3>Today’s priority order</h3>
        <ol>
          <li>Check items needing Geronimo approval.</li>
          <li>Review missing info and partner blockers.</li>
          <li>Review deal and certification queues.</li>
          <li>Check visibility mismatches across Wix, HEHA Local, HEHA Swipe, and HubSpot.</li>
          <li>Prepare the weekly report notes.</li>
        </ol>
      </article>
      <article className="command-card">
        <h3>Myren can do</h3>
        <p>Track status, organize missing assets, route content requests, prepare approval items, flag blockers, and keep weekly reporting clean.</p>
      </article>
      <article className="command-card danger-outline">
        <h3>Myren cannot approve</h3>
        <p>Certification, final deals, pricing, payments, sensitive public publishing, sponsor agreements, or public health/quality claims.</p>
      </article>
      <article className="command-card">
        <h3>Current account mode</h3>
        <p>{isGeronimo ? "You can review final-decision queues." : isMyren ? "You can manage workflow queues and route approvals." : "Read-only internal view."}</p>
      </article>
    </section>
  );
}

function RecordsTable({ config, rows }) {
  if (!config) return null;
  if (!rows.length) {
    return <div className="empty-admin-table">No records yet for this section. This is normal before Myren starts using the workflow.</div>;
  }

  return (
    <div className="admin-table-wrap">
      <table className="admin-data-table">
        <thead>
          <tr>
            {config.columns.map((column) => <th key={column}>{labelize(column)}</th>)}
            <th>Updated</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              {config.columns.map((column) => (
                <td key={column}>
                  <span className={isStatusColumn(column) ? `status-pill ${statusClass(row[column])}` : ""}>
                    {formatValue(row[column])}
                  </span>
                </td>
              ))}
              <td>{formatValue(row.updated_at || row.created_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function FieldGuide({ config }) {
  if (!config?.editable?.length) return null;
  return (
    <aside className="field-guide-box">
      <h4>Future editable fields</h4>
      <p>These fields are prepared for the next phase, but editing is not active in this safety build.</p>
      <div className="field-chip-row">
        {config.editable.map((field) => <span key={field}>{labelize(field)}</span>)}
      </div>
      <StatusGuide fields={config.editable} />
    </aside>
  );
}

function StatusGuide({ fields }) {
  const visible = fields.filter((field) => STATUS_OPTIONS[field]);
  if (!visible.length) return null;
  return (
    <div className="status-guide-grid">
      {visible.map((field) => (
        <div key={field}>
          <strong>{labelize(field)}</strong>
          <p>{STATUS_OPTIONS[field].join(" · ")}</p>
        </div>
      ))}
    </div>
  );
}

function labelize(value) {
  return String(value || "").replaceAll("_", " ").replace(/\b\w/g, (char) => char.toUpperCase());
}

function isStatusColumn(column) {
  return column.includes("status") || column.includes("priority") || column.includes("risk") || column.includes("approval");
}

function sectionDescription(tabId) {
  const descriptions = {
    partners: "Track each business from lead status to profile readiness, listing status, and certification review readiness.",
    missing: "Track every missing logo, photo, description, link, menu, proof point, deal term, or follow-up item.",
    deals: "Track Community Pass, Swoop, SuperSwoop, founding offers, and local discounts before Geronimo approval.",
    certification: "Keep listed businesses separate from HEHA Certified / Verified businesses until Geronimo decides.",
    visibility: "Catch inconsistent or broken visibility across HEHA Swipe, HEHA Local, Wix, HubSpot, Instagram, and newsletter.",
    content: "Coordinate profile copy, deal cards, Canva graphics, social posts, HEHA Local listings, Wix copy, and newsletter features.",
    approvals: "Central queue for everything Geronimo must approve before it goes public or becomes final.",
    tasks: "Track team tasks, blockers, next steps, due dates, and approval needs across app, Wix, content, outreach, HubSpot, Sheets, and QA.",
    reports: "Prepare weekly updates: what moved forward, what is blocked, what needs approval, closest-to-live items, and next-week focus.",
  };
  return descriptions[tabId] || "Internal dashboard section.";
}
