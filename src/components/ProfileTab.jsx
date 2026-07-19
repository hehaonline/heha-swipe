import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const VISIBLE_LISTING_STATUSES = ["approved", "listed", "live"];

function formatMonthYear(value) {
  if (!value) return "recently";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "recently";
  return date.toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

function formatStatus(value, fallback = "Pending") {
  const status = String(value || "").trim();
  if (!status) return fallback;
  return status
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function completionLabel(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return "0%";
  return `${Math.round(numeric)}%`;
}

export default function ProfileTab({
  user,
  profile,
  partners = [],
  saves = [],
  isBusiness = false,
  listing = null,
  onSignOut,
  onListBusiness,
  onRefresh,
}) {
  const [busy, setBusy] = useState(false);
  const [profileMessage, setProfileMessage] = useState(null);
  const [profileError, setProfileError] = useState(null);
  const [messages, setMessages] = useState([]);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [ownedListing, setOwnedListing] = useState(listing);
  const [form, setForm] = useState({
    full_name: "",
    phone: "",
    location: "",
    instagram: "",
  });

  useEffect(() => {
    setForm({
      full_name: profile?.full_name || "",
      phone: profile?.phone || user?.phone || "",
      location: profile?.location || "",
      instagram: profile?.instagram || "",
    });
  }, [profile, user?.phone]);

  useEffect(() => {
    if (!user?.id) return;
    loadMessages();
  }, [user?.id]);

  useEffect(() => {
    setOwnedListing(listing || null);
  }, [listing]);

  useEffect(() => {
    if (!isBusiness || !user?.id) return;

    let cancelled = false;
    const loadOwnedListing = async () => {
      const { data, error } = await supabase
        .from("partners")
        .select("id, name, category, status, created_at, updated_at, complete_pct, heha_partner")
        .eq("owner_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (cancelled) return;
      if (error) {
        setProfileError(error.message || "Could not load your business listing details.");
        return;
      }
      setOwnedListing(data || null);
    };

    loadOwnedListing();
    return () => {
      cancelled = true;
    };
  }, [isBusiness, user?.id]);

  const activeListing = ownedListing || listing;

  const certifiedCount = useMemo(
    () => partners.filter((partner) => partner.heha_partner).length,
    [partners]
  );

  const unreadCount = useMemo(
    () => messages.filter((message) => !message.is_read).length,
    [messages]
  );

  const listedCount = partners.length;
  const initialSource = isBusiness
    ? activeListing?.name || user?.email || "B"
    : profile?.full_name || form.full_name || user?.email || "H";
  const initial = (initialSource.charAt(0) || "H").toUpperCase();
  const joinDate = formatMonthYear(user?.created_at);
  const partnerSinceDate = formatMonthYear(
    activeListing?.created_at || profile?.created_at || user?.created_at
  );
  const listingStatus = String(activeListing?.status || "").toLowerCase();
  const listingIsVisible = VISIBLE_LISTING_STATUSES.includes(listingStatus);
  const businessTitle = activeListing?.name || "Business partner";
  const businessCertified = activeListing?.heha_partner === true ? "Yes" : "Not certified yet";

  const updateForm = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
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

  const handleRefreshBusinesses = async () => {
    setBusy(true);
    setProfileError(null);
    setProfileMessage(null);
    try {
      await onRefresh?.();
      setProfileMessage("Businesses refreshed.");
    } catch (error) {
      setProfileError(error?.message || "Could not refresh businesses yet.");
    } finally {
      setBusy(false);
    }
  };

  const saveUserProfile = async () => {
    if (!user?.id) return;

    setBusy(true);
    setProfileError(null);
    setProfileMessage(null);

    try {
      const cleanInstagram = form.instagram.trim().replace(/^@/, "");

      // This screen edits an existing authenticated user's profile only.
      // Using update avoids the INSERT candidate created by upsert, which can
      // activate protected supporter-subscription defaults and security triggers.
      const { data: updatedProfile, error } = await supabase
        .from("profiles")
        .update({
          full_name: form.full_name.trim() || null,
          phone: form.phone.trim() || null,
          location: form.location.trim() || null,
          instagram: cleanInstagram || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", user.id)
        .select("id")
        .maybeSingle();

      if (error) throw error;
      if (!updatedProfile) {
        throw new Error("Your profile row is missing or is not editable. Please refresh and try again.");
      }

      setProfileMessage(
        isBusiness
          ? "Business contact details saved."
          : "Profile saved. This information can support future HEHA ordering and delivery."
      );
      await onRefresh?.();
    } catch (error) {
      setProfileError(error.message || "Could not save your profile yet.");
    } finally {
      setBusy(false);
    }
  };

  const resetAppProfile = async () => {
    const confirmed = window.confirm(
      "Reset your HEHA Swipe profile data? This clears saved partners and onboarding profile data, but does not delete your login account."
    );
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
    const confirmed = window.confirm(
      "Request full account deletion? HEHA will receive a deletion request. Your login may remain active until the account is removed from Supabase Auth by an admin."
    );
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
          <p className="eyebrow">{isBusiness ? "Business Account" : "Local Explorer"}</p>
          <h2>
            {isBusiness
              ? businessTitle
              : profile?.full_name || form.full_name || "Healthy local explorer"}
          </h2>
          <p>{user?.email || user?.phone || "Signed in"}</p>
          <small>
            {isBusiness
              ? `Partner account since ${partnerSinceDate}`
              : `Member since ${joinDate}`}
          </small>
        </div>
      </div>

      <div className={isBusiness ? "metric-grid business-metrics" : "metric-grid"}>
        {isBusiness ? (
          <>
            <div>
              <strong>{formatStatus(activeListing?.status, activeListing ? "Pending" : "No listing")}</strong>
              <span>Listing status</span>
            </div>
            <div>
              <strong>{completionLabel(activeListing?.complete_pct)}</strong>
              <span>Completion %</span>
            </div>
            <div>
              <strong>{businessCertified}</strong>
              <span>HEHA Certified</span>
            </div>
          </>
        ) : (
          <>
            <div><strong>{certifiedCount}</strong><span>HEHA certified</span></div>
            <div><strong>{listedCount}</strong><span>listed</span></div>
            <div><strong>{unreadCount}</strong><span>inbox</span></div>
          </>
        )}
      </div>

      <div className="profile-card card-like">
        <p className="eyebrow">HEHA updates</p>
        <h3>What’s new</h3>
        <p>HEHA Swipe is in early access. Community Pass perks, local deals, and partner updates are rolling out.</p>
      </div>

      <div className="profile-card card-like inbox-card">
        <div className="inbox-heading">
          <div>
            <p className="eyebrow">Your inbox</p>
            <h3>Your messages</h3>
          </div>
          {unreadCount > 0 && <button onClick={markAllMessagesRead} disabled={busy}>Mark read</button>}
        </div>
        {messagesLoading ? (
          <p>Loading messages…</p>
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
          <p>No personal messages yet. Discount replies and order updates will appear here.</p>
        )}
      </div>

      <div className="profile-card card-like">
        <p className="eyebrow">{isBusiness ? "Business contact" : "Your profile"}</p>
        <h3>
          {isBusiness
            ? "Manage your HEHA business contact details."
            : "Prepare your HEHA account for future orders."}
        </h3>
        <p>
          {isBusiness
            ? "Keep your business contact info ready for HEHA review, partner updates, and future customer coordination."
            : "Add the basic details HEHA will need later for ordering, delivery coordination, and local recommendations."}
        </p>

        <div className="profile-form">
          <label className="field-block">
            <span>{isBusiness ? "Contact name" : "Full name"}</span>
            <input
              value={form.full_name}
              onChange={(event) => updateForm("full_name", event.target.value)}
              placeholder={isBusiness ? "Best HEHA contact" : "Your name"}
              autoComplete="name"
            />
          </label>

          <label className="field-block">
            <span>{isBusiness ? "Business phone number" : "Phone number"}</span>
            <input
              value={form.phone}
              onChange={(event) => updateForm("phone", event.target.value)}
              placeholder={isBusiness ? "For partner updates" : "For order/delivery updates later"}
              autoComplete="tel"
            />
          </label>

          <label className="field-block">
            <span>{isBusiness ? "Business area / address" : "Default delivery area / address"}</span>
            <textarea
              value={form.location}
              onChange={(event) => updateForm("location", event.target.value)}
              placeholder={
                isBusiness
                  ? "Example: South Tampa, Hyde Park, or business address"
                  : "Example: South Tampa, Hyde Park, or full delivery address for future orders"
              }
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
            {busy ? "Saving…" : isBusiness ? "Save contact details" : "Save profile"}
          </button>
        </div>
      </div>

      {isBusiness ? (
        activeListing ? (
          <div className="profile-card card-like">
            <p className="eyebrow">Your business</p>
            <h3>Your business listing</h3>
            <p>
              {listingIsVisible
                ? "Your business is visible on HEHA Swipe. HEHA Certified status is separate and remains admin-controlled."
                : listingStatus === "pending"
                ? "Your business has been submitted. HEHA reviews listings before they appear publicly."
                : "Your business is not publicly visible right now. HEHA reviews listing changes before they appear publicly."}
            </p>
            <p className="fine-print">Approved/listed status is not the same as HEHA Certified.</p>
          </div>
        ) : (
          <div className="profile-card card-like">
            <p className="eyebrow">Business registration</p>
            <h3>Start or continue your business registration.</h3>
            <p>Your business account is active, but no listing was found yet. Start or continue your business registration.</p>
            <button className="primary-button" onClick={onListBusiness}>Register my business</button>
            <p className="fine-print">Already submitted? HEHA will review listings before they appear publicly.</p>
          </div>
        )
      ) : (
        <button className="partner-cta" onClick={onListBusiness}>
          <div>
            <span>🏪</span>
            <h3>Have a healthy business?</h3>
            <p>Get listed on HEHA Swipe and become visible to local customers looking for cleaner options.</p>
          </div>
          <strong>Start →</strong>
        </button>
      )}

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
        <button className="secondary-button" onClick={handleRefreshBusinesses} disabled={busy}>{busy ? "Refreshing…" : "Refresh businesses"}</button>
        <button className="secondary-button" onClick={resetAppProfile} disabled={busy}>Reset app profile</button>
        <button className="danger-button" onClick={requestAccountDeletion} disabled={busy}>Request account deletion</button>
        <button className="secondary-button" onClick={onSignOut} disabled={busy}>Sign out</button>
      </div>
    </section>
  );
}
