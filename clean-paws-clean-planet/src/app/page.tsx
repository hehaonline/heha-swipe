import HeroSection from "@/components/HeroSection";
import Section, { SectionHeading } from "@/components/Section";
import ServiceCard from "@/components/ServiceCard";
import PartnerCard from "@/components/PartnerCard";
import PartnerBenefitCard from "@/components/PartnerBenefitCard";
import EcoDisclaimer from "@/components/EcoDisclaimer";
import CTAButton from "@/components/CTAButton";
import {
  services,
  partners,
  partnerBenefits,
  customerBenefits,
  testimonials,
} from "@/lib/mockData";

const howItWorks = [
  {
    step: "1",
    title: "Pet owner submits a request",
    detail:
      "One simple form captures your pet, your preferences, and salon or mobile choice.",
  },
  {
    step: "2",
    title: "HEHA Local reviews the request",
    detail:
      "We review details and match you with a suitable local, eco-conscious partner.",
  },
  {
    step: "3",
    title: "A local partner confirms availability",
    detail:
      "An approved salon or mobile partner confirms a time that works for you.",
  },
  {
    step: "4",
    title: "Care happens — join recurring support",
    detail:
      "Get great care and optionally set up a recurring plan for steady upkeep.",
  },
];

export default function HomePage() {
  return (
    <>
      <HeroSection />

      {/* How it works */}
      <Section id="how-it-works" tone="sand">
        <SectionHeading
          eyebrow="How it works"
          title="One request, coordinated locally"
          subtitle="No more calling around town. Tell us about your pet once and HEHA Local helps connect you with the right local partner."
        />
        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {howItWorks.map((item) => (
            <div
              key={item.step}
              className="relative rounded-2xl border border-line bg-white p-6 shadow-soft"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-full bg-orange text-base font-bold text-white">
                {item.step}
              </span>
              <h3 className="mt-4 font-display text-base font-bold text-ink">
                {item.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-muted">
                {item.detail}
              </p>
            </div>
          ))}
        </div>
      </Section>

      {/* Service categories */}
      <Section id="services">
        <SectionHeading
          eyebrow="Service categories"
          title="Grooming and pet care, all in one place"
          subtitle="From a full salon groom to a curbside mobile visit, a neighborhood walk, or eco-conscious add-ons."
        />
        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {services.map((service) => (
            <ServiceCard key={service.slug} service={service} />
          ))}
        </div>
      </Section>

      {/* Anchor partner section */}
      <Section tone="cream">
        <div className="grid items-center gap-10 lg:grid-cols-2">
          <div>
            <span className="eyebrow mb-4">Salon anchor + mobile coverage</span>
            <h2 className="font-display text-3xl font-extrabold leading-tight text-ink sm:text-4xl">
              A trusted salon anchor, supported by mobile convenience
            </h2>
            <p className="mt-4 text-base leading-relaxed text-muted">
              A well-loved grooming salon can be positioned as the trusted salon
              anchor for customers who prefer in-person grooming and recurring
              care. Mobile partners then extend convenience and neighborhood
              coverage across more ZIP codes.
            </p>
            <p className="mt-3 text-base leading-relaxed text-muted">
              Together, a salon anchor plus mobile partners can cover more of
              Tampa Bay than either could alone — that&apos;s the core of the
              referral network.
            </p>
            <div className="mt-6 rounded-2xl border border-orange/20 bg-orange-soft px-4 py-3 text-sm text-orange-deep">
              ℹ️ Demo note: salon and partner names shown in this prototype are
              illustrative. No partnership has been agreed, including with any
              salon shown as a concept.
            </div>
            <div className="mt-6">
              <CTAButton href="/partners" variant="primary">
                See the demo partner network
              </CTAButton>
            </div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="rounded-3xl border border-line bg-white p-6 shadow-soft">
              <span className="text-3xl">🛁</span>
              <h3 className="mt-3 font-display font-bold text-ink">
                Salon anchor
              </h3>
              <p className="mt-1.5 text-sm text-muted">
                In-person grooming, recurring full grooms, and a trusted home
                base for customers who prefer a salon.
              </p>
            </div>
            <div className="mt-0 rounded-3xl border border-line bg-white p-6 shadow-soft sm:mt-8">
              <span className="text-3xl">🚐</span>
              <h3 className="mt-3 font-display font-bold text-ink">
                Mobile partners
              </h3>
              <p className="mt-1.5 text-sm text-muted">
                Curbside convenience, route-based coverage, and support for
                anxious pets or busy households.
              </p>
            </div>
          </div>
        </div>
      </Section>

      {/* Eco-conscious care */}
      <Section id="eco" tone="moss">
        <div className="grid items-start gap-10 lg:grid-cols-[1fr_1.1fr]">
          <div>
            <span className="eyebrow mb-4">🌿 Eco-conscious care</span>
            <h2 className="font-display text-3xl font-extrabold leading-tight text-ink sm:text-4xl">
              Local care that&apos;s mindful of waste — and honest about it
            </h2>
            <p className="mt-4 text-base leading-relaxed text-muted">
              Participating partners can share product practices, low-waste
              efforts, route-batching availability, and pet-safe care
              preferences. We highlight eco-conscious options without
              overstating them.
            </p>
          </div>
          <div className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              {[
                { icon: "♻️", t: "Low-waste efforts", d: "Refillable supplies and reduced single-use where partners choose to." },
                { icon: "🗺️", t: "Route-batching", d: "Mobile partners can group nearby visits to cut drive time." },
                { icon: "🧴", t: "Product practices", d: "Partners can share pet-safe, low-waste product preferences." },
                { icon: "🐾", t: "Pet-safe care", d: "Care preferences captured up front for each pet." },
              ].map((c) => (
                <div
                  key={c.t}
                  className="rounded-2xl border border-line bg-white p-5"
                >
                  <span className="text-2xl">{c.icon}</span>
                  <h3 className="mt-2 font-display text-sm font-bold text-ink">
                    {c.t}
                  </h3>
                  <p className="mt-1 text-sm text-muted">{c.d}</p>
                </div>
              ))}
            </div>
            <EcoDisclaimer />
          </div>
        </div>
      </Section>

      {/* Featured demo partners */}
      <Section>
        <div className="flex flex-wrap items-end justify-between gap-4">
          <SectionHeading
            eyebrow="Demo partner network"
            title="A preview of the local network"
            subtitle="Demo profiles that show how the network could come together across Tampa Bay."
          />
          <CTAButton href="/partners" variant="secondary">
            View all demo partners
          </CTAButton>
        </div>
        <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {partners.slice(0, 3).map((partner) => (
            <PartnerCard key={partner.slug} partner={partner} />
          ))}
        </div>
      </Section>

      {/* Benefits split */}
      <Section tone="sand">
        <div className="grid gap-10 lg:grid-cols-2">
          <div>
            <span className="eyebrow mb-4">For partners</span>
            <h2 className="font-display text-2xl font-extrabold text-ink sm:text-3xl">
              Why partners join
            </h2>
            <div className="mt-6 space-y-3">
              {partnerBenefits.map((b) => (
                <PartnerBenefitCard key={b.title} benefit={b} />
              ))}
            </div>
            <div className="mt-6">
              <CTAButton href="/partner" variant="moss">
                Become a Partner
              </CTAButton>
            </div>
          </div>
          <div>
            <span className="eyebrow mb-4">For pet owners</span>
            <h2 className="font-display text-2xl font-extrabold text-ink sm:text-3xl">
              Why pet owners love it
            </h2>
            <div className="mt-6 space-y-3">
              {customerBenefits.map((b) => (
                <PartnerBenefitCard key={b.title} benefit={b} tone="moss" />
              ))}
            </div>
            <div className="mt-6">
              <CTAButton href="/request" variant="primary">
                Request Pet Care
              </CTAButton>
            </div>
          </div>
        </div>
      </Section>

      {/* Testimonials */}
      <Section>
        <SectionHeading
          eyebrow="Illustrative quotes"
          title="How it could feel"
          subtitle="Placeholder quotes that illustrate the concept — not real endorsements."
          align="center"
        />
        <div className="mt-10 grid gap-5 sm:grid-cols-3">
          {testimonials.map((t) => (
            <figure
              key={t.role}
              className="flex h-full flex-col rounded-3xl border border-line bg-white p-6 shadow-soft"
            >
              <span className="text-3xl text-orange">&ldquo;</span>
              <blockquote className="mt-2 flex-1 text-sm leading-relaxed text-ink">
                {t.quote}
              </blockquote>
              <figcaption className="mt-4 border-t border-line pt-4">
                <p className="text-sm font-semibold text-ink">
                  {t.attribution}
                </p>
                <p className="text-xs text-muted">{t.role}</p>
              </figcaption>
            </figure>
          ))}
        </div>
      </Section>

      {/* CTA footer band */}
      <Section>
        <div className="overflow-hidden rounded-3xl border border-orange/20 bg-gradient-to-br from-orange via-orange-bright to-orange-deep px-6 py-12 text-center text-white shadow-card sm:px-12 sm:py-16">
          <h2 className="mx-auto max-w-2xl font-display text-3xl font-extrabold leading-tight sm:text-4xl">
            Let&apos;s build a cleaner, more local way to care for Tampa&apos;s
            pets
          </h2>
          <p className="mx-auto mt-4 max-w-xl text-base text-white/90">
            Whether you&apos;re a pet owner or a local pet-care pro, this
            prototype shows where Clean Paws, Clean Planet could go.
          </p>
          <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
            <CTAButton
              href="/request"
              variant="secondary"
              className="!bg-white"
            >
              Request Pet Care
            </CTAButton>
            <CTAButton
              href="/partner"
              variant="ghost"
              className="!bg-white/15 !text-white hover:!bg-white/25"
            >
              Become a Partner
            </CTAButton>
            <CTAButton
              href="/pitch"
              variant="ghost"
              className="!bg-white/15 !text-white hover:!bg-white/25"
            >
              See the partner pitch
            </CTAButton>
          </div>
        </div>
      </Section>
    </>
  );
}
