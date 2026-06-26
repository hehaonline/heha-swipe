import CTAButton from "./CTAButton";

interface DemoFormSuccessProps {
  title: string;
  message: string;
  primaryHref?: string;
  primaryLabel?: string;
  secondaryHref?: string;
  secondaryLabel?: string;
  onReset?: () => void;
  resetLabel?: string;
}

export default function DemoFormSuccess({
  title,
  message,
  primaryHref = "/",
  primaryLabel = "Back to home",
  secondaryHref = "/partners",
  secondaryLabel = "View demo partners",
  onReset,
  resetLabel = "Submit another",
}: DemoFormSuccessProps) {
  return (
    <div className="mx-auto max-w-xl rounded-3xl border border-line bg-white p-8 text-center shadow-card sm:p-10">
      <span className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-moss-soft text-3xl">
        ✅
      </span>
      <h2 className="mt-5 font-display text-2xl font-extrabold text-ink">
        {title}
      </h2>
      <p className="mt-3 text-sm leading-relaxed text-muted">{message}</p>

      <div className="mt-6 rounded-2xl border border-orange/20 bg-orange-soft px-4 py-3 text-xs font-medium text-orange-deep">
        🧪 This is a prototype. Nothing was sent, stored, or booked — the form
        only updated this screen.
      </div>

      <div className="mt-7 flex flex-col gap-3 sm:flex-row sm:justify-center">
        {onReset && (
          <button
            type="button"
            onClick={onReset}
            className="inline-flex items-center justify-center gap-2 rounded-full border border-line bg-white px-6 py-3 text-sm font-semibold text-ink transition hover:border-orange hover:text-orange-deep"
          >
            {resetLabel}
          </button>
        )}
        <CTAButton href={secondaryHref} variant="secondary">
          {secondaryLabel}
        </CTAButton>
        <CTAButton href={primaryHref} variant="primary">
          {primaryLabel}
        </CTAButton>
      </div>
    </div>
  );
}
