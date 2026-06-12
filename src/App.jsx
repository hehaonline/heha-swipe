import { useEffect, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import OnboardingScreen from "./components/OnboardingScreen";
import PartnerWizard from "./components/PartnerWizard";
import SwipeTab from "./components/SwipeTab";
import FavesTab from "./components/FavesTab";
import ProfileTab from "./components/ProfileTab";
import PasswordResetScreen from "./components/PasswordResetScreen";

const TABS = [
  { id: "swipe", label: "Discover", icon: "⌕" },
  { id: "faves", label: "Saved", icon: "♡" },
  { id: "deals", label: "Deals", icon: "⌑" },
  { id: "profile", label: "Profile", icon: "♙" },
];

const SUPPORT_PROMPT_STORAGE_KEY = "heha_swipe_support_prompt_skipped";

const COMPLETED_SUBSCRIPTION_TYPES = [
  "instagram",
  "monthly",
  "customer_free",
  "customer_supporter",
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

function getInitialSupportPromptDismissed() {
  try {
    return window.sessionStorage.getItem(SUPPORT_PROMPT_STORAGE_KEY) === "true";
  } catch {
    return false;
  }
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
  const [supportPromptDismissed, setSupportPromptDismissed] = useState(getInitialSupportPromptDismissed);
  const [supportPromptError, setSupportPromptError] = useState(null);
  const [dataLoading, setDataLoading] = useState(false);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [showPartnerWizard, setShowPartnerWizard] = useState(false);
  const [passwordRecovery, setPasswordRecovery] = useState(false);
  const [notice, setNotice] = useState(null);
  const [appError, setAppError] = useState(null);

  useEffect(() => {
    const timer = window.setTimeout(() => setSplashReady(true), 3400);
    return () => window.clearTimeout(timer);
  }, []);

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
      if (event === "PASSWORD_RECOVERY") {
        setPasswordRecovery(true);
      }
      if (!newSession) {
        setProfile(null);
        setPartners([]);
        setSaves([]);
        setNeedsOnboarding(false);
        setShowPartnerWizard(false);
        setPasswordRecovery(false);
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
    const checkoutType = params.get("type");
    window.history.replaceState(null, "", window.location.pathname);
    setNeedsOnboarding(false);
    if (returnRole === "partner") setShowPartnerWizard(true);
    if (checkoutType === "superswoop") {
      flashNotice("SuperSwoop payment received. HEHA will activate it after Stripe confirms the $2 payment.");
    }
    if (checkoutType === "dollar_support") {
      flashNotice("Thank you for the $1 prototype support. Every push helps HEHA Swipe and HEHA Local move forward.");
    }
    loadData(session.user.id);
  }, [session?.user?.id]);

  const savedPartnerIds = useMemo(
    () => new Set(saves.map((save) => save.partner_id)),
    [saves]
  );

  const loadData = async (uid = session?.user?.id) => {
    if (!uid) return;
    setDataLoading(true);
    setAppError(null);

    try {
      const [profileResult, partnerResult, saveResult] = await Promise.all([
        supabase.from("profiles").select("*").eq("id", uid).maybeSingle(),
        supabase
          .from("partners")
          .select("*")
          .in("status", ["approved", "listed"])
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
      setNeedsOnboarding(!isOnboarded(nextProfile));

      if (isPartnerProfile(nextProfile)) {
        const { data: existing, error } = await supabase
          .from("partners")
          .select("id")
          .eq("owner_id", uid)
          .maybeSingle();
        if (error) throw error;
        if (!existing) setShowPartnerWizard(true);
      }
    } catch (error) {
      setAppError(error.message || "Could not load HEHA Swipe.");
    } finally {
      setDataLoading(false);
    }
  };

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

  const dismissSupportPrompt = () => {
    try {
      window.sessionStorage.setItem(SUPPORT_PROMPT_STORAGE_KEY, "true");
    } catch {
      // Browsers can block storage in some privacy modes. Skipping should still work.
    }
    setSupportPromptDismissed(true);
  };

  const handleDollarSupport = () => {
    try {
      const stripeLink = import.meta.env.VITE_STRIPE_DOLLAR_SUPPORT_CHECKOUT_URL;
      if (!stripeLink) {
        throw new Error("$1 support checkout is not connected yet. Add VITE_STRIPE_DOLLAR_SUPPORT_CHECKOUT_URL in Vercel after creating the Stripe payment link.");
      }

      dismissSupportPrompt();
      const url = new URL(stripeLink);
      url.searchParams.set("client_reference_id", session?.user?.id ? `dollar_support__${session.user.id}` : "dollar_support__guest");
      url.searchParams.set("prefilled_email", session?.user?.email || "");
      window.location.href = url.toString();
    } catch (error) {
      setSupportPromptError(error.message || "Could not open $1 support checkout yet.");
    }
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
    const uid = session?.user?.id;
    if (!uid || !partner?.id) return;

    try {
      const stripeLink = import.meta.env.VITE_STRIPE_SUPERSWOOP_CHECKOUT_URL;
      if (!stripeLink) {
        throw new Error("SuperSwoop checkout is not connected yet. Add VITE_STRIPE_SUPERSWOOP_CHECKOUT_URL in Vercel after creating the $2 Stripe payment link.");
      }

      await recordSwipeEvent(partner, "super_checkout_started");

      const url = new URL(stripeLink);
      url.searchParams.set("client_reference_id", `superswoop__${uid}__${partner.id}`);
      url.searchParams.set("prefilled_email", session.user.email || "");
      window.location.href = url.toString();
    } catch (error) {
      flashNotice(error.message || "Could not open SuperSwoop checkout yet.");
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

  if (!supportPromptDismissed) {
    return (
      <SupportPromptScreen
        error={supportPromptError}
        onSupport={handleDollarSupport}
        onSkip={dismissSupportPrompt}
      />
    );
  }

  if (loading || !splashReady) return <SplashScreen />;
  if (!session) return <AuthScreen />;
  if (passwordRecovery) {
    return (
      <PasswordResetScreen
        onComplete={() => {
          setPasswordRecovery(false);
          loadData(session.user.id);
        }}
      />
    );
  }

  if (needsOnboarding) {
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

  if (showPartnerWizard) {
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

  return (
    <div className="app-shell">
      <header className="app-header luxe-header">
        <SwipeLogo compact />
        <button className="ghost-pill" onClick={() => setShowPartnerWizard(true)}>Get listed</button>
      </header>

      {notice && <div className="toast-notice">{notice}</div>}
      {appError && <div className="error-banner">{appError}</div>}

      <main className="app-content" aria-busy={dataLoading}>
        {tab === "swipe" && (
          <SwipeTab
            partners={partners}
            saves={saves}
            onSave={handleSave}
            onPass={handlePass}
            onSuperSwipe={handleSuperSwipe}
            dataLoading={dataLoading}
          />
        )}
        {tab === "faves" && (
          <FavesTab
            partners={partners}
            saves={saves}
            onUnsave={handleUnsave}
            onDiscountCheck={handleDiscountCheck}
          />
        )}
        {tab === "deals" && <DealsTab />}
        {tab === "profile" && (
          <ProfileTab
            user={session.user}
            profile={profile}
            partners={partners}
            saves={saves}
            onSignOut={handleSignOut}
            onListBusiness={() => setShowPartnerWizard(true)}
            onRefresh={() => loadData(session.user.id)}
          />
        )}
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

function SupportPromptScreen({ error, onSupport, onSkip }) {
  return (
    <main className="splash-screen">
      <section className="splash-card">
        <div className="brand-mark large">H</div>
        <p className="eyebrow">Prototype support</p>
        <h1>Help push HEHA forward.</h1>
        <p>
          HEHA Swipe and HEHA Local are still early. Tap once to support the team and help us share the prototype with more local businesses, artists, and wellness partners.
        </p>

        <button
          type="button"
          className="primary-button"
          onClick={onSupport}
          style={{
            width: "190px",
            height: "190px",
            borderRadius: "999px",
            margin: "22px auto 12px",
            display: "grid",
            placeItems: "center",
            fontSize: "19px",
            lineHeight: "1.15",
            whiteSpace: "pre-line",
          }}
        >
          {"Tap to support\n$1 per push"}
        </button>

        <button className="text-button center" type="button" onClick={onSkip}>
          Skip for now
        </button>

        <p className="soft-note">Optional. No paywall — just community support while the apps are still in prototype mode.</p>
        {error && <div className="error-banner">{error}</div>}
      </section>
    </main>
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

function DealsTab() {
  return (
    <section className="saved-screen deals-screen">
      <div className="section-hero clean-section-hero">
        <p className="eyebrow">Member offers</p>
        <h2>Deals are coming soon.</h2>
        <p>Saved discount requests and partner offers will live here once HEHA starts activating member deals.</p>
      </div>
    </section>
  );
}
