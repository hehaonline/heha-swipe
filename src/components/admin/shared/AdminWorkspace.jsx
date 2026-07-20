import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { AdminCard, Guard, Metric, RecordForm, RecordList, Tabs, useFormState } from "./AdminPrimitives";

function applyFilter(query, filter) {
  if (!filter) return query;
  if (filter.type === "eq") return query.eq(filter.column, filter.value);
  if (filter.type === "in") return query.in(filter.column, filter.value);
  return query;
}

function cleanPayload(payload) {
  return Object.entries(payload).reduce((next, [key, value]) => {
    next[key] = value === "" ? null : value;
    return next;
  }, {});
}

async function runScoutHubSpotSync() {
  const { data: released, error: releaseError } = await supabase.rpc("release_hubspot_sync_queue", {
    p_limit: 10,
  });

  if (releaseError) throw releaseError;
  if (!released) return { success: 0, released: 0 };

  const { data, error } = await supabase.functions.invoke("hubspot-sync", {
    body: { limit: Math.min(Number(released), 10) },
  });

  if (error) throw error;
  if (data?.configured === false) throw new Error("HubSpot sync secret is not configured.");
  if (data?.failed > 0) throw new Error(`${data.failed} HubSpot queue item${data.failed === 1 ? "" : "s"} failed to sync.`);

  return { ...data, released };
}

export default function AdminWorkspace({ lane, title, subtitle, final, tabs, overview }) {
  const [activeTab, setActiveTab] = useState("overview");
  const [rows, setRows] = useState({});
  const [counts, setCounts] = useState({});
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);
  const loadingRef = useRef(false);
  const refreshTimerRef = useRef(null);

  const activeConfig = useMemo(() => tabs.find((tab) => tab.id === activeTab), [tabs, activeTab]);
  const navTabs = useMemo(() => [{ id: "overview", label: "Overview" }, ...tabs.map((tab) => ({ id: tab.id, label: tab.label }))], [tabs]);
  const tableNames = useMemo(() => [...new Set(tabs.map((tab) => tab.table).filter(Boolean))], [tabs]);

  function flash(message) {
    setNotice(message);
    window.setTimeout(() => setNotice(null), 3600);
  }

  const loadData = useCallback(async ({ quiet = false } = {}) => {
    if (loadingRef.current) return;
    loadingRef.current = true;
    if (!quiet) setLoading(true);

    try {
      const results = await Promise.all(tabs.map(async (tab) => {
        let query = supabase.from(tab.table).select("*").order(tab.orderBy || "created_at", { ascending: false }).limit(tab.limit || 25);
        query = applyFilter(query, tab.filter);
        const { data, error } = await query;
        if (error) throw error;
        let countQuery = supabase.from(tab.table).select("id", { count: "exact", head: true });
        countQuery = applyFilter(countQuery, tab.filter);
        const { count, error: countError } = await countQuery;
        if (countError) throw countError;
        return [tab.id, data || [], count || 0];
      }));
      setRows(Object.fromEntries(results.map(([id, data]) => [id, data])));
      setCounts(Object.fromEntries(results.map(([id, _data, count]) => [id, count])));
      setLastUpdated(new Date());
    } catch (error) {
      flash(error.message || "Dashboard data could not load.");
    } finally {
      loadingRef.current = false;
      if (!quiet) setLoading(false);
    }
  }, [tabs]);

  const scheduleQuietRefresh = useCallback(() => {
    window.clearTimeout(refreshTimerRef.current);
    refreshTimerRef.current = window.setTimeout(() => loadData({ quiet: true }), 350);
  }, [loadData]);

  useEffect(() => {
    loadData();

    const interval = window.setInterval(() => {
      if (document.visibilityState === "visible") loadData({ quiet: true });
    }, 30000);

    const handleFocus = () => loadData({ quiet: true });
    const handleVisibility = () => {
      if (document.visibilityState === "visible") loadData({ quiet: true });
    };

    window.addEventListener("focus", handleFocus);
    document.addEventListener("visibilitychange", handleVisibility);

    return () => {
      window.clearInterval(interval);
      window.clearTimeout(refreshTimerRef.current);
      window.removeEventListener("focus", handleFocus);
      document.removeEventListener("visibilitychange", handleVisibility);
    };
  }, [loadData]);

  useEffect(() => {
    if (!tableNames.length) return undefined;

    let channel = supabase.channel(`admin-workspace-${lane.replace(/[^a-z0-9]+/gi, "-").toLowerCase()}`);
    tableNames.forEach((table) => {
      channel = channel.on("postgres_changes", { event: "*", schema: "public", table }, scheduleQuietRefresh);
    });
    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [lane, tableNames, scheduleQuietRefresh]);

  async function saveRecord(tab, payload, reset) {
    const nextPayload = cleanPayload({ ...tab.defaults, ...payload });
    const { error } = await supabase.from(tab.table).insert(nextPayload);
    if (error) return flash(error.message || "Could not save this record.");

    reset?.();

    if (tab.table === "scout_leads") {
      try {
        const sync = await runScoutHubSpotSync();
        const synced = sync?.success || 0;
        flash(synced > 0 ? `${tab.label} saved. HubSpot synced ${synced} queue item${synced === 1 ? "" : "s"}.` : `${tab.label} saved. No HubSpot queue item needed syncing.`);
      } catch (syncError) {
        flash(`${tab.label} saved. HubSpot sync remains queued: ${syncError.message || "sync unavailable"}`);
      }
    } else {
      flash(`${tab.label} saved.`);
    }

    loadData();
  }

  return (
    <main className="admin-panel">
      {notice && <div className="admin-toast">{notice}</div>}
      <AdminCard eyebrow={lane} title={title} wide>
        <p>{subtitle}</p>
        <button onClick={() => loadData()} disabled={loading}>{loading ? "Refreshing..." : "Refresh dashboard"}</button>
        <small>{lastUpdated ? `Auto-updated ${lastUpdated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : "Connecting live data..."}</small>
      </AdminCard>
      <Tabs tabs={navTabs} activeTab={activeTab} onChange={setActiveTab} />
      {activeTab === "overview" ? (
        <OverviewPanel counts={counts} rows={rows} tabs={tabs} final={final} overview={overview} lane={lane} onOpenTab={setActiveTab} />
      ) : (
        <TabPanel config={activeConfig} rows={rows[activeConfig?.id] || []} onSave={saveRecord} />
      )}
    </main>
  );
}

function OverviewPanel({ counts, rows, tabs, final, overview, lane, onOpenTab }) {
  return (
    <section className="admin-grid">
      <Guard final={final} lane={lane} />
      {overview?.map((item) => <AdminCard key={item.title} eyebrow={item.eyebrow} title={item.title}>{item.body && <p>{item.body}</p>}</AdminCard>)}
      {tabs.map((tab) => <Metric key={tab.id} name={tab.label} value={counts[tab.id] || 0} help={tab.help} onClick={() => onOpenTab(tab.id)} />)}
      {tabs.slice(0, 2).map((tab) => <RecordList key={tab.id} title={`Recent ${tab.label}`} rows={rows[tab.id] || []} primary={tab.primary} secondary={tab.secondary} status={tab.status} onOpen={() => onOpenTab(tab.id)} />)}
    </section>
  );
}

function TabPanel({ config, rows, onSave }) {
  const [form, update, reset] = useFormState(config.initial || {});
  if (!config) return null;
  return (
    <section className="admin-crud">
      <h2>{config.label}</h2>
      {config.description && <p>{config.description}</p>}
      {!config.readOnly && <RecordForm fields={config.fields || []} form={form} update={update} onSubmit={() => onSave(config, form, reset)} buttonLabel={config.buttonLabel || `Save ${config.label}`} />}
      <RecordList rows={rows} primary={config.primary} secondary={config.secondary} status={config.status} emptyText={`No ${config.label.toLowerCase()} yet.`} />
    </section>
  );
}
