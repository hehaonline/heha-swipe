import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import StatusBadge from "@/components/StatusBadge";
import EcoDisclaimer from "@/components/EcoDisclaimer";
import CTAButton from "@/components/CTAButton";
import Section from "@/components/Section";
import { partners, getPartnerBySlug, type Partner } from "@/lib/mockData";

export function generateStaticParams() {
  return partners.map((p) => ({ slug: p.slug }));
}

export function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Metadata {
  const partner = getPartnerBySlug(params.slug);
  if (!partner) return { title: "Partner not found" };
  return {
    title: `${partner.name} — Demo profile`,
    description: partner.tagline,
  };
}

const accentGradients: Record<Partner["accent"], string> = {
  orange: "from-orange/30 via-peach/50 to-orange-soft",
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

export default function PartnerDetailPage({
  params,
}: {
  params: { slug: string };
}) {
  const partner = getPartnerBySlug(params.slug);
  if (!partner) notFound();

  return (
    <div>
      {/* Hero */}
      <div
        className={`relative overflow-hidden border-b border-line bg-gradient-to-br ${accentGradients[partner.accent]}`}
      >
        <div className="container-page py-12 sm:py-16">
          <Link
            href="/partners"
            className="inline-flex items-center gap-1.5 text-sm font-semibold text-ink/70 transition hover:text-ink"
          >
            ← All demo partners
          </Link>
          <div className="mt-6 flex flex-col gap-6 sm:flex-row sm:items-center">
            <span className="flex h-24 w-24 flex-shrink-0 items-center justify-center rounded-3xl bg-white/80 text-5xl shadow-soft">
              {accentEmoji[partner.category]}
            </span>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-orange-deep">
                  {partner.category}
                </span>
                <StatusBadge status={partner.status} />
              </div>
              <h1 className="mt-3 font-display text-3xl font-extrabold leading-tight text-ink sm:text-4xl">
                {partner.name}
              </h1>
              <p className="mt-2 text-base text-ink/70">📍 {partner.serviceArea}</p>
            </div>
          </div>
          <div className="mt-4 inline-flex rounded-full bg-white/70 px-3 py-1.5 text-xs font-medium text-ink/70">
            🧪 Demo profile · built from mock data · not an official partnership
          </div>
        </div>
      </div>

      <div className="container-page py-12 sm:py-16">
        <div className="grid gap-10 lg:grid-cols-[1.6fr_1fr]">
          {/* Main */}
          <div className="space-y-10">
            <section>
              <h2 className="font-display text-xl font-bold text-ink">
                About this partner concept
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                {partner.description}
              </p>
            </section>

            <section>
              <h2 className="font-display text-xl font-bold text-ink">
                Services
              </h2>
              <div className="mt-4 flex flex-wrap gap-2">
                {partner.services.map((s) => (
                  <span
                    key={s}
                    className="rounded-full border border-line bg-white px-3.5 py-2 text-sm font-medium text-ink"
                  >
                    {s}
                  </span>
                ))}
              </div>
            </section>

            <section>
              <h2 className="font-display text-xl font-bold text-ink">
                🌿 Eco-conscious practices
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                {partner.ecoNotes}
              </p>
              <EcoDisclaimer variant="compact" className="mt-3" />
            </section>

            <section>
              <h2 className="font-display text-xl font-bold text-ink">
                Referral fit
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                {partner.referralFit}
              </p>
            </section>

            <section>
              <h2 className="font-display text-xl font-bold text-ink">
                Example customer journey
              </h2>
              <ol className="mt-4 space-y-3">
                {partner.customerJourney.map((step, i) => (
                  <li key={i} className="flex gap-3">
                    <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-orange text-xs font-bold text-white">
                      {i + 1}
                    </span>
                    <p className="pt-0.5 text-sm leading-relaxed text-muted">
                      {step}
                    </p>
                  </li>
                ))}
              </ol>
            </section>
          </div>

          {/* Sticky CTA */}
          <aside className="lg:sticky lg:top-24 lg:h-fit">
            <div className="card-soft p-6">
              <h3 className="font-display text-lg font-bold text-ink">
                Interested in this partner?
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-muted">
                In the real pilot, HEHA Local would coordinate the connection and
                confirm availability before anything is booked.
              </p>
              <div className="mt-5 flex flex-col gap-3">
                <CTAButton href="/request" variant="primary" fullWidth>
                  Request care from this partner
                </CTAButton>
                <CTAButton href="/partner" variant="moss" fullWidth>
                  Invite this partner to join
                </CTAButton>
              </div>
              <p className="mt-4 text-center text-xs text-muted">
                Demo only — no live booking is created.
              </p>
            </div>
          </aside>
        </div>
      </div>

      {/* Other partners */}
      <Section tone="sand">
        <h2 className="font-display text-xl font-bold text-ink">
          Other demo partners
        </h2>
        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {partners
            .filter((p) => p.slug !== partner.slug)
            .slice(0, 3)
            .map((p) => (
              <Link
                key={p.slug}
                href={`/partners/${p.slug}`}
                className="flex items-center gap-3 rounded-2xl border border-line bg-white p-4 transition hover:border-orange/40 hover:shadow-soft"
              >
                <span className="flex h-12 w-12 items-center justify-center rounded-xl bg-cream text-2xl">
                  {accentEmoji[p.category]}
                </span>
                <div>
                  <p className="text-sm font-bold text-ink">{p.name}</p>
                  <p className="text-xs text-muted">{p.category}</p>
                </div>
              </Link>
            ))}
        </div>
      </Section>
    </div>
  );
}
