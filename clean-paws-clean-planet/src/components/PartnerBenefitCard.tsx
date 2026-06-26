interface BenefitLike {
  title: string;
  detail: string;
  icon: string;
}

export default function PartnerBenefitCard({
  benefit,
  tone = "orange",
}: {
  benefit: BenefitLike;
  tone?: "orange" | "moss";
}) {
  const iconBg = tone === "moss" ? "bg-moss-soft" : "bg-orange-soft";
  return (
    <div className="flex gap-4 rounded-2xl border border-line bg-white p-5 transition hover:border-orange/30 hover:shadow-soft">
      <span
        className={`flex h-11 w-11 flex-shrink-0 items-center justify-center rounded-xl ${iconBg} text-xl`}
        aria-hidden
      >
        {benefit.icon}
      </span>
      <div>
        <h3 className="font-display text-base font-bold text-ink">
          {benefit.title}
        </h3>
        <p className="mt-1 text-sm leading-relaxed text-muted">
          {benefit.detail}
        </p>
      </div>
    </div>
  );
}
