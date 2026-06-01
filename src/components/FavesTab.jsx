export default function FavesTab({ saves, partners, onUnsave }) {
  const saved = partners.filter(p => saves.some(s => s.partner_id === p.id));

  if (!saved.length) return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", height: "100%", gap: 16, padding: "0 32px", background: "#fff" }}>
      <div style={{ width: 80, height: 80, borderRadius: 24, background: "#fff4f0", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 36 }}>♥</div>
      <div style={{ textAlign: "center" }}>
        <div style={{ fontFamily: "Syne, sans-serif", fontSize: 20, fontWeight: 800, color: "#111", marginBottom: 6 }}>No favorites yet</div>
        <div style={{ fontSize: 14, color: "#aaa", lineHeight: 1.6 }}>Swipe right on businesses you love to save them here.</div>
      </div>
    </div>
  );

  return (
    <div style={{ background: "#fff", height: "100%", overflowY: "auto" }}>
      <div style={{ background: "linear-gradient(135deg, #e85d2b, #ff7a47)", padding: "24px 20px 32px", position: "relative", overflow: "hidden" }}>
        <div style={{ position: "absolute", top: -30, right: -30, width: 120, height: 120, borderRadius: "50%", background: "rgba(255,255,255,0.1)" }} />
        <div style={{ fontFamily: "Syne, sans-serif", fontSize: 24, fontWeight: 800, color: "#fff" }}>Your Favorites</div>
        <div style={{ fontSize: 13, color: "rgba(255,255,255,0.8)", marginTop: 4 }}>
          {saved.length} business{saved.length !== 1 ? "es" : ""} saved
        </div>
      </div>

      <div style={{ padding: "16px", display: "flex", flexDirection: "column", gap: 12, marginTop: -12 }}>
        {saved.map(p => (
          <div key={p.id} style={{ background: "#fff", borderRadius: 18, overflow: "hidden", boxShadow: "0 2px 14px rgba(0,0,0,0.07)", display: "flex", border: "1px solid #f5f5f5" }}>
            <div style={{ width: 72, background: p.color || "#1e4d1e", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, flexShrink: 0 }}>
              {p.photo_emoji || "🏷️"}
            </div>
            <div style={{ flex: 1, padding: "13px 14px" }}>
              <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 700, fontSize: 15, color: "#111" }}>{p.name}</div>
              <div style={{ fontSize: 12, color: "#e85d2b", fontWeight: 600, marginTop: 2 }}>{p.category}</div>
              {p.neighborhood && <div style={{ fontSize: 11, color: "#aaa", marginTop: 2 }}>📍 {p.neighborhood}</div>}
              {p.tagline && <div style={{ fontSize: 12, color: "#888", marginTop: 5, fontStyle: "italic", lineHeight: 1.4 }}>"{p.tagline}"</div>}
            </div>
            <button onClick={() => onUnsave(p.id)}
              style={{ background: "none", border: "none", padding: "0 16px", cursor: "pointer", color: "#ddd", fontSize: 18, flexShrink: 0 }}>
              ×
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
