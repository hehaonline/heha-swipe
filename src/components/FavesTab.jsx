import { useMemo, useState } from "react";

function fallbackImage(partner) {
  if (partner.image_url) return partner.image_url;
  if (partner.category === "Events") return "/partner-images/events.svg";
  if (partner.category === "Wellness" || partner.category === "Service" || partner.category === "Coach") return "/partner-images/wellness.svg";
  if (partner.category === "Vendor") return "/partner-images/market.svg";
  return "/partner-images/clean-food.svg";
}

function galleryImages(partner) {
  const gallery = Array.isArray(partner.gallery_urls) ? partner.gallery_urls.filter(Boolean) : [];
  return gallery.length ? gallery : [fallbackImage(partner)];
}

function instagramUrl(handle) {
  if (!handle) return null;
  if (handle.startsWith("http")) return handle;
  return `https://instagram.com/${handle.replace("@", "")}`;
}

function itemUrl(item) {
  return item?.url || item?.product_url || item?.link || null;
}

export default function FavesTab({ partners = [], saves = [], onUnsave, onDiscountCheck }) {
  const [selectedPartner, setSelectedPartner] = useState(null);
  const [selectedItems, setSelectedItems] = useState([]);
  const [galleryIndex, setGalleryIndex] = useState(0);

  const saved = saves
    .map((save) => partners.find((partner) => partner.id === save.partner_id))
    .filter(Boolean);

  const selectedOrderUrl = useMemo(() => {
    if (!selectedPartner) return null;
    const items = Array.isArray(selectedPartner.items) ? selectedPartner.items : [];
    if (!selectedItems.length) return null;
    const firstSelected = items.find((item) => selectedItems.includes(item.name));
    return itemUrl(firstSelected);
  }, [selectedPartner, selectedItems]);

  const toggleItem = (itemName) => {
    setSelectedItems((current) => (
      current.includes(itemName)
        ? current.filter((item) => item !== itemName)
        : [...current, itemName]
    ));
  };

  const openDetails = (partner) => {
    setSelectedPartner(partner);
    setSelectedItems([]);
    setGalleryIndex(0);
  };

  const closeDetails = () => {
    setSelectedPartner(null);
    setSelectedItems([]);
    setGalleryIndex(0);
  };

  if (selectedPartner) {
    const items = Array.isArray(selectedPartner.items) ? selectedPartner.items : [];
    const tags = [...new Set([...(selectedPartner.offerings || []), ...(selectedPartner.tags || [])])].slice(0, 8);
    const ig = instagramUrl(selectedPartner.instagram);
    const hasSelectedItems = selectedItems.length > 0;
    const images = galleryImages(selectedPartner);
    const currentImage = images[galleryIndex] || fallbackImage(selectedPartner);
    const isOfficialPartner = Boolean(selectedPartner.heha_partner);

    return (
      <section className="saved-screen partner-detail-screen">
        <button className="detail-back" onClick={closeDetails}>← Saved</button>

        <article className="partner-detail-card">
          <div className="detail-image-wrap gallery-hero">
            <img src={currentImage} alt={`${selectedPartner.name} preview`} />
            <div className="detail-avatar">{selectedPartner.photo_emoji || "🌿"}</div>
            {selectedPartner.heha_partner && <span className="detail-verified">HEHA Certified</span>}
            {!selectedPartner.heha_partner && <span className="detail-listed">Listed on HEHA Swipe</span>}
            {images.length > 1 && (
              <div className="gallery-dots" aria-label="Partner photo gallery">
                {images.map((image, index) => (
                  <button
                    key={`${image}-${index}`}
                    className={galleryIndex === index ? "active" : ""}
                    onClick={() => setGalleryIndex(index)}
                    aria-label={`Show photo ${index + 1}`}
                  />
                ))}
              </div>
            )}
          </div>

          <div className="detail-body">
            <p className="eyebrow">{selectedPartner.category || "Local"} · {selectedPartner.neighborhood || "Tampa Bay"}</p>
            <h2>{selectedPartner.name}</h2>
            {selectedPartner.price_range && <div className="price-range-pill">{selectedPartner.price_range}</div>}
            {selectedPartner.tagline && <p className="detail-tagline">{selectedPartner.tagline}</p>}
            {selectedPartner.bio && <p className="detail-bio">{selectedPartner.bio}</p>}

            {tags.length > 0 && (
              <div className="detail-tags">
                {tags.map((tag) => <span key={tag}>{tag}</span>)}
              </div>
            )}
          </div>
        </article>

        <section className="detail-section card-like">
          <div className="detail-section-heading">
            <p className="eyebrow">{items.length ? "Select items" : isOfficialPartner ? "Ordering" : "Community interest"}</p>
            <h3>{items.length ? "Choose what you want to order" : isOfficialPartner ? "Ordering coming soon" : "Want HEHA member discounts here?"}</h3>
          </div>

          {items.length ? (
            <div className="order-item-list">
              {items.map((item, index) => {
                const name = item.name || `Item ${index + 1}`;
                const active = selectedItems.includes(name);
                const url = itemUrl(item);
                return (
                  <button
                    key={`${name}-${index}`}
                    className={active ? "order-item active" : "order-item"}
                    onClick={() => toggleItem(name)}
                  >
                    <span>{item.emoji || "✦"}</span>
                    <strong>{name}</strong>
                    <small>{url ? "Order ↗" : "Soon"}</small>
                  </button>
                );
              })}
            </div>
          ) : (
            <p className="detail-bio">
              {isOfficialPartner
                ? "This partner does not have orderable items listed yet. You can still contact them or HEHA."
                : "This business is listed for discovery, but it is not yet an official HEHA partner. Tap below to show interest so HEHA can request a member discount or partnership."}
            </p>
          )}

          <div className="detail-order-actions">
            {selectedOrderUrl ? (
              <a className="primary-button" href={selectedOrderUrl} target="_blank" rel="noreferrer">
                Order selected item on HEHA
              </a>
            ) : isOfficialPartner ? (
              <button className="primary-button" disabled>
                {hasSelectedItems ? "HEHA product link coming soon" : "Select an item to order"}
              </button>
            ) : (
              <button className="discount-button" type="button" onClick={() => onDiscountCheck?.(selectedPartner)}>
                Check for Discounts
              </button>
            )}
            {!isOfficialPartner && (
              <p className="discount-note">HEHA can use this interest to approach the business and ask for member discounts.</p>
            )}
            {ig && <a className="secondary-button" href={ig} target="_blank" rel="noreferrer">Open Instagram</a>}
            {selectedPartner.website && <a className="secondary-button" href={selectedPartner.website} target="_blank" rel="noreferrer">Open website</a>}
          </div>
        </section>
      </section>
    );
  }

  if (!saved.length) {
    return (
      <section className="saved-screen">
        <div className="empty-state card-like">
          <div className="empty-icon">♥</div>
          <h2>Your HEHA list is empty for now.</h2>
          <p>Swipe right on restaurants, wellness partners, markets, and local services you want to remember.</p>
        </div>
      </section>
    );
  }

  return (
    <section className="saved-screen">
      <div className="section-hero compact">
        <p className="eyebrow">Your saved map</p>
        <h2>{saved.length} healthy business{saved.length === 1 ? "" : "es"} saved</h2>
        <p>Tap a saved business to view details, learn more, order through HEHA, or request member discounts.</p>
      </div>

      <div className="saved-list">
        {saved.map((partner) => (
          <article key={partner.id} className="saved-card clickable" onClick={() => openDetails(partner)}>
            <div className="saved-icon" style={{ background: partner.color || "var(--heha-green)" }}>
              {partner.photo_emoji || "🌿"}
            </div>
            <div>
              <div className="saved-title-row">
                <h3>{partner.name}</h3>
                {partner.heha_partner ? <span>Certified</span> : <span>Listed</span>}
              </div>
              <p>{partner.category} · {partner.neighborhood || "Tampa Bay"}</p>
              {partner.price_range && <small>{partner.price_range}</small>}
              {!partner.price_range && partner.tagline && <small>{partner.tagline}</small>}
              <div className="saved-actions">
                <button type="button" onClick={(event) => { event.stopPropagation(); openDetails(partner); }}>View details</button>
                {!partner.heha_partner && <button type="button" onClick={(event) => { event.stopPropagation(); onDiscountCheck?.(partner); }}>Check discounts</button>}
                {partner.instagram && <a onClick={(event) => event.stopPropagation()} href={instagramUrl(partner.instagram)} target="_blank" rel="noreferrer">Instagram</a>}
              </div>
            </div>
            <button className="remove-button" onClick={(event) => { event.stopPropagation(); onUnsave?.(partner.id); }} aria-label={`Remove ${partner.name}`}>×</button>
          </article>
        ))}
      </div>
    </section>
  );
}
