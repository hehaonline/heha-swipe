import { useState } from "react";
import { supabase } from "../lib/supabase";

const CATEGORIES = ["Restaurant", "Vendor", "Coach", "Service", "Wellness"];
const CATEGORY_EMOJIS = { Restaurant: "🥗", Vendor: "🛍️", Coach: "🏆", Service: "💆", Wellness: "🧘" };
const CARD_COLORS = ["#1e4d1e","#2a7c3f","#c8531a","#1a5f7a","#7b4f8c","#8B6914","#3a7ca5","#d4552b","#5a3e8f","#8b4513"];
const STEPS = [
  { id: "basics", label: "Basics", icon: "🏪" },
  { id: "details", label: "Details", icon: "📝" },
  { id: "contact", label: "Contact", icon: "📞" },
  { id: "offerings", label: "Offerings", icon: "⭐" },
  { id: "style", label: "Style", icon: "🎨" },
  { id: "review", label: "Review", icon: "✅" },
];

const inputStyle = (hasError) => ({
  width: "100%", padding: "12px 14px", borderRadius: 10, boxSizing: "border-box",
  border: `1.5px solid ${hasError ? "#e85d2b" : "#e0dbd4"}`,
  fontSize: 15, outline: "none", background: "#faf9f7", fontFamily: "system-ui, sans-serif"
});
const labelStyle = { fontSize: 13, fontWeight: 600, color: "#555", marginBottom: 6, display: "block" };

export default function PartnerWizard({ user, onComplete, onCancel }) {
  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState({});
  const [form, setForm] = useState({
    name: "", category: "", neighborhood: "", tagline: "",
    bio: "", hours: "", business_type: "",
    phone: "", contact: "", website: "", instagram: "", location: "",
    offerings: [], items: [],
    photo_emoji: "🏪", color: "#1e4d1e",
  });
  const [newOffering, setNewOffering] = useState("");
  const [newItem, setNewItem] = useState({ name: "", price: "", emoji: "⭐" });

  const set = (field, value) => {
    setForm((f) => ({ ...f, [field]: value }));
    setErrors((e) => ({ ...e, [field]: null }));
  };

  const validate = () => {
    const e = {};
    if (step === 0) {
      if (!form.name.trim()) e.name = "Business name is required";
      if (!form.category) e.category = "Please choose a category";
      if (!form.neighborhood.trim()) e.neighborhood = "Neighborhood is required";
      if (!form.tagline.trim()) e.tagline = "A short tagline is required";
    }
    if (step === 1) { if (!form.bio.trim()) e.bio = "Tell people about your business"; }
    if (step === 2) { if (!form.phone.trim() && !form.contact.trim()) e.phone = "At least one contact method required"; }
    setErrors(e);
    return Object.keys(e).length === 0;
  };

  const next = () => { if (validate()) setStep((s) => s + 1); };
  const back = () => setStep((s) => s - 1);

  const submit = async () => {
    setLoading(true);
    try {
      const completePct = [form.name,form.category,form.neighborhood,form.tagline,form.bio,form.phone||form.contact,form.website,form.instagram,form.offerings.length>0,form.items.length>0].filter(Boolean).length * 10;
      const { data, error } = await supabase.from("partners").insert({
        owner_id: user.id, name: form.name.trim(), category: form.category,
        neighborhood: form.neighborhood.trim(), tagline: form.tagline.trim(),
        bio: form.bio.trim(), hours: form.hours.trim() || null,
        business_type: form.business_type.trim() || null,
        phone: form.phone.trim() || null, contact: form.contact.trim() || null,
        website: form.website.trim() || null, instagram: form.instagram.trim() || null,
        location: form.location.trim() || null, offerings: form.offerings,
        items: form.items, photo_emoji: form.photo_emoji, color: form.color,
        status: "pending", complete_pct: completePct, heha_partner: false,
      }).select().single();
      if (error) throw error;
      try {
        const webhookUrl = import.meta.env.VITE_MAKE_PARTNER_APPROVAL_WEBHOOK;
        if (webhookUrl) {
          await fetch(webhookUrl, {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ partner_id: data.id, partner_name: data.name, category: data.category, neighborhood: data.neighborhood, owner_email: user.email || user.phone, status: "pending_review" }),
          });
        }
      } catch (_) {}
      onComplete(data);
    } catch (e) {
      setErrors({ submit: e.message });
    } finally {
      setLoading(false);
    }
  };

  const Header = () => (
    <div style={{ marginBottom: 24 }}>
      <div style={{ display: "flex", gap: 4, marginBottom: 20 }}>
        {STEPS.map((s, i) => (
          <div key={s.id} style={{ flex: 1, height: 4, borderRadius: 4, background: i <= step ? "#2a7c3f" : "#e8e3dc", transition: "background 0.3s" }} />
        ))}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <span style={{ fontSize: 28 }}>{STEPS[step].icon}</span>
        <div>
          <div style={{ fontSize: 11, color: "#aaa", fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.5 }}>Step {step + 1} of {STEPS.length}</div>
          <div style={{ fontSize: 20, fontWeight: 800, color: "#1a1a1a" }}>{STEPS[step].label}</div>
        </div>
      </div>
    </div>
  );

  if (step === 0) return (
    <Screen onCancel={onCancel}><Header />
      <label style={labelStyle}>Business Name *</label>
      <input style={inputStyle(errors.name)} value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="e.g. Green Bowl Tampa" />
      {errors.name && <Error>{errors.name}</Error>}
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Category *</label>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
        {CATEGORIES.map((cat) => (
          <button key={cat} onClick={() => set("category", cat)}
            style={{ padding: "10px 16px", borderRadius: 12, border: "none", cursor: "pointer", background: form.category === cat ? "#1a1a1a" : "#f0ede8", color: form.category === cat ? "#fff" : "#555", fontSize: 14, fontWeight: 600, display: "flex", alignItems: "center", gap: 6 }}>
            {CATEGORY_EMOJIS[cat]} {cat}
          </button>
        ))}
      </div>
      {errors.category && <Error>{errors.category}</Error>}
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Neighborhood *</label>
      <input style={inputStyle(errors.neighborhood)} value={form.neighborhood} onChange={(e) => set("neighborhood", e.target.value)} placeholder="e.g. South Tampa, Hyde Park, Ybor City" />
      {errors.neighborhood && <Error>{errors.neighborhood}</Error>}
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Tagline * <span style={{ fontWeight: 400, color: "#aaa" }}>(one line, shown on card)</span></label>
      <input style={inputStyle(errors.tagline)} value={form.tagline} onChange={(e) => set("tagline", e.target.value)} placeholder="e.g. Fresh bowls built around local, organic ingredients" maxLength={80} />
      <div style={{ fontSize: 11, color: "#aaa", marginTop: 4 }}>{form.tagline.length}/80</div>
      {errors.tagline && <Error>{errors.tagline}</Error>}
      <NavButtons onBack={onCancel} backLabel="Cancel" onNext={next} />
    </Screen>
  );

  if (step === 1) return (
    <Screen onCancel={onCancel}><Header />
      <label style={labelStyle}>About Your Business *</label>
      <textarea style={{ ...inputStyle(errors.bio), minHeight: 100, resize: "vertical" }} value={form.bio} onChange={(e) => set("bio", e.target.value)} placeholder="Tell customers what makes you special..." />
      {errors.bio && <Error>{errors.bio}</Error>}
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Business Type <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <input style={inputStyle()} value={form.business_type} onChange={(e) => set("business_type", e.target.value)} placeholder="e.g. Brick & mortar, Mobile, Online, Pop-up" />
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Hours <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <input style={inputStyle()} value={form.hours} onChange={(e) => set("hours", e.target.value)} placeholder="e.g. Mon-Fri 8am-6pm, Sat 9am-3pm" />
      <NavButtons onBack={back} onNext={next} />
    </Screen>
  );

  if (step === 2) return (
    <Screen onCancel={onCancel}><Header />
      <label style={labelStyle}>Phone *</label>
      <input style={inputStyle(errors.phone)} value={form.phone} onChange={(e) => set("phone", e.target.value)} placeholder="(813) 555-0101" type="tel" />
      {errors.phone && <Error>{errors.phone}</Error>}
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Email <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <input style={inputStyle()} value={form.contact} onChange={(e) => set("contact", e.target.value)} placeholder="hello@yourbusiness.com" type="email" />
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Website <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <input style={inputStyle()} value={form.website} onChange={(e) => set("website", e.target.value)} placeholder="yourbusiness.com" />
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Instagram <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <div style={{ position: "relative" }}>
        <span style={{ position: "absolute", left: 14, top: "50%", transform: "translateY(-50%)", color: "#aaa", fontSize: 15 }}>@</span>
        <input style={{ ...inputStyle(), paddingLeft: 28 }} value={form.instagram} onChange={(e) => set("instagram", e.target.value)} placeholder="yourbusiness" />
      </div>
      <div style={{ height: 16 }} />
      <label style={labelStyle}>Full Address <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <input style={inputStyle()} value={form.location} onChange={(e) => set("location", e.target.value)} placeholder="123 Main St, Tampa, FL 33601" />
      <NavButtons onBack={back} onNext={next} />
    </Screen>
  );

  if (step === 3) return (
    <Screen onCancel={onCancel}><Header />
      <label style={labelStyle}>What do you offer? <span style={{ fontWeight: 400, color: "#aaa" }}>(add tags)</span></label>
      <div style={{ display: "flex", gap: 8, marginBottom: 10 }}>
        <input style={{ ...inputStyle(), flex: 1 }} value={newOffering} onChange={(e) => setNewOffering(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && newOffering.trim()) { set("offerings", [...form.offerings, newOffering.trim()]); setNewOffering(""); } }}
          placeholder="e.g. Meal prep, Acai bowls, 1-on-1 coaching" />
        <button onClick={() => { if (newOffering.trim()) { set("offerings", [...form.offerings, newOffering.trim()]); setNewOffering(""); } }}
          style={{ padding: "0 16px", borderRadius: 10, border: "none", background: "#1a1a1a", color: "#fff", fontWeight: 700, cursor: "pointer", fontSize: 20 }}>+</button>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 20 }}>
        {form.offerings.map((o, i) => (
          <span key={i} style={{ background: "#e8f5ee", color: "#2a7c3f", padding: "5px 12px", borderRadius: 20, fontSize: 13, fontWeight: 600, display: "flex", alignItems: "center", gap: 6 }}>
            {o}
            <button onClick={() => set("offerings", form.offerings.filter((_, j) => j !== i))} style={{ background: "none", border: "none", cursor: "pointer", color: "#2a7c3f", fontSize: 14, padding: 0 }}>×</button>
          </span>
        ))}
        {form.offerings.length === 0 && <span style={{ fontSize: 13, color: "#bbb" }}>No offerings added yet</span>}
      </div>
      <label style={labelStyle}>Featured Items <span style={{ fontWeight: 400, color: "#aaa" }}>(optional)</span></label>
      <div style={{ display: "flex", gap: 8, marginBottom: 8 }}>
        <input style={{ ...inputStyle(), flex: 2 }} value={newItem.name} onChange={(e) => setNewItem((n) => ({ ...n, name: e.target.value }))} placeholder="Item name" />
        <input style={{ ...inputStyle(), flex: 1 }} value={newItem.price} onChange={(e) => setNewItem((n) => ({ ...n, price: e.target.value }))} placeholder="$0" />
      </div>
      <button onClick={() => { if (newItem.name.trim()) { set("items", [...form.items, { ...newItem, id: Date.now() }]); setNewItem({ name: "", price: "", emoji: "⭐" }); } }}
        style={{ width: "100%", padding: "10px", borderRadius: 10, border: "1.5px dashed #e0dbd4", background: "transparent", color: "#888", fontSize: 14, cursor: "pointer", marginBottom: 12 }}>
        + Add Item
      </button>
      {form.items.map((item, i) => (
        <div key={item.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 12px", background: "#faf9f7", borderRadius: 8, marginBottom: 6 }}>
          <span style={{ fontSize: 14, color: "#1a1a1a" }}>{item.emoji} {item.name}</span>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            {item.price && <span style={{ fontSize: 13, color: "#2a7c3f", fontWeight: 600 }}>{item.price}</span>}
            <button onClick={() => set("items", form.items.filter((_, j) => j !== i))} style={{ background: "none", border: "none", cursor: "pointer", color: "#ccc", fontSize: 18 }}>×</button>
          </div>
        </div>
      ))}
      <NavButtons onBack={back} onNext={next} />
    </Screen>
  );

  if (step === 4) return (
    <Screen onCancel={onCancel}><Header />
      <p style={{ fontSize: 14, color: "#888", margin: "0 0 20px" }}>Choose how your card looks in the swipe deck.</p>
      <div style={{ background: form.color, borderRadius: 16, padding: "20px", marginBottom: 20, minHeight: 100, display: "flex", flexDirection: "column", justifyContent: "flex-end" }}>
        <div style={{ fontSize: 40, marginBottom: 6 }}>{form.photo_emoji}</div>
        <div style={{ color: "#fff", fontWeight: 800, fontSize: 18 }}>{form.name || "Your Business"}</div>
        <div style={{ display: "flex", gap: 8, marginTop: 6 }}>
          <span style={{ background: "rgba(255,255,255,0.2)", color: "#fff", padding: "2px 10px", borderRadius: 20, fontSize: 11, fontWeight: 600 }}>{form.category || "Category"}</span>
          <span style={{ color: "rgba(255,255,255,0.8)", fontSize: 11 }}>{form.neighborhood || "Neighborhood"}</span>
        </div>
      </div>
      <label style={labelStyle}>Card Icon</label>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 10, marginBottom: 20 }}>
        {["🥗","🍜","☕","🥤","🧃","🏋️","🧘","💆","🌿","🏪","🛍️","🏆","💪","🌱","🥦","🍱","🫙","🧴"].map((e) => (
          <button key={e} onClick={() => set("photo_emoji", e)}
            style={{ width: 44, height: 44, borderRadius: 10, border: "none", fontSize: 22, cursor: "pointer", background: form.photo_emoji === e ? "#1a1a1a" : "#f0ede8" }}>{e}</button>
        ))}
      </div>
      <label style={labelStyle}>Card Color</label>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
        {CARD_COLORS.map((c) => (
          <button key={c} onClick={() => set("color", c)}
            style={{ width: 40, height: 40, borderRadius: 10, border: form.color === c ? "3px solid #1a1a1a" : "3px solid transparent", background: c, cursor: "pointer" }} />
        ))}
      </div>
      <NavButtons onBack={back} onNext={next} nextLabel="Review →" />
    </Screen>
  );

  return (
    <Screen onCancel={onCancel}><Header />
      <p style={{ fontSize: 14, color: "#888", margin: "0 0 20px" }}>Everything look good? We'll review your listing within 24 hours.</p>
      <div style={{ borderRadius: 16, overflow: "hidden", boxShadow: "0 4px 20px rgba(0,0,0,0.1)", marginBottom: 20 }}>
        <div style={{ background: form.color, padding: "20px 18px 16px" }}>
          <div style={{ fontSize: 40, marginBottom: 6 }}>{form.photo_emoji}</div>
          <div style={{ color: "#fff", fontWeight: 800, fontSize: 20 }}>{form.name}</div>
          <div style={{ display: "flex", gap: 8, marginTop: 6 }}>
            <span style={{ background: "rgba(255,255,255,0.2)", color: "#fff", padding: "3px 10px", borderRadius: 20, fontSize: 12, fontWeight: 600 }}>{form.category}</span>
            <span style={{ color: "rgba(255,255,255,0.8)", fontSize: 12 }}>{form.neighborhood}</span>
          </div>
        </div>
        <div style={{ background: "#fff", padding: "14px 18px" }}>
          <p style={{ margin: "0 0 8px", fontSize: 14, color: "#555", fontStyle: "italic" }}>"{form.tagline}"</p>
          {form.phone && <div style={{ fontSize: 13, color: "#888" }}>📞 {form.phone}</div>}
          {form.website && <div style={{ fontSize: 13, color: "#2a7c3f", fontWeight: 600 }}>🌐 {form.website}</div>}
        </div>
      </div>
      {[["About", form.bio?.slice(0, 80) + (form.bio?.length > 80 ? "…" : "")],["Hours", form.hours || "Not specified"],["Instagram", form.instagram ? `@${form.instagram}` : "Not specified"],["Offerings", form.offerings.length ? form.offerings.join(", ") : "None added"],["Featured items", form.items.length ? `${form.items.length} items` : "None added"]].map(([k, v]) => (
        <div key={k} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: "1px solid #f0ede8", fontSize: 13 }}>
          <span style={{ color: "#aaa", fontWeight: 600 }}>{k}</span>
          <span style={{ color: "#1a1a1a", textAlign: "right", maxWidth: "60%" }}>{v}</span>
        </div>
      ))}
      <div style={{ background: "#fff8f0", borderRadius: 10, padding: "12px 14px", margin: "16px 0", fontSize: 13, color: "#8b4513", lineHeight: 1.5 }}>
        ⏳ After submitting, your listing goes into <strong>pending review</strong>. We'll approve it within 24 hours!
      </div>
      {errors.submit && <Error>{errors.submit}</Error>}
      <button onClick={submit} disabled={loading}
        style={{ width: "100%", padding: "15px", borderRadius: 14, border: "none", background: loading ? "#ccc" : "#2a7c3f", color: "#fff", fontSize: 16, fontWeight: 700, cursor: loading ? "wait" : "pointer", marginTop: 8 }}>
        {loading ? "Submitting…" : "Submit for Review 🌿"}
      </button>
      <button onClick={back} style={{ background: "none", border: "none", width: "100%", marginTop: 12, fontSize: 13, color: "#aaa", cursor: "pointer" }}>← Back to edit</button>
    </Screen>
  );
}

function Screen({ children, onCancel }) {
  return (
    <div style={{ minHeight: "100vh", background: "#f5f0eb", fontFamily: "system-ui, sans-serif", paddingBottom: 40 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "16px 20px 0" }}>
        <div style={{ fontSize: 18, fontWeight: 800, color: "#1a1a1a" }}>HEHA<span style={{ color: "#e85d2b" }}>·</span>swipe</div>
        <button onClick={onCancel} style={{ background: "none", border: "none", fontSize: 13, color: "#aaa", cursor: "pointer" }}>Save & exit</button>
      </div>
      <div style={{ padding: "20px 20px 0" }}>{children}</div>
    </div>
  );
}

function NavButtons({ onBack, backLabel = "← Back", onNext, nextLabel = "Next →" }) {
  return (
    <div style={{ display: "flex", gap: 12, marginTop: 28 }}>
      <button onClick={onBack} style={{ flex: 1, padding: "13px", borderRadius: 12, border: "1.5px solid #e0dbd4", background: "#fff", color: "#666", fontSize: 15, fontWeight: 600, cursor: "pointer" }}>{backLabel}</button>
      <button onClick={onNext} style={{ flex: 2, padding: "13px", borderRadius: 12, border: "none", background: "#1a1a1a", color: "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer" }}>{nextLabel}</button>
    </div>
  );
}

function Error({ children }) {
  return <div style={{ fontSize: 12, color: "#e85d2b", marginTop: 4 }}>{children}</div>;
}
