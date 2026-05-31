import { useState, useEffect, useCallback } from "react";
import SwipeCard from "./SwipeCard";

const CATEGORIES = ["All", "Restaurant", "Vendor", "Coach", "Service", "Wellness"];

const shuffle = (arr) => {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

export default function SwipeTab({ partners, saves, onSave, onPass }) {
  const [category, setCategory] = useState("All");
  const [deck, setDeck] = useState([]);
  const [seenIds, setSeenIds] = useState(new Set());
  const [reshuffled, setReshuffled] = useState(false);

  const buildDeck = useCallback((cats, seen, allPartners, currentSaves, isReshuffle = false) => {
    const savedIds = new Set(currentSaves.map((s) => s.partner_id));
    const pool = allPartners.filter((p) => (cats === "All" || p.category === cats) && !savedIds.has(p.id));
    if (isReshuffle) return shuffle(pool);
    const unseen = pool.filter((p) => !seen.has(p.id));
    return unseen.length > 0 ? unseen : null;
  }, []);

  useEffect(() => {
    const result = buildDeck(category, seenIds, partners, saves);
    if (result === null) {
      const reshuffledDeck = buildDeck(category, new Set(), partners, saves, true);
      setDeck(reshuffledDeck);
      setSeenIds(new Set());
      setReshuffled(true);
      setTimeout(() => setReshuffled(false), 3000);
    } else {
      setDeck(result);
    }
  }, [partners, category, saves, buildDeck]);

  const handleSwipe = async (direction) => {
    if (!deck.length) return;
    const partner = deck[0];
    setDeck((d) => d.slice(1));
    setSeenIds((s) => new Set([...s, partner.id]));
    if (direction === "right") await onSave(partner);
    else await onPass(partner);
  };

  const current = deck[0];

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", padding: "0 16px" }}>
      {reshuffled && (
        <div style={{
          position: "absolute", top: 60, left: "50%", transform: "translateX(-50%)",
          background: "#1a1a1a", color: "#fff", padding: "8px 18px", borderRadius: 20,
          fontSize: 13, fontWeight: 600, zIndex: 100, whiteSpace: "nowrap",
          boxShadow: "0 4px 12px rgba(0,0,0,0.2)"
        }}>
          🔀 Reshuffled — showing all businesses again
        </div>
      )}

      <div style={{ display: "flex", gap: 8, overflowX: "auto", padding: "12px 0", scrollbarWidth: "none" }}>
        {CATEGORIES.map((cat) => (
          <button key={cat} onClick={() => { setCategory(cat); setSeenIds(new Set()); }}
            style={{
              flexShrink: 0, padding: "7px 16px", borderRadius: 20, border: "none",
              background: category === cat ? "#2a7c3f" : "#e8e3dc",
              color: category === cat ? "#fff" : "#555",
              fontSize: 13, fontWeight: 600, cursor: "pointer", transition: "all 0.15s"
            }}>
            {category === cat && cat !== "All" ? `✓ ${cat}` : cat}
          </button>
        ))}
      </div>

      <div style={{ flex: 1, position: "relative", marginBottom: 16 }}>
        {current ? (
          <>
            {deck[1] && (
              <div style={{
                position: "absolute", width: "100%", borderRadius: 20,
                background: deck[1]?.color || "#2a7c3f", height: 200,
                top: 8, transform: "scale(0.96)", opacity: 0.5, zIndex: 0
              }} />
            )}
            <SwipeCard key={current.id} partner={current} onSwipe={handleSwipe} />
          </>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", height: "100%", gap: 12 }}>
            <div style={{ fontSize: 56 }}>🌿</div>
            <div style={{ fontSize: 17, fontWeight: 700, color: "#2a7c3f" }}>You've seen everyone!</div>
            <div style={{ fontSize: 14, color: "#aaa", textAlign: "center", maxWidth: 220 }}>Check back soon for new local businesses.</div>
            <button onClick={() => { setSeenIds(new Set()); setCategory("All"); }}
              style={{
                marginTop: 8, padding: "12px 28px", borderRadius: 24, border: "none",
                background: "#2a7c3f", color: "#fff", fontSize: 14, fontWeight: 700, cursor: "pointer"
              }}>
              Reload ↺
            </button>
          </div>
        )}
      </div>

      {current && (
        <>
          <div style={{ display: "flex", justifyContent: "center", gap: 20, paddingBottom: 8 }}>
            <button onClick={() => handleSwipe("left")} style={{ width: 60, height: 60, borderRadius: "50%", border: "none", background: "#fff", boxShadow: "0 2px 12px rgba(0,0,0,0.12)", fontSize: 24, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>✕</button>
            <button style={{ width: 50, height: 50, borderRadius: "50%", border: "none", background: "#fff", boxShadow: "0 2px 12px rgba(0,0,0,0.12)", fontSize: 18, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", alignSelf: "center" }}>ℹ️</button>
            <button onClick={() => handleSwipe("right")} style={{ width: 60, height: 60, borderRadius: "50%", border: "none", background: "#fff", boxShadow: "0 2px 12px rgba(0,0,0,0.12)", fontSize: 24, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>❤️</button>
          </div>
          <div style={{ textAlign: "center", fontSize: 12, color: "#aaa", paddingBottom: 4 }}>{deck.length} left to explore</div>
        </>
      )}
    </div>
  );
}
