import { useState } from "react";
import { supabase } from "../lib/supabase";

export default function ProfileTab({
  user,
  profile,
  partners = [],
  saves = [],
  onSignOut,
  onListBusiness,
  onRefresh,
}) {
  const [busy, setBusy] = useState(false);
  const [profileMessage, setProfileMessage] = useState(null);
  const [profileError, setProfileError] = useState(null);
  const initial = (profile?.full_name?.charAt(0) || user?.email?.charAt(0) || "H").toUpperCase();
  const joinDate = user?.created_at
    ? new Date(user.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })
    : "recently";

  const resetAppProfile = async () => {
    const confirmed = window.confirm("Reset your HEHA Swipe profile data? This clears saved partners and onboarding profile data, but does not delete your login account.");
    if (!confirmed) return;

    setBusy(true);
    setProfileError(null);
    setProfileMessage(null);

    try {
      await supabase.from("saves").delete().eq("user_id", user.id);
      await supabase.from("customer_profiles").delete().eq("user_id", user.id);
      await supabase.from("profiles").delete().eq("id", user.id);
      localStorage.removeItem("heha_signup_role");
      setProfileMessage("Profile reset. Sign out and sign back in to start over.");
      onRefresh?.();
    } catch (error) {
      setProfileError(error.message || "Could not reset your profile.");
    } finally {
      setBusy(false);
    }
  };

  const requestAccountDeletion = async () => {
    const confirmed = window.confirm("Request full account deletion? HEHA will receive a deletion request. Your login may remain active until the account is removed from Supabase Auth by an admin.");
    if (!confirmed) return;

    setBusy(true);
    setProfileError(null);
    setProfileMessage(null);

    try {
      const { error } = await supabase.from("account_deletion_requests").insert({
        user_id: user.id,
        email: user.email || null,
        reason: "User requested account deletion from HEHA Swipe profile.",
      });
      if (error) throw error;
      await supabase.from("saves").delete().eq("user_id", user.id);
      await supabase.from("customer_profiles").delete().eq("user_id", user.id);
      await supabase.from("profiles").delete().eq("id", user.id);
      localStorage.removeItem("heha_signup_role");
      setProfileMessage("Deletion request created. Your HEHA Swipe data was cleared from the app tables.");
    } catch (error) {
      setProfileError(error.message || "Could not request account deletion.");
    } finally {
      setBusy(false);
    }
  };

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

      {profileMessage && <div className="success-banner">{profileMessage}</div>}
      {profileError && <div className="error-banner">{profileError}</div>}

      <div className="profile-actions">
        <button className="secondary-button" onClick={onRefresh} disabled={busy}>Refresh partners</button>
        <button className="secondary-button" onClick={resetAppProfile} disabled={busy}>Reset app profile</button>
        <button className="danger-button" onClick={requestAccountDeletion} disabled={busy}>Request account deletion</button>
        <button className="secondary-button" onClick={onSignOut} disabled={busy}>Sign out</button>
      </div>
    </section>
  );
}
