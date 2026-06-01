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
  { id: "swipe", label: "Discover", icon: "✦" },
  { id: "faves", label: "Saved", icon: "♥" },
  { id: "profile", label: "Profile", icon: "◎" },
];

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
];

function isOnboarded(profile) {
  const type = profile?.subscription_type;
  if (!type) return false;
  return COMPLETED_SUBSCRIPTION_TYPES.some(
    (acceptedType) => type === acceptedType || type.startsWith(`${acceptedType}_`)
  );
}

function isPartnerProfile(profile) {
  return profile?.subscription_type?.startsWith("partner");
}

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [partners, setPartners] = useState([]);
  const [saves, setSaves] = useState([]);
  const [tab, setTab] = useState("swipe");
  const [loading, setLoading] = useState(true);
  const [dataLoading, setDataLoading] = useState(false);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [showPartnerWizard, setShowPartnerWizard] = useState(false);
  const [passwordRecovery, setPasswordRecovery] = useState(false);
  const [notice, setNotice] = useState(null);
  const [appError, setAppError] = useState(null);

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
    window.history.replaceState(null, "", window.location.pathname);
    setNeedsOnboarding(false);
    if (returnRole === "partner") setShowPartnerWizard(true);
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

      await Promise.all([
        recordSwipeEvent(partner, "right"),
        supabase
          .from("partners")
          .update({ total_saves: (partner.total_saves || 0) + 1 })
          .eq("id", partner.id),
      ]);

      flashNotice(`${partner.name} saved to your HEHA list.`);
    } catch (error) {
      flashNotice(error.message || "Could not save this business yet.");
    }
  };

  const handlePass = async (partner) => {
    if (!partner?.id) return;
    try {
      await Promise.all([
        recordSwipeEvent(partner, "left"),
        supabase
          .from("partners")
          .update({ total_swipes: (partner.total_swipes || 0) + 1 })
          .eq("id", partner.id),
      ]);
    } catch {
      // Passing should feel lightweight. We quietly preserve the user flow.
    }
  };

  const handleSuperSwipe = async (partner) => {
    const uid = session?.user?.id;
    if (!uid || !partner?.id) return;

    try {
      await Promise.all([
        recordSwipeEvent(partner, "super"),
        supabase
          .from("partners")
          .update({ total_swipes: (partner.total_swipes || 0) + 1 })
          .eq("id", partner.id),
      ]);

      flashNotice(`SuperSwoop sent for ${partner.name}. HEHA will know this one stands out.`);
    } catch (error) {
      flashNotice(error.message || "Could not send SuperSwoop yet.");
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

  if (loading) return <SplashScreen />;
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
      <header className="app-header">
        <div className="brand-lockup">
          <div className="brand-mark">✦</div>
          <div>
            <div className="brand-name">HEHA<span>·</span>swipe</div>
            <div className="brand-subtitle">Tampa Bay healthy discovery</div>
          </div>
        </div>
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
          <FavesTab partners={partners} saves={saves} onUnsave={handleUnsave} />
        )}
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

      <nav className="bottom-nav" aria-label="Primary navigation">
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

function SplashScreen() {
  return (
    <div className="splash-screen">
      <div className="splash-card">
        <div className="brand-mark large">✦</div>
        <h1>HEHA<span>·</span>swipe</h1>
        <p>Curating Tampa Bay's healthy food, wellness, movement, and local business scene.</p>
        <div className="loading-bar"><span /></div>
      </div>
    </div>
  );
}