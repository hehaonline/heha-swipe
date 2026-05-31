export default function ProfileTab({ user, profile, onSignOut, onListBusiness }) {
  return (
    <div style={{ padding: "24px 16px", display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        <div style={{
          width: 64, height: 64, borderRadius: "50%", background: "#e8e3dc",
          display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28
        }}>
          {profile?.full_name?.charAt(0) || user?.email?.charAt(0) || "👤"}
        </div>
        <div>
          <div style={{ fontWeight: 700, fontSize: 18, color: "#1a1a1a" }}>
            {profile?.full_name || "HEHA Member"}
          </div>
          <div style={{ fontSize: 13, color: "#888" }}>
            {user?.email || user?.phone || ""}
          </div>
        </div>
      </div>

      <div style={{ background: "#fff", borderRadius: 14, padding: "16px", boxShadow: "0 2px 8px rgba(0,0,0,0.06)" }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: "#aaa", marginBottom: 12, textTransform: "uppercase", letterSpacing: 0.5 }}>Account</div>
        {[
          { label: "Email", value: user?.email || "—" },
          { label: "Phone", value: user?.phone || "—" },
          { label: "Location", value: profile?.location || "Tampa Bay" },
        ].map(({ label, value }) => (
          <div key={label} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: "1px solid #f0ede8", fontSize: 14 }}>
            <span style={{ color: "#666" }}>{label}</span>
            <span style={{ color: "#1a1a1a", fontWeight: 500 }}>{value}</span>
          </div>
        ))}
      </div>

      <button onClick={onListBusiness}
        style={{
          padding: "13px", borderRadius: 12, border: "none",
          background: "#2a7c3f", color: "#fff", fontSize: 15, fontWeight: 600,
          cursor: "pointer", width: "100%"
        }}>
        🏪 List Your Business
      </button>

      <button onClick={onSignOut}
        style={{
          padding: "13px", borderRadius: 12, border: "1.5px solid #e0dbd4",
          background: "#fff", color: "#666", fontSize: 15, fontWeight: 600,
          cursor: "pointer", width: "100%"
        }}>
        Sign out
      </button>
    </div>
  );
}
