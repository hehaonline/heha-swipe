import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";

const PILLARS = [
  ["all", "All"],
  ["nourish", "Nourish"],
  ["relax", "Relax"],
  ["educate", "Educate"],
  ["elevate", "Elevate"],
];

const PAGE_SIZE = 12;

function textIndex(partner) {
  return [
    partner.name,
    partner.category,
    partner.business_type,
    partner.tagline,
    partner.bio,
    partner.neighborhood,
    partner.location,
    ...(partner.tags || []),
    ...(partner.offerings || []),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function primaryUrl(partner) {
  const path = partner.primary_cta_path || `/?partner=${partner.id}`;
  if (partner.primary_cta_destination === "local") {
    return `https://hehalocal.app${path.startsWith("/") ? path : `/${path}`}`;
  }
  return `https://hehaswipe.app${path.startsWith("/") ? path : `/${path}`}`;
}

function secondaryUrl(partner) {
  return `https://hehaswipe.app/?partner=${partner.id}`;
}

function locationLabel(partner) {
  return partner.neighborhood || partner.location || "Tampa Bay";
}

function summary(partner) {
  return partner.tagline || partner.bio || "Discover this local HEHA partner.";
}

export default function PartnerDirectoryEmbed() {
  const [partners, setPartners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [pillar, setPillar] = useState("all");
  const [sort, setSort] = useState("recommended");
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);

  useEffect(() => {
    let cancelled = false;

    async function loadPartners() {
      setLoading(true);
      setError("");
      const { data, error: loadError } = await supabase
        .from("public_partner_directory")
        .select("id,name,category,business_type,tagline,bio,neighborhood,location,tags,offerings,image_url,photo_emoji,heha_pillar,primary_cta_destination,primary_cta_label,primary_cta_path,created_at")
        .order("created_at", { ascending: false });

      if (cancelled) return;
      if (loadError) {
        setError("The HEHA partner directory could not load right now.");
        setPartners([]);
      } else {
        setPartners(data || []);
      }
      setLoading(false);
    }

    loadPartners();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    setVisibleCount(PAGE_SIZE);
  }, [query, pillar, sort]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const next = partners.filter((partner) => {
      if (pillar !== "all" && partner.heha_pillar !== pillar) return false;
      if (sort === "events" && partner.category !== "Events") return false;
      return !needle || textIndex(partner).includes(needle);
    });

    if (sort === "az") return [...next].sort((a, b) => a.name.localeCompare(b.name));
    if (sort === "newest") return [...next].sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    return next;
  }, [partners, query, pillar, sort]);

  const visible = filtered.slice(0, visibleCount);

  return (
    <main className="embed-page directory-embed">
      <section className="embed-hero">
        <p className="embed-eyebrow">HEHA partner directory</p>
        <h1>Find something intentional.</h1>
        <p>Search healthy food, wellness, education, events, and local community partners. HEHA will take you to the right next experience.</p>
      </section>

      <section className="directory-controls" aria-label="Partner directory filters">
        <label className="directory-search">
          <span aria-hidden="true">⌕</span>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search restaurants, yoga, herbalists, events…"
            aria-label="Search HEHA partners"
          />
        </label>

        <div className="pillar-tabs" role="tablist" aria-label="HEHA pillars">
          {PILLARS.map(([value, label]) => (
            <button
              key={value}
              type="button"
              className={pillar === value ? "active" : ""}
              onClick={() => setPillar(value)}
            >
              {label}
            </button>
          ))}
        </div>

        <div className="directory-sort-row">
          <strong>{filtered.length} local option{filtered.length === 1 ? "" : "s"}</strong>
          <select value={sort} onChange={(event) => setSort(event.target.value)} aria-label="Sort or filter partners">
            <option value="recommended">Recommended</option>
            <option value="az">A–Z</option>
            <option value="newest">Newest</option>
            <option value="events">Events</option>
          </select>
        </div>
      </section>

      {loading ? (
        <section className="embed-state">Loading healthy local partners…</section>
      ) : error ? (
        <section className="embed-state error">{error}</section>
      ) : visible.length === 0 ? (
        <section className="embed-state">
          <h2>No exact match yet.</h2>
          <p>Try another search or explore all HEHA pillars.</p>
          <button type="button" onClick={() => { setQuery(""); setPillar("all"); setSort("recommended"); }}>Show all partners</button>
        </section>
      ) : (
        <section className="partner-grid">
          {visible.map((partner) => (
            <article className="directory-card" key={partner.id}>
              <div className="directory-card-media">
                {partner.image_url ? (
                  <img src={partner.image_url} alt="" loading="lazy" />
                ) : (
                  <span>{partner.photo_emoji || "✦"}</span>
                )}
                {partner.heha_pillar && <strong>{partner.heha_pillar}</strong>}
              </div>

              <div className="directory-card-body">
                <p className="directory-meta">{[partner.category, partner.business_type].filter(Boolean).join(" · ")}</p>
                <h2>{partner.name}</h2>
                <p className="directory-location">⌖ {locationLabel(partner)}</p>
                <p className="directory-summary">{summary(partner)}</p>

                {!!(partner.tags?.length || partner.offerings?.length) && (
                  <div className="directory-tags">
                    {[...(partner.tags || []), ...(partner.offerings || [])].slice(0, 4).map((tag) => <span key={`${partner.id}-${tag}`}>{tag}</span>)}
                  </div>
                )}

                <div className="directory-actions">
                  <a className="directory-primary" href={primaryUrl(partner)} target="_top">
                    {partner.primary_cta_label || (partner.primary_cta_destination === "local" ? "Explore Local" : "Discover Partner")}
                    <span>→</span>
                  </a>
                  {partner.primary_cta_destination === "local" && (
                    <a className="directory-secondary" href={secondaryUrl(partner)} target="_top">Discover in Swipe</a>
                  )}
                </div>
              </div>
            </article>
          ))}
        </section>
      )}

      {visibleCount < filtered.length && (
        <button className="load-more" type="button" onClick={() => setVisibleCount((count) => count + PAGE_SIZE)}>
          Load more partners
        </button>
      )}

      <footer className="embed-footer">
        <span>HEHA Local = food & ordering</span>
        <span>HEHA Swipe = discovery</span>
      </footer>
    </main>
  );
}
