import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { OVERVIEW_CARD_DEFS, TABLES } from "./dashboardSchema";

function applyFilter(query, card) {
  if (card.filterType === "eq") return query.eq(card.col, card.val);
  if (card.filterType === "in") return query.in(card.col, card.vals);
  if (card.filterType === "notIn") return query.not(card.col, "in", `(${card.vals.join(",")})`);
  if (card.filterType === "visibilityOr") return query.or(card.orClause);
  return query;
}

export function useMyrenDashboard() {
  const [counts, setCounts] = useState({});
  const [records, setRecords] = useState({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [lastLoadedAt, setLastLoadedAt] = useState(null);

  const loadCounts = useCallback(async () => {
    const next = {};
    await Promise.allSettled(OVERVIEW_CARD_DEFS.map(async (card) => {
      let query = supabase.from(card.table).select("id", { count: "exact", head: true });
      query = applyFilter(query, card);
      const { count, error } = await query;
      next[card.key] = error ? "—" : (count ?? 0);
    }));
    setCounts(next);
  }, []);

  const loadRecords = useCallback(async () => {
    const next = {};
    await Promise.allSettled(Object.entries(TABLES).map(async ([tabId, config]) => {
      const { data, error } = await supabase
        .from(config.table)
        .select("*")
        .order(config.order || "updated_at", { ascending: false })
        .limit(50);
      next[tabId] = error ? { rows: [], error: error.message } : { rows: data || [], error: null };
    }));
    setRecords(next);
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      await Promise.all([loadCounts(), loadRecords()]);
      setLastLoadedAt(new Date().toISOString());
    } catch (err) {
      setError(err?.message || "Could not load Myren dashboard data.");
    } finally {
      setLoading(false);
    }
  }, [loadCounts, loadRecords]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { counts, records, loading, error, lastLoadedAt, refresh };
}
