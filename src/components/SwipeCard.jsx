import { useState, useRef } from "react";

export default function SwipeCard({ partner, onSwipe }) {
  const [dragging, setDragging] = useState(false);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const startRef = useRef(null);
  const cardRef = useRef(null);

  const rot = () => Math.min(Math.max(offset.x / 12, -18), 18);
  const getOverlay = () => {
    if (offset.x > 50) return { label: "♥", text: "LIKE", color: "rgba(232,93,43,0.88)" };
    if (offset.x < -50) return { label: "✕", text: "PASS", color: "rgba(17,17,17,0.88)" };
    return null;
  };

  const onPD = (e) => { setDragging(true); startRef.current = { x: e.clientX, y: e.clientY }; cardRef.current?.setPointerCapture(e.pointerId); };
  const onPM = (e) => { if (!dragging || !startRef.current) return; setOffset({ x: e.clientX - startRef.current.x, y: e.clientY - startRef.current.y }); };
  const onPU = () => { setDragging(false); if (Math.abs(offset.x) > 80) onSwipe(offset.x > 0 ? "right" : "left"); setOffset({ x: 0, y: 0 }); startRef.current = null; };

  const ov = getOverlay();

  return (
    <div ref={cardRef} onPointerDown={onPD} onPointerMove={onPM} onPointerUp={onPU}
      style={{
        position: "absolute", width: "100%",
        transform: `translateX(${offset.x}px) translateY(${offset.y * 0.25}px) rotate(${rot()}deg)`,
        transition: dragging ? "none" : "transform 0.4s cubic-bezier(0.25,0.46,0.45,0.94)",
        cursor: dragging ? "grabbing" : "grab",
        userSelect: "none", touchAction: "none",
        borderRadius: 24, overflow: "hidden",
        boxShadow: "0 12px 40px rgba(0,0,0,0.15)", zIndex: 1,
      }}>

      {/* Header */}
      <div style={{ background: partner.color || "#1e4d1e", padding: "28px 22px 22px", minHeight: 190, display: "flex", flexDirection: "column", justifyContent: "flex-end", position: "relative", overflow: "hidden" }}>
        <div style={{ position: "absolute", top: -30, right: -30, width: 120, height: 120, borderRadius: "50%", background: "rgba(255,255,255,0.07)" }} />
        <div style={{ position: "absolute", top: 20, right: 20, width: 60, height: 60, borderRadius: "50%", background: "rgba(255,255,255,0.05)" }} />
        <div style={{ fontSize: 58, marginBottom: 10, lineHeight: 1, position: "relative" }}>{partner.photo_emoji || "🏷️"}</div>
        <div style={{ fontFamily: "Syne, sans-serif", color: "#fff", fontWeight: 800, fontSize: 24, lineHeight: 1.2, marginBottom: 10, position: "relative" }}>{partner.name}</div>
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", position: "relative" }}>
          <span style={{ background: "rgba(255,255,255,0.18)", color: "#fff", padding: "4px 12px", borderRadius: 20, fontSize: 11, fontWeight: 700, letterSpacing: 0.8, textTransform: "uppercase", backdropFilter: "blur(8px)" }}>
            {partner.category}
          </span>
          {partner.neighborhood && <span style={{ color: "rgba(255,255,255,0.7)", fontSize: 12 }}>📍 {partner.neighborhood}</span>}
        </div>
      </div>

      {/* Body */}
      <div style={{ background: "#fff", padding: "16px 20px 20px" }}>
        {(partner.tagline || partner.bio) && (
          <p style={{ margin: "0 0 14px", fontSize: 14, color: "#555", lineHeight: 1.65, fontStyle: "italic" }}>
            "{partner.tagline || partner.bio?.slice(0, 100)}"
          </p>
        )}
        <div style={{ display: "flex", gap: 14, fontSize: 12, color: "#aaa", flexWrap: "wrap" }}>
          {partner.phone && <span style={{ display: "flex", alignItems: "center", gap: 4 }}><span style={{ color: "#e85d2b" }}>📞</span>{partner.phone}</span>}
          {partner.website && <span style={{ color: "#e85d2b", fontWeight: 600 }}>🌐 Website</span>}
          {partner.instagram && <span style={{ color: "#e85d2b", fontWeight: 600 }}>📸 @{partner.instagram}</span>}
        </div>
        {partner.heha_partner && (
          <div style={{ marginTop: 12, display: "inline-flex", alignItems: "center", gap: 6, background: "#fff4f0", border: "1px solid #ffe0d6", borderRadius: 20, padding: "4px 12px" }}>
            <span style={{ color: "#e85d2b", fontSize: 11 }}>✦</span>
            <span style={{ fontSize: 11, fontWeight: 700, color: "#e85d2b", letterSpacing: 0.5, fontFamily: "Syne, sans-serif" }}>HEHA VERIFIED</span>
          </div>
        )}
      </div>

      {/* Overlay */}
      {ov && (
        <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: ov.color, borderRadius: 24, gap: 8 }}>
          <div style={{ fontSize: 64 }}>{ov.label}</div>
          <div style={{ fontFamily: "Syne, sans-serif", fontWeight: 800, fontSize: 30, color: "#fff", letterSpacing: 3 }}>{ov.text}</div>
        </div>
      )}
    </div>
  );
}
