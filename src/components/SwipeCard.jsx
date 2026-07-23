import { useMemo, useRef, useState } from "react";
import ShareSheet from "./ShareSheet";
import { filterPublicTags } from "../lib/partnerTags";
import { publicDescription, TWO_LINE_CLAMP } from "../lib/cardCopy";
import { isHehaLocalPartner, partnerOrderLabel, partnerOrderUrl } from "../lib/hehaLocalRouting";

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
  if (gallery.length) return gallery.slice(0, 6);
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
  // Names wrap to 2 lines in the UI (TWO_LINE_CLAMP) instead of hard-truncating.
  return name;
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
          <h2 style={TWO_LINE_CLAMP}>{displayName(partner.name)}</h2>
          {publicDescription(partner) && <p className="tagline">{publicDescription(partner)}</p>}
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
  const photoTouchStart = useRef(null);
  const currentImage = images[imageIndex] || fallbackImage(partner);
  const hasMultipleImages = images.length > 1;
  const ig = instagramUrl(partner.instagram);
  const website = hasRealWebsite(partner.website) ? partner.website : null;
  const localDestination = isHehaLocalPartner(partner);
  const firstOrderUrl = localDestination
    ? partnerOrderUrl(partner)
    : items.map(itemUrl).find(Boolean);
  const orderLabel = localDestination ? partnerOrderLabel(partner) : "Order / view on HEHA";
  const showingStockImage = isStockPlaceholder(partner, currentImage);

  const showPreviousImage = () => {
    if (!hasMultipleImages) return;
    setImageIndex((current) => (current - 1 + images.length) % images.length);
  };

  const showNextImage = () => {
    if (!hasMultipleImages) return;
    setImageIndex((current) => (current + 1) % images.length);
  };

  const startPhotoSwipe = (event) => {
    if (!hasMultipleImages) return;
    const touch = event.touches[0];
    photoTouchStart.current = { x: touch.clientX, y: touch.clientY };
  };

  const finishPhotoSwipe = (event) => {
    const start = photoTouchStart.current;
    photoTouchStart.current = null;
    if (!start || !hasMultipleImages) return;

    const touch = event.changedTouches[0];
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    const isHorizontalSwipe = Math.abs(deltaX) >= 42 && Math.abs(deltaX) > Math.abs(deltaY) * 1.15;
    if (!isHorizontalSwipe) return;

    if (deltaX < 0) showNextImage();
    else showPreviousImage();
  };

  return (
    <div className="preview-backdrop" role="dialog" aria-modal="true" aria-label={`${partner.name} preview`} onClick={onClose}>
      <section className="partner-preview-sheet swipe-preview-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close preview">×</button>
        <div
          className={`preview-hero category-${categoryGroup.className}`}
          role="region"
          aria-roledescription="carousel"
          aria-label={`${partner.name} photo gallery`}
          onTouchStart={startPhotoSwipe}
          onTouchEnd={finishPhotoSwipe}
          onTouchCancel={() => { photoTouchStart.current = null; }}
        >
          <img
            key={currentImage}
            className="preview-hero-image"
            src={currentImage}
            alt={`${partner.name} photo ${imageIndex + 1} of ${images.length}`}
            draggable="false"
          />
          <span className="preview-category-pill">{categoryGroup.emoji} {categoryGroup.label}</span>
          <span className="preview-status-pill">{statusBadge(partner)}</span>
          {showingStockImage && <span className="preview-stock-pill">Photo coming soon</span>}
          {hasMultipleImages && (
            <>
              <button
                className="preview-gallery-nav previous"
                type="button"
                onClick={showPreviousImage}
                aria-label="Show previous photo"
              >
                ‹
              </button>
              <button
                className="preview-gallery-nav next"
                type="button"
                onClick={showNextImage}
                aria-label="Show next photo"
              >
                ›
              </button>
              <div className="preview-gallery-progress" aria-live="polite">
                {imageIndex + 1} / {images.length} · Swipe
              </div>
              <div className="gallery-dots preview-dots" aria-label="Choose a partner photo">
                {images.map((image, index) => (
                  <button
                    key={`${image}-${index}`}
                    className={imageIndex === index ? "active" : ""}
                    type="button"
                    onClick={() => setImageIndex(index)}
                    aria-label={`Show photo ${index + 1}`}
                    aria-current={imageIndex === index ? "true" : undefined}
                  />
                ))}
              </div>
            </>
          )}
        </div>

        <div className="preview-body">
          <p className="eyebrow">{partner.neighborhood || partner.location || "Tampa Bay"}</p>
          <h2>{partner.name}</h2>
          {partner.price_range && <span className="price-range-pill">{partner.price_range}</span>}
          {publicDescription(partner) && <p className="preview-tagline">{publicDescription(partner)}</p>}

          {tags.length > 0 && (
            <div className="detail-tags preview-tags">{tags.join(", ")}</div>
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
            {firstOrderUrl && <a className="primary-button" href={firstOrderUrl} target="_blank" rel="noreferrer">{orderLabel}</a>}
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
