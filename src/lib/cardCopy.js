// Display-only helpers for partner cards. These do NOT modify any data — they
// just decide what is safe/useful to render publicly.

// Internal placeholder values that should never render as a real description
// (they are status strings, not descriptions). Compared case-insensitively.
const PLACEHOLDER_DESCRIPTIONS = new Set([
  "listed on heha swipe",
  "listed on heha",
]);

// Returns the partner's public description (tagline, else bio), or "" when the
// only text is an internal placeholder. Callers should render nothing when "".
export function publicDescription(partner) {
  const text = String(partner?.tagline || partner?.bio || "").trim();
  if (!text) return "";
  if (PLACEHOLDER_DESCRIPTIONS.has(text.toLowerCase())) return "";
  return text;
}

// Inline style to let a card name wrap to 2 lines instead of hard-truncating.
export const TWO_LINE_CLAMP = {
  display: "-webkit-box",
  WebkitLineClamp: 2,
  WebkitBoxOrient: "vertical",
  overflow: "hidden",
};
