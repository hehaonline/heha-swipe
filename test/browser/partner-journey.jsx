import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import ProfileTab from "../../src/components/ProfileTab";
import CommunityPassTab from "../../src/components/CommunityPassTab";
import { fetchClaimReturnPartner } from "../../src/lib/partnerClaimFlow";
import { supabase } from "../../src/lib/supabase";
import "../../src/index.css";
import "../../src/mobile-fit.css";
import "../../src/account-actions.css";
import "../../src/onboarding-fix.css";
import "../../src/heha-brand-theme.css";
import "../../src/saved-detail-cleanup.css";
import "../../src/super-swoop.css";
import "../../src/preview-and-onboarding-fixes.css";
import "../../src/partner-wizard-clean.css";
import "../../src/placeholder-photo.css";
import "../../src/location-modal.css";
import "../../src/community-pass.css";
import "../../src/partner-media.css";
import "../../src/partner-offers.css";
import "../../src/embed.css";

// Synthetic authenticated component props, NOT a real login or claim. The actual
// claim-return query and production Profile/Community Pass/editor/media render.
const user = { id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", email: "synthetic-owner@example.invalid", created_at: "2020-01-01T00:00:00Z" };
const profile = { id: user.id, full_name: "Synthetic Owner", subscription_type: "partner_free" };
const claimedId = "11111111-1111-4111-8111-111111111111";

function Fixture() {
  const [listing, setListing] = useState(null);
  const [tab, setTab] = useState("Profile");
  const [error, setError] = useState(null);
  useEffect(() => {
    fetchClaimReturnPartner(supabase, user.id, { partnerId: claimedId })
      .then(setListing).catch((failure) => setError(failure.message));
  }, []);
  return <div className="app-shell">
    <nav aria-label="Synthetic journey views">
      {["Profile", "Community Pass"].map((name) => <button key={name} type="button" aria-pressed={tab === name} onClick={() => setTab(name)}>{name}</button>)}
    </nav>
    <main aria-label="Partner account">
      {error && <p role="alert">{error}</p>}
      {!listing ? <p role="status">Loading exact claimed card…</p> : tab === "Profile"
        ? <ProfileTab user={user} profile={profile} isBusiness listing={listing} onSignOut={() => {}} />
        : <CommunityPassTab user={user} profile={profile} listing={listing} />}
    </main>
  </div>;
}

createRoot(document.getElementById("root")).render(<Fixture />);
