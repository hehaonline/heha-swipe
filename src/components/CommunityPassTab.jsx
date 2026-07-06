import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { startSupporterCheckout } from "../lib/supporterCheckout";
import { fetchActiveSupporterSubscription } from "../lib/supporterStatus";
import PartnerListingPreview from "./PartnerListingPreview";
import PartnerProfileEditor from "./PartnerProfileEditor";
import PartnerMediaManager from "./PartnerMediaManager";
import PartnerCommunityOfferBuilder from "./PartnerCommunityOfferBuilder";

// Community Pass & Local Deals dashboard.
// Partner/business users see a read-only Partner Hub instead of customer supporter
// checkout content. Admin-controlled partner fields stay display-only here.

const REMINDER_COPY =
  "HEHA Swipe grows through the people using it. If this community helps you discover better local options, even $1/month helps us keep building.";

const BENEFITS = [
  { icon: "✨", title: "Early access to HEHA Swipe features" },
  { icon: "🎟️", title: "Supporter-only local deal drops" },
  { icon: "🗳️", title: "Vote on future HEHA partners" },
  { icon: "🔎", title: "First look at new restaurants, wellness spaces, and markets" },
  { icon: "📣", title: "HEHA community updates" },
  { icon: "🕊️", title: "Freebird / community mission updates" },
  { icon: "🎉", title: "Event invites and local partner announcements" },
];

const SUPPORTER_TYPES = ["supporter_membership", "customer_supporter", "partner_supporter"];
const PARTNER_TYPES = [
  "partner_free",
  "partner_supporter",
  "partner_instagram",
  "partner_monthly",
  "partner",
  "listed",
];
const VISIBLE_STATUSES = ["approved", "live"];

function isActiveSupporter(profile) {
  if (!profile) return false;
  const type = profile.subscription_type || "";
  return profile.subscription_active === true && SUPPORTER_TYPES.includes(type);
}

function isPartnerProfile(profile) {
  return PARTNER_TYPES.includes(profile?.subscription_type || "");
}

function normalizeStatus(status) {
  return (status || "pending").toLowerCase();
}

function formatStatus(status) {
  return normalizeStatus(status).replace(/_/g, " ");
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

function completionLabel(value) {
  if (value === null || value === undefined || value === "") return "Not calculated yet";
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return "Not calculated yet";
  return `${Math.max(0, Math.min(100, Math.round(parsed)))}%`;
}

function statusLabel(profile) {
  const s = (profile?.subscription_status || "").toLowerCase();
  if (s === "active") return "Active";
  if (s === "trialing") return "Trialing";
  if (s === "past_due") return "Payment past due";
  if (s === "canceled" || s === "cancelled") return "Canceled";
  return profile?.subscription_active ? "Active" : "—";
}

function ManageSupportModal({ portalUrl, onClose }) {
  const [billingNote, setBillingNote] = useState(null);

  const goToBilling = () => {
    if (portalUrl) {
      window.open(portalUrl, "_blank", "noopener,noreferrer");
    } else {
      setBillingNote(
        "Billing management is almost ready. For now, contact HEHA support or manage your subscription through Stripe."
      );
    }
  };

  return (
    <div className="cp-modal-backdrop" role="dialog" aria-modal="true" aria-label="Manage support" onClick={onClose}>
      <section className="cp-modal card-like" onClick={(e) => e.stopPropagation()}>
        <button className="cp-modal-close" type="button" aria-label="Close" onClick={onClose}>×</button>
        <p className="eyebrow">Manage support</p>
        <h2>Before you cancel…</h2>
        <p className="cp-modal-copy">
          Your support helps HEHA Swipe grow the local healthy discovery network, highlight small
          businesses, and keep early-access features moving forward. Even $1/month helps.
        </p>

        <div className="cp-modal-actions">
          <button className="primary-button" type="button" onClick={onClose}>Keep my support</button>
          <button className="secondary-button" type="button" disabled title="Coming soon">Lower to $1/month · Coming soon</button>
          <button className="secondary-button" type="button" onClick={goToBilling}>Pause support</button>
          <button className="text-button center" type="button" onClick={goToBilling}>Continue to billing</button>
        </div>

        {billingNote && <div className="cp-billing-note">{billingNote}</div>}
      </section>
    </div>
  );
}

function CustomerCommunityPass({ user, profile }) {
  const [showManage, setShowManage] = useState(false);
  const [amount, setAmount] = useState(5);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [subRow, setSubRow] = useState(null);

  const profileSupporter = isActiveSupporter(profile);

  useEffect(() => {
    if (profileSupporter || !user?.id) {
      setSubRow(null);
      return undefined;
    }
    let cancelled = false;
    fetchActiveSupporterSubscription(user.id)
      .then((row) => {
        if (!cancelled) setSubRow(row);
      })
      .catch(() => {
        if (!cancelled) setSubRow(null);
      });
    return () => {
      cancelled = true;
    };
  }, [profileSupporter, user?.id]);

  const supporter = profileSupporter || !!subRow;
  const currentAmount = profileSupporter
    ? Number(profile?.subscription_amount || 0)
    : subRow
    ? Number(subRow.amount_cents || 0) / 100
    : 0;
  const supporterStatus = profileSupporter
    ? statusLabel(profile)
    : subRow
    ? (subRow.status === "trialing" ? "Trialing" : "Active")
    : statusLabel(profile);
  const portalUrl = import.meta.env.VITE_STRIPE_CUSTOMER_PORTAL_URL || null;

  const goToCheckout = async (qty) => {
    setBusy(true);
    setError(null);
    try {
      await startSupporterCheckout(qty);
    } catch (e) {
      setError(e.message || "Supporter checkout is not available yet. Please try again later.");
      setBusy(false);
    }
  };

  return (
    <>
      <header className="cp-hero">
        <p className="eyebrow">Community-supported</p>
        <h1>Community Pass &amp; Local Deals</h1>
        <p className="cp-sub">
          HEHA Swipe is community-supported. Supporters help us grow Tampa Bay’s local healthy
          discovery network and unlock early features and local deal drops.
        </p>
      </header>

      {supporter ? (
        <>
          <div className="cp-status-card card-like">
            <span className="cp-badge">✓ Active supporter</span>
            <div className="cp-status-grid">
              <div>
                <span className="cp-status-label">Monthly support</span>
                <strong className="cp-status-value">{currentAmount > 0 ? `$${currentAmount}/month` : "Active"}</strong>
              </div>
              <div>
                <span className="cp-status-label">Status</span>
                <strong className="cp-status-value">{supporterStatus}</strong>
              </div>
            </div>
            <p className="cp-thanks">Thank you for helping HEHA Swipe grow Tampa Bay’s local healthy discovery network.</p>
          </div>

          <h2 className="cp-section-title">Benefits unlocked</h2>
          <div className="cp-benefits-grid">
            {BENEFITS.map((b) => (
              <div className="cp-benefit-card" key={b.title}>
                <span className="cp-benefit-icon">{b.icon}</span>
                <span>{b.title}</span>
              </div>
            ))}
          </div>

          <h2 className="cp-section-title">Local deals &amp; partner offers</h2>
          <div className="cp-panel card-like"><p>Supporter local deal drops are on the way. New partner offers will appear here as HEHA activates them — no fake deals until they’re real.</p></div>

          <h2 className="cp-section-title">HEHA updates</h2>
          <div className="cp-panel card-like"><p>Community and Freebird mission updates, new partner announcements, and event invites will show up here.</p></div>

          <h2 className="cp-section-title">Community impact</h2>
          <div className="cp-panel card-like"><p>Your monthly support helps highlight small local businesses and keeps early-access features moving forward for the whole HEHA Swipe community.</p></div>

          <button className="secondary-button cp-manage-btn" type="button" onClick={() => setShowManage(true)}>Manage support</button>
          {showManage && <ManageSupportModal portalUrl={portalUrl} onClose={() => setShowManage(false)} />}
        </>
      ) : (
        <>
          <div className="cp-panel card-like">
            <p className="cp-explainer">
              HEHA Swipe grows through the people using it. Supporters get early access, supporter-only
              local deal drops, and a say in which local businesses HEHA highlights next.
            </p>
          </div>

          <h2 className="cp-section-title">What supporters get</h2>
          <div className="cp-benefits-grid">
            {BENEFITS.map((b) => (
              <div className="cp-benefit-card cp-benefit-preview" key={b.title}>
                <span className="cp-benefit-icon">{b.icon}</span>
                <span>{b.title}</span>
              </div>
            ))}
          </div>

          <div className="cp-cta-card card-like">
            <div className="cp-amount-row">
              <div>
                <span className="cp-status-label">Choose your monthly support</span>
                <span className="cp-amount-hint">$1 to $100/month</span>
              </div>
              <strong className="cp-status-value">${amount}/month</strong>
            </div>
            <input type="range" min="1" max="100" step="1" value={amount} onChange={(e) => setAmount(Number(e.target.value))} aria-label="Monthly support amount" disabled={busy} />

            <button className="primary-button" type="button" onClick={() => goToCheckout(amount)} disabled={busy}>
              {busy ? "Opening checkout…" : `Become a Supporter · $${amount}/month`}
            </button>
            <button className="secondary-button" type="button" onClick={() => goToCheckout(1)} disabled={busy}>Start at $1/month</button>

            {error && <div className="cp-billing-note">{error}</div>}
            <p className="cp-reminder">{REMINDER_COPY}</p>
          </div>
        </>
      )}
    </>
  );
}

function PartnerHubTab({ user, listing, loading, error, isPartnerAccount, onRefresh, onListBusiness }) {
  const [actionNote, setActionNote] = useState(null);
  const [showPreview, setShowPreview] = useState(false);
  const [showEditor, setShowEditor] = useState(false);
  const [showMedia, setShowMedia] = useState(false);
  const [showOffer, setShowOffer] = useState(false);
  const status = normalizeStatus(listing?.status);
  const visible = Boolean(listing && VISIBLE_STATUSES.includes(status));
  const certified = listing?.heha_partner === true;

  const comingSoon = (label) => {
    setActionNote(`${label} will open after the next dashboard update.`);
  };

  const openPreview = () => {
    if (!listing) {
      setActionNote("Submit a business profile before previewing your listing.");
      return;
    }
    setActionNote(null);
    setShowPreview(true);
  };

  const openEditor = () => {
    if (!listing) {
      onListBusiness?.();
      return;
    }
    setActionNote(null);
    setShowEditor(true);
  };

  const openMedia = () => {
    if (!listing) {
      setActionNote("Submit a business profile before adding logo or photos.");
      return;
    }
    setActionNote(null);
    setShowMedia(true);
  };

  const openOffer = () => {
    if (!listing) {
      setActionNote("Submit a business profile before creating a Community Offer.");
      return;
    }
    setActionNote(null);
    setShowOffer(true);
  };

  const handleEditorSaved = async (_savedListing, note) => {
    setShowEditor(false);
    setActionNote(note || "Business profile saved.");
    await onRefresh?.();
  };

  const copy = !listing
    ? "Your business account is active, but no listing was found yet. Start or continue your business registration."
    : status === "pending"
    ? "Your listing has been submitted. HEHA reviews listings before they become publicly visible."
    : visible
    ? "Your listing is approved and visible in HEHA Swipe discovery. Certification is still separate unless marked HEHA Certified."
    : "Your listing is not publicly visible right now. HEHA review and admin actions control publication and certification.";

  return (
    <>
      <header className="cp-hero partner-hub-hero">
        <p className="eyebrow">Business Partner Hub</p>
        <h1>Your HEHA Swipe listing</h1>
        <p className="cp-sub">Track your listing status, update missing info, and prepare your profile for HEHA review.</p>
      </header>

      <section className="partner-hub-card card-like" aria-busy={loading}>
        {loading ? (
          <div className="partner-hub-loading">Loading your listing status…</div>
        ) : error ? (
          <>
            <h2>Listing status unavailable</h2>
            <p className="partner-hub-copy">HEHA Swipe could not load your business listing yet. This may be a Supabase/RLS access issue or a temporary connection problem.</p>
            <button className="secondary-button" type="button" onClick={onRefresh}>Refresh status</button>
          </>
        ) : listing ? (
          <>
            <div className="partner-hub-topline">
              <div>
                <span className="cp-status-label">Business name</span>
                <h2>{listing.name || "Unnamed business"}</h2>
              </div>
              <span className={visible ? "partner-status-pill visible" : "partner-status-pill hidden"}>{formatStatus(status)}</span>
            </div>

            <p className="partner-hub-copy">{copy}</p>

            <div className="partner-hub-grid">
              <div><span className="cp-status-label">Category</span><strong>{listing.category || "Not set"}</strong></div>
              <div><span className="cp-status-label">Status</span><strong>{formatStatus(status)}</strong></div>
              <div><span className="cp-status-label">Submitted</span><strong>{formatDate(listing.created_at)}</strong></div>
              <div><span className="cp-status-label">Last updated</span><strong>{formatDate(listing.updated_at)}</strong></div>
              <div><span className="cp-status-label">Completion</span><strong>{completionLabel(listing.complete_pct)}</strong></div>
              <div><span className="cp-status-label">Public visibility</span><strong>{visible ? "Visible" : "Hidden until review"}</strong></div>
              <div><span className="cp-status-label">HEHA Certified</span><strong>{certified ? "Certified" : "Not certified yet"}</strong></div>
            </div>

            <div className="partner-cert-note">Approved/live status is not the same as HEHA Certified. HEHA certification remains admin-controlled.</div>
          </>
        ) : (
          <>
            <h2>No listing found</h2>
            <p className="partner-hub-copy">{copy}</p>
            {isPartnerAccount && (
              <button className="primary-button" type="button" onClick={onListBusiness}>Start or continue business registration</button>
            )}
          </>
        )}
      </section>

      <section className="partner-hub-actions card-like">
        <h2>Partner actions</h2>
        <div className="partner-action-grid">
          <button className="secondary-button" type="button" onClick={onRefresh}>Refresh status</button>
          <button className="secondary-button" type="button" onClick={openEditor}>{listing ? "Edit business profile" : "Start business profile"}</button>
          <button className="secondary-button" type="button" onClick={openMedia}>Add logo / photos</button>
          <button className="secondary-button" type="button" onClick={openPreview}>Preview listing</button>
          <button className="secondary-button" type="button" onClick={openOffer}>Community Offer</button>
          <button className="secondary-button" type="button" onClick={() => comingSoon("Request certification review")}>Request certification review</button>
        </div>
        {actionNote && <div className="cp-billing-note">{actionNote}</div>}
        <p className="partner-hub-fineprint">HEHA review controls visibility and certification. This hub never auto-publishes, auto-certifies, or changes paid SuperSwoop settings.</p>
      </section>

      {showPreview && listing && <PartnerListingPreview listing={listing} onClose={() => setShowPreview(false)} />}
      {showEditor && listing && (
        <PartnerProfileEditor
          user={user}
          listing={listing}
          onClose={() => setShowEditor(false)}
          onSaved={handleEditorSaved}
        />
      )}
      {showMedia && listing && (
        <PartnerMediaManager
          user={user}
          listing={listing}
          onClose={() => setShowMedia(false)}
          onChanged={onRefresh}
        />
      )}
      {showOffer && listing && (
        <PartnerCommunityOfferBuilder
          user={user}
          listing={listing}
          onClose={() => setShowOffer(false)}
          onChanged={onRefresh}
        />
      )}
    </>
  );
}

export default function CommunityPassTab({ user, profile, onListBusiness }) {
  const [ownerListing, setOwnerListing] = useState(null);
  const [listingLoading, setListingLoading] = useState(false);
  const [listingError, setListingError] = useState(null);

  const partnerByProfile = isPartnerProfile(profile);

  const fetchOwnerListing = useCallback(async () => {
    if (!user?.id) {
      setOwnerListing(null);
      return;
    }

    setListingLoading(true);
    setListingError(null);
    try {
      const { data, error } = await supabase
        .from("partners")
        .select("id, name, category, status, created_at, updated_at, complete_pct, heha_partner, logo_url, image_url, gallery_urls, neighborhood, tagline, bio, tags, offerings, items, website, instagram, price_range, photo_emoji, color, location, hours, contact, business_type, phone, delivery_days, pricing_notes")
        .eq("owner_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) throw error;
      setOwnerListing(data || null);
    } catch (e) {
      setOwnerListing(null);
      setListingError(e);
    } finally {
      setListingLoading(false);
    }
  }, [user?.id]);

  useEffect(() => {
    fetchOwnerListing();
  }, [fetchOwnerListing]);

  const ownsListing = !!ownerListing;
  const showPartnerHub = partnerByProfile || ownsListing;

  return (
    <section className="community-pass-screen">
      {showPartnerHub ? (
        <PartnerHubTab
          user={user}
          listing={ownerListing}
          loading={listingLoading}
          error={listingError}
          isPartnerAccount={partnerByProfile}
          onRefresh={fetchOwnerListing}
          onListBusiness={onListBusiness}
        />
      ) : (
        <CustomerCommunityPass user={user} profile={profile} />
      )}
    </section>
  );
}
