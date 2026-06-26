import type { Metadata } from "next";
import { Syne, DM_Sans } from "next/font/google";
import "./globals.css";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";

const syne = Syne({
  subsets: ["latin"],
  weight: ["600", "700", "800"],
  variable: "--font-syne",
  display: "swap",
});

const dmSans = DM_Sans({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-dmsans",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Clean Paws, Clean Planet — Local eco-conscious pet care in Tampa",
  description:
    "Clean Paws, Clean Planet connects Tampa pet owners with trusted local grooming salons, mobile groomers, and eco-conscious pet-care partners. A HEHA Local concept prototype.",
  keywords: [
    "Tampa pet grooming",
    "mobile dog grooming Tampa",
    "eco-conscious pet care",
    "HEHA Local",
    "pet care referral",
  ],
  openGraph: {
    title: "Clean Paws, Clean Planet",
    description:
      "Local eco-conscious grooming and pet-care referrals across Tampa Bay. Powered by HEHA Local.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${syne.variable} ${dmSans.variable}`}>
      <body className="font-sans antialiased">
        <div className="flex min-h-screen flex-col">
          <Navbar />
          <main className="flex-1">{children}</main>
          <Footer />
        </div>
      </body>
    </html>
  );
}
