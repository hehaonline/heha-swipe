import type { Metadata } from "next";
import Section, { SectionHeading } from "@/components/Section";
import RoadmapTimeline from "@/components/RoadmapTimeline";
import CTAButton from "@/components/CTAButton";
import { roadmapPhases } from "@/lib/mockData";

export const metadata: Metadata = {
  title: "Roadmap — Clean Paws, Clean Planet",
  description:
    "The build roadmap for Clean Paws, Clean Planet — from prototype to pilot, MVP, marketplace, and HEHA Swipe discovery.",
};

const buildStages = [
  { icon: "🧪", title: "Prototype", detail: "This pitch site: concept, intake forms, and demo network.", state: "Now" },
  { icon: "🚀", title: "Pilot", detail: "A handful of real partners and manual referrals in one area.", state: "Next" },
  { icon: "🛠️", title: "MVP", detail: "Partner dashboard, request statuses, and basic coordination tools.", state: "Later" },
  { icon: "🏪", title: "Marketplace", detail: "Broader local pet-care marketplace with more categories.", state: "Later" },
  { icon: "✨", title: "HEHA Swipe discovery", detail: "Discovery-style browsing connected to the wider HEHA ecosystem.", state: "Later" },
  { icon: "📊", title: "Partner analytics", detail: "Referral volume, conversion, and recurring-customer insights.", state: "Later" },
  { icon: "🗺️", title: "Route batching", detail: "Tools that group mobile visits by neighborhood and ZIP.", state: "Later" },
  { icon: "💳", title: "Stripe payments", detail: "Optional deposits and payments, added once trust is proven.", state: "Later" },
  { icon: "🔁", title: "Recurring memberships", detail: "Recurring care plans and membership-style support.", state: "Later" },
];

const notIncluded = [
  "Live booking calendar",
  "Real partner payouts",
  "Stripe Connect",
  "Vet / medical services",
  "Automated dispatch",
  "Legal certification",
  "Verified eco badge",
];

const stateStyle: Record<string, string> = {
  Now: "bg-orange text-white",
  Next: "bg-moss text-white",
  Later: "bg-white text-muted border border-line",
};

export default function RoadmapPage() {
  return (
    <div>
      <section className="border-b border-line bg-gradient-to-br from-cream to-sand/60">
        <div className="container-page py-14 sm:py-20">
          <div className="max-w-2xl">
            <span className="eyebrow mb-4">Product roadmap</span>
            <h1 className="font-display text-4xl font-extrabold leading-[1.1] text-ink sm:text-5xl">
              How Clean Paws, Clean Planet gets built
            </h1>
            <p className="mt-4 text-lg leading-relaxed text-muted">
              A transparent, phased plan. We add capability only as trust and
              demand are proven — starting with referrals, not a full
              marketplace.
            </p>
          </div>
        </div>
      </section>

      {/* Phase timeline */}
      <Section>
        <SectionHeading
          eyebrow="Phased rollout"
          title="The five phases"
          subtitle="Each phase builds on validated demand from the one before it."
        />
        <div className="mt-10 max-w-2xl">
          <RoadmapTimeline phases={roadmapPhases} />
        </div>
      </Section>

      {/* Build stages grid */}
      <Section tone="sand">
        <SectionHeading
          eyebrow="The bigger picture"
          title="From prototype to platform"
        />
        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {buildStages.map((s) => (
            <div
              key={s.title}
              className="rounded-2xl border border-line bg-white p-5 shadow-soft"
            >
              <div className="flex items-center justify-between">
                <span className="text-2xl">{s.icon}</span>
                <span
                  className={`rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${stateStyle[s.state]}`}
                >
                  {s.state}
                </span>
              </div>
              <h3 className="mt-3 font-display font-bold text-ink">{s.title}</h3>
              <p className="mt-1.5 text-sm leading-relaxed text-muted">
                {s.detail}
              </p>
            </div>
          ))}
        </div>
      </Section>

      {/* Not included */}
      <Section>
        <div className="rounded-3xl border border-line bg-white p-7 shadow-soft sm:p-10">
          <span className="eyebrow mb-3">Scope & honesty</span>
          <h2 className="font-display text-2xl font-extrabold text-ink sm:text-3xl">
            Not included in this prototype yet
          </h2>
          <p className="mt-3 max-w-2xl text-muted">
            We&apos;re being upfront about what this demo intentionally does
            <em> not</em> do. These require real operational, legal, or payment
            infrastructure that comes in later phases.
          </p>
          <div className="mt-6 flex flex-wrap gap-2.5">
            {notIncluded.map((item) => (
              <span
                key={item}
                className="inline-flex items-center gap-2 rounded-full border border-line bg-cream px-4 py-2 text-sm font-medium text-muted"
              >
                <span className="text-rose-400">✕</span>
                {item}
              </span>
            ))}
          </div>
        </div>
      </Section>

      {/* CTA */}
      <Section tone="moss">
        <div className="text-center">
          <h2 className="mx-auto max-w-2xl font-display text-2xl font-extrabold text-ink sm:text-3xl">
            Want to help shape what gets built next?
          </h2>
          <p className="mx-auto mt-3 max-w-xl text-muted">
            Partner interest and pet-owner requests directly inform which phase
            we build toward first.
          </p>
          <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
            <CTAButton href="/partner" variant="moss">
              Become a Partner
            </CTAButton>
            <CTAButton href="/request" variant="secondary">
              Request Pet Care
            </CTAButton>
          </div>
        </div>
      </Section>
    </div>
  );
}
