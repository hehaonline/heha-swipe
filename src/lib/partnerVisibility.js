import {
  PARTNER_DESTINATIONS,
  supportsHehaLocal,
} from "./partnerPublicationConsent.js";
import { hasSpecificHehaLocalDestination } from "./hehaLocalRouting.js";

const PUBLIC_LISTING_STATUSES = new Set(["approved", "live"]);

function partnerCategories(partner) {
  if (Array.isArray(partner?.categories) && partner.categories.length) {
    return partner.categories;
  }
  return partner?.category ? [partner.category] : [];
}

export function partnerSurfaceVisibility(partner, publicationStatus) {
  const status = String(partner?.status || "").toLowerCase();
  const baseVisible = PUBLIC_LISTING_STATUSES.has(status);
  const wave1FoodPartner = supportsHehaLocal(partnerCategories(partner));
  const publicationDestinations = new Set(
    Array.isArray(publicationStatus?.publication_destinations)
      ? publicationStatus.publication_destinations
      : []
  );

  const swipeVisible = baseVisible
    && partner?.swipe_eligible === true
    && (
      !wave1FoodPartner
      || publicationDestinations.has(PARTNER_DESTINATIONS.swipe)
    );

  const localVisible = baseVisible
    && wave1FoodPartner
    && partner?.local_eligible === true
    && publicationDestinations.has(PARTNER_DESTINATIONS.local)
    && hasSpecificHehaLocalDestination(partner);

  return { swipeVisible, localVisible };
}
