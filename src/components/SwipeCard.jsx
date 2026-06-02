import { useMemo, useState } from "react";
import ShareSheet from "./ShareSheet";

const dragThreshold = 72;

function getPartnerTags(partner) {
  const tags = [
    ...(partner.offerings || []),
    ...(partner.tags || []),
  ].filter(Boolean);
  return [...new Set(tags)].slice(0, 3);
}

function fallbackImage(partner) {
  if (partner.image_url) return partner.image_url;
  if (partner.category === "Events") return "/partner-images/events.svg";
  if (partner.category === "Wellness" || partner.category === "Service" || partner.category === "Coach") return "/partner-images/wellness.svg";
  if (partner.category === "Vendor") return "/partner-images/market.svg";
  return "/partner-images/clean-food.svg";
}

function statusBadge(partner) {
  if (partner.heha_partner) return "HEHA Certified";
  return "Listed on HEHA Swipe";
}

export default function SwipeCard({ partner, onSwipe }) {
  const [dragStart, setDragStart] = useState(null);
  const [drag, setDrag] = useState({ x: 0, y: 0 });
  const [showShare, setShowShare] = useState(false);

  const tags = useMemo(() => getPartnerTags(partner), [partner]);
  const featuredItems = Array.isArray(partner.items) ? partner.items.slice(0, 2) : [];
  const imageUrl = fallbackImage(partner);
  const isSuperIntent = drag.y < -62 && Math.abs(drag.x) < 95;
  const isSaveIntent = drag.x > 62;
  const isPassIntent = drag.x < -62;

  const startDrag = (clientX, clientY) => setDragStart({ x: clientX, y: clientY });
  const moveDrag = (clientX, clientY) => {
    if (!dragStart) return;
    setDrag({ x: clientX - dragStart.x, y: clientY - dragStart.y });
  };

  const endDrag = () => {
    if (!dragStart) return;
    if (drag.y < -dragThreshold && Math.abs(drag.x) < dragThreshold * 1.2) onSwipe?.("super");
    else if (drag.x > dragThreshold) onSwipe?.("right");
    else if (drag.x < -dragThreshold) onSwipe?.("left");
    setDragStart(null);
    setDrag({ x: 0, y: 0 });
  };

  return (
    <article
      className="swipe-card compact"
      style={{
        transform: `translate(${drag.x}px, ${drag.y}px) rotate(${drag.x / 22}deg)`,
        background: partner.color || "var(--heha-green)",
      }}
      onMouseDown={(event) => startDrag(event.clientX, event.clientY)}
      onMouseMove={(event) => moveDrag(event.clientX, event.clientY)}
      onMouseUp={endDrag}
      onMouseLeave={endDrag}
      onTouchStart={(event) => startDrag(event.touches[0].clientX, event.touches[0].clientY)}
      onTouchMove={(event) => moveDrag(event.touches[0].clientX, event.touches[0].clientY)}
      onTouchEnd={endDrag}
    >
      <div className={`swipe-intent save ${isSaveIntent ? "visible" : ""}`}>SAVE</div>
      <div className={`swipe-intent pass ${isPassIntent ? "visible" : ""}`}>PASS</div>
      <div className={`swipe-intent super ${isSuperIntent ? "visible" : ""}`}>SUPER</div>

      <div className="card-image-wrap">
        <img src={imageUrl} alt={`${partner.name} preview`} loading="lazy" />
        <div className="partner-avatar floating-avatar">{partner.photo_emoji || "🌿"}</div>
        <div className="partner-badges image-badges">
          <span className={partner.heha_partner ? "verified-badge" : "listed-badge"}>{statusBadge(partner)}</span>
          <span>{partner.category || "Local"}</span>
        </div>
      </div>

      <div className="card-main compact-main">
        <p className="location-line">📍 {partner.neighborhood || partner.location || "Tampa Bay"}</p>
        <h2>{partner.name}</h2>
        {partner.tagline && <p className="tagline">{partner.tagline}</p>}
        {!partner.tagline && partner.bio && <p className="tagline">{partner.bio}</p>}
      </div>

      {tags.length > 0 && (
        <div className="tag-row compact-tags">
          {tags.map((tag) => <span key={tag}>{tag}</span>)}
        </div>
      )}

      {featuredItems.length > 0 && (
        <div className="featured-strip compact-items">
          {featuredItems.map((item, index) => (
            <div key={`${item.name}-${index}`}>
              <span>{item.emoji || "✦"}</span>
              <strong>{item.name}</strong>
              {item.price && <small>{item.price}</small>}
            </div>
          ))}
        </div>
      )}

      <div className="card-footer compact-footer">
        <div className="social-proof">
          {partner.rating ? <strong>★ {Number(partner.rating).toFixed(1)}</strong> : <strong>{partner.heha_partner ? "Certified" : "Directory"}</strong>}
          <span>{partner.review_count ? `${partner.review_count} reviews` : "by HEHA"}</span>
        </div>
        <button type="button" onClick={(event) => { event.stopPropagation(); setShowShare(true); }}>Share ↗</button>
      </div>

      <div className="gesture-helper">Pass left · Save right · SuperSwoop up</div>

      {showShare && <ShareSheet partner={partner} onClose={() => setShowShare(false)} />}
    </article>
  );
}