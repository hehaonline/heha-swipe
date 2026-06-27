import { useMemo, useState } from "react";
import ShareSheet from "./ShareSheet";
import { filterPublicTags } from "../lib/partnerTags";

const dragThreshold = 72;

const CATEGORY_GROUPS = {
  Restaurant: { label: "Food", className: "food", emoji: "🥗" },
  Vendor: { label: "Market", className: "market", emoji: "🛍️" },
  Wellness: { label: "Wellness", className: "wellness", emoji: "🧘" },
  Coach: { label: "Coach", className: "coach", emoji: "🏆" },
  Service: { label: "Service", className: "service", emoji: "💆" },
  Events: { label: "Events", className: "events", emoji: "🎉" },
};

const STOCK_GALLERIES = {
  Restaurant: ["/partner-images/clean-food.svg", "/partner-images/market.svg", "/partner-images/events.svg"],
  Vendor: ["/partner-images/market.svg", "/partner-images/clean-food.svg", "/partner-images/wellness.svg"],
  Wellness: ["/partner-images/wellness.svg", "/partner-images/clean-food.svg", "/partner-images/events.svg"],
  Coach: ["/partner-images/wellness.svg", "/partner-images/events.svg", "/partner-images/clean-food.svg"],
  Service: ["/partner-images/wellness.svg", "/partner-images/clean-food.svg", "/partner-images/market.svg"],
  Events: ["/partner-images/events.svg", "/partner-images/clean-food.svg", "/partner-images/market.svg"],
};

function getCategoryGroup(partner) {
  const terms = [partner.category, ...(partner.offerings || []), ...(partner.tags || [])]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  if (terms.includes("private chef") || terms.includes("chef")) {
    return { label: "Private Chef", className: "food", emoji: "👨‍🍳" };
  }

  return CATEGORY_GROUPS[partner.category] || { label: partner.category || "Local", className: "local", emoji: "✦" };
}

function getPartnerTags(partner) {
  const tags = filterPublicTags([
    ...(partner.offerings || []),
    ...(partner.tags || []),
  ]);
  return [...new Set(tags)].slice(0, 2);
}

function stockGallery(partner) {
  return STOCK_GALLERIES[partner.category] || ["/partner-images/clean-food.svg", "/partner-images/market.svg", "/partner-images/wellness.svg"];
}

function fallbackImage(partner) {
  if (partner.image_url) return partner.image_url;
  return stockGallery(partner)[0];
}

function galleryImages(partner) {
  const gallery = Array.isArray(partner.gallery_urls) ? partner.gallery_urls.filter(Boolean) : [];
  if (gallery.length) return gallery.slice(0, 3);
  if (partner.image_url) return [partner.image_url];
  return stockGallery(partner).slice(0, 3);
}

function isStockPlaceholder(partner, image) {
  const realImages = [
    partner.image_url,
    ...(Array.isArray(partner.gallery_urls) ? partner.gallery_urls : []),
  ].filter(Boolean);
  return !realImages.includes(image);
}

function instagramUrl(handle) {
  if (!handle) return null;
  if (handle.startsWith("http")) return handle;
  return `https://instagram.com/${handle.replace("@", "")}`;
}

function hasRealWebsite(url) {
  if (!url) return false;
  const clean = String(url).trim().toLowerCase();
  return clean.startsWith("http") && !clean.includes("example.com") && clean !== "https://heha.online";
}

function statusBadge(partner) {
  if (partner.heha_partner) return "HEHA Reviewed";
  return "Listed on HEHA Swipe";
}

function displayName(name = "") {
  return name.length > 38 ? `${name.slice(0, 35)}…` : name;
}

function itemUrl(item) {
  return item?.url || item?.product_url || item?.link || null;
}

export default function SwipeCard({ partner, onSwipe }) {
  const [dragStart, setDragStart] = useState(null);
  const [drag, setDrag] = useState({ x: 0, y: 0 });
  const [showShare, setShowShare] = useState(false);
  const [showPreview, setShowPreview] = useState(false);
  const [touchMoved, setTouchMoved] = useState(false);

  const tags = useMemo(() => getPartnerTags(partner), [partner]);
  const items = Array.isArray(partner.items) ? partner.items.filter(Boolean) : [];
  const featuredItem = items[0];
  const imageUrl = fallbackImage(partner);
  const categoryGroup = getCategoryGroup(partner);
  const images = galleryImages(partner);
  const showingStockImage = isStockPlaceholder(partner, imageUrl);
  const isSuperIntent = drag.y < -62 && Math.abs(drag.x) < 95;
  const isSaveIntent = drag.x > 62;
  const isPassIntent = drag.x < -62;

  const startDrag = (clientX, clientY) => {
    setDragStart({ x: clientX, y: clientY });
    setTouchMoved(false);
  };

  const moveDrag = (clientX, clientY) => {
    if (!dragStart) return;
    const nextDrag = { x: clientX - dragStart.x, y: clientY - dragStart.y };
    if (Math.abs(nextDrag.x) > 12 || Math.abs(nextDrag.y) > 12) setTouchMoved(true);
    setDrag(nextDrag);
  };

  const endDrag = () => {
    if (!dragStart) return;

    const wasSwipe = Math.abs(drag.x) > dragThreshold || drag.y < -dragThreshold;
    if (drag.y < -dragThreshold && Math.abs(drag.x) < dragThreshold * 1.2) onSwipe?.("super");
    else if (drag.x > dragThreshold) onSwipe?.("right");
    else if (drag.x < -dragThreshold) onSwipe?.("left");

    setDragStart(null);
    setDrag({ x: 0, y: 0 });
    if (wasSwipe) {
      setTouchMoved(true);
      window.setTimeout(() => setTouchMoved(false), 180);
    } else {
      window.setTimeout(() => setTouchMoved(false), 0);
    }
  };

  const openPreview = () => {
    if (touchMoved || Math.abs(drag.x) > 12 || Math.abs(drag.y) > 12) return;
    setShowPreview(true);
  };

  const stopButtonGesture = (event) => {
    event.stopPropagation();
    setDragStart(null);
    setDrag({ x: 0, y: 0 });
    setTouchMoved(false);
  };

  const openPreviewFromButton = (event) => {
    stopButtonGesture(event);
    setShowPreview(true);
  };

  return (
    <>
      <article
        className={`swipe-card compact polished-card category-${categoryGroup.className}`}
        style={{ transform: `translate(${drag.x}px, ${drag.y}px) rotate(${drag.x / 22}deg)` }}
        onClick={openPreview}
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

        <div className="card-category-strip">
          <div className="strip-image-card">
            <img src={imageUrl} alt={`${partner.name} preview`} loading="lazy" />
            <div className="partner-avatar floating-avatar">{partner.photo_emoji || categoryGroup.emoji}</div>
          </div>
          <div className="partner-badges image-badges">
            <span className={partner.heha_partner ? "verified-badge" : "listed-badge"}>{statusBadge(partner)}</span>
            <span>{categoryGroup.label}</span>
            {showingStockImage && <span className="stock-photo-pill">Photo coming soon</span>}
          </div>
        </div>

        <div className="card-main compact-main clean-main">
          <p className="location-line">📍 {partner.neighborhood || partner.location || "Tampa Bay"}</p>
          <h2>{displayName(partner.name)}</h2>
          {partner.tagline && <p className="tagline">{partner.tagline}</p>}
          {!partner.tagline && partner.bio && <p className="tagline">{partner.bio}</p>}
        </div>

        <div className="card-bottom-zone">
          {tags.length > 0 && (
            <div className="tag-row compact-tags clean-tags">
              {tags.map((tag) => <span key={tag}>{tag}</span>)}
            </div>
          )}

          {featuredItem && (
            <div className="featured-mini-row clean-featured" aria-label="Featured HEHA item preview">
              <span className="featured-mini-pill">
                <span>{featuredItem.emoji || "✦"}</span>
                <strong>Featured: {featuredItem.name}</strong>
              </span>
            </div>
          )}

          <div className="card-footer compact-footer clean-footer">
            <div className="social-proof">
              <strong>{partner.heha_partner ? "Reviewed" : "Listed"}</strong>
              <span>by HEHA</span>
            </div>
            <button
              type="button"
              className="preview-card-button"
              onPointerDown={stopButtonGesture}
              onMouseDown={stopButtonGesture}
              onTouchStart={stopButtonGesture}
              onClick={openPreviewFromButton}
            >
              Preview
            </button>
          </div>
        </div>

        <div className="gesture-helper">Tap for details · Save right · Pass left</div>
      </article>

      {showPreview && (
        <PartnerPreviewSheet
          partner={partner}
          categoryGroup={categoryGroup}
          images={images}
          tags={tags}
          items={items}
          onClose={() => setShowPreview(false)}
          onSave={() => {
            setShowPreview(false);
            onSwipe?.("right");
          }}
          onPass={() => {
            setShowPreview(false);
            onSwipe?.("left");
          }}
          onShare={() => {
            setShowPreview(false);
            setShowShare(true);
          }}
        />
      )}

      {showShare && <ShareSheet partner={partner} onClose={() => setShowShare(false)} />}
    </>
  );
}

function PartnerPreviewSheet({ partner, categoryGroup, images, tags, items, onClose, onSave, onPass, onShare }) {
  const [imageIndex, setImageIndex] = useState(0);
  const currentImage = images[imageIndex] || fallbackImage(partner);
  const ig = instagramUrl(partner.instagram);
  const website = hasRealWebsite(partner.website) ? partner.website : null;
  const firstOrderUrl = items.map(itemUrl).find(Boolean);
  const showingStockImage = isStockPlaceholder(partner, currentImage);

  return (
    <div className="preview-backdrop" role="dialog" aria-modal="true" aria-label={`${partner.name} preview`} onClick={onClose}>
      <section className="partner-preview-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close preview">×</button>
        <div className={`preview-hero category-${categoryGroup.className}`}>
          <img src={currentImage} alt={`${partner.name} preview`} />
          <span className="preview-category-pill">{categoryGroup.emoji} {categoryGroup.label}</span>
          <span className="preview-status-pill">{statusBadge(partner)}</span>
          {showingStockImage && <span className="preview-stock-pill">Photo coming soon</span>}
          {images.length > 1 && (
            <div className="gallery-dots preview-dots">
              {images.map((image, index) => (
                <button
                  key={`${image}-${index}`}
                  className={imageIndex === index ? "active" : ""}
                  onClick={() => setImageIndex(index)}
                  aria-label={`Show photo ${index + 1}`}
                />
              ))}
            </div>
          )}
        </div>

        <div className="preview-body">
          <p className="eyebrow">{partner.neighborhood || partner.location || "Tampa Bay"}</p>
          <h2>{partner.name}</h2>
          {partner.price_range && <span className="price-range-pill">{partner.price_range}</span>}
          {partner.tagline && <p className="preview-tagline">{partner.tagline}</p>}
          {partner.bio && <p className="preview-bio">{partner.bio}</p>}

          {tags.length > 0 && (
            <div className="detail-tags preview-tags">
              {tags.map((tag) => <span key={tag}>{tag}</span>)}
            </div>
          )}

          {items.length > 0 && (
            <div className="preview-items">
              <strong>Featured options</strong>
              {items.slice(0, 3).map((item, index) => (
                <div key={`${item.name || index}-${index}`}>
                  <span>{item.emoji || "✦"}</span>
                  <span>{item.name || `Item ${index + 1}`}</span>
                </div>
              ))}
            </div>
          )}

          <div className="preview-actions">
            {firstOrderUrl && <a className="primary-button" href={firstOrderUrl} target="_blank" rel="noreferrer">Order / view on HEHA</a>}
            {ig && <a className="secondary-button" href={ig} target="_blank" rel="noreferrer">Open Instagram</a>}
            {website && <a className="secondary-button" href={website} target="_blank" rel="noreferrer">Open website</a>}
            <button className="primary-button" type="button" onClick={onSave}>Save to HEHA list</button>
            <button className="secondary-button" type="button" onClick={onShare}>Share</button>
            <button className="text-button center" type="button" onClick={onPass}>Pass for now</button>
          </div>
        </div>
      </section>
    </div>
  );
}
