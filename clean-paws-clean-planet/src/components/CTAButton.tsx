import Link from "next/link";
import type { ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost" | "moss";

const variants: Record<Variant, string> = {
  primary:
    "bg-orange text-white shadow-glow hover:bg-orange-bright active:translate-y-px",
  secondary:
    "bg-white text-ink border border-line hover:border-orange hover:text-orange-deep",
  ghost:
    "bg-transparent text-ink hover:bg-orange-soft",
  moss: "bg-moss text-white hover:bg-moss-dark active:translate-y-px",
};

interface CTAButtonProps {
  href: string;
  children: ReactNode;
  variant?: Variant;
  className?: string;
  fullWidth?: boolean;
}

export default function CTAButton({
  href,
  children,
  variant = "primary",
  className = "",
  fullWidth = false,
}: CTAButtonProps) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-sm font-semibold transition-all duration-200";
  const width = fullWidth ? "w-full" : "";
  const classes = `${base} ${variants[variant]} ${width} ${className}`.trim();

  const isExternal = href.startsWith("http") || href.startsWith("#");

  if (isExternal) {
    return (
      <a href={href} className={classes}>
        {children}
      </a>
    );
  }

  return (
    <Link href={href} className={classes}>
      {children}
    </Link>
  );
}
