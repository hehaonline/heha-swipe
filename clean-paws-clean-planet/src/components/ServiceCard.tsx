import type { ServiceCategory } from "@/lib/mockData";

export default function ServiceCard({ service }: { service: ServiceCategory }) {
  return (
    <div className="group flex h-full flex-col rounded-2xl border border-line bg-white p-5 transition hover:-translate-y-0.5 hover:border-orange/40 hover:shadow-soft">
      <span
        className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-orange-soft text-xl"
        aria-hidden
      >
        {service.icon}
      </span>
      <h3 className="mt-4 font-display text-base font-bold text-ink">
        {service.name}
      </h3>
      <p className="mt-1.5 text-sm leading-relaxed text-muted">
        {service.blurb}
      </p>
    </div>
  );
}
