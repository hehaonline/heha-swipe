import Link from "next/link";

export default function Logo({ compact = false }: { compact?: boolean }) {
  return (
    <Link
      href="/"
      className="group inline-flex items-center gap-2.5"
      aria-label="Clean Paws, Clean Planet home"
    >
      <span className="relative inline-flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-orange to-orange-bright text-lg shadow-glow">
        <span aria-hidden>🐾</span>
      </span>
      <span className="flex flex-col leading-none">
        <span className="font-display text-[15px] font-extrabold tracking-tight text-ink">
          Clean Paws<span className="text-orange">,</span> Clean Planet
        </span>
        {!compact && (
          <span className="mt-0.5 text-[10px] font-semibold uppercase tracking-[0.18em] text-muted">
            Powered by HEHA Local
          </span>
        )}
      </span>
    </Link>
  );
}
