import { PARTNER_DESTINATIONS } from "./partnerPublicationConsent.js";

export function partnerSurfaceVisibility(partner, publicationStatus) {
  // The server resolves owner consent, exact staff review, listing state, and
  // each final public view. Never reconstruct that security decision from a
  // raw partner row or owner consent alone: doing so could tell an owner that a
  // profile is live while the reviewed public projection correctly hides it.
  void partner;
  const publicDestinations = new Set(
    Array.isArray(publicationStatus?.public_destinations)
      ? publicationStatus.public_destinations
      : []
  );

  return {
    swipeVisible: publicDestinations.has(PARTNER_DESTINATIONS.swipe),
    localVisible: publicDestinations.has(PARTNER_DESTINATIONS.local),
  };
}
