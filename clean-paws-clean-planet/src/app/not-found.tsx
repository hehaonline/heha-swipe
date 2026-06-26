import CTAButton from "@/components/CTAButton";

export default function NotFound() {
  return (
    <div className="container-page flex min-h-[60vh] flex-col items-center justify-center py-20 text-center">
      <span className="text-6xl">🐾</span>
      <h1 className="mt-6 font-display text-3xl font-extrabold text-ink">
        This page wandered off
      </h1>
      <p className="mt-3 max-w-md text-muted">
        We couldn&apos;t find that page. Let&apos;s get you back to the pack.
      </p>
      <div className="mt-7 flex flex-col gap-3 sm:flex-row">
        <CTAButton href="/" variant="primary">
          Back to home
        </CTAButton>
        <CTAButton href="/partners" variant="secondary">
          View demo partners
        </CTAButton>
      </div>
    </div>
  );
}
