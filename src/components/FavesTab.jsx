export default function FavesTab({ saves, partners, onUnsave }) {
  const savedPartners = partners.filter((p) => saves.some((s) => s.partner_id === p.id));

  if (!savedPartners.length) return (
    <div style={{
      display: "flex", flexDirection: "column", alignItems: "center",
      justifyContent: "center", height: "100%", gap: 12, color: "#aaa"
    }}>
      <div style={{ fontSize: 48 }}>💫</div>
      <div style={{ fontSize: 16, fontWeight: 600, color: "#555" }}>No favorites yet</div>
      <div style={{ fontSize: 14 }}>Swipe right on partners you love!</div>
    </div>
  );

  return (
    <div style={{ padding: "12px 16px", overflowY: "auto" }}>
      <h3 style={{ margin: "0 0 16px", fontSize: 18, fontWeight: 700, color: "#1a1a1a" }}>
        Your Favorites ({savedPartners.length})
      </h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        {savedPartners.map((p) => (
          <div key={p.id} style={{
            background: "#fff", borderRadius: 14, overflow: "hidden",
            boxShadow: "0 2px 8px rgba(0,0,0,0.07)", display: "flex"
          }}>
            <div style={{
              width: 72, background: p.color || "#1e4d1e",
              display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28
            }}>
              {p.photo_emoji || "🏷️"}
            </div>
            <div style={{ flex: 1, padding: "12px 14px" }}>
              <div style={{ fontWeight: 700, fontSize: 15, color: "#1a1a1a" }}>{p.name}</div>
              <div style={{ fontSize: 12, color: "#888", marginTop: 2 }}>
                {p.category}{p.neighborhood ? ` · ${p.neighborhood}` : ""}
              </div>
              {p.tagline && (
                <div style={{ fontSize: 12, color: "#666", marginTop: 4, fontStyle: "italic" }}>
                  "{p.tagline}"
                </div>
              )}
            </div>
            <button onClick={() => onUnsave(p.id)}
              style={{
                background: "none", border: "none", padding: "0 14px",
                cursor: "pointer", fontSize: 18, color: "#ccc"
              }}>✕</button>
          </div>
        ))}
      </div>
    </div>
  );
}
