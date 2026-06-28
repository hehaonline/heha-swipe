// Internal / status taxonomy that must never render as a public chip on a
// business card (the card already shows a single status badge). Shared by the
// discover card and the saved detail so the filter stays consistent.
export const INTERNAL_TAGS = new Set([
  "certified", "heha-certified", "heha certified", "heha-reviewed", "heha reviewed",
  "approved", "approved-partner", "approved partner", "listed", "heha-listed",
  "verified", "heha-verified", "heha", "heha-partner", "partner",
  "crm", "crm-seed", "crm seed", "seed", "internal",
]);

// Generic category/taxonomy slugs that just duplicate the card's category/status
// label — hide them as chips (the category chip already conveys this).
const GENERIC_CATEGORY_TAGS = new Set([
  "event", "events", "market", "markets", "restaurant", "restaurants",
  "vendor", "vendors", "wellness", "coach", "coaches", "service", "services",
  "catering", "private chef", "senior", "facility", "senior & facility",
  "senior and facility", "heha market",
]);

export function filterPublicTags(rawTags = []) {
  return rawTags
    .filter(Boolean)
    .map((tag) => String(tag).trim())
    .filter((tag) => {
      const key = tag.toLowerCase();
      if (!key) return false;
      // Hide all CRM/import pipeline tags (crm, crm-import, crm-seed, crm-*) and bare "import".
      if (key.startsWith("crm")) return false;
      if (key === "import") return false;
      if (GENERIC_CATEGORY_TAGS.has(key)) return false;
      return !INTERNAL_TAGS.has(key);
    });
}
