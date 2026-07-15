import { useCallback, useEffect, useMemo, useState } from "react";
import SwipeCard from "./SwipeCard";
import { hehaLocalItemUrl, isHehaLocalPartner } from "../lib/hehaLocalRouting";

const CATEGORIES = [
  "All",
  "Restaurant",
  "Markets",
  "Catering",
  "Private Chef",
  "Wellness",
  "Coach",
  "Service",
  "Events",
];

const CATEGORY_LABELS = {
  All: "All",
  Restaurant: "Food",
  Markets: "Markets",
  Vendor: "Markets",
  Catering: "Catering",
  "Private Chef": "Private Chefs",
  Wellness: "Wellness",
  Coach: "Coaches",
  Service: "Services",
  Events: "Events",
};

const CATEGORY_ICONS = {
  All: "✦",
  Restaurant: "🥗",
  Markets: "🛒",
  Catering: "🍱",
  "Private Chef": "👨‍🍳",
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

function partnerTerms(partner) {
  return [partner.category, partner.subcategory, partner.tagline, partner.bio, ...(partner.tags || []), ...(partner.offerings || [])]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function isPrivateChef(partner) {
  const terms = partnerTerms(partner);
  return partner.category === "Private Chef" || terms.includes("private chef") || terms.includes("retreat chef");
}

function isCatering(partner) {
  const terms = partnerTerms(partner);
  return partner.category === "Catering" || terms.includes("catering") || terms.includes("staff meals") || terms.includes("food truck") || terms.includes("group orders");
}

function isMarket(partner) {
  const terms = partnerTerms(partner);
  return partner.category === "Markets" || partner.category === "Vendor" || terms.includes("market") || terms.includes("farmers market") || terms.includes("grocery");
}

function partnerMatchesCategory(partner, activeCategory) {
  if (activeCategory === "All") return true;
  if (activeCategory === "Private Chef") return isPrivateChef(partner);
  if (activeCategory === "Catering") return isCatering(partner);
  if (activeCategory === "Markets") return isMarket(partner);
  if (activeCategory === "Restaurant") return partner.category === "Restaurant" && !isPrivateChef(partner) && !isCatering(partner);
  return partner.category === activeCategory;
}

function withHehaLocalItemLinks(partner) {
  if (!partner || !isHehaLocalPartner(partner)) return partner;
  const items = Array.isArray(partner.items) ? partner.items : [];
  return {
    ...partner,
    items: items.map((item) => ({
      ...item,
      // HEHA Local is the order/detail source for Local-eligible partners.
      // This intentionally overrides stale GoDaddy product URLs in Swipe.
      url: hehaLocalItemUrl(partner, item),
    })),
  };
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
  const featuredPartnerId = useMemo(() => new URLSearchParams(window.location.search).get("partner"), []);

  const savedIds = useMemo(() => new Set(saves.map((save) => save.partner_id)), [saves]);
  const swipePartners = useMemo(() => partners.filter((partner) => partner.swipe_eligible !== false), [partners]);

  const buildDeck = useCallback(
    (activeCategory, seen, isReshuffle = false) => {
      const pool = swipePartners.filter((partner) => {
        const matchesCategory = partnerMatchesCategory(partner, activeCategory);
        const alreadySaved = savedIds.has(partner.id);
        const isFeatured = partner.id === featuredPartnerId;
        return matchesCategory && (!alreadySaved || isFeatured);
      });

      const featured = pool.find((partner) => partner.id === featuredPartnerId);
      const orderedPool = featured ? [featured, ...pool.filter((partner) => partner.id !== featured.id)] : pool;

      if (isReshuffle) return featured ? [featured, ...shuffle(orderedPool.slice(1))] : shuffle(orderedPool);
      const unseen = orderedPool.filter((partner) => !seen.has(partner.id));
      return unseen.length ? unseen : null;
    },
    [swipePartners, savedIds, featuredPartnerId]
  );

  useEffect(() => {
    const result = buildDeck(category, seenIds);
    if (result === null && swipePartners.length) {
      setDeck(buildDeck(category, new Set(), true) || []);
      setSeenIds(new Set());
      setReshuffled(true);
      window.setTimeout(() => setReshuffled(false), 1800);
    } else {
      setDeck(result || []);
    }
  }, [swipePartners, saves, category, buildDeck]);

  const current = deck[0];
  const routedCurrent = useMemo(() => withHehaLocalItemLinks(current), [current]);

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
    if (category === "All") return swipePartners.length;
    return swipePartners.filter((partner) => partnerMatchesCategory(partner, category)).length;
  }, [swipePartners, category]);

  return (
    <section className="discover-screen compact-discover luxe-discover">
      {reshuffled && <div className="floating-status">Fresh businesses loaded</div>}

      <div className="discover-topline">
        <div>
          <p className="eyebrow">Discover</p>
          <h2>Swipe healthy local.</h2>
        </div>
        <div className="hero-chip">{activeCategoryCount}</div>
      </div>

      <div className="category-rail compact-rail luxe-rail" role="tablist" aria-label="Partner categories">
        {CATEGORIES.map((cat) => (
          <button
            key={cat}
            className={category === cat ? "active" : ""}
            onClick={() => {
              setCategory(cat);
              setSeenIds(new Set());
            }}
          >
            <span>{CATEGORY_ICONS[cat]}</span>
            {CATEGORY_LABELS[cat]}
          </button>
        ))}
      </div>

      {dataLoading && <div className="inline-loader">Refreshing businesses…</div>}

      <div className="deck-stage compact-stage clean-stage luxe-stage">
        {routedCurrent ? (
          <>
            {deck[1] && <div className="next-card-shadow clean-shadow luxe-shadow" />}
            <SwipeCard partner={routedCurrent} onSwipe={handleSwipe} />
          </>
        ) : (
          <EmptyDeck category={CATEGORY_LABELS[category] || category} onReset={() => setCategory("All")} />
        )}
      </div>

      {current && (
        <div className="action-dock luxe-action-dock" aria-label="Swipe actions">
          <button className="action-circle pass" onClick={() => handleSwipe("left")} aria-label="Pass for now">×</button>
          <button className="action-circle super" onClick={() => handleSwipe("super")} aria-label="Preview or highlight this business">i</button>
          <button className="action-circle save" onClick={() => handleSwipe("right")} aria-label="Save this business">♥</button>
        </div>
      )}
    </section>
  );
}

function EmptyDeck({ category, onReset }) {
  return (
    <div className="empty-state card-like luxe-empty">
      <div className="empty-icon">♡</div>
      <h3>{category === "All" ? "You caught up with the current map." : `No more ${String(category).toLowerCase()} right now.`}</h3>
      <p>New healthy businesses can be added weekly. Saved partners stay in your HEHA list so you can come back later.</p>
      <button className="primary-button" onClick={onReset}>Explore all categories</button>
    </div>
  );
}
