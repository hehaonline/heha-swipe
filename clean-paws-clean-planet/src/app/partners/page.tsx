import type { Metadata } from "next";
import PartnerCard from "@/components/PartnerCard";
import EcoDisclaimer from "@/components/EcoDisclaimer";
import CTAButton from "@/components/CTAButton";
import { partners } from "@/lib/mockData";

export const metadata: Metadata = {
  title: "Demo Partners — Clean Paws, Clean Planet",
  description:
    "A demo directory of the kinds of local pet-care partners the Clean Paws, Clean Planet network could include across Tampa Bay.",
};

export default function PartnersPage() {
  return (
    <div className="container-page py-12 sm:py-16">
      <div className="max-w-2xl">
        <span className="eyebrow mb-4">Demo partner directory</span>
        <h1 className="font-display text-4xl font-extrabold text-ink sm:text-5xl">
          The kinds of partners in the network
        </h1>
        <p className="mt-4 text-lg leading-relaxed text-muted">
          These are demo profiles built from mock data to show how a local,
          eco-conscious pet-care network could come together. Status badges show
          how each profile would be treated before any public listing.
        </p>
      </div>

      <div className="mt-8">
        <EcoDisclaimer />
      </div>

      {/* Legend */}
      <div className="mt-8 flex flex-wrap gap-2 text-xs">
        {[
          "Potential Anchor Partner",
          "Potential Partner",
          "Pilot Candidate",
          "Self-Reported Eco Practices",
          "HEHA Review Needed",
        ].map((s) => (
          <span
            key={s}
            className="rounded-full border border-line bg-white px-3 py-1.5 font-medium text-muted"
          >
            {s}
          </span>
        ))}
      </div>

      <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {partners.map((partner) => (
          <PartnerCard key={partner.slug} partner={partner} />
        ))}
      </div>

      <div className="mt-14 overflow-hidden rounded-3xl border border-line bg-gradient-to-br from-moss-soft to-cream p-8 text-center sm:p-10">
        <h2 className="font-display text-2xl font-extrabold text-ink sm:text-3xl">
          Are you a local pet-care pro?
        </h2>
        <p className="mx-auto mt-3 max-w-lg text-base text-muted">
          Add your business to the network. HEHA Local reviews every partner
          before any public listing or referral.
        </p>
        <div className="mt-6 flex flex-col justify-center gap-3 sm:flex-row">
          <CTAButton href="/partner" variant="moss">
            Become a Partner
          </CTAButton>
          <CTAButton href="/request" variant="secondary">
            Request Pet Care
          </CTAButton>
        </div>
      </div>
    </div>
  );
}
