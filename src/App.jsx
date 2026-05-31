import { useState, useEffect } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import OnboardingScreen from "./components/OnboardingScreen";
import PartnerWizard from "./components/PartnerWizard";
import SwipeTab from "./components/SwipeTab";
import FavesTab from "./components/FavesTab";
import ProfileTab from "./components/ProfileTab";

const TABS = [
  { id: "swipe", label: "Discover", icon: "🃏" },
  { id: "faves", label: "Saved", icon: "❤️" },
  { id: "profile", label: "Profile", icon: "👤" },
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
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session?.user) return;
    loadData();
    pingNewUserWebhook(session.user);
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
    const doneTypes = ["instagram","monthly","partner_instagram","partner_monthly","partner","pending_partner","pending_customer"];
    const isDone = prof?.subscription_type && doneTypes.some(t => prof.subscription_type.startsWith(t) || prof.subscription_type === t);
    if (!isDone) setNeedsOnboarding(true);
    if (prof?.subscription_type === "partner_monthly" || prof?.subscription_type === "partner_instagram" || prof?.subscription_type === "partner") {
      const { data: existing } = await supabase.from("partners").select("id").eq("owner_id", uid).maybeSingle();
      if (!existing) setShowPartnerWizard(true);
    }
  };

  const pingNewUserWebhook = async (user) => {
    try {
      const webhookUrl = import.meta.env.VITE_MAKE_NEW_USER_WEBHOOK;
      if (!webhookUrl) return;
      await fetch(webhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: user.id, email: user.email || null, phone: user.phone || null, created_at: user.created_at }),
      });
    } catch (_) {}
  };

  const handleSave = async (partner) => {
    const uid = session.user.id;
    const { data } = await supabase.from("saves").insert({ user_id: uid, partner_id: partner.id }).select().single();
    if (data) setSaves((s) => [...s, data]);
    await supabase.from("partners").update({ total_saves: (partner.total_saves || 0) + 1 }).eq("id", partner.id);
    await supabase.from("swipe_events").insert({ user_id: uid, partner_id: partner.id, direction: "right" });
  };

  const handlePass = async (partner) => {
    const uid = session.user.id;
    await supabase.from("swipe_events").insert({ user_id: uid, partner_id: partner.id, direction: "left" });
    await supabase.from("partners").update({ total_swipes: (partner.total_swipes || 0) + 1 }).eq("id", partner.id);
  };

  const handleUnsave = async (partnerId) => {
    const uid = session.user.id;
    await supabase.from("saves").delete().eq("user_id", uid).eq("partner_id", partnerId);
    setSaves((s) => s.filter((sv) => sv.partner_id !== partnerId));
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSession(null); setProfile(null); setSaves([]);
  };

  if (loading) return (
    <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: "#f5f0eb", fontSize: 28 }}>⏳</div>
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
    <div style={{ maxWidth: 430, margin: "0 auto", height: "100dvh", display: "flex", flexDirection: "column", background: "#f5f0eb", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "14px 18px 10px", flexShrink: 0 }}>
        <div style={{ fontSize: 20, fontWeight: 800, letterSpacing: "-0.5px", color: "#1a1a1a" }}>HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe</div>
        <button onClick={handleSignOut} style={{ padding: "5px 14px", borderRadius: 20, border: "1.5px solid #ddd", background: "transparent", fontSize: 12, color: "#666", cursor: "pointer" }}>sign out</button>
      </div>
      <div style={{ flex: 1, overflow: "hidden", position: "relative" }}>
        {tab === "swipe" && <SwipeTab partners={partners} saves={saves} onSave={handleSave} onPass={handlePass} />}
        {tab === "faves" && <FavesTab saves={saves} partners={partners} onUnsave={handleUnsave} />}
        {tab === "profile" && <ProfileTab user={session.user} profile={profile} onSignOut={handleSignOut} onListBusiness={() => setShowPartnerWizard(true)} />}
      </div>
      <div style={{ display: "flex", borderTop: "1px solid #e8e3dc", background: "#fff", flexShrink: 0, paddingBottom: "env(safe-area-inset-bottom)" }}>
        {TABS.map((t) => (
          <button key={t.id} onClick={() => setTab(t.id)}
            style={{ flex: 1, padding: "10px 0", border: "none", background: "transparent", display: "flex", flexDirection: "column", alignItems: "center", gap: 3, cursor: "pointer" }}>
            <span style={{ fontSize: 20 }}>{t.icon}</span>
            <span style={{ fontSize: 10, fontWeight: 600, letterSpacing: 0.3, color: tab === t.id ? "#2a7c3f" : "#aaa", textTransform: "uppercase" }}>{t.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
