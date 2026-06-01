import { useState, useEffect, useCallback } from "react";
import SwipeCard from "./SwipeCard";

const CATEGORIES = ["All", "Restaurant", "Vendor", "Coach", "Service", "Wellness", "Events"];
const CAT_ICONS = { All: "✦", Restaurant: "🥗", Vendor: "🛍️", Coach: "🏆", Service: "💆", Wellness: "🧘", Events: "🎉" };

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

  const buildDeck = useCallback((cat, seen, allPartners, currentSaves, isReshuffle = false) => {
    const savedIds = new Set(currentSaves.map(s => s.partner_id));
    const pool = allPartners.filter(p => (cat === "All" || p.category === cat) && !savedIds.has(p.id));
    if (isReshuffle) return shuffle(pool);
    const unseen = pool.filter(p => !seen.has(p.id));
    return unseen.length > 0 ? unseen : null;
  }, []);

  useEffect(() => {
    const result = buildDeck(category, seenIds, partners, saves);
    if (result === null) {
      setDeck(buildDeck(category, new Set(), partners, saves, true));
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
    setDeck(d => d.slice(1));
    setSeenIds(s => new Set([...s, partner.id]));
    if (direction === "right") await onSave(partner);
    else await onPass(partner);
  };

  const current = deck[0];

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: "#fff" }}>

      {reshuffled && (
        <div style={{ position: "absolute", top: 12, left: "50%", transform: "translateX(-50%)", background: "#111", color: "#fff", padding: "8px 18px", borderRadius: 20, fontSize: 12, fontWeight: 600, zIndex: 100, whiteSpace: "nowrap", boxShadow: "0 4px 16px rgba(0,0,0,0.25)", animation: "slideUp 0.3s ease" }}>
          🔀 Showing all businesses again
        </div>
      )}

      {/* Category filters */}
      <div style={{ display: "flex", gap: 6, overflowX: "auto", padding: "12px 16px 10px", scrollbarWidth: "none", flexShrink: 0 }}>
        {CATEGORIES.map(cat => (
          <button key={cat} onClick={() => { setCategory(cat); setSeenIds(new Set()); }}
            style={{
              flexShrink: 0, padding: "7px 14px", borderRadius: 20, border: "none", cursor: "pointer",
              background: category === cat ? "#e85d2b" : "#f5f5f5",
              color: category === cat ? "#fff" : "#666",
              fontSize: 12, fontWeight: 600, display: "flex", alignItems: "center", gap: 5,
              transition: "all 0.15s", fontFamily: "DM Sans, sans-serif",
              boxShadow: category === cat ? "0 4px 12px rgba(232,93,43,0.3)" : "none"
            }}>
            <span>{CAT_ICONS[cat]}</span>{cat}
          </button>
        ))}
      </div>

      {/* Counter strip */}
      {current && (
        <div style={{ margin: "0 16px 12px", background: "#fff4f0", borderRadius: 12, padding: "9px 14px", display: "flex", justifyContent: "space-between", alignItems: "center", border: "1px solid #ffe0d6", flexShrink: 0 }}>
          <div style={{ fontSize: 12, color: "#e85d2b", fontWeight: 700 }}>{deck.length} left to explore</div>
          <div style={{ display: "flex", gap: 4 }}>
            {[0,1,2].map(i => (
              <div key={i} style={{ width: 6, height: 6, borderRadius: "50%", background: i === 0 ? "#e85d2b" : "#ffd5c8" }} />
            ))}
          </div>
        </div>
      )}

      {/* Card area */}
      <div style={{ flex: 1, position: "relative", padding: "0 16px", marginBottom: 8, overflow: "hidden" }}>
        {current ? (
          <>
            {deck[1] && (
              <div style={{ position: "absolute", width: "calc(100% - 32px)", borderRadius: 24, background: deck[1]?.color || "#2a7c3f", height: 180, top: 10, transform: "scale(0.95)", opacity: 0.35, zIndex: 0 }} />
            )}
            <SwipeCard key={current.id} partner={current} onSwipe={handleSwipe} />
          </>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", height: "100%", gap: 16, padding: "0 24px" }}>
            <div style={{ width: 80, height: 80, borderRadius: 24, background: "linear-gradient(135deg, #fff4f0, #ffe8e0)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 36 }}>🌿</div>
            <div style={{ textAlign: "center" }}>
              <div style={{ fontFamily: "Syne, sans-serif", fontSize: 20, fontWeight: 800, color: "#111", marginBottom: 6 }}>You've seen everyone!</div>
              <div style={{ fontSize: 14, color: "#aaa", lineHeight: 1.6 }}>New businesses join every week. Check back soon!</div>
            </div>
            <button onClick={() => { setSeenIds(new Set()); setCategory("All"); }}
              style={{ padding: "12px 28px", borderRadius: 24, border: "none", background: "linear-gradient(135deg, #e85d2b, #ff7a47)", color: "#fff", fontSize: 14, fontWeight: 700, cursor: "pointer", boxShadow: "0 4px 16px rgba(232,93,43,0.35)", fontFamily: "Syne, sans-serif" }}>
              Start over ↺
            </button>
          </div>
        )}
      </div>

      {/* Action buttons */}
      {current && (
        <div style={{ padding: "0 16px 16px", flexShrink: 0 }}>
          <div style={{ display: "flex", justifyContent: "center", gap: 16, alignItems: "center" }}>
            <button onClick={() => handleSwipe("left")}
              style={{ width: 60, height: 60, borderRadius: "50%", border: "2px solid #f0f0f0", background: "#fff", fontSize: 22, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 2px 12px rgba(0,0,0,0.07)", transition: "transform 0.15s" }}>
              ✕
            </button>
            <button style={{ width: 48, height: 48, borderRadius: "50%", border: "2px solid #f0f0f0", background: "#fff", fontSize: 16, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 2px 8px rgba(0,0,0,0.06)" }}>
              ℹ️
            </button>
            <button onClick={() => handleSwipe("right")}
              style={{ width: 60, height: 60, borderRadius: "50%", border: "none", background: "linear-gradient(135deg, #e85d2b, #ff7a47)", fontSize: 22, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 4px 20px rgba(232,93,43,0.4)", transition: "transform 0.15s", color: "#fff" }}>
              ♥
            </button>
          </div>
          <div style={{ textAlign: "center", fontSize: 10, color: "#ddd", marginTop: 8, fontFamily: "Syne, sans-serif", letterSpacing: 1.5, textTransform: "uppercase" }}>
            swipe or tap
          </div>
        </div>
      )}
    </div>
  );
}
