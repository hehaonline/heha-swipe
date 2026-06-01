export default function ProfileTab({
  user,
  profile,
  partners = [],
  saves = [],
  onSignOut,
  onListBusiness,
  onRefresh,
}) {
  const initial = (profile?.full_name?.charAt(0) || user?.email?.charAt(0) || "H").toUpperCase();
  const joinDate = user?.created_at
    ? new Date(user.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })
    : "recently";

  return (
    <section className="profile-screen">
      <div className="profile-hero">
        <div className="profile-avatar">{initial}</div>
        <div>
          <p className="eyebrow">HEHA member</p>
          <h2>{profile?.full_name || "Healthy local explorer"}</h2>
          <p>{user?.email || user?.phone || "Signed in"}</p>
          <small>Member since {joinDate}</small>
        </div>
      </div>

      <div className="metric-grid">
        <div><strong>{partners.length}</strong><span>live partners</span></div>
        <div><strong>{saves.length}</strong><span>saved</span></div>
        <div><strong>20%</strong><span>profit mission</span></div>
      </div>

      <button className="partner-cta" onClick={onListBusiness}>
        <div>
          <span>🏪</span>
          <h3>Have a healthy business?</h3>
          <p>Get listed on HEHA Swipe and become visible to local customers looking for cleaner options.</p>
        </div>
        <strong>Start →</strong>
      </button>

      <div className="profile-card card-like">
        <p className="eyebrow">Why HEHA Swipe exists</p>
        <h3>Marketing for the local healthy economy.</h3>
        <p>
          HEHA Swipe is built to help people find food, wellness, movement, and natural products that support a healthier human experience — while giving local businesses a cleaner way to be discovered.
        </p>
      </div>

      <div className="profile-card card-like soft">
        <h3>Freebird Fund</h3>
        <p>HEHA keeps the Freebird Fund mission connected to growth. As the community grows, the goal is to support people transitioning toward safer, more independent living.</p>
      </div>

      <div className="profile-actions">
        <button className="secondary-button" onClick={onRefresh}>Refresh partners</button>
        <button className="secondary-button" onClick={onSignOut}>Sign out</button>
      </div>
    </section>
  );
}
