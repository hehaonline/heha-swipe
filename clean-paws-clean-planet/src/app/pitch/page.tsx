import type { Metadata } from "next";
import Section, { SectionHeading } from "@/components/Section";
import CTAButton from "@/components/CTAButton";
import EcoDisclaimer from "@/components/EcoDisclaimer";

export const metadata: Metadata = {
  title: "Partner Pitch — Clean Paws, Clean Planet",
  description:
    "The opportunity, the pilot plan, and how local referrals could work for grooming salons and mobile groomers in Tampa Bay.",
};

const pitchBlocks = [
  {
    icon: "🌎",
    title: "The opportunity",
    body: "Tampa pet owners juggle multiple providers for grooming, mobile visits, walks, and sitting. There's no simple, local, eco-conscious way to request pet care and get matched to a trusted provider. That gap is the opportunity: a community-first referral network that sends the right pet owners to the right local pros.",
  },
  {
    icon: "🐾",
    title: "What we are building",
    body: "Clean Paws, Clean Planet is a local pet-care referral network. Pet owners submit one request; HEHA Local reviews it and connects them with an approved salon or mobile partner. We're starting with referrals and partnership validation before building a full marketplace.",
  },
  {
    icon: "🛁",
    title: "Why grooming salons benefit",
    body: "A salon can be positioned as the trusted in-person anchor for customers who prefer a salon and recurring care. That means qualified referral leads, fill for slower weekdays, and optional recurring full-groom customers — without paying for ads or building your own booking tech.",
  },
  {
    icon: "🚐",
    title: "Why mobile groomers benefit",
    body: "Mobile partners get route-based appointment opportunities. Requests can be grouped by neighborhood and ZIP code into efficient routes, lowering drive time and helping you serve more pets per day — including anxious pets and busy households that prefer curbside.",
  },
  {
    icon: "🔁",
    title: "How referrals would work",
    body: "A pet owner submits a request. HEHA Local reviews it and suggests a fitting partner — salon first for in-person preference, mobile for convenience or coverage. The partner confirms availability, care happens, and customers can opt into recurring support. Simple, manual, and transparent to start.",
  },
];

const needFromPartners = [
  "Your services, service area, and rough starting prices",
  "Whether you'd accept referral leads (yes / no / maybe)",
  "Whether you'd try a free, no-commitment pilot",
  "Any eco-conscious practices you'd like noted (self-reported)",
];

const hehaHandles = [
  "Building and maintaining the landing page and intake forms",
  "Reviewing requests and matching them to suitable partners",
  "Coordinating the initial connection between owner and partner",
  "Keeping copy honest, local, and community-first",
  "Reviewing partners before any public listing or referral",
];

const futureApp = [
  "Partner dashboard with referral statuses",
  "Recurring care plans and reminders",
  "Route-batching tools for mobile partners",
  "Optional deposits via Stripe (later phase)",
  "HEHA Swipe-style local discovery",
];

const roadmap = [
  { phase: "Phase 1", label: "Partner interest + landing page" },
  { phase: "Phase 2", label: "Manual referrals + intake forms" },
  { phase: "Phase 3", label: "Partner dashboard + booking statuses" },
  { phase: "Phase 4", label: "Recurring care plans + Stripe deposits" },
  { phase: "Phase 5", label: "HEHA Swipe discovery + local pet marketplace" },
];

export default function PitchPage() {
  return (
    <div>
      {/* Hero */}
      <section className="border-b border-line bg-gradient-to-br from-orange-soft via-cream to-peach/30">
        <div className="container-page py-16 sm:py-20">
          <div className="max-w-3xl">
            <span className="eyebrow mb-4">Partner pitch</span>
            <h1 className="font-display text-4xl font-extrabold leading-[1.08] text-ink sm:text-5xl">
              A local, eco-conscious referral network for Tampa pet care
            </h1>
            <p className="mt-5 text-lg leading-relaxed text-muted">
              Built for grooming salons, mobile groomers, and local pet-care
              pros. This page walks through the opportunity, how referrals would
              work, and a simple pilot with no upfront commitment.
            </p>
            <div className="mt-7 flex flex-col gap-3 sm:flex-row">
              <CTAButton href="/partner" variant="primary">
                Express partner interest
              </CTAButton>
              <CTAButton href="/partners" variant="secondary">
                See the demo network
              </CTAButton>
            </div>
          </div>
        </div>
      </section>

      {/* Pitch blocks */}
      <Section>
        <div className="grid gap-5 lg:grid-cols-2">
          {pitchBlocks.map((b) => (
            <div
              key={b.title}
              className="rounded-3xl border border-line bg-white p-7 shadow-soft"
            >
              <span className="text-3xl">{b.icon}</span>
              <h2 className="mt-3 font-display text-xl font-bold text-ink">
                {b.title}
              </h2>
              <p className="mt-2 leading-relaxed text-muted">{b.body}</p>
            </div>
          ))}
        </div>
      </Section>

      {/* Pilot plan + no commitment */}
      <Section tone="moss">
        <div className="grid gap-8 lg:grid-cols-2">
          <div className="rounded-3xl border border-line bg-white p-7 shadow-soft">
            <span className="eyebrow mb-3">The pilot plan</span>
            <h2 className="font-display text-2xl font-extrabold text-ink">
              Start small, prove value, then grow
            </h2>
            <ol className="mt-5 space-y-3">
              {[
                "Confirm a handful of local partners interested in referrals.",
                "Collect real pet-owner requests through the intake form.",
                "HEHA Local manually matches and connects, partner confirms.",
                "Review what worked, then expand coverage and add tooling.",
              ].map((s, i) => (
                <li key={i} className="flex gap-3">
                  <span className="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-moss text-xs font-bold text-white">
                    {i + 1}
                  </span>
                  <p className="pt-0.5 text-sm leading-relaxed text-muted">
                    {s}
                  </p>
                </li>
              ))}
            </ol>
          </div>

          <div className="rounded-3xl border border-orange/20 bg-orange-soft p-7">
            <span className="text-3xl">🤝</span>
            <h2 className="mt-3 font-display text-2xl font-extrabold text-ink">
              No upfront commitment required
            </h2>
            <p className="mt-3 leading-relaxed text-orange-deep/90">
              The pilot is free to try. No contracts, no setup fees, no
              obligation to accept any specific referral. The goal is simply to
              validate whether local, eco-conscious referrals create real value
              for your business — before anyone builds a bigger platform.
            </p>
            <div className="mt-6">
              <CTAButton href="/partner" variant="primary">
                Join the free pilot
              </CTAButton>
            </div>
          </div>
        </div>
      </Section>

      {/* What we need / what HEHA handles */}
      <Section>
        <div className="grid gap-8 lg:grid-cols-2">
          <div>
            <SectionHeading
              eyebrow="What we need from partners"
              title="Just a few simple things"
            />
            <ul className="mt-6 space-y-3">
              {needFromPartners.map((item) => (
                <li
                  key={item}
                  className="flex items-start gap-3 rounded-2xl border border-line bg-white p-4"
                >
                  <span className="text-orange">✔</span>
                  <span className="text-sm text-ink">{item}</span>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <SectionHeading
              eyebrow="What HEHA Local handles"
              title="We do the coordination"
            />
            <ul className="mt-6 space-y-3">
              {hehaHandles.map((item) => (
                <li
                  key={item}
                  className="flex items-start gap-3 rounded-2xl border border-line bg-white p-4"
                >
                  <span className="text-moss">✔</span>
                  <span className="text-sm text-ink">{item}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </Section>

      {/* Roadmap visual */}
      <Section tone="sand">
        <SectionHeading
          eyebrow="Visual roadmap"
          title="Where this could go"
          subtitle="A phased plan that adds tooling only as trust and demand are proven."
        />
        <div className="mt-10 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {roadmap.map((r, i) => (
            <div key={r.phase} className="relative">
              <div
                className={`h-full rounded-2xl border p-5 ${
                  i === 0
                    ? "border-orange bg-white shadow-soft"
                    : "border-line bg-white/70"
                }`}
              >
                <span
                  className={`text-xs font-bold uppercase tracking-wide ${
                    i === 0 ? "text-orange-deep" : "text-muted"
                  }`}
                >
                  {r.phase}
                </span>
                <p className="mt-2 text-sm font-medium leading-snug text-ink">
                  {r.label}
                </p>
                {i === 0 && (
                  <span className="mt-3 inline-block rounded-full bg-orange px-2.5 py-0.5 text-[11px] font-semibold text-white">
                    You are here
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      </Section>

      {/* Future app */}
      <Section>
        <div className="grid items-start gap-8 lg:grid-cols-[1fr_1.2fr]">
          <SectionHeading
            eyebrow="What the future app could include"
            title="From referrals to a full local pet-care platform"
            subtitle="None of this is built yet — it's the direction the prototype points toward."
          />
          <div className="grid gap-3 sm:grid-cols-2">
            {futureApp.map((f) => (
              <div
                key={f}
                className="rounded-2xl border border-line bg-white p-4 text-sm font-medium text-ink"
              >
                ✨ {f}
              </div>
            ))}
          </div>
        </div>
        <div className="mt-10">
          <EcoDisclaimer />
        </div>
      </Section>

      {/* CTA */}
      <Section>
        <div className="overflow-hidden rounded-3xl bg-gradient-to-br from-orange via-orange-bright to-orange-deep px-6 py-12 text-center text-white shadow-card sm:px-12">
          <h2 className="mx-auto max-w-2xl font-display text-3xl font-extrabold sm:text-4xl">
            Want to be one of the first local partners?
          </h2>
          <p className="mx-auto mt-3 max-w-xl text-white/90">
            Express interest in a few minutes. No commitment — just a
            conversation about whether this fits your business.
          </p>
          <div className="mt-7 flex justify-center">
            <CTAButton href="/partner" variant="secondary" className="!bg-white">
              Become a Partner
            </CTAButton>
          </div>
        </div>
      </Section>
    </div>
  );
}
