import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
  PrivateChef: "Private Chefs",
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

function canonicalCategory(value) {
  if (value === "Vendor") return "Markets";
  if (value === "PrivateChef") return "Private Chef";
  return value;
}

function partnerCategories(partner) {
  const selected = Array.isArray(partner?.categories) ? partner.categories : [];
  return new Set(
    [...selected, partner?.category]
      .filter(Boolean)
      .map(canonicalCategory)
  );
}

function partnerTerms(partner) {
  return [
    partner.category,
    ...(Array.isArray(partner.categories) ? partner.categories : []),
    partner.subcategory,
    partner.tagline,
    partner.bio,
    ...(partner.tags || []),
    ...(partner.offerings || []),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function isPrivateChef(partner) {
  const terms = partnerTerms(partner);
  return partnerCategories(partner).has("Private Chef") || terms.includes("private chef") || terms.includes("retreat chef");
}

function isCatering(partner) {
  const terms = partnerTerms(partner);
  return partnerCategories(partner).has("Catering") || terms.includes("catering") || terms.includes("staff meals") || terms.includes("food truck") || terms.includes("group orders");
}

function isMarket(partner) {
  const terms = partnerTerms(partner);
  return partnerCategories(partner).has("Markets") || terms.includes("market") || terms.includes("farmers market") || terms.includes("grocery");
}

function partnerMatchesCategory(partner, activeCategory) {
  if (activeCategory === "All") return true;

  const selectedCategories = partnerCategories(partner);
  if (selectedCategories.has(activeCategory)) return true;

  if (activeCategory === "Private Chef") return isPrivateChef(partner);
  if (activeCategory === "Catering") return isCatering(partner);
  if (activeCategory === "Markets") return isMarket(partner);
  if (activeCategory === "Restaurant") {
    return canonicalCategory(partner.category) === "Restaurant" && !isPrivateChef(partner) && !isCatering(partner);
  }

  return false;
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
  onUndoSwipe,
  dataLoading = false,
}) {
  const [category, setCategory] = useState("All");
  const [deck, setDeck] = useState([]);
  const [seenIds, setSeenIds] = useState(new Set());
  const [reshuffled, setReshuffled] = useState(false);
  const [lastSwipe, setLastSwipe] = useState(null);
  const [restoredPartner, setRestoredPartner] = useState(null);
  const [undoing, setUndoing] = useState(false);
  const undoingRef = useRef(false);
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
    const putRestoredPartnerFirst = (items = []) => {
      if (!restoredPartner || !partnerMatchesCategory(restoredPartner, category)) return items;
      return [restoredPartner, ...items.filter((partner) => partner.id !== restoredPartner.id)];
    };

    const result = buildDeck(category, seenIds);
    if (result === null && swipePartners.length) {
      setDeck(putRestoredPartnerFirst(buildDeck(category, new Set(), true) || []));
      setSeenIds(new Set());
      setReshuffled(true);
      window.setTimeout(() => setReshuffled(false), 1800);
    } else {
      setDeck(putRestoredPartnerFirst(result || []));
    }
  }, [swipePartners, saves, category, buildDeck, restoredPartner]);

  const current = deck[0];
  const routedCurrent = useMemo(() => withHehaLocalItemLinks(current), [current]);

  const handleSwipe = (direction) => {
    if (!current || undoingRef.current) return;
    const partner = current;
    const wasSaved = savedIds.has(partner.id);

    setRestoredPartner(null);
    setDeck((items) => items.slice(1));
    setSeenIds((ids) => new Set([...ids, partner.id]));

    const operation = (async () => {
      try {
        if (direction === "right") return await onSave?.(partner);
        if (direction === "left") return await onPass?.(partner);
        if (direction === "super") return await onSuperSwipe?.(partner);
        return true;
      } catch {
        return false;
      }
    })();

    setLastSwipe({ partner, direction, wasSaved, operation });
  };

  const handleUndo = async () => {
    if (!lastSwipe || undoingRef.current) return;

    const swipeToUndo = lastSwipe;
    undoingRef.current = true;
    setUndoing(true);

    try {
      await swipeToUndo.operation;
      const didUndo = await onUndoSwipe?.(
        swipeToUndo.partner,
        swipeToUndo.direction,
        { wasSaved: swipeToUndo.wasSaved }
      );
      if (didUndo === false) return;

      setSeenIds((ids) => {
        const nextIds = new Set(ids);
        nextIds.delete(swipeToUndo.partner.id);
        return nextIds;
      });
      setRestoredPartner(swipeToUndo.partner);
      setLastSwipe(null);
    } finally {
      undoingRef.current = false;
      setUndoing(false);
    }
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
              setLastSwipe(null);
              setRestoredPartner(null);
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

      {(current || lastSwipe) && (
        <div className="action-dock luxe-action-dock" aria-label="Swipe actions">
          {lastSwipe && (
            <button
              className="action-circle undo"
              type="button"
              onClick={handleUndo}
              disabled={undoing}
              aria-label="Undo last swipe"
              title="Undo last swipe"
            >
              <span className="undo-icon" aria-hidden="true">↶</span>
              <span className="undo-label">{undoing ? "Wait" : "Undo"}</span>
            </button>
          )}
          {current && (
            <>
              <button className="action-circle pass" type="button" onClick={() => handleSwipe("left")} disabled={undoing} aria-label="Pass for now">×</button>
              <button className="action-circle super" type="button" onClick={() => handleSwipe("super")} disabled={undoing} aria-label="Preview or highlight this business">i</button>
              <button className="action-circle save" type="button" onClick={() => handleSwipe("right")} disabled={undoing} aria-label="Save this business">♥</button>
            </>
          )}
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
