function cleanList(value) {
  return Array.isArray(value)
    ? value.map((item) => String(item || "").trim()).filter(Boolean)
    : [];
}

function display(value, fallback = "Not provided") {
  const text = String(value || "").trim();
  return text || fallback;
}

function itemSummary(items) {
  if (!Array.isArray(items) || !items.length) return "None added";
  return items.map((item) => {
    if (!item || typeof item !== "object") return String(item);
    return [item.emoji, item.name, item.price].filter(Boolean).join(" ");
  }).join(", ");
}

export default function PartnerPublicationPreview({ snapshot, compact = false }) {
  if (!snapshot || typeof snapshot !== "object") {
    return (
      <div className="wizard-note">
        The public profile preview is unavailable. Do not approve publication until it reloads.
      </div>
    );
  }

  const categories = cleanList(snapshot.categories);
  const tags = cleanList(snapshot.tags);
  const offerings = cleanList(snapshot.offerings);
  const deliveryDays = cleanList(snapshot.delivery_days);
  const gallery = cleanList(snapshot.gallery_urls);
  const wave1FoodProfile = categories.some((category) =>
    ["catering", "privatechef", "private chef"].includes(category.toLowerCase())
  ) || ["catering", "privatechef", "private chef"].includes(
    String(snapshot.category || "").toLowerCase()
  );
  const rows = [
    ["Business name", display(snapshot.name)],
    ["Categories", categories.length ? categories.join(", ") : display(snapshot.category)],
    ["Public service area", display(snapshot.neighborhood)],
    ["Tagline", display(snapshot.tagline)],
    ["About", display(snapshot.bio)],
    ["Tags", tags.length ? tags.join(", ") : "None added"],
    ["Hours", display(snapshot.hours)],
    ["Business type", display(snapshot.business_type)],
    ["Offerings", offerings.length ? offerings.join(", ") : "None added"],
    ...(wave1FoodProfile
      ? [["Wave 1 pricing", "To be quoted — the chef or caterer sets the food/service price"]]
      : [
          ["Featured items", itemSummary(snapshot.items)],
          ["Price range", display(snapshot.price_range)],
        ]),
    ["Delivery days", deliveryDays.length ? deliveryDays.join(", ") : "Not provided"],
    ["Website", display(snapshot.website)],
    ["Instagram", snapshot.instagram ? `@${String(snapshot.instagram).replace(/^@/, "")}` : "Not provided"],
    ["Card icon / color", `${display(snapshot.photo_emoji, "None")} / ${display(snapshot.color)}`],
  ];

  return (
    <section className={`publication-preview${compact ? " compact" : ""}`} aria-label="Exact partner-authored profile version">
      <div>
        <p className="eyebrow">Exact partner-authored profile version</p>
        <h3>{display(snapshot.name, "Business profile")}</h3>
        <p>These are the partner-authored fields HEHA may show after separate review and activation. HEHA-controlled badges, reviews, and routing are separate.</p>
      </div>

      {snapshot.image_url && (
        <img className="publication-preview-hero" src={snapshot.image_url} alt="Primary business profile media" />
      )}
      {gallery.length > 0 && (
        <div className="publication-preview-gallery" aria-label="Business profile gallery">
          {gallery.map((url, index) => (
            <img key={`${url}-${index}`} src={url} alt={`Business profile gallery item ${index + 1}`} />
          ))}
        </div>
      )}

      <div className="wizard-review-list publication-preview-fields">
        {rows.map(([label, value]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>

      <div className="wizard-note">
        Kept private: full address, phone, direct contact, account owner, consent evidence, analytics, internal routing notes, and HEHA fee/payout internals.
      </div>
    </section>
  );
}
