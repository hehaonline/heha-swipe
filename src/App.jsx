import { useEffect, useMemo, useState } from "react";
import { supabase } from "./lib/supabase";
import AuthScreen from "./components/AuthScreen";
import OnboardingScreen from "./components/OnboardingScreen";
import PartnerWizard from "./components/PartnerWizard";
import SwipeTab from "./components/SwipeTab";
import FavesTab from "./components/FavesTab";
import ProfileTab from "./components/ProfileTab";
import PasswordResetScreen from "./components/PasswordResetScreen";
import LocationModal, { getActiveLocationLabel } from "./components/LocationModal";
import CommunityPassTab from "./components/CommunityPassTab";
import { fetchActiveSupporterSubscription } from "./lib/supporterStatus";

const TABS = [
{ id: "swipe", label: "Discover", icon: "\u2315" },
{ id: "faves", label: "Saved", icon: "\u2661" },
{ id: "deals", label: "Community", icon: "\u2311" },
{ id: "profile", label: "Profile", icon: "\u2659" },
];

const COMPLETED_SUBSCRIPTION_TYPES = [
"instagram",
"monthly",
"customer_free",
"customer_supporter",
"supporter_membership",
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

function isActiveSupporter(profile) {
if (!profile) return false;
const status = (profile.subscription_status || "").toLowerCase();
// A paid/active supporter is always allowed into the app (no onboarding gate).
return profile.subscription_active === true && (status === "active" || status === "trialing");
}

function isOnboarded(profile) {
if (isActiveSupporter(profile)) return true;
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
const [passwordRecovery, setPasswordRecovery] = useState(false);
const [notice, setNotice] = useState(null);
const [appError, setAppError] = useState(null);
const [showLocationModal, setShowLocationModal] = useState(false);
const [locationLabel, setLocationLabel] = useState(null);
// True when the app first loaded on the post-payment success route — used to avoid
// bouncing a just-paid supporter back into onboarding while the webhook settles.
const [supportReturn] = useState(() => window.location.pathname === "/support/success");

useEffect(() => {
const timer = window.setTimeout(() => setSplashReady(true), 3400);
return () => window.clearTimeout(timer);
}, []);

// Sync locationLabel from profile or localStorage on load/profile change
useEffect(() => {
setLocationLabel(getActiveLocationLabel(profile?.location || null));
}, [profile]);

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
// Refresh location label for guest state
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

const savedPartnerIds = useMemo(
() => new Set(saves.map((save) => save.partner_id)),
[saves]
);

// Does the authenticated user have an active/trialing supporter subscription?
const hasActiveSupporterSub = async (uid) => !!(await fetchActiveSupporterSubscription(uid));

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
// Allow app entry if the profile says active supporter OR an active/trialing
// supporter_subscriptions row exists (covers webhook/profile-flip lag).
const supporterBySub = isActiveSupporter(nextProfile) ? true : await hasActiveSupporterSub(uid);
setNeedsOnboarding(!(isOnboarded(nextProfile) || supporterBySub));

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

const supportCheckoutStatus = window.location.pathname === "/support/success"
? "success"
: window.location.pathname === "/support/cancel"
? "cancel"
: null;

// Refetch the profile on demand (used by the success page to wait for the
// Stripe webhook to mark the user as an active supporter). Returns true once
// active-supporter state is visible.
const refreshProfileNow = async () => {
const uid = session?.user?.id;
if (!uid) return false;
const { data } = await supabase.from("profiles").select("*").eq("id", uid).maybeSingle();
if (data) setProfile(data);
const profileSupporter = isActiveSupporter(data);
const supporterActive = profileSupporter ? true : await hasActiveSupporterSub(uid);
setNeedsOnboarding(!(((data && isOnboarded(data)) || supporterActive)));
return profileSupporter || supporterActive;
};

const handleSupportStatusContinue = async () => {
await refreshProfileNow();
window.history.replaceState(null, "", "/");
setTab("deals"); // land on the Community / supporter dashboard
};

if (loading || !splashReady) return <SplashScreen />;
if (supportCheckoutStatus) {
return <SupportCheckoutStatus status={supportCheckoutStatus} onContinue={handleSupportStatusContinue} onPoll={refreshProfileNow} />;
}
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

if (needsOnboarding && !supportReturn) {
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
<button
className="location-pill ghost-pill"
onClick={() => setShowLocationModal(true)}
aria-label="Set your location"
title="Set your location"
>
<span className="location-pill-icon">📍</span>
<span className="location-pill-label">{locationLabel || "Tampa Bay"}</span>
</button>
<button className="ghost-pill" onClick={() => setShowPartnerWizard(true)}>Get listed</button>
</header>

{notice && <div className="toast-notice">{notice}</div>}
{appError && <div className="error-banner">{appError}</div>}

{showLocationModal && (
<LocationModal
user={session?.user || null}
profileLocation={profile?.location || null}
onClose={() => setShowLocationModal(false)}
onLocationSaved={handleLocationSaved}
/>
)}

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
{tab === "deals" && <CommunityPassTab user={session.user} profile={profile} />}
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
// checking -> waiting for the Stripe webhook to mark supporter active
// ready    -> active supporter confirmed
// slow     -> webhook taking longer than expected (still let the user continue)
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
// run once on mount for the success screen
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

