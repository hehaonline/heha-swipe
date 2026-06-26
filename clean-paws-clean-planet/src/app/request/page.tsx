"use client";

import { useState } from "react";
import DemoFormSuccess from "@/components/DemoFormSuccess";
import EcoDisclaimer from "@/components/EcoDisclaimer";
import { serviceOptions } from "@/lib/mockData";

const species = ["Dog", "Cat", "Other"];
const weightRanges = ["Under 15 lbs", "15–40 lbs", "40–70 lbs", "70+ lbs"];
const ageRanges = ["Puppy / Kitten", "Young adult", "Adult", "Senior"];
const coatTypes = ["Short", "Medium", "Long", "Curly / Doodle", "Double coat"];
const preferences = ["Salon appointment", "Mobile appointment", "Either is fine"];
const recurring = ["One-time", "Weekly", "Every 2 weeks", "Monthly"];
const timeWindows = [
  "Weekday morning",
  "Weekday afternoon",
  "Weekday evening",
  "Weekend morning",
  "Weekend afternoon",
  "Flexible",
];

export default function RequestPage() {
  const [submitted, setSubmitted] = useState(false);
  const [selectedServices, setSelectedServices] = useState<string[]>([]);
  const [smsConsent, setSmsConsent] = useState(false);

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
    setSmsConsent(false);
  }

  return (
    <div className="container-page py-12 sm:py-16">
      <div className="mx-auto max-w-3xl">
        {!submitted ? (
          <>
            <div className="text-center">
              <span className="eyebrow mb-4">Request pet care</span>
              <h1 className="font-display text-3xl font-extrabold text-ink sm:text-4xl">
                Tell us about your pet
              </h1>
              <p className="mx-auto mt-3 max-w-xl text-base leading-relaxed text-muted">
                One simple request. In the real pilot, HEHA Local would review it
                and connect you with an approved local partner — salon or mobile.
              </p>
            </div>

            <form onSubmit={handleSubmit} className="mt-10 space-y-6">
              {/* Contact */}
              <FormCard title="Your contact info" step="1">
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Your name" required>
                    <input className="input-field" name="customerName" required placeholder="Jane Doe" />
                  </Field>
                  <Field label="Phone" required>
                    <input className="input-field" name="phone" type="tel" required placeholder="(813) 555-0123" />
                  </Field>
                  <Field label="Email" required>
                    <input className="input-field" name="email" type="email" required placeholder="jane@email.com" />
                  </Field>
                  <Field label="ZIP code" required>
                    <input className="input-field" name="zip" required placeholder="33606" />
                  </Field>
                  <div className="sm:col-span-2">
                    <Field label="Address or neighborhood">
                      <input className="input-field" name="address" placeholder="South Tampa / Hyde Park" />
                    </Field>
                  </div>
                </div>
              </FormCard>

              {/* Pet */}
              <FormCard title="About your pet" step="2">
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Pet name" required>
                    <input className="input-field" name="petName" required placeholder="Biscuit" />
                  </Field>
                  <Field label="Species" required>
                    <select className="input-field" name="species" required defaultValue="Dog">
                      {species.map((s) => (
                        <option key={s}>{s}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Breed">
                    <input className="input-field" name="breed" placeholder="Goldendoodle" />
                  </Field>
                  <Field label="Weight range">
                    <select className="input-field" name="weight" defaultValue="">
                      <option value="" disabled>Select…</option>
                      {weightRanges.map((w) => (
                        <option key={w}>{w}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Age range">
                    <select className="input-field" name="age" defaultValue="">
                      <option value="" disabled>Select…</option>
                      {ageRanges.map((a) => (
                        <option key={a}>{a}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Coat type">
                    <select className="input-field" name="coat" defaultValue="">
                      <option value="" disabled>Select…</option>
                      {coatTypes.map((c) => (
                        <option key={c}>{c}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Temperament">
                    <input className="input-field" name="temperament" placeholder="Friendly, a little nervous at first" />
                  </Field>
                  <Field label="Allergies / sensitivities">
                    <input className="input-field" name="allergies" placeholder="Sensitive skin, no oatmeal shampoo" />
                  </Field>
                </div>
              </FormCard>

              {/* Service */}
              <FormCard title="What do you need?" step="3">
                <p className="label-field">Service needed (select any)</p>
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
                            ? "border-orange bg-orange text-white"
                            : "border-line bg-white text-ink hover:border-orange/50"
                        }`}
                      >
                        {service}
                      </button>
                    );
                  })}
                </div>

                <div className="mt-5 grid gap-4 sm:grid-cols-2">
                  <Field label="Preference">
                    <select className="input-field" name="preference" defaultValue="Either is fine">
                      {preferences.map((p) => (
                        <option key={p}>{p}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Preferred time window">
                    <select className="input-field" name="timeWindow" defaultValue="Flexible">
                      {timeWindows.map((t) => (
                        <option key={t}>{t}</option>
                      ))}
                    </select>
                  </Field>
                  <div className="sm:col-span-2">
                    <p className="label-field">Recurring preference</p>
                    <div className="flex flex-wrap gap-2">
                      {recurring.map((r, i) => (
                        <label key={r} className="chip border-line bg-white text-ink has-[:checked]:border-moss has-[:checked]:bg-moss has-[:checked]:text-white">
                          <input
                            type="radio"
                            name="recurring"
                            value={r}
                            defaultChecked={i === 0}
                            className="sr-only"
                          />
                          {r}
                        </label>
                      ))}
                    </div>
                  </div>
                </div>

                <div className="mt-4">
                  <Field label="Notes">
                    <textarea
                      className="input-field min-h-[96px] resize-y"
                      name="notes"
                      placeholder="Anything else we should know to match you well?"
                    />
                  </Field>
                </div>
              </FormCard>

              {/* Consent */}
              <FormCard title="Consent" step="4">
                <label className="flex items-start gap-3 rounded-2xl border border-line bg-cream/50 p-4">
                  <input
                    type="checkbox"
                    className="mt-1 h-5 w-5 rounded border-line text-orange focus:ring-orange"
                    checked={smsConsent}
                    onChange={(e) => setSmsConsent(e.target.checked)}
                  />
                  <span className="text-sm leading-relaxed text-muted">
                    I agree to receive appointment-related messages. Message and
                    data rates may apply. Reply STOP to opt out.
                  </span>
                </label>
                <EcoDisclaimer variant="compact" className="mt-4" />
              </FormCard>

              <button
                type="submit"
                disabled={!smsConsent}
                className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-orange px-6 py-4 text-base font-semibold text-white shadow-glow transition hover:bg-orange-bright disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
              >
                Submit request
              </button>
              {!smsConsent && (
                <p className="text-center text-xs text-muted sm:text-left">
                  Please check the consent box to submit this demo request.
                </p>
              )}
            </form>
          </>
        ) : (
          <DemoFormSuccess
            title="Request received 🐾"
            message="This prototype does not send live bookings yet, but in the real pilot, HEHA Local would review your request and connect you with an approved partner — salon or mobile — that fits your pet and your neighborhood."
            primaryHref="/partners"
            primaryLabel="Browse demo partners"
            secondaryHref="/"
            secondaryLabel="Back to home"
            onReset={reset}
            resetLabel="Submit another request"
          />
        )}
      </div>
    </div>
  );
}

function FormCard({
  title,
  step,
  children,
}: {
  title: string;
  step: string;
  children: React.ReactNode;
}) {
  return (
    <div className="card-soft p-6 sm:p-7">
      <div className="mb-5 flex items-center gap-3">
        <span className="flex h-8 w-8 items-center justify-center rounded-full bg-orange-soft text-sm font-bold text-orange-deep">
          {step}
        </span>
        <h2 className="font-display text-lg font-bold text-ink">{title}</h2>
      </div>
      {children}
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
        {required && <span className="text-orange"> *</span>}
      </span>
      {children}
    </label>
  );
}
