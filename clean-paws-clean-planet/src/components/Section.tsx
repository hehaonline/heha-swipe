import type { ReactNode } from "react";

interface SectionProps {
  children: ReactNode;
  className?: string;
  id?: string;
  tone?: "default" | "sand" | "moss" | "cream";
}

const tones: Record<NonNullable<SectionProps["tone"]>, string> = {
  default: "",
  sand: "bg-sand/40",
  cream: "bg-cream",
  moss: "bg-moss-soft/60",
};

export default function Section({
  children,
  className = "",
  id,
  tone = "default",
}: SectionProps) {
  return (
    <section id={id} className={`py-14 sm:py-20 ${tones[tone]} ${className}`}>
      <div className="container-page">{children}</div>
    </section>
  );
}

export function SectionHeading({
  eyebrow,
  title,
  subtitle,
  align = "left",
}: {
  eyebrow?: string;
  title: string;
  subtitle?: string;
  align?: "left" | "center";
}) {
  const alignment = align === "center" ? "text-center mx-auto" : "";
  return (
    <div className={`max-w-2xl ${alignment}`}>
      {eyebrow && <span className="eyebrow mb-4">{eyebrow}</span>}
      <h2 className="font-display text-3xl font-extrabold leading-tight text-ink sm:text-4xl">
        {title}
      </h2>
      {subtitle && (
        <p className="mt-4 text-base leading-relaxed text-muted">{subtitle}</p>
      )}
    </div>
  );
}
