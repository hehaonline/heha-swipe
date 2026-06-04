import { useCallback, useEffect, useMemo, useState } from "react";
import SwipeCard from "./SwipeCard";

const CATEGORIES = ["All", "Restaurant", "Vendor", "Wellness", "Coach", "Service", "Events"];
const CATEGORY_LABELS = {
  All: "All",
  Restaurant: "Food",
  Vendor: "Market",
  Wellness: "Wellness",
  Coach: "Coaches",
  Service: "Services",
  Events: "Events",
};
const CAT_ICONS = {
  All: "✦",
  Restaurant: "🥗",
  Vendor: "🛍️",
  Wellness: "🧘",
  Coach: "🏆",
  Service: "💆",
  Events: "🎉",
};

const shuffle = (items) => {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
};

function partnerMatchesCategory(partner, activeCategory) {
  if (activeCategory === "All") return true;
  if (activeCategory === "Restaurant") {
    const terms = [partner.category, ...(partner.tags || []), ...(partner.offerings || [])]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return partner.category === "Restaurant" || terms.includes("private chef") || terms.includes("chef");
  }
  return partner.category === activeCategory;
}

export default function SwipeTab({
  partners = [],
  saves = [],
  onSave,
  onPass,
  onSuperSwipe,
  dataLoading = false,
}) {
  const [category, setCategory] = useState("All");
  const [deck, setDeck] = useState([]);
  const [seenIds, setSeenIds] = useState(new Set());
  const [reshuffled, setReshuffled] = useState(false);

  const savedIds = useMemo(() => new Set(saves.map((save) => save.partner_id)), [saves]);

  const buildDeck = useCallback(
    (activeCategory, seen, isReshuffle = false) => {
      const pool = partners.filter((partner) => {
        const matchesCategory = partnerMatchesCategory(partner, activeCategory);
        const alreadySaved = savedIds.has(partner.id);
        return matchesCategory && !alreadySaved;
      });

      if (isReshuffle) return shuffle(pool);
      const unseen = pool.filter((partner) => !seen.has(partner.id));
      return unseen.length ? unseen : null;
    },
    [partners, savedIds]
  );

  useEffect(() => {
    const result = buildDeck(category, seenIds);
    if (result === null && partners.length) {
      setDeck(buildDeck(category, new Set(), true) || []);
      setSeenIds(new Set());
      setReshuffled(true);
      window.setTimeout(() => setReshuffled(false), 1800);
    } else {
      setDeck(result || []);
    }
  }, [partners, saves, category, buildDeck]);

  const current = deck[0];

  const handleSwipe = async (direction) => {
    if (!current) return;
    const partner = current;
    setDeck((items) => items.slice(1));
    setSeenIds((ids) => new Set([...ids, partner.id]));

    if (direction === "right") await onSave?.(partner);
    if (direction === "left") await onPass?.(partner);
    if (direction === "super") await onSuperSwipe?.(partner);
  };

  const activeCategoryCount = useMemo(() => {
    if (category === "All") return partners.length;
    return partners.filter((partner) => partnerMatchesCategory(partner, category)).length;
  }, [partners, category]);

  return (
    <section className="discover-screen compact-discover">
      {reshuffled && <div className="floating-status">Fresh businesses loaded</div>}

      <div className="discover-hero compact-hero clean-hero">
        <div>
          <p className="eyebrow">Local healthy discovery</p>
          <h2>Tampa Bay’s healthy scene.</h2>
          <p>Tap a card to preview. Swipe right to save businesses you want to remember.</p>
        </div>
        <div className="hero-chip">{activeCategoryCount}</div>
      </div>

      <div className="category-rail compact-rail" role="tablist" aria-label="Partner categories">
        {CATEGORIES.map((cat) => (
          <button
            key={cat}
            className={category === cat ? "active" : ""}
            onClick={() => {
              setCategory(cat);
              setSeenIds(new Set());
            }}
          >
            <span>{CAT_ICONS[cat]}</span>
            {CATEGORY_LABELS[cat]}
          </button>
        ))}
      </div>

      {dataLoading && <div className="inline-loader">Refreshing partners…</div>}

      <div className="deck-stage compact-stage clean-stage">
        {current ? (
          <>
            {deck[1] && <div className="next-card-shadow clean-shadow" />}
            <SwipeCard partner={current} onSwipe={handleSwipe} />
          </>
        ) : (
          <EmptyDeck category={category} onReset={() => setCategory("All")} />
        )}
      </div>

      {current && (
        <div className="action-dock" aria-label="Swipe actions">
          <button className="action-circle pass" onClick={() => handleSwipe("left")} aria-label="Pass for now">×</button>
          <button className="action-circle super" onClick={() => handleSwipe("super")} aria-label="SuperSwoop this partner">✦</button>
          <button className="action-circle save" onClick={() => handleSwipe("right")} aria-label="Save this partner">♥</button>
        </div>
      )}
    </section>
  );
}

function EmptyDeck({ category, onReset }) {
  return (
    <div className="empty-state card-like">
      <div className="empty-icon">🌿</div>
      <h3>{category === "All" ? "You caught up with the current map." : `No more ${category.toLowerCase()} partners right now.`}</h3>
      <p>New healthy businesses can be added weekly. Saved partners stay in your HEHA list so you can come back later.</p>
      <button className="primary-button" onClick={onReset}>Explore all categories</button>
    </div>
  );
}
