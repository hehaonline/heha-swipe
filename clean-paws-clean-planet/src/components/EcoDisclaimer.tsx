export default function EcoDisclaimer({
  variant = "default",
  className = "",
}: {
  variant?: "default" | "compact";
  className?: string;
}) {
  if (variant === "compact") {
    return (
      <p className={`text-xs leading-relaxed text-muted ${className}`}>
        🌿 Eco details are partner-submitted and self-reported.
        HEHA-reviewed partners coming soon — no eco claims are verified in this
        prototype.
      </p>
    );
  }

  return (
    <div
      className={`rounded-2xl border border-moss/25 bg-moss-soft px-5 py-4 ${className}`}
    >
      <p className="text-sm font-semibold text-moss-dark">
        🌿 About “eco-conscious” language
      </p>
      <p className="mt-1.5 text-sm leading-relaxed text-moss-dark/80">
        We use “eco-conscious options” and “partner-submitted practices” on
        purpose. Partners can share product practices, low-waste efforts,
        route-batching availability, and pet-safe care preferences. Nothing here
        is a verified or guaranteed eco claim — HEHA-reviewed partners and any
        eco badge are coming in a later phase.
      </p>
    </div>
  );
}
