export default function FavesTab({ partners = [], saves = [], onUnsave }) {
  const saved = saves
    .map((save) => partners.find((partner) => partner.id === save.partner_id))
    .filter(Boolean);

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
        <p>Use this list for future visits, orders, outreach, or partner inspiration.</p>
      </div>

      <div className="saved-list">
        {saved.map((partner) => (
          <article key={partner.id} className="saved-card">
            <div className="saved-icon" style={{ background: partner.color || "var(--heha-green)" }}>
              {partner.photo_emoji || "🌿"}
            </div>
            <div>
              <div className="saved-title-row">
                <h3>{partner.name}</h3>
                {partner.heha_partner && <span>Verified</span>}
              </div>
              <p>{partner.category} · {partner.neighborhood || "Tampa Bay"}</p>
              {partner.tagline && <small>{partner.tagline}</small>}
              <div className="saved-actions">
                {partner.website && <a href={partner.website} target="_blank" rel="noreferrer">Website</a>}
                {partner.instagram && <a href={`https://instagram.com/${partner.instagram.replace("@", "")}`} target="_blank" rel="noreferrer">Instagram</a>}
              </div>
            </div>
            <button className="remove-button" onClick={() => onUnsave?.(partner.id)} aria-label={`Remove ${partner.name}`}>×</button>
          </article>
        ))}
      </div>
    </section>
  );
}
