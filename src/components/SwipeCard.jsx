import { useMemo, useState } from "react";
import ShareSheet from "./ShareSheet";

const dragThreshold = 82;

function getPartnerTags(partner) {
  const tags = [
    ...(partner.offerings || []),
    ...(partner.tags || []),
  ].filter(Boolean);
  return [...new Set(tags)].slice(0, 4);
}

export default function SwipeCard({ partner, onSwipe }) {
  const [dragStart, setDragStart] = useState(null);
  const [drag, setDrag] = useState({ x: 0, y: 0 });
  const [showShare, setShowShare] = useState(false);

  const tags = useMemo(() => getPartnerTags(partner), [partner]);
  const featuredItems = Array.isArray(partner.items) ? partner.items.slice(0, 3) : [];
  const isSuperIntent = drag.y < -70 && Math.abs(drag.x) < 100;
  const isSaveIntent = drag.x > 70;
  const isPassIntent = drag.x < -70;

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
      className="swipe-card"
      style={{
        transform: `translate(${drag.x}px, ${drag.y}px) rotate(${drag.x / 20}deg)`,
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
      <div className={`swipe-intent super ${isSuperIntent ? "visible" : ""}`}>SUPERSWOOP</div>

      <div className="card-top-row">
        <div className="partner-avatar">{partner.photo_emoji || "🌿"}</div>
        <div className="partner-badges">
          {partner.heha_partner && <span className="verified-badge">HEHA Verified</span>}
          <span>{partner.category || "Local"}</span>
        </div>
      </div>

      <div className="card-main">
        <p className="location-line">📍 {partner.neighborhood || partner.location || "Tampa Bay"}</p>
        <h2>{partner.name}</h2>
        {partner.tagline && <p className="tagline">{partner.tagline}</p>}
        {!partner.tagline && partner.bio && <p className="tagline">{partner.bio}</p>}
      </div>

      {tags.length > 0 && (
        <div className="tag-row">
          {tags.map((tag) => <span key={tag}>{tag}</span>)}
        </div>
      )}

      {featuredItems.length > 0 && (
        <div className="featured-strip">
          {featuredItems.map((item, index) => (
            <div key={`${item.name}-${index}`}>
              <span>{item.emoji || "✦"}</span>
              <strong>{item.name}</strong>
              {item.price && <small>{item.price}</small>}
            </div>
          ))}
        </div>
      )}

      <div className="card-footer">
        <div className="social-proof">
          {partner.rating ? <strong>★ {Number(partner.rating).toFixed(1)}</strong> : <strong>Curated</strong>}
          <span>{partner.review_count ? `${partner.review_count} reviews` : "by HEHA"}</span>
        </div>
        <button type="button" onClick={(event) => { event.stopPropagation(); setShowShare(true); }}>Share ↗</button>
      </div>

      <div className="gesture-helper">Swipe right to save · up for SuperSwoop</div>

      {showShare && <ShareSheet partner={partner} onClose={() => setShowShare(false)} />}
    </article>
  );
}
