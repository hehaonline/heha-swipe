"use client";

import { useState } from "react";
import DemoFormSuccess from "@/components/DemoFormSuccess";
import PartnerBenefitCard from "@/components/PartnerBenefitCard";
import EcoDisclaimer from "@/components/EcoDisclaimer";
import { partnerTypeOptions, serviceOptions, partnerBenefits } from "@/lib/mockData";

const partnerTypeCards = [
  { icon: "🛁", title: "Grooming salon", detail: "In-person grooming and recurring care." },
  { icon: "🚐", title: "Mobile groomer", detail: "Curbside, route-based grooming." },
  { icon: "🦮", title: "Dog walker", detail: "Scheduled walks and check-ins." },
  { icon: "🏠", title: "Pet sitter", detail: "In-home sitting and comfort visits." },
  { icon: "🌿", title: "Pet wellness / product vendor", detail: "Eco-conscious add-ons and products." },
  { icon: "🤝", title: "Referral partner", detail: "Send and receive local referrals." },
];

const yesNoMaybe = ["Yes", "No", "Maybe"];

export default function PartnerPage() {
  const [submitted, setSubmitted] = useState(false);
  const [selectedServices, setSelectedServices] = useState<string[]>([]);
  const [insuranceConfirmed, setInsuranceConfirmed] = useState(false);

  function toggleService(service: string) {
    setSelectedServices((prev) =>
      prev.includes(service)
        ? prev.filter((s) => s !== service)
        : [...prev, service],
    );
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSubmitted(true);
    if (typeof window !== "undefined") {
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  }

  function reset() {
    setSubmitted(false);
    setSelectedServices([]);
    setInsuranceConfirmed(false);
  }

  if (submitted) {
    return (
      <div className="container-page py-12 sm:py-16">
        <DemoFormSuccess
          title="Partner interest received 🤝"
          message="In a real pilot, HEHA Local would review your information before publishing your profile or sending any referrals. Thanks for helping validate the concept — we'll keep partners local, eco-conscious, and community-first."
          primaryHref="/pitch"
          primaryLabel="See the partner pitch"
          secondaryHref="/partners"
          secondaryLabel="View demo partners"
          onReset={reset}
          resetLabel="Submit another"
        />
      </div>
    );
  }

  return (
    <div>
      {/* Hero */}
      <section className="relative overflow-hidden border-b border-line bg-moss-soft/50">
        <div className="container-page py-14 sm:py-20">
          <div className="max-w-2xl">
            <span className="eyebrow mb-4">Become a partner</span>
            <h1 className="font-display text-4xl font-extrabold leading-[1.1] text-ink sm:text-5xl">
              Join the local eco pet-care network
            </h1>
            <p className="mt-4 text-lg leading-relaxed text-muted">
              For grooming salons, mobile groomers, dog walkers, pet sitters,
              eco pet-product vendors, and other local pet-care providers. Tell
              us about your business — HEHA Local reviews every partner before
              any public listing or referral.
            </p>
            <a
              href="#partner-form"
              className="mt-7 inline-flex items-center justify-center gap-2 rounded-full bg-moss px-6 py-3 text-sm font-semibold text-white shadow-soft transition hover:bg-moss-dark"
            >
              Express interest ↓
            </a>
          </div>
        </div>
      </section>

      {/* Partner types */}
      <div className="container-page py-14 sm:py-16">
        <h2 className="font-display text-2xl font-extrabold text-ink sm:text-3xl">
          Who can join
        </h2>
        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {partnerTypeCards.map((c) => (
            <div
              key={c.title}
              className="rounded-2xl border border-line bg-white p-5 shadow-soft"
            >
              <span className="text-3xl">{c.icon}</span>
              <h3 className="mt-3 font-display font-bold text-ink">{c.title}</h3>
              <p className="mt-1 text-sm text-muted">{c.detail}</p>
            </div>
          ))}
        </div>

        {/* Benefits */}
        <h2 className="mt-16 font-display text-2xl font-extrabold text-ink sm:text-3xl">
          What partners get
        </h2>
        <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {partnerBenefits.map((b) => (
            <PartnerBenefitCard key={b.title} benefit={b} />
          ))}
        </div>
      </div>

      {/* Form */}
      <div id="partner-form" className="bg-sand/40 py-14 sm:py-16">
        <div className="container-page">
          <div className="mx-auto max-w-3xl">
            <div className="text-center">
              <h2 className="font-display text-3xl font-extrabold text-ink sm:text-4xl">
                Partner interest form
              </h2>
              <p className="mx-auto mt-3 max-w-xl text-base text-muted">
                This is a demo form. Submitting shows a confirmation only —
                nothing is sent or stored in this prototype.
              </p>
            </div>

            <form onSubmit={handleSubmit} className="mt-10 space-y-6">
              <div className="card-soft p-6 sm:p-7">
                <h3 className="mb-5 font-display text-lg font-bold text-ink">
                  Business details
                </h3>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Business name" required>
                    <input className="input-field" name="businessName" required placeholder="BarkSuds Grooming" />
                  </Field>
                  <Field label="Contact name" required>
                    <input className="input-field" name="contactName" required placeholder="Owner / manager" />
                  </Field>
                  <Field label="Phone" required>
                    <input className="input-field" name="phone" type="tel" required placeholder="(813) 555-0123" />
                  </Field>
                  <Field label="Email" required>
                    <input className="input-field" name="email" type="email" required placeholder="hello@business.com" />
                  </Field>
                  <Field label="Website">
                    <input className="input-field" name="website" placeholder="https://" />
                  </Field>
                  <Field label="Instagram">
                    <input className="input-field" name="instagram" placeholder="@yourhandle" />
                  </Field>
                  <Field label="Partner type" required>
                    <select className="input-field" name="partnerType" required defaultValue="">
                      <option value="" disabled>Select…</option>
                      {partnerTypeOptions.map((t) => (
                        <option key={t}>{t}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Service area / ZIP codes" required>
                    <input className="input-field" name="serviceArea" required placeholder="33606, 33611, South Tampa" />
                  </Field>
                </div>
              </div>

              <div className="card-soft p-6 sm:p-7">
                <h3 className="mb-5 font-display text-lg font-bold text-ink">
                  Services & coverage
                </h3>
                <p className="label-field">Services offered (select any)</p>
                <div className="flex flex-wrap gap-2">
                  {serviceOptions.map((service) => {
                    const active = selectedServices.includes(service);
                    return (
                      <button
                        type="button"
                        key={service}
                        onClick={() => toggleService(service)}
                        aria-pressed={active}
                        className={`chip ${
                          active
                            ? "border-moss bg-moss text-white"
                            : "border-line bg-white text-ink hover:border-moss/50"
                        }`}
                      >
                        {service}
                      </button>
                    );
                  })}
                </div>

                <div className="mt-5 grid gap-4 sm:grid-cols-2">
                  <Field label="Starting prices">
                    <input className="input-field" name="startingPrices" placeholder="Full groom from $75" />
                  </Field>
                  <div />
                  <Field label="Mobile available?">
                    <select className="input-field" name="mobileAvailable" defaultValue="No">
                      <option>Yes</option>
                      <option>No</option>
                    </select>
                  </Field>
                  <Field label="Salon location?">
                    <select className="input-field" name="salonLocation" defaultValue="No">
                      <option>Yes</option>
                      <option>No</option>
                    </select>
                  </Field>
                </div>
              </div>

              <div className="card-soft p-6 sm:p-7">
                <h3 className="mb-5 font-display text-lg font-bold text-ink">
                  Eco practices & pilot fit
                </h3>
                <Field label="Eco-conscious practices / product notes">
                  <textarea
                    className="input-field min-h-[96px] resize-y"
                    name="ecoNotes"
                    placeholder="Low-waste efforts, refillable supplies, route-batching, pet-safe products…"
                  />
                </Field>
                <p className="mt-2 text-xs text-muted">
                  Eco details are partner-submitted. We&apos;ll describe them as
                  self-reported until HEHA review is available.
                </p>

                <div className="mt-5 grid gap-4 sm:grid-cols-2">
                  <Field label="Would you accept referral leads?">
                    <select className="input-field" name="acceptReferrals" defaultValue="Maybe">
                      {yesNoMaybe.map((o) => (
                        <option key={o}>{o}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Would you join a free pilot?">
                    <select className="input-field" name="joinPilot" defaultValue="Maybe">
                      {yesNoMaybe.map((o) => (
                        <option key={o}>{o}</option>
                      ))}
                    </select>
                  </Field>
                </div>

                <div className="mt-4">
                  <Field label="Notes">
                    <textarea
                      className="input-field min-h-[80px] resize-y"
                      name="notes"
                      placeholder="Anything else you'd like us to know?"
                    />
                  </Field>
                </div>

                <label className="mt-5 flex items-start gap-3 rounded-2xl border border-line bg-cream/50 p-4">
                  <input
                    type="checkbox"
                    className="mt-1 h-5 w-5 rounded border-line text-moss focus:ring-moss"
                    checked={insuranceConfirmed}
                    onChange={(e) => setInsuranceConfirmed(e.target.checked)}
                  />
                  <span className="text-sm leading-relaxed text-muted">
                    I confirm my business carries appropriate insurance and any
                    licenses required for the services I offer. (Demo
                    confirmation — not verified in this prototype.)
                  </span>
                </label>

                <EcoDisclaimer variant="compact" className="mt-4" />
              </div>

              <button
                type="submit"
                disabled={!insuranceConfirmed}
                className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-moss px-6 py-4 text-base font-semibold text-white shadow-soft transition hover:bg-moss-dark disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
              >
                Submit partner interest
              </button>
              {!insuranceConfirmed && (
                <p className="text-center text-xs text-muted sm:text-left">
                  Please check the insurance/license confirmation to submit.
                </p>
              )}
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  required,
  children,
}: {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="label-field">
        {label}
        {required && <span className="text-moss"> *</span>}
      </span>
      {children}
    </label>
  );
}
