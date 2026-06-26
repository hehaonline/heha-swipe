import Link from "next/link";
import type { Partner } from "@/lib/mockData";
import StatusBadge from "./StatusBadge";

const accentGradients: Record<Partner["accent"], string> = {
  orange: "from-orange/25 via-peach/40 to-orange-soft",
  moss: "from-moss/25 via-moss-soft to-moss-soft",
  peach: "from-peach/60 via-orange-soft to-cream",
};

const accentEmoji: Record<Partner["category"], string> = {
  "Salon Grooming Anchor": "🛁",
  "Mobile Groomer": "🚐",
  "Dog Walker": "🦮",
  "Pet Sitter": "🏠",
  "Eco Pet Product Vendor": "🌿",
};

export default function PartnerCard({ partner }: { partner: Partner }) {
  return (
    <Link
      href={`/partners/${partner.slug}`}
      className="group flex h-full flex-col overflow-hidden rounded-3xl border border-line bg-white shadow-soft transition hover:-translate-y-1 hover:shadow-card"
    >
      <div
        className={`relative flex h-32 items-center justify-center bg-gradient-to-br ${accentGradients[partner.accent]}`}
      >
        <span className="text-4xl" aria-hidden>
          {accentEmoji[partner.category]}
        </span>
        <div className="absolute left-3 top-3">
          <StatusBadge status={partner.status} />
        </div>
      </div>

      <div className="flex flex-1 flex-col p-5">
        <p className="text-xs font-semibold uppercase tracking-[0.14em] text-orange-deep">
          {partner.category}
        </p>
        <h3 className="mt-1.5 font-display text-lg font-bold leading-tight text-ink">
          {partner.name}
        </h3>
        <p className="mt-1 text-sm text-muted">📍 {partner.serviceArea}</p>

        <p className="mt-3 line-clamp-2 text-sm leading-relaxed text-muted">
          {partner.tagline}
        </p>

        <div className="mt-4 flex flex-wrap gap-1.5">
          {partner.services.slice(0, 3).map((s) => (
            <span
              key={s}
              className="rounded-full bg-cream px-2.5 py-1 text-[11px] font-medium text-ink"
            >
              {s}
            </span>
          ))}
          {partner.services.length > 3 && (
            <span className="rounded-full bg-cream px-2.5 py-1 text-[11px] font-medium text-muted">
              +{partner.services.length - 3} more
            </span>
          )}
        </div>

        <p className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-orange-deep transition group-hover:gap-2">
          View partner concept <span aria-hidden>→</span>
        </p>
      </div>
    </Link>
  );
}
