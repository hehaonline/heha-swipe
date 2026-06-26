"use client";

import Link from "next/link";
import { useState } from "react";
import Logo from "./Logo";
import CTAButton from "./CTAButton";

const navLinks = [
  { href: "/partners", label: "Demo Partners" },
  { href: "/pitch", label: "Partner Pitch" },
  { href: "/roadmap", label: "Roadmap" },
  { href: "/admin-demo", label: "Admin Demo" },
];

export default function Navbar() {
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-line/70 bg-cream/80 backdrop-blur-md">
      <div className="container-page flex h-16 items-center justify-between">
        <Logo />

        <nav className="hidden items-center gap-6 md:flex">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-muted transition hover:text-orange-deep"
            >
              {link.label}
            </Link>
          ))}
        </nav>

        <div className="hidden items-center gap-3 md:flex">
          <CTAButton href="/partner" variant="secondary">
            Become a Partner
          </CTAButton>
          <CTAButton href="/request" variant="primary">
            Request Pet Care
          </CTAButton>
        </div>

        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="inline-flex h-10 w-10 items-center justify-center rounded-xl border border-line bg-white text-ink md:hidden"
          aria-label="Toggle menu"
          aria-expanded={open}
        >
          <span className="text-lg">{open ? "✕" : "☰"}</span>
        </button>
      </div>

      {open && (
        <div className="border-t border-line bg-cream md:hidden">
          <nav className="container-page flex flex-col gap-1 py-4">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                onClick={() => setOpen(false)}
                className="rounded-xl px-3 py-2.5 text-sm font-medium text-ink transition hover:bg-orange-soft"
              >
                {link.label}
              </Link>
            ))}
            <div className="mt-3 flex flex-col gap-2">
              <CTAButton href="/partner" variant="secondary" fullWidth>
                Become a Partner
              </CTAButton>
              <CTAButton href="/request" variant="primary" fullWidth>
                Request Pet Care
              </CTAButton>
            </div>
          </nav>
        </div>
      )}
    </header>
  );
}
