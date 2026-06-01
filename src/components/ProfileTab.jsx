export default function ProfileTab({ user, profile, onSignOut, onListBusiness }) {
  const initial = (profile?.full_name?.charAt(0) || user?.email?.charAt(0) || "?").toUpperCase();
  const joinDate = user?.created_at ? new Date(user.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" }) : null;

  return (
    <div style={{ background: "#fff", height: "100%", overflowY: "auto" }}>

      {/* Orange hero */}
      <div style={{ background: "linear-gradient(135deg, #e85d2b, #ff7a47)", padding: "32px 20px 48px", position: "relative", overflow: "hidden" }}>
        <div style={{ position: "absolute", top: -40, right: -40, width: 160, height: 160, borderRadius: "50%", background: "rgba(255,255,255,0.1)" }} />
        <div style={{ position: "absolute", bottom: -20, left: 10, width: 100, height: 100, borderRadius: "50%", background: "rgba(0,0,0,0.06)" }} />
        <div style={{ display: "flex", alignItems: "center", gap: 16, position: "relative" }}>
          <div style={{ width: 68, height: 68, borderRadius: 22, background: "rgba(255,255,255,0.22)", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "Syne, sans-serif", fontSize: 30, fontWeight: 800, color: "#fff", flexShrink: 0 }}>
            {initial}
          </div>
          <div>
            <div style={{ fontFamily: "Syne, sans-serif", fontSize: 20, fontWeight: 800, color: "#fff" }}>
              {profile?.full_name || "HEHA Member"}
            </div>
            <div style={{ fontSize: 13, color: "rgba(255,255,255,0.8)", marginTop: 3 }}>
              {user?.email || user?.phone || ""}
            </div>
            {joinDate && (
              <div style={{ fontSize: 11, color: "rgba(255,255,255,0.6)", marginTop: 3 }}>
                Member since {joinDate}
              </div>
            )}
          </div>
        </div>
      </div>

      <div style={{ padding: "16px", marginTop: -14 }}>

        {/* Account card */}
        <div style={{ background: "#fff", borderRadius: 20, padding: "20px", boxShadow: "0 4px 24px rgba(0,0,0,0.07)", marginBottom: 14, border: "1px solid #f5f5f5" }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: "#e85d2b", marginBottom: 14, textTransform: "uppercase", letterSpacing: 1.2, fontFamily: "Syne, sans-serif" }}>
            Account Details
          </div>
          {[
            { label: "Email", value: user?.email || "—", icon: "📧" },
            { label: "Phone", value: user?.phone || "—", icon: "📱" },
            { label: "Location", value: profile?.location || "Tampa Bay", icon: "📍" },
          ].map(({ label, value, icon }) => (
            <div key={label} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 0", borderBottom: "1px solid #f8f8f8" }}>
              <span style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14, color: "#999" }}>
                <span>{icon}</span>{label}
              </span>
              <span style={{ fontSize: 13, color: "#111", fontWeight: 500, maxWidth: "58%", textAlign: "right" }}>{value}</span>
            </div>
          ))}
        </div>

        {/* List business */}
        <button onClick={onListBusiness}
          style={{ width: "100%", padding: "18px 20px", borderRadius: 20, border: "none", background: "linear-gradient(135deg, #111, #2a2a2a)", color: "#fff", cursor: "pointer", textAlign: "left", marginBottom: 12, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <div style={{ fontFamily: "Syne, sans-serif", fontSize: 15, fontWeight: 800, marginBottom: 4 }}>
              🏪 Have a healthy business?
            </div>
            <div style={{ fontSize: 12, color: "rgba(255,255,255,0.55)", lineHeight: 1.4 }}>
              List it on HEHA Swipe — reach Tampa locals
            </div>
          </div>
          <span style={{ color: "#e85d2b", fontSize: 22, flexShrink: 0 }}>→</span>
        </button>

        {/* HEHA promo */}
        <div style={{ background: "#fff4f0", borderRadius: 18, padding: "16px 18px", marginBottom: 14, border: "1px solid #ffe0d6", display: "flex", alignItems: "center", gap: 14 }}>
          <div style={{ width: 44, height: 44, borderRadius: 14, background: "linear-gradient(135deg, #e85d2b, #ff7a47)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 20, flexShrink: 0 }}>✦</div>
          <div>
            <div style={{ fontFamily: "Syne, sans-serif", fontSize: 13, fontWeight: 700, color: "#e85d2b", marginBottom: 2 }}>HEHA Swipe Tampa Bay</div>
            <div style={{ fontSize: 12, color: "#aaa", lineHeight: 1.5 }}>Discover the healthiest local businesses in your city.</div>
          </div>
        </div>

        {/* Sign out */}
        <button onClick={onSignOut}
          style={{ width: "100%", padding: "14px", borderRadius: 16, border: "1.5px solid #eee", background: "#fff", color: "#aaa", fontSize: 14, fontWeight: 600, cursor: "pointer", fontFamily: "DM Sans, sans-serif" }}>
          Sign out
        </button>
      </div>
    </div>
  );
}
