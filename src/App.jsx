import { useState, useEffect } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import OnboardingScreen from "./components/OnboardingScreen";
import PartnerWizard from "./components/PartnerWizard";
import SwipeTab from "./components/SwipeTab";
import FavesTab from "./components/FavesTab";
import ProfileTab from "./components/ProfileTab";

const TABS = [
  { id: "swipe", label: "Discover", icon: "✦" },
  { id: "faves", label: "Saved", icon: "♥" },
  { id: "profile", label: "Profile", icon: "◎" },
];

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [partners, setPartners] = useState([]);
  const [saves, setSaves] = useState([]);
  const [tab, setTab] = useState("swipe");
  const [loading, setLoading] = useState(true);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [showPartnerWizard, setShowPartnerWizard] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setLoading(false);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, session) => {
      setSession(session);
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session?.user) return;
    loadData();
    pingWebhook(session.user);
  }, [session?.user?.id]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("checkout") === "success" && session?.user) {
      const returnRole = params.get("role");
      window.history.replaceState(null, "", window.location.pathname);
      setNeedsOnboarding(false);
      if (returnRole === "partner") setShowPartnerWizard(true);
      loadData();
    }
  }, [session?.user?.id]);

  const loadData = async () => {
    const uid = session.user.id;
    const [{ data: prof }, { data: prtners }, { data: svs }] = await Promise.all([
      supabase.from("profiles").select("*").eq("id", uid).single(),
      supabase.from("partners").select("*").eq("status", "approved").order("created_at", { ascending: false }),
      supabase.from("saves").select("*").eq("user_id", uid),
    ]);
    setProfile(prof);
    setPartners(prtners || []);
    setSaves(svs || []);
    const done = ["instagram", "monthly", "partner_instagram", "partner_monthly", "partner"];
    const isDone = prof?.subscription_type && done.some(t => prof.subscription_type === t || prof.subscription_type.startsWith(t));
    if (!isDone) setNeedsOnboarding(true);
    else setNeedsOnboarding(false);
    if (["partner_monthly", "partner_instagram", "partner"].includes(prof?.subscription_type)) {
      const { data: existing } = await supabase.from("partners").select("id").eq("owner_id", uid).maybeSingle();
      if (!existing) setShowPartnerWizard(true);
    }
  };

  const pingWebhook = async (user) => {
    try {
      const url = import.meta.env.VITE_MAKE_NEW_USER_WEBHOOK;
      if (!url) return;
      await fetch(url, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: user.id, email: user.email || null, phone: user.phone || null, created_at: user.created_at })
      });
    } catch (_) {}
  };

  const handleSave = async (partner) => {
    const uid = session.user.id;
    const { data } = await supabase.from("saves").insert({ user_id: uid, partner_id: partner.id }).select().single();
    if (data) setSaves(s => [...s, data]);
    await Promise.all([
      supabase.from("partners").update({ total_saves: (partner.total_saves || 0) + 1 }).eq("id", partner.id),
      supabase.from("swipe_events").insert({ user_id: uid, partner_id: partner.id, direction: "right" })
    ]);
  };

  const handlePass = async (partner) => {
    const uid = session.user.id;
    await Promise.all([
      supabase.from("swipe_events").insert({ user_id: uid, partner_id: partner.id, direction: "left" }),
      supabase.from("partners").update({ total_swipes: (partner.total_swipes || 0) + 1 }).eq("id", partner.id)
    ]);
  };

  const handleUnsave = async (partnerId) => {
    await supabase.from("saves").delete().eq("user_id", session.user.id).eq("partner_id", partnerId);
    setSaves(s => s.filter(sv => sv.partner_id !== partnerId));
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null); setProfile(null); setSaves([]); setNeedsOnboarding(false);
  };

  if (loading) return (
    <div style={{ minHeight: "100dvh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#fff", gap: 16, fontFamily: "DM Sans, sans-serif" }}>
      <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, fontSize: 32, letterSpacing: "-1px", color: "#111" }}>
        HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe
      </div>
      <div style={{ width: 48, height: 3, borderRadius: 2, background: "#f0f0f0", overflow: "hidden" }}>
        <div style={{ height: "100%", width: "50%", background: "#e85d2b", animation: "slideRight 1.2s ease infinite" }} />
      </div>
    </div>
  );

  if (!session) return <AuthScreen />;
  if (needsOnboarding) return (
    <OnboardingScreen user={session.user} onComplete={(role) => {
      setNeedsOnboarding(false);
      if (role === "partner") setShowPartnerWizard(true);
    }} />
  );
  if (showPartnerWizard) return (
    <PartnerWizard user={session.user}
      onComplete={() => { setShowPartnerWizard(false); setTab("profile"); }}
      onCancel={() => setShowPartnerWizard(false)} />
  );

  return (
    <div style={{ maxWidth: 480, margin: "0 auto", height: "100dvh", display: "flex", flexDirection: "column", background: "#fff", position: "relative", overflow: "hidden", fontFamily: "DM Sans, sans-serif" }}>

      {/* Header */}
      <div style={{ background: "#fff", padding: "14px 20px 12px", display: "flex", justifyContent: "space-between", alignItems: "center", borderBottom: "1px solid #f0f0f0", flexShrink: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{ width: 34, height: 34, borderRadius: 10, background: "linear-gradient(135deg, #e85d2b, #ff7a47)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 16, boxShadow: "0 4px 12px rgba(232,93,43,0.3)" }}>✦</div>
          <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, fontSize: 20, letterSpacing: "-0.5px", color: "#111" }}>
            HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {tab === "swipe" && (
            <div style={{ fontSize: 11, color: "#e85d2b", background: "#fff4f0", padding: "4px 10px", borderRadius: 20, fontWeight: 600, border: "1px solid #ffe0d6" }}>
              📍 Tampa Bay
            </div>
          )}
          <button onClick={handleSignOut} style={{ background: "none", border: "1px solid #eee", borderRadius: 20, padding: "5px 12px", fontSize: 12, color: "#aaa", cursor: "pointer" }}>
            out
          </button>
        </div>
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflow: "hidden", position: "relative" }}>
        {tab === "swipe" && <SwipeTab partners={partners} saves={saves} onSave={handleSave} onPass={handlePass} />}
        {tab === "faves" && <FavesTab saves={saves} partners={partners} onUnsave={handleUnsave} />}
        {tab === "profile" && <ProfileTab user={session.user} profile={profile} onSignOut={handleSignOut} onListBusiness={() => setShowPartnerWizard(true)} />}
      </di
cat > src/App.jsx << 'EOF'
import { useState, useEffect } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import OnboardingScreen from "./components/OnboardingScreen";
import PartnerWizard from "./components/PartnerWizard";
import SwipeTab from "./components/SwipeTab";
import FavesTab from "./components/FavesTab";
import ProfileTab from "./components/ProfileTab";

const TABS = [
  { id: "swipe", label: "Discover", icon: "✦" },
  { id: "faves", label: "Saved", icon: "♥" },
  { id: "profile", label: "Profile", icon: "◎" },
];

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [partners, setPartners] = useState([]);
  const [saves, setSaves] = useState([]);
  const [tab, setTab] = useState("swipe");
  const [loading, setLoading] = useState(true);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [showPartnerWizard, setShowPartnerWizard] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setLoading(false);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, session) => {
      setSession(session);
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session?.user) return;
    loadData();
    pingWebhook(session.user);
  }, [session?.user?.id]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("checkout") === "success" && session?.user) {
      const returnRole = params.get("role");
      window.history.replaceState(null, "", window.location.pathname);
      setNeedsOnboarding(false);
      if (returnRole === "partner") setShowPartnerWizard(true);
      loadData();
    }
  }, [session?.user?.id]);

  const loadData = async () => {
    const uid = session.user.id;
    const [{ data: prof }, { data: prtners }, { data: svs }] = await Promise.all([
      supabase.from("profiles").select("*").eq("id", uid).single(),
      supabase.from("partners").select("*").eq("status", "approved").order("created_at", { ascending: false }),
      supabase.from("saves").select("*").eq("user_id", uid),
    ]);
    setProfile(prof);
    setPartners(prtners || []);
    setSaves(svs || []);
    const done = ["instagram", "monthly", "partner_instagram", "partner_monthly", "partner"];
    const isDone = prof?.subscription_type && done.some(t => prof.subscription_type === t || prof.subscription_type.startsWith(t));
    if (!isDone) setNeedsOnboarding(true);
    else setNeedsOnboarding(false);
    if (["partner_monthly", "partner_instagram", "partner"].includes(prof?.subscription_type)) {
      const { data: existing } = await supabase.from("partners").select("id").eq("owner_id", uid).maybeSingle();
      if (!existing) setShowPartnerWizard(true);
    }
  };

  const pingWebhook = async (user) => {
    try {
      const url = import.meta.env.VITE_MAKE_NEW_USER_WEBHOOK;
      if (!url) return;
      await fetch(url, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: user.id, email: user.email || null, phone: user.phone || null, created_at: user.created_at })
      });
    } catch (_) {}
  };

  const handleSave = async (partner) => {
    const uid = session.user.id;
    const { data } = await supabase.from("saves").insert({ user_id: uid, partner_id: partner.id }).select().single();
    if (data) setSaves(s => [...s, data]);
    await Promise.all([
      supabase.from("partners").update({ total_saves: (partner.total_saves || 0) + 1 }).eq("id", partner.id),
      supabase.from("swipe_events").insert({ user_id: uid, partner_id: partner.id, direction: "right" })
    ]);
  };

  const handlePass = async (partner) => {
    const uid = session.user.id;
    await Promise.all([
      supabase.from("swipe_events").insert({ user_id: uid, partner_id: partner.id, direction: "left" }),
      supabase.from("partners").update({ total_swipes: (partner.total_swipes || 0) + 1 }).eq("id", partner.id)
    ]);
  };

  const handleUnsave = async (partnerId) => {
    await supabase.from("saves").delete().eq("user_id", session.user.id).eq("partner_id", partnerId);
    setSaves(s => s.filter(sv => sv.partner_id !== partnerId));
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null); setProfile(null); setSaves([]); setNeedsOnboarding(false);
  };

  if (loading) return (
    <div style={{ minHeight: "100dvh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#fff", gap: 16, fontFamily: "DM Sans, sans-serif" }}>
      <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, fontSize: 32, letterSpacing: "-1px", color: "#111" }}>
        HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe
      </div>
      <div style={{ width: 48, height: 3, borderRadius: 2, background: "#f0f0f0", overflow: "hidden" }}>
        <div style={{ height: "100%", width: "50%", background: "#e85d2b", animation: "slideRight 1.2s ease infinite" }} />
      </div>
    </div>
  );

  if (!session) return <AuthScreen />;
  if (needsOnboarding) return (
    <OnboardingScreen user={session.user} onComplete={(role) => {
      setNeedsOnboarding(false);
      if (role === "partner") setShowPartnerWizard(true);
    }} />
  );
  if (showPartnerWizard) return (
    <PartnerWizard user={session.user}
      onComplete={() => { setShowPartnerWizard(false); setTab("profile"); }}
      onCancel={() => setShowPartnerWizard(false)} />
  );

  return (
    <div style={{ maxWidth: 480, margin: "0 auto", height: "100dvh", display: "flex", flexDirection: "column", background: "#fff", position: "relative", overflow: "hidden", fontFamily: "DM Sans, sans-serif" }}>

      {/* Header */}
      <div style={{ background: "#fff", padding: "14px 20px 12px", display: "flex", justifyContent: "space-between", alignItems: "center", borderBottom: "1px solid #f0f0f0", flexShrink: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{ width: 34, height: 34, borderRadius: 10, background: "linear-gradient(135deg, #e85d2b, #ff7a47)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 16, boxShadow: "0 4px 12px rgba(232,93,43,0.3)" }}>✦</div>
          <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, fontSize: 20, letterSpacing: "-0.5px", color: "#111" }}>
            HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {tab === "swipe" && (
            <div style={{ fontSize: 11, color: "#e85d2b", background: "#fff4f0", padding: "4px 10px", borderRadius: 20, fontWeight: 600, border: "1px solid #ffe0d6" }}>
              📍 Tampa Bay
            </div>
          )}
          <button onClick={handleSignOut} style={{ background: "none", border: "1px solid #eee", borderRadius: 20, padding: "5px 12px", fontSize: 12, color: "#aaa", cursor: "pointer" }}>
            out
          </button>
        </div>
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflow: "hidden", position: "relative" }}>
        {tab === "swipe" && <SwipeTab partners={partners} saves={saves} onSave={handleSave} onPass={handlePass} />}
        {tab === "faves" && <FavesTab saves={saves} partners={partners} onUnsave={handleUnsave} />}
        {tab === "profile" && <ProfileTab user={session.user} profile={profile} onSignOut={handleSignOut} onListBusiness={() => setShowPartnerWizard(true)} />}
      </div>

      {/* Bottom nav */}
      <div style={{ background: "#fff", borderTop: "1px solid #f0f0f0", display: "flex", flexShrink: 0, paddingBottom: "env(safe-area-inset-bottom)" }}>
        {TABS.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            style={{ flex: 1, padding: "12px 0 10px", border: "none", background: "transparent", display: "flex", flexDirection: "column", alignItems: "center", gap: 4, cursor: "pointer", position: "relative" }}>
            {tab === t.id && (
              <div style={{ position: "absolute", top: 0, left: "50%", transform: "translateX(-50%)", width: 28, height: 3, borderRadius: 2, background: "#e85d2b" }} />
            )}
            <span style={{ fontSize: 16, color: tab === t.id ? "#e85d2b" : "#ccc", transition: "color 0.2s", fontWeight: tab === t.id ? 700 : 400 }}>{t.icon}</span>
            <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: 0.8, color: tab === t.id ? "#e85d2b" : "#bbb", textTransform: "uppercase", fontFamily: "Syne, sans-serif" }}>{t.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
