import Link from "next/link";
import Logo from "./Logo";

const columns = [
  {
    heading: "For pet owners",
    links: [
      { href: "/request", label: "Request Pet Care" },
      { href: "/partners", label: "Browse Demo Partners" },
      { href: "/roadmap", label: "Product Roadmap" },
    ],
  },
  {
    heading: "For partners",
    links: [
      { href: "/partner", label: "Become a Partner" },
      { href: "/pitch", label: "Partner Pitch" },
      { href: "/admin-demo", label: "Admin Demo" },
    ],
  },
];

export default function Footer() {
  return (
    <footer className="mt-16 border-t border-line bg-sand/50">
      <div className="container-page py-12">
        <div className="grid gap-10 md:grid-cols-[1.4fr_1fr_1fr]">
          <div>
            <Logo />
            <p className="mt-4 max-w-xs text-sm leading-relaxed text-muted">
              A local eco-conscious pet-care referral concept for Tampa Bay.
              Powered by HEHA Local / Healthy Habit LLC.
            </p>
            <p className="mt-4 inline-flex rounded-full border border-line bg-white px-3 py-1.5 text-xs font-semibold text-muted">
              🧪 Concept prototype — not a live booking service
            </p>
          </div>

          {columns.map((col) => (
            <div key={col.heading}>
              <h4 className="text-xs font-semibold uppercase tracking-[0.16em] text-ink">
                {col.heading}
              </h4>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((link) => (
                  <li key={link.href}>
                    <Link
                      href={link.href}
                      className="text-sm text-muted transition hover:text-orange-deep"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-10 border-t border-line pt-6 text-xs leading-relaxed text-muted">
          <p>
            © {new Date().getFullYear()} Healthy Habit LLC · HEHA Local. Clean
            Paws, Clean Planet is a concept prototype for partnership validation.
            No live bookings, payments, payouts, or verified eco claims are made
            in this demo. Partner names and profiles shown as demos do not imply
            any partnership has been agreed.
          </p>
        </div>
      </div>
    </footer>
  );
}
