import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const VIBE_PASSIONS = [
  "Clean food",
  "Local farms",
  "Yoga",
  "Breathwork",
  "Primal movement",
  "Traditional medicine",
  "Sea moss",
  "Art",
  "Music",
  "Nature",
  "Eco living",
  "Community events",
  "Peace & culture",
  "Vanlife",
];

const VIBE_INTERESTS = [
  "Restaurants",
  "Markets",
  "Wellness",
  "Coaches",
  "Private chefs",
  "Catering",
  "Events",
  "Artists",
  "Local brands",
  "Services",
];

const VIBE_THEMES = [
  { id: "earth", label: "Earth Green", emoji: "🌿" },
  { id: "sunrise", label: "Sunrise Orange", emoji: "🌅" },
  { id: "ocean", label: "Ocean Blue", emoji: "🌊" },
  { id: "lavender", label: "Lavender Calm", emoji: "🪻" },
  { id: "ember", label: "Creative Ember", emoji: "🔥" },
];

function toggleValue(list, value) {
  return list.includes(value) ? list.filter((item) => item !== value) : [...list, value];
}

function cleanArray(value) {
  return Array.isArray(value) ? value.filter(Boolean) : [];
}

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
  const [messages, setMessages] = useState([]);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [form, setForm] = useState({
    full_name: "",
    phone: "",
    location: "",
    instagram: "",
    vibe_passions: [],
    vibe_interests: [],
    vibe_theme: "earth",
  });

  useEffect(() => {
    setForm({
      full_name: profile?.full_name || "",
      phone: profile?.phone || user?.phone || "",
      location: profile?.location || "",
      instagram: profile?.instagram || "",
      vibe_passions: cleanArray(profile?.vibe_passions),
      vibe_interests: cleanArray(profile?.vibe_interests),
      vibe_theme: profile?.vibe_theme || "earth",
    });
  }, [profile, user?.phone]);

  useEffect(() => {
    if (!user?.id) return;
    loadMessages();
  }, [user?.id]);

  const certifiedCount = useMemo(
    () => partners.filter((partner) => partner.heha_partner).length,
    [partners]
  );

  const unreadCount = useMemo(
    () => messages.filter((message) => !message.is_read).length,
    [messages]
  );

  const vibeCount = form.vibe_passions.length + form.vibe_interests.length;
  const listedCount = partners.length;
  const initial = (profile?.full_name?.charAt(0) || form.full_name?.charAt(0) || user?.email?.charAt(0) || "H").toUpperCase();
  const joinDate = user?.created_at
    ? new Date(user.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })
    : "recently";

  const updateForm = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
  };

  const togglePassion = (value) => {
    setForm((current) => ({ ...current, vibe_passions: toggleValue(current.vibe_passions, value) }));
  };

  const toggleInterest = (value) => {
    setForm((current) => ({ ...current, vibe_interests: toggleValue(current.vibe_interests, value) }));
  };

  const loadMessages = async () => {
    if (!user?.id) return;
    setMessagesLoading(true);
    try {
      const { data, error } = await supabase
        .from("in_app_messages")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(10);
      if (error) throw error;
      setMessages(data || []);
    } catch {
      setMessages([]);
    } finally {
      setMessagesLoading(false);
    }
  };

  const markAllMessagesRead = async () => {
    if (!user?.id || !messages.length) return;
    setBusy(true);
    setProfileError(null);
    try {
      const { error } = await supabase
        .from("in_app_messages")
        .update({ is_read: true })
        .eq("user_id", user.id)
        .eq("is_read", false);
      if (error) throw error;
      await loadMessages();
    } catch (error) {
      setProfileError(error.message || "Could not update inbox yet.");
    } finally {
      setBusy(false);
    }
  };

  const saveUserProfile = async () => {
    setBusy(true);
    setProfileError(null);
    setProfileMessage(null);

    try {
      const cleanInstagram = form.instagram.trim().replace(/^@/, "");
      const { error } = await supabase.from("profiles").upsert({
        id: user.id,
        email: user.email || null,
        full_name: form.full_name.trim() || null,
        phone: form.phone.trim() || null,
        location: form.location.trim() || null,
        instagram: cleanInstagram || null,
        vibe_passions: form.vibe_passions,
        vibe_interests: form.vibe_interests,
        vibe_theme: form.vibe_theme || "earth",
        updated_at: new Date().toISOString(),
      });

      if (error) throw error;
      setProfileMessage("Profile saved. Your Vibe Setter will personalize colors and future recommendations.");
      onRefresh?.();
    } catch (error) {
      setProfileError(error.message || "Could not save your profile yet.");
    } finally {
      setBusy(false);
    }
  };

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
          <p className="eyebrow">Local Explorer</p>
          <h2>{profile?.full_name || form.full_name || "Healthy local explorer"}</h2>
          <p>{user?.email || user?.phone || "Signed in"}</p>
          <small>Member since {joinDate}</small>
        </div>
      </div>

      <div className="metric-grid">
        <div><strong>{certifiedCount}</strong><span>HEHA certified</span></div>
        <div><strong>{listedCount}</strong><span>listed</span></div>
        <div><strong>{unreadCount}</strong><span>inbox</span></div>
      </div>

      <div className="profile-card card-like vibe-card">
        <p className="eyebrow">Vibe Setter</p>
        <h3>Shape your HEHA Swipe experience.</h3>
        <p>Pick what you care about. HEHA Swipe can use this to highlight matching businesses, artists, wellness brands, events, and future community profiles.</p>

        <div className="field-stack">
          <div className="field-block">
            <span>Passions</span>
            <div className="wizard-chip-grid">
              {VIBE_PASSIONS.map((passion) => (
                <button
                  type="button"
                  key={passion}
                  className={form.vibe_passions.includes(passion) ? "selected" : ""}
                  onClick={() => togglePassion(passion)}
                >
                  {passion}
                </button>
              ))}
            </div>
          </div>

          <div className="field-block">
            <span>What do you want to discover?</span>
            <div className="wizard-chip-grid">
              {VIBE_INTERESTS.map((interest) => (
                <button
                  type="button"
                  key={interest}
                  className={form.vibe_interests.includes(interest) ? "selected" : ""}
                  onClick={() => toggleInterest(interest)}
                >
                  {interest}
                </button>
              ))}
            </div>
          </div>

          <div className="field-block">
            <span>Theme highlight</span>
            <div className="wizard-chip-grid">
              {VIBE_THEMES.map((theme) => (
                <button
                  type="button"
                  key={theme.id}
                  className={form.vibe_theme === theme.id ? "selected" : ""}
                  onClick={() => updateForm("vibe_theme", theme.id)}
                >
                  <span>{theme.emoji}</span>
                  {theme.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="soft-note">{vibeCount ? `${vibeCount} vibe signals selected. These will help tune your discovery feed.` : "Start with 3–5 selections for the best prototype recommendations."}</div>
      </div>

      <div className="profile-card card-like inbox-card">
        <div className="inbox-heading">
          <div>
            <p className="eyebrow">HEHA Inbox</p>
            <h3>Updates from HEHA</h3>
          </div>
          {unreadCount > 0 && <button onClick={markAllMessagesRead} disabled={busy}>Mark read</button>}
        </div>
        {messagesLoading ? (
          <p>Loading inbox…</p>
        ) : messages.length ? (
          <div className="inbox-list">
            {messages.map((message) => (
              <article key={message.id} className={message.is_read ? "inbox-message" : "inbox-message unread"}>
                <strong>{message.title}</strong>
                <p>{message.body}</p>
                <small>{new Date(message.created_at).toLocaleString()}</small>
              </article>
            ))}
          </div>
        ) : (
          <p>No HEHA messages yet. Discount updates, partner replies, and future order notes can appear here.</p>
        )}
      </div>

      <div className="profile-card card-like">
        <p className="eyebrow">Your profile</p>
        <h3>Prepare your HEHA account for future orders.</h3>
        <p>Add the basic details HEHA will need later for ordering, delivery coordination, and local recommendations.</p>

        <div className="profile-form">
          <label className="field-block">
            <span>Full name</span>
            <input
              value={form.full_name}
              onChange={(event) => updateForm("full_name", event.target.value)}
              placeholder="Your name"
              autoComplete="name"
            />
          </label>

          <label className="field-block">
            <span>Phone number</span>
            <input
              value={form.phone}
              onChange={(event) => updateForm("phone", event.target.value)}
              placeholder="For order/delivery updates later"
              autoComplete="tel"
            />
          </label>

          <label className="field-block">
            <span>Default delivery area / address</span>
            <textarea
              value={form.location}
              onChange={(event) => updateForm("location", event.target.value)}
              placeholder="Example: South Tampa, Hyde Park, or full delivery address for future orders"
              autoComplete="street-address"
            />
          </label>

          <label className="field-block">
            <span>Instagram optional</span>
            <input
              value={form.instagram}
              onChange={(event) => updateForm("instagram", event.target.value)}
              placeholder="@yourhandle"
            />
          </label>

          <button className="primary-button" onClick={saveUserProfile} disabled={busy}>
            {busy ? "Saving…" : "Save profile + vibe"}
          </button>
        </div>
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
        <button className="secondary-button" onClick={onRefresh} disabled={busy}>Refresh businesses</button>
        <button className="secondary-button" onClick={resetAppProfile} disabled={busy}>Reset app profile</button>
        <button className="danger-button" onClick={requestAccountDeletion} disabled={busy}>Request account deletion</button>
        <button className="secondary-button" onClick={onSignOut} disabled={busy}>Sign out</button>
      </div>
    </section>
  );
}
