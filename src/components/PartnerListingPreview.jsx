import { useMemo, useState } from "react";
import { filterPublicTags } from "../lib/partnerTags";
import { publicDescription } from "../lib/cardCopy";

const CATEGORY_GROUPS = {
  Restaurant: { label: "Food", className: "food", emoji: "🥗" },
  Vendor: { label: "Market", className: "market", emoji: "🛍️" },
  Catering: { label: "Catering", className: "food", emoji: "🍱" },
  PrivateChef: { label: "Private Chef", className: "food", emoji: "👨‍🍳" },
  Wellness: { label: "Wellness", className: "wellness", emoji: "🧘" },
  Coach: { label: "Coach", className: "coach", emoji: "🏆" },
  Service: { label: "Service", className: "service", emoji: "💆" },
  Events: { label: "Events", className: "events", emoji: "🎉" },
};

const STOCK_GALLERIES = {
  Restaurant: ["/partner-images/clean-food.svg", "/partner-images/market.svg", "/partner-images/events.svg"],
  Vendor: ["/partner-images/market.svg", "/partner-images/clean-food.svg", "/partner-images/wellness.svg"],
  Catering: ["/partner-images/clean-food.svg", "/partner-images/events.svg", "/partner-images/market.svg"],
  PrivateChef: ["/partner-images/clean-food.svg", "/partner-images/events.svg", "/partner-images/market.svg"],
  Wellness: ["/partner-images/wellness.svg", "/partner-images/clean-food.svg", "/partner-images/events.svg"],
  Coach: ["/partner-images/wellness.svg", "/partner-images/events.svg", "/partner-images/clean-food.svg"],
  Service: ["/partner-images/wellness.svg", "/partner-images/clean-food.svg", "/partner-images/market.svg"],
  Events: ["/partner-images/events.svg", "/partner-images/clean-food.svg", "/partner-images/market.svg"],
};

function categoryGroup(listing) {
  const terms = [listing.category, ...(listing.offerings || []), ...(listing.tags || [])]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  if (terms.includes("private chef") || terms.includes("chef")) {
    return { label: "Private Chef", className: "food", emoji: "👨‍🍳" };
  }

  return CATEGORY_GROUPS[listing.category] || {
    label: listing.category || "Local",
    className: "local",
    emoji: "✦",
  };
}

function stockGallery(listing) {
  return STOCK_GALLERIES[listing.category] || [
    "/partner-images/clean-food.svg",
    "/partner-images/market.svg",
    "/partner-images/wellness.svg",
  ];
}

function galleryImages(listing) {
  const gallery = Array.isArray(listing.gallery_urls) ? listing.gallery_urls.filter(Boolean) : [];
  if (gallery.length) return gallery.slice(0, 3);
  if (listing.image_url) return [listing.image_url];
  return stockGallery(listing).slice(0, 3);
}

function isStockPlaceholder(listing, image) {
  const realImages = [
    listing.image_url,
    ...(Array.isArray(listing.gallery_urls) ? listing.gallery_urls : []),
  ].filter(Boolean);
  return !realImages.includes(image);
}

function instagramUrl(handle) {
  if (!handle) return null;
  if (handle.startsWith("http")) return handle;
  return `https://instagram.com/${handle.replace("@", "")}`;
}

function realWebsite(url) {
  if (!url) return null;
  const clean = String(url).trim();
  const lower = clean.toLowerCase();
  if (!lower.startsWith("http")) return null;
  if (lower.includes("example.com") || lower === "https://heha.online") return null;
  return clean;
}

export default function PartnerListingPreview({ listing, onClose }) {
  const [imageIndex, setImageIndex] = useState(0);
  const group = useMemo(() => categoryGroup(listing), [listing]);
  const images = useMemo(() => galleryImages(listing), [listing]);
  const tags = useMemo(
    () => [...new Set(filterPublicTags([...(listing.offerings || []), ...(listing.tags || [])]))].slice(0, 2),
    [listing]
  );
  const items = Array.isArray(listing.items) ? listing.items.filter(Boolean) : [];
  const currentImage = images[imageIndex] || stockGallery(listing)[0];
  const showingStockImage = isStockPlaceholder(listing, currentImage);
  const ig = instagramUrl(listing.instagram);
  const website = realWebsite(listing.website);

  return (
    <div
      className="preview-backdrop"
      role="dialog"
      aria-modal="true"
      aria-label={`${listing.name || "Business"} listing preview`}
      onClick={onClose}
    >
      <section className="partner-preview-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close preview">×</button>

        <div className={`preview-hero category-${group.className}`}>
          <img src={currentImage} alt={`${listing.name || "Business"} preview`} />
          <span className="preview-category-pill">{group.emoji} {group.label}</span>
          <span className="preview-status-pill">{listing.heha_partner ? "HEHA Reviewed" : "Preview only"}</span>
          {showingStockImage && <span className="preview-stock-pill">Photo coming soon</span>}

          {images.length > 1 && (
            <div className="gallery-dots preview-dots">
              {images.map((image, index) => (
                <button
                  key={`${image}-${index}`}
                  className={imageIndex === index ? "active" : ""}
                  type="button"
                  onClick={() => setImageIndex(index)}
                  aria-label={`Show photo ${index + 1}`}
                />
              ))}
            </div>
          )}
        </div>

        <div className="preview-body">
          <p className="eyebrow">{listing.neighborhood || listing.location || "Tampa Bay"}</p>
          <h2>{listing.name || "Unnamed business"}</h2>
          {listing.price_range && <span className="price-range-pill">{listing.price_range}</span>}
          {publicDescription(listing) && <p className="preview-tagline">{publicDescription(listing)}</p>}

          {tags.length > 0 && <div className="detail-tags preview-tags">{tags.join(", ")}</div>}

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

          <div className="partner-cert-note">
            Preview only. This uses your currently saved listing data and does not publish, certify, or activate a deal.
          </div>

          <div className="preview-actions">
            {ig && <a className="secondary-button" href={ig} target="_blank" rel="noreferrer">Open Instagram</a>}
            {website && <a className="secondary-button" href={website} target="_blank" rel="noreferrer">Open website</a>}
            <button className="primary-button" type="button" onClick={onClose}>Back to Partner Hub</button>
          </div>
        </div>
      </section>
    </div>
  );
}
