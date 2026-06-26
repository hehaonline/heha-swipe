import type { PartnerStatus } from "@/lib/mockData";

const styles: Record<string, string> = {
  "Potential Anchor Partner": "bg-orange-soft text-orange-deep border-orange/30",
  "Potential Partner": "bg-peach/50 text-orange-deep border-orange/20",
  "Pilot Candidate": "bg-moss-soft text-moss-dark border-moss/30",
  "Self-Reported Eco Practices": "bg-moss-soft text-moss-dark border-moss/30",
  "HEHA Review Needed": "bg-amber-50 text-amber-700 border-amber-200",
};

export default function StatusBadge({
  status,
  className = "",
}: {
  status: PartnerStatus | string;
  className?: string;
}) {
  const style = styles[status] ?? "bg-white text-muted border-line";
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-semibold ${style} ${className}`}
    >
      <span className="h-1.5 w-1.5 rounded-full bg-current opacity-70" />
      {status}
    </span>
  );
}
