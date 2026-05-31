import { useState, useRef } from "react";

export default function SwipeCard({ partner, onSwipe }) {
  const [dragging, setDragging] = useState(false);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const startRef = useRef(null);
  const cardRef = useRef(null);

  const getRotation = () => Math.min(Math.max(offset.x / 15, -15), 15);
  const getOverlay = () => {
    if (offset.x > 40) return { label: "❤️", color: "rgba(52,199,89,0.85)" };
    if (offset.x < -40) return { label: "✕", color: "rgba(255,59,48,0.85)" };
    return null;
  };

  const handlePointerDown = (e) => {
    setDragging(true);
    startRef.current = { x: e.clientX, y: e.clientY };
    cardRef.current?.setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e) => {
    if (!dragging || !startRef.current) return;
    setOffset({ x: e.clientX - startRef.current.x, y: e.clientY - startRef.current.y });
  };

  const handlePointerUp = () => {
    setDragging(false);
    if (Math.abs(offset.x) > 80) onSwipe(offset.x > 0 ? "right" : "left");
    setOffset({ x: 0, y: 0 });
    startRef.current = null;
  };

  const overlay = getOverlay();

  return (
    <div ref={cardRef}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      style={{
        position: "absolute", width: "100%",
        transform: `translateX(${offset.x}px) translateY(${offset.y * 0.3}px) rotate(${getRotation()}deg)`,
        transition: dragging ? "none" : "transform 0.35s cubic-bezier(0.25,0.46,0.45,0.94)",
        cursor: dragging ? "grabbing" : "grab",
        userSelect: "none", touchAction: "none",
        borderRadius: 20, overflow: "hidden",
        boxShadow: "0 8px 32px rgba(0,0,0,0.12)",
      }}>
      <div style={{
        background: partner.color || "#1e4d1e", padding: "28px 22px 22px",
        minHeight: 160, display: "flex", flexDirection: "column", justifyContent: "flex-end"
      }}>
        <div style={{ fontSize: 52, marginBottom: 8 }}>{partner.photo_emoji || "🏷️"}</div>
        <div style={{ color: "#fff", fontWeight: 800, fontSize: 22, lineHeight: 1.2 }}>{partner.name}</div>
        <div style={{ display: "flex", gap: 8, marginTop: 8, alignItems: "center" }}>
          <span style={{ background: "rgba(255,255,255,0.2)", color: "#fff", padding: "3px 10px", borderRadius: 20, fontSize: 12, fontWeight: 600 }}>{partner.category}</span>
          {partner.neighborhood && <span style={{ color: "rgba(255,255,255,0.8)", fontSize: 12 }}>{partner.neighborhood}</span>}
        </div>
      </div>
      <div style={{ background: "#fff", padding: "16px 20px 20px" }}>
        {(partner.tagline || partner.bio) && (
          <p style={{ margin: "0 0 12px", fontSize: 14, color: "#555", fontStyle: "italic", lineHeight: 1.5 }}>
            "{partner.tagline || partner.bio?.slice(0, 100)}"
          </p>
        )}
        <div style={{ display: "flex", gap: 16, fontSize: 13, color: "#888" }}>
          {partner.contact && <span>📞 {partner.contact}</span>}
          {partner.website && <span style={{ color: "#2a7c3f", fontWeight: 600 }}>🌐 Website</span>}
        </div>
      </div>
      {overlay && (
        <div style={{
          position: "absolute", inset: 0, display: "flex", alignItems: "center",
          justifyContent: "center", background: overlay.color, fontSize: 56, borderRadius: 20,
        }}>
          {overlay.label}
        </div>
      )}
    </div>
  );
}
