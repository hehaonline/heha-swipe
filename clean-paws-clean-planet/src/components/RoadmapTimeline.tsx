import type { RoadmapPhase } from "@/lib/mockData";

const stateStyles: Record<RoadmapPhase["state"], string> = {
  Prototype: "bg-orange text-white border-orange",
  Next: "bg-moss text-white border-moss",
  Later: "bg-white text-muted border-line",
};

const dotStyles: Record<RoadmapPhase["state"], string> = {
  Prototype: "bg-orange ring-4 ring-orange-soft",
  Next: "bg-moss ring-4 ring-moss-soft",
  Later: "bg-line ring-4 ring-cream",
};

export default function RoadmapTimeline({
  phases,
}: {
  phases: RoadmapPhase[];
}) {
  return (
    <ol className="relative space-y-6 border-l-2 border-dashed border-line pl-6">
      {phases.map((phase) => (
        <li key={phase.phase} className="relative">
          <span
            className={`absolute -left-[31px] top-1.5 h-4 w-4 rounded-full ${dotStyles[phase.state]}`}
            aria-hidden
          />
          <div className="rounded-2xl border border-line bg-white p-5 shadow-soft">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-xs font-semibold uppercase tracking-[0.16em] text-muted">
                {phase.phase}
              </p>
              <span
                className={`rounded-full border px-2.5 py-0.5 text-[11px] font-semibold ${stateStyles[phase.state]}`}
              >
                {phase.state === "Prototype"
                  ? "You are here"
                  : phase.state === "Next"
                    ? "Up next"
                    : "Later"}
              </span>
            </div>
            <h3 className="mt-2 font-display text-base font-bold text-ink">
              {phase.title}
            </h3>
            <p className="mt-1.5 text-sm leading-relaxed text-muted">
              {phase.detail}
            </p>
          </div>
        </li>
      ))}
    </ol>
  );
}
