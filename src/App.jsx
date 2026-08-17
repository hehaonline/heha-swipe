import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import EntryGate from "./components/EntryGate";
import AuthPromptModal from "./components/AuthPromptModal";
import {
  isGuestSession,
  setGuestSession,
  clearGuestSession,
  shouldShowEntryGate,
  stripEntryParams,
  readReturnPath,
  isLandingEntry,
} from "./lib/entryGate";
import OnboardingScreen from "./components/OnboardingScreen";
import PartnerWizard from "./components/PartnerWizard";
import SwipeTab from "./components/SwipeTab";
import FavesTab from "./components/FavesTab";
import ProfileTab from "./components/ProfileTab";
import PasswordResetScreen from "./components/PasswordResetScreen";
import LocationModal, { getActiveLocationLabel } from "./components/LocationModal";
import CommunityPassTab from "./components/CommunityPassTab";
import { fetchActiveSupporterSubscription } from "./lib/supporterStatus";
import { clearClaimSuccess, consumeClaimSuccess, removeClaimSuccessParam } from "./lib/partnerClaimUx";

const TABS = [
  { id: "swipe", label: "Discover", icon: "⌕" },
  { id: "faves", label: "Saved", icon: "♡" },
  { id: "deals", label: "Community", icon: "⌑" },
  { id: "profile", label: "Profile", icon: "♙" },
];

const COMPLETED_SUBSCRIPTION_TYPES = [
  "instagram",
  "monthly",
  "customer_free",
  "partner_free",
  "partner_supporter",
  "partner_instagram",
  "partner_monthly",
  "partner",
  "listed",
];

const PARTNER_SUBSCRIPTION_TYPES = [
  "instagram",
  "monthly",
  "partner_free",
  "partner_supporter",
  "partner_instagram",
  "partner_monthly",
  "partner",
  "listed",
];

function isOnboarded(profile) {
  const type = profile?.subscription_type;
  if (!type) return false;
  return COMPLETED_SUBSCRIPTION_TYPES.some(
    (acceptedType) => type === acceptedType || type.startsWith(`${acceptedType}_`)
  );
}

function isPartnerProfile(profile) {
  const type = profile?.subscription_type;
  if (!type) return false;
  return PARTNER_SUBSCRIPTION_TYPES.some(
    (acceptedType) => type === acceptedType || type.startsWith(`${acceptedType}_`)
  );
}

function SwipeLogo({ compact = false }) {
  return (
    <div className={compact ? "swipe-logo compact-logo" : "swipe-logo"} aria-label="HEHA Swipe">
      <span className="swipe-logo-square" />
      <span className="swipe-logo-heha">HEHA</span>
      <span className="swipe-logo-word">swipe</span>
    </div>
  );
}

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [partners, setPartners] = useState([]);
  const [saves, setSaves] = useState([]);
  const [tab, setTab] = useState("swipe");
  const [loading, setLoading] = useState(true);
  const [splashReady, setSplashReady] = useState(false);
  const [dataLoading, setDataLoading] = useState(false);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [showPartnerWizard, setShowPartnerWizard] = useState(false);
  // The signed-in user's own partner listing if they own one, so role-aware
  // Profile and Community screens can use business copy without schema changes.
  const [myListing, setMyListing] = useState(null);
  const [passwordRecovery, setPasswordRecovery] = useState(false);
  const [notice, setNotice] = useState(null);
  const [appError, setAppError] = useState(null);
  const [showLocationModal, setShowLocationModal] = useState(false);
  const [locationLabel, setLocationLabel] = useState(null);
  // Landing entry gate + guest browsing state. `guest` is true only after the
  // visitor explicitly chose "continue as guest" (remembered for the session).
  // `authIntent` routes a landing/guest visitor into the existing AuthScreen in
  // sign-in or create-account mode. `authPrompt` drives the protected-action
  // modal for guests. None of these grant any server-side capability.
  const [guest, setGuestFlag] = useState(() => isGuestSession());
  const [authIntent, setAuthIntent] = useState(null); // null | "signin" | "create"
  const [authPrompt, setAuthPrompt] = useState(null); // null | { message?: string }
  const arrivedFromLanding = useRef(isLandingEntry(window.location.search));
  const [supportReturn] = useState(() => window.location.pathname === "/support/success");
  const [supportView, setSupportView] = useState(() =>
    window.location.pathname === "/support/success"
      ? "success"
      : window.location.pathname === "/support/cancel"
      ? "cancel"
      : null
  );
  const [claimSuccess, setClaimSuccess] = useState(null);
  const visibleClaimSuccess = claimSuccess?.userId === session?.user?.id ? claimSuccess : null;

  useEffect(() => {
    const timer = window.setTimeout(() => setSplashReady(true), 3400);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    setLocationLabel(getActiveLocationLabel(profile?.location || null));
  }, [profile]);

  useEffect(() => {
    if (claimSuccess && claimSuccess.userId !== session?.user?.id) {
      setClaimSuccess(null);
      return;
    }
    if (!session?.user?.id || claimSuccess) return;
    const success = consumeClaimSuccess(window.location.search, sessionStorage, session.user.id);
    if (!success) return;
    setClaimSuccess(success);
    window.history.replaceState(null, "", removeClaimSuccessParam(window.location));
  }, [session?.user?.id, claimSuccess]);

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (!mounted) return;
      if (error) setAppError(error.message);
      setSession(data?.session || null);
      setLoading(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((event, newSession) => {
      setSession(newSession);
      if (event === "PASSWORD_RECOVERY") setPasswordRecovery(true);
      if (newSession) {
        // A real session supersedes any guest choice. Clearing it means a later
        // sign-out returns to the auth screen, never to a lingering guest pass.
        clearGuestSession();
        setGuestFlag(false);
        setAuthIntent(null);
        setAuthPrompt(null);
      }
      if (!newSession) {
        setClaimSuccess(null);
        setProfile(null);
        setPartners([]);
        setSaves([]);
        setNeedsOnboarding(false);
        setShowPartnerWizard(false);
        setMyListing(null);
        setPasswordRecovery(false);
        setLocationLabel(getActiveLocationLabel(null));
      }
    });

    return () => {
      mounted = false;
      listener?.subscription?.unsubscribe?.();
    };
  }, []);

  useEffect(() => {
    if (!session?.user?.id || passwordRecovery) return;
    loadData(session.user.id);
    pingNewUserWebhook(session.user);
  }, [session?.user?.id, passwordRecovery]);

  useEffect(() => {
    if (!session?.user) return;
    const params = new URLSearchParams(window.location.search);
    const checkoutSuccess = params.get("checkout") === "success";
    if (!checkoutSuccess) return;

    const returnRole = params.get("role");
    window.history.replaceState(null, "", window.location.pathname);
    setNeedsOnboarding(false);
    if (returnRole === "partner") setShowPartnerWizard(true);
    loadData(session.user.id);
  }, [session?.user?.id]);

  // Authenticated visitors bypass the gate automatically: strip the landing
  // params (preserving a safe return destination) once the session is known.
  useEffect(() => {
    if (loading) return;
    if (session?.user && isLandingEntry(window.location.search)) {
      finalizeEntryUrl();
    }
  }, [loading, session?.user?.id]);

  // Guest browsing loads the public partner deck once, with no session.
  useEffect(() => {
    if (session?.user?.id) return;
    if (!guest) return;
    loadPublicPartners();
  }, [guest, session?.user?.id]);

  const savedPartnerIds = useMemo(
    () => new Set(saves.map((save) => save.partner_id)),
    [saves]
  );

  const hasActiveSupporterSub = async (uid) => !!(await fetchActiveSupporterSubscription(uid));

  const loadData = async (uid = session?.user?.id) => {
    if (!uid) return;
    setDataLoading(true);
    setAppError(null);

    try {
      const [profileResult, partnerResult, saveResult] = await Promise.all([
        supabase.from("profiles").select("*").eq("id", uid).maybeSingle(),
        supabase
          .from("public_swipe_partners")
          .select("*")
          .order("heha_partner", { ascending: false })
          .order("created_at", { ascending: false }),
        supabase.from("saves").select("*").eq("user_id", uid),
      ]);

      if (profileResult.error) throw profileResult.error;
      if (partnerResult.error) throw partnerResult.error;
      if (saveResult.error) throw saveResult.error;

      const nextProfile = profileResult.data;
      const nextPartners = partnerResult.data || [];
      const nextSaves = saveResult.data || [];

      setProfile(nextProfile);
      setPartners(nextPartners);
      setSaves(nextSaves);
      const supporterByEntitlement = await hasActiveSupporterSub(uid);
      setNeedsOnboarding(!(isOnboarded(nextProfile) || supporterByEntitlement));

      let signupIntent = null;
      try {
        signupIntent = localStorage.getItem("heha_signup_role");
      } catch {
        // Browser storage is optional; ownership remains authoritative.
      }
      const { data: ownedListings, error: ownedListingError } = await supabase
        .from("partners")
        .select("id, name, category, status, created_at, updated_at, complete_pct, heha_partner")
        .eq("owner_id", uid)
        .order("created_at", { ascending: false })
        .limit(1);
      if (ownedListingError) throw ownedListingError;
      const existing = ownedListings?.[0] || null;
      setMyListing(existing);
      if (existing) setNeedsOnboarding(false);

      if (isPartnerProfile(nextProfile) || existing || signupIntent === "partner") {
        if (!existing) {
          setShowPartnerWizard(true);
          setNeedsOnboarding(false);
          if (signupIntent === "partner") {
            try {
              localStorage.removeItem("heha_signup_role");
            } catch {
              // Do not block the owner flow when browser storage is unavailable.
            }
          }
        }
      }
    } catch (error) {
      setAppError(error.message || "Could not load HEHA Swipe.");
    } finally {
      setDataLoading(false);
    }
  };

  // Guest discovery: load only the public, anon-readable partner view. No
  // profile, saves, swipe history, or any user-scoped data is touched, and no
  // Supabase user or row is created. Server-side RLS remains the real boundary.
  const loadPublicPartners = async () => {
    setDataLoading(true);
    setAppError(null);
    try {
      const { data, error } = await supabase
        .from("public_swipe_partners")
        .select("*")
        .order("heha_partner", { ascending: false })
        .order("created_at", { ascending: false });
      if (error) throw error;
      setPartners(data || []);
    } catch (error) {
      setAppError(error.message || "Could not load HEHA Swipe.");
    } finally {
      setDataLoading(false);
    }
  };

  // Clean the entry params out of the URL after a choice, honoring a sanitized
  // internal return destination when one was supplied.
  const finalizeEntryUrl = () => {
    const safeReturn = readReturnPath(window.location.search);
    const target =
      safeReturn ||
      `${window.location.pathname}${stripEntryParams(window.location.search)}${window.location.hash}`;
    window.history.replaceState(null, "", target);
  };

  const handleChooseGuest = () => {
    setGuestSession();
    setGuestFlag(true);
    setAuthIntent(null);
    setAuthPrompt(null);
    finalizeEntryUrl();
  };

  const handleChooseAuth = (intent) => {
    setAuthPrompt(null);
    setAuthIntent(intent === "create" ? "create" : "signin");
    finalizeEntryUrl();
  };

  const requireAuth = (message) =>
    setAuthPrompt({
      message:
        message ||
        "Create a free account or log in to use this. You can keep browsing as a guest in the meantime.",
    });

  const pingNewUserWebhook = async (user) => {
    try {
      const webhookUrl = import.meta.env.VITE_MAKE_NEW_USER_WEBHOOK;
      if (!webhookUrl) return;
      await fetch(webhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          user_id: user.id,
          email: user.email || null,
          phone: user.phone || null,
          created_at: user.created_at,
          source: "heha_swipe",
        }),
      });
    } catch {
      // Marketing webhook failures should never block app usage.
    }
  };

  const flashNotice = (message) => {
    setNotice(message);
    window.setTimeout(() => setNotice(null), 2600);
  };

  const recordSwipeEvent = async (partner, direction) => {
    const uid = session?.user?.id;
    if (!uid || !partner?.id) return;

    const { error } = await supabase.from("swipe_events").insert({
      user_id: uid,
      partner_id: partner.id,
      direction,
    });

    if (error) throw error;
  };

  const handleSave = async (partner) => {
    const uid = session?.user?.id;
    if (!uid || !partner?.id) return;

    try {
      if (!savedPartnerIds.has(partner.id)) {
        const { data, error } = await supabase
          .from("saves")
          .insert({ user_id: uid, partner_id: partner.id })
          .select()
          .single();
        if (error) throw error;
        if (data) setSaves((current) => [...current, data]);
      }

      await recordSwipeEvent(partner, "right");
      flashNotice(`${partner.name} saved to your HEHA list.`);
    } catch (error) {
      flashNotice(error.message || "Could not save this business yet.");
    }
  };

  const handlePass = async (partner) => {
    if (!partner?.id) return;
    try {
      await recordSwipeEvent(partner, "left");
    } catch {
      // Passing should feel lightweight. We quietly preserve the user flow.
    }
  };

  const handleSuperSwipe = async (partner) => {
    if (!partner?.id) return;
    flashNotice("SuperSwoop is coming soon. For now, save this spot and help us see what the community wants next.");
  };

  const handleUndoSwipe = async (partner, direction, { wasSaved = false } = {}) => {
    const uid = session?.user?.id;
    if (!uid || !partner?.id) return false;

    try {
      if (direction === "right" && !wasSaved) {
        const { error } = await supabase
          .from("saves")
          .delete()
          .eq("user_id", uid)
          .eq("partner_id", partner.id);
        if (error) throw error;
        setSaves((current) => current.filter((save) => save.partner_id !== partner.id));
      }

      flashNotice(`${partner.name} is back in your swipe deck.`);
      return true;
    } catch (error) {
      flashNotice(error.message || "Could not undo that swipe yet.");
      return false;
    }
  };

  const handleDiscountCheck = async (partner, request = {}) => {
    const uid = session?.user?.id;
    if (!uid || !partner?.id) return;

    const phone = request.user_phone?.trim() || null;
    const preference = request.contact_preference || "text";
    const note = request.user_note?.trim() || null;
    const consent = Boolean(request.consent_to_contact);

    try {
      const { error } = await supabase.from("discount_interest_requests").insert({
        user_id: uid,
        partner_id: partner.id,
        partner_name: partner.name,
        partner_category: partner.category || null,
        partner_neighborhood: partner.neighborhood || partner.location || null,
        user_phone: phone,
        contact_preference: preference,
        user_note: note,
        consent_to_contact: consent,
        source: "saved_detail",
        user_followup_status: phone && consent ? "pending" : "no_contact_requested",
      });
      if (error) throw error;

      await Promise.allSettled([
        recordSwipeEvent(partner, "discount_interest"),
        supabase.from("in_app_messages").insert({
          user_id: uid,
          title: "Discount request received",
          body: `HEHA saved your request for ${partner.name}. If a discount or partner offer becomes available, it can appear here in your inbox${phone && consent ? " and a team member may follow up by your selected contact method" : ""}.`,
          related_partner_id: partner.id,
          message_type: "discount_request",
        }),
      ]);

      flashNotice(`Discount request saved for ${partner.name}. Check your Profile inbox for updates.`);
    } catch (error) {
      flashNotice(error.message || "Could not save discount interest yet.");
    }
  };

  const handleUnsave = async (partnerId) => {
    try {
      const { error } = await supabase
        .from("saves")
        .delete()
        .eq("user_id", session.user.id)
        .eq("partner_id", partnerId);
      if (error) throw error;
      setSaves((current) => current.filter((save) => save.partner_id !== partnerId));
      flashNotice("Removed from your saved HEHA list.");
    } catch (error) {
      flashNotice(error.message || "Could not remove this business yet.");
    }
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null);
  };

  const handleLocationSaved = (locationString, displayLabel) => {
    setLocationLabel(displayLabel || locationString);
  };

  const refreshProfileNow = async () => {
    const uid = session?.user?.id;
    if (!uid) return false;
    const { data } = await supabase.from("profiles").select("*").eq("id", uid).maybeSingle();
    if (data) setProfile(data);
    const supporterActive = await hasActiveSupporterSub(uid);
    setNeedsOnboarding(!(((data && isOnboarded(data)) || supporterActive)));
    return supporterActive;
  };

  const handleSupportStatusContinue = () => {
    setSupportView(null);
    window.history.replaceState(null, "", "/");
    setTab("deals");
    refreshProfileNow();
  };

  const dismissClaimSuccess = () => {
    clearClaimSuccess(sessionStorage);
    setClaimSuccess(null);
    window.history.replaceState(null, "", removeClaimSuccessParam(window.location));
  };

  const reviewClaimedAccount = () => {
    setTab("profile");
    dismissClaimSuccess();
  };

  if (loading || !splashReady) return <SplashScreen />;
  if (supportView) {
    return <SupportCheckoutStatus status={supportView} onContinue={handleSupportStatusContinue} onPoll={refreshProfileNow} />;
  }
  // Unauthenticated: entry gate, auth screen, or guest browsing. Authenticated
  // users never enter this branch and keep their existing flow untouched.
  if (!session) {
    if (authIntent) {
      // Guest/landing visitor chose Log in or Create an account. Reuse the
      // existing auth system; offer a safe path back to guest browsing.
      return <AuthScreen initialMode={authIntent} onBack={handleChooseGuest} />;
    }
    if (shouldShowEntryGate({ search: window.location.search, hasSession: false, isGuest: guest })) {
      return (
        <EntryGate
          onGuest={handleChooseGuest}
          onLogin={() => handleChooseAuth("signin")}
          onCreate={() => handleChooseAuth("create")}
        />
      );
    }
    if (!guest) {
      // Direct (non-landing) visitors keep the exact existing behavior: the auth
      // screen with no guest affordance. Landing visitors get a way back.
      return <AuthScreen onBack={arrivedFromLanding.current ? handleChooseGuest : undefined} />;
    }
    // Otherwise: guest browsing -> fall through to the guest-safe app shell.
  }

  if (session && passwordRecovery) {
    return (
      <PasswordResetScreen
        onComplete={() => {
          setPasswordRecovery(false);
          loadData(session.user.id);
        }}
      />
    );
  }

  if (session && needsOnboarding && !supportReturn) {
    return (
      <OnboardingScreen
        user={session.user}
        onComplete={(role) => {
          setNeedsOnboarding(false);
          if (role === "partner") setShowPartnerWizard(true);
          loadData(session.user.id);
        }}
      />
    );
  }

  if (session && showPartnerWizard) {
    return (
      <PartnerWizard
        user={session.user}
        onComplete={() => {
          setShowPartnerWizard(false);
          setTab("profile");
          loadData(session.user.id);
        }}
        onCancel={() => setShowPartnerWizard(false)}
      />
    );
  }

  const isGuestMode = !session && guest;
  const guestSaveMessage = "Create a free account or log in to save spots to your HEHA list.";

  return (
    <div className={isGuestMode ? "app-shell guest-shell" : "app-shell"}>
      <header className="app-header luxe-header">
        <SwipeLogo compact />
        <button
          className="location-pill ghost-pill"
          onClick={() => setShowLocationModal(true)}
          aria-label="Set your location"
          title="Set your location"
        >
          <span className="location-pill-icon">📍</span>
          <span className="location-pill-label">{locationLabel || "Tampa Bay"}</span>
        </button>
        <button
          className="ghost-pill"
          onClick={
            isGuestMode
              ? () => requireAuth("Log in or create an account to list your business on HEHA Swipe.")
              : () => setShowPartnerWizard(true)
          }
        >
          Get listed
        </button>
      </header>

      {isGuestMode && (
        <div className="guest-ribbon" role="status">
          <span>You're browsing as a guest.</span>
          <span className="guest-ribbon-actions">
            <button type="button" className="text-button" onClick={() => handleChooseAuth("signin")}>
              Log in
            </button>
            <button type="button" className="guest-ribbon-cta" onClick={() => handleChooseAuth("create")}>
              Create account
            </button>
          </span>
        </div>
      )}

      {notice && <div className="toast-notice">{notice}</div>}
      {appError && <div className="error-banner">{appError}</div>}
      {visibleClaimSuccess && (
        <section className="claim-success-panel" role="status" aria-live="polite">
          <div>
            <strong>{visibleClaimSuccess.partnerName} is now connected to your HEHA account.</strong>
            <p>Your saves, swipes, and history carried over—nothing was published or changed publicly yet. Head to your profile to review and prepare updates.</p>
            {visibleClaimSuccess.profileSetupPending && <p>HEHA will finish setting up the account profile; your business claim was successful.</p>}
          </div>
          <div className="claim-success-actions">
            <button className="primary-button" type="button" onClick={reviewClaimedAccount}>Review your HEHA account</button>
            <button className="text-button" type="button" onClick={dismissClaimSuccess} aria-label="Dismiss claim confirmation">Dismiss</button>
          </div>
        </section>
      )}

      {showLocationModal && (
        <LocationModal
          user={session?.user || null}
          profileLocation={profile?.location || null}
          onClose={() => setShowLocationModal(false)}
          onLocationSaved={handleLocationSaved}
        />
      )}

      {authPrompt && (
        <AuthPromptModal
          message={authPrompt.message}
          onLogin={() => handleChooseAuth("signin")}
          onCreate={() => handleChooseAuth("create")}
          onCancel={() => setAuthPrompt(null)}
        />
      )}

      <main className="app-content" aria-busy={dataLoading}>
        {tab === "swipe" && (
          <SwipeTab
            partners={partners}
            saves={saves}
            onSave={isGuestMode ? () => requireAuth(guestSaveMessage) : handleSave}
            onPass={handlePass}
            onSuperSwipe={
              isGuestMode
                ? () => requireAuth("SuperSwoop is a member feature. Log in or create an account to try it.")
                : handleSuperSwipe
            }
            onUndoSwipe={
              isGuestMode
                ? () => {
                    requireAuth("Log in or create an account to save and undo swipes.");
                    return false;
                  }
                : handleUndoSwipe
            }
            dataLoading={dataLoading}
          />
        )}
        {tab === "faves" &&
          (isGuestMode ? (
            <GuestTabGate
              title="Save your favorite spots"
              message="Log in or create a free account to keep a personal list of the healthy places you love."
              onLogin={() => handleChooseAuth("signin")}
              onCreate={() => handleChooseAuth("create")}
            />
          ) : (
            <FavesTab
              partners={partners}
              saves={saves}
              onUnsave={handleUnsave}
              onDiscountCheck={handleDiscountCheck}
            />
          ))}
        {tab === "deals" &&
          (isGuestMode ? (
            <GuestTabGate
              title="Join the HEHA community"
              message="Community passes and offers are for members. Log in or create a free account to take part."
              onLogin={() => handleChooseAuth("signin")}
              onCreate={() => handleChooseAuth("create")}
            />
          ) : (
            <CommunityPassTab
              user={session.user}
              profile={profile}
              onListBusiness={() => setShowPartnerWizard(true)}
            />
          ))}
        {tab === "profile" &&
          (isGuestMode ? (
            <GuestTabGate
              title="Your HEHA profile"
              message="Log in or create a free account to personalize discovery, manage saved spots, and support local."
              onLogin={() => handleChooseAuth("signin")}
              onCreate={() => handleChooseAuth("create")}
            />
          ) : (
            <ProfileTab
              user={session.user}
              profile={profile}
              partners={partners}
              saves={saves}
              isBusiness={isPartnerProfile(profile) || !!myListing}
              listing={myListing}
              onSignOut={handleSignOut}
              onListBusiness={() => setShowPartnerWizard(true)}
              onRefresh={() => loadData(session.user.id)}
            />
          ))}
      </main>

      <nav className="bottom-nav luxe-nav" aria-label="Primary navigation">
        {TABS.map((navItem) => (
          <button
            key={navItem.id}
            className={tab === navItem.id ? "active" : ""}
            onClick={() => setTab(navItem.id)}
          >
            <span>{navItem.icon}</span>
            <strong>{navItem.label}</strong>
          </button>
        ))}
      </nav>
    </div>
  );
}

function GuestTabGate({ title, message, onLogin, onCreate }) {
  return (
    <div className="empty-state guest-tab-gate">
      <div className="empty-icon" aria-hidden="true">♡</div>
      <h2>{title}</h2>
      <p>{message}</p>
      <div className="guest-tab-gate-actions">
        <button type="button" className="primary-button" onClick={onCreate}>
          Create an account
        </button>
        <button type="button" className="text-button center" onClick={onLogin}>
          Log in
        </button>
      </div>
    </div>
  );
}

function SplashScreen() {
  return (
    <div className="splash-screen heha-splash luxe-splash">
      <div className="splash-logo-lockup">
        <span className="splash-square" />
        <span className="splash-heha">HEHA</span>
        <span className="splash-swipe">swipe</span>
      </div>
      <p className="heha-powered">powered by Healthy Habit LLC</p>
    </div>
  );
}

function SupportCheckoutStatus({ status, onContinue, onPoll }) {
  const isSuccess = status === "success";
  const [phase, setPhase] = useState(isSuccess ? "checking" : "ready");

  useEffect(() => {
    if (!isSuccess) return;
    let cancelled = false;
    let tries = 0;
    const tick = async () => {
      tries += 1;
      let ok = false;
      try {
        ok = await onPoll?.();
      } catch {
        ok = false;
      }
      if (cancelled) return;
      if (ok) return setPhase("ready");
      if (tries >= 5) return setPhase("slow");
      window.setTimeout(tick, 2000);
    };
    tick();
    return () => {
      cancelled = true;
    };
  }, []);

  const retry = async () => {
    setPhase("checking");
    let ok = false;
    try {
      ok = await onPoll?.();
    } catch {
      ok = false;
    }
    setPhase(ok ? "ready" : "slow");
  };

  if (!isSuccess) {
    return (
      <main className="onboarding-screen">
        <section className="join-card card-like">
          <p className="eyebrow">Monthly support</p>
          <h1>Supporter checkout canceled.</h1>
          <p>No worries. You can keep exploring HEHA Swipe for free.</p>
          <button className="primary-button" type="button" onClick={onContinue}>
            Continue to HEHA Swipe
          </button>
        </section>
      </main>
    );
  }

  return (
    <main className="onboarding-screen">
      <section className="join-card card-like">
        <p className="eyebrow">Monthly support</p>
        <h1>Thank you for supporting HEHA Swipe.</h1>
        {phase === "checking" ? (
          <p>Finalizing your supporter access…</p>
        ) : phase === "slow" ? (
          <p>Still finalizing your supporter access — this can take a moment. You can continue into HEHA Swipe now.</p>
        ) : (
          <p>Your monthly support helps us grow the local healthy discovery network.</p>
        )}

        {phase === "checking" ? (
          <button className="primary-button" type="button" disabled>
            Finalizing…
          </button>
        ) : (
          <>
            <button className="primary-button" type="button" onClick={onContinue}>
              Continue to HEHA Swipe
            </button>
            {phase === "slow" && (
              <button className="text-button center" type="button" onClick={retry}>
                Retry
              </button>
            )}
          </>
        )}
      </section>
    </main>
  );
}
