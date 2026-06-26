import CTAButton from "./CTAButton";

const trustItems = [
  "Local-first",
  "Eco-conscious options",
  "Recurring care plans",
  "Salon + mobile support",
];

export default function HeroSection() {
  return (
    <section className="relative overflow-hidden">
      <div className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-orange/15 blur-3xl" />
      <div className="pointer-events-none absolute -left-20 top-40 h-64 w-64 rounded-full bg-moss/15 blur-3xl" />

      <div className="container-page relative pt-14 sm:pt-20">
        <div className="grid items-center gap-12 lg:grid-cols-[1.1fr_0.9fr]">
          <div>
            <span className="eyebrow mb-5">
              🐾 Tampa Bay · A HEHA Local concept
            </span>
            <h1 className="font-display text-4xl font-extrabold leading-[1.08] tracking-tight text-ink sm:text-5xl">
              Eco-conscious pet care, local grooming, and mobile convenience —
              all in one{" "}
              <span className="bg-gradient-to-r from-orange to-orange-deep bg-clip-text text-transparent">
                Tampa network.
              </span>
            </h1>
            <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted">
              Clean Paws, Clean Planet helps connect pet owners with trusted
              local grooming salons, mobile groomers, and pet-care partners.
            </p>

            <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
              <CTAButton href="/request" variant="primary">
                Request Pet Care
              </CTAButton>
              <CTAButton href="/partner" variant="moss">
                Become a Partner
              </CTAButton>
              <CTAButton href="/partners" variant="secondary">
                View Demo Partners
              </CTAButton>
            </div>

            <p className="mt-5 text-xs font-medium text-muted">
              🧪 Concept prototype for partnership validation — no live bookings
              or payments yet.
            </p>
          </div>

          {/* Visual placeholder card stack */}
          <div className="relative mx-auto hidden w-full max-w-sm lg:block">
            <div className="animate-floaty rounded-3xl border border-line bg-white p-5 shadow-card">
              <div className="flex h-40 items-center justify-center rounded-2xl bg-gradient-to-br from-orange/25 via-peach/50 to-orange-soft text-5xl">
                🐶
              </div>
              <div className="mt-4 flex items-center justify-between">
                <div>
                  <p className="font-display text-sm font-bold text-ink">
                    Salon or mobile?
                  </p>
                  <p className="text-xs text-muted">One request. Local match.</p>
                </div>
                <span className="rounded-full bg-moss-soft px-2.5 py-1 text-[11px] font-semibold text-moss-dark">
                  Eco-conscious
                </span>
              </div>
            </div>

            <div className="absolute -bottom-8 -left-6 w-44 rotate-[-6deg] rounded-2xl border border-line bg-white p-4 shadow-soft">
              <div className="flex h-20 items-center justify-center rounded-xl bg-gradient-to-br from-moss/25 to-moss-soft text-3xl">
                🚐
              </div>
              <p className="mt-2 text-xs font-semibold text-ink">
                Mobile partner
              </p>
              <p className="text-[11px] text-muted">Route-based coverage</p>
            </div>

            <div className="absolute -right-4 -top-6 w-40 rotate-[6deg] rounded-2xl border border-line bg-white p-4 shadow-soft">
              <div className="flex h-16 items-center justify-center rounded-xl bg-gradient-to-br from-peach/60 to-cream text-2xl">
                🌿
              </div>
              <p className="mt-2 text-xs font-semibold text-ink">Eco add-ons</p>
              <p className="text-[11px] text-muted">Partner-submitted</p>
            </div>
          </div>
        </div>

        {/* Trust strip */}
        <div className="mt-14 grid grid-cols-2 gap-3 rounded-3xl border border-line bg-white/70 p-4 sm:grid-cols-4 sm:gap-4">
          {trustItems.map((item) => (
            <div
              key={item}
              className="flex items-center justify-center gap-2 rounded-2xl bg-cream px-3 py-3 text-center text-sm font-semibold text-ink"
            >
              <span className="text-orange" aria-hidden>
                ✦
              </span>
              {item}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
