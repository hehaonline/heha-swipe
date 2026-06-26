import type { Metadata } from "next";
import MockDashboard from "@/components/MockDashboard";

export const metadata: Metadata = {
  title: "Admin Demo — Clean Paws, Clean Planet",
  description:
    "A demo dashboard showing how HEHA Local could triage incoming pet-care requests. Not a real or secured admin panel.",
};

export default function AdminDemoPage() {
  return (
    <div className="container-page py-12 sm:py-16">
      <div className="mb-8 flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl">
          <span className="eyebrow mb-4">Admin demo</span>
          <h1 className="font-display text-3xl font-extrabold text-ink sm:text-4xl">
            Request triage dashboard
          </h1>
          <p className="mt-3 text-base leading-relaxed text-muted">
            This is how HEHA Local could review incoming requests and move them
            through to a confirmed booking. Drag-free demo: use the buttons to
            advance a request through each status.
          </p>
        </div>
      </div>

      <div className="mb-8 rounded-2xl border border-amber-200 bg-amber-50 px-5 py-4">
        <p className="text-sm font-semibold text-amber-800">
          ⚠️ Demo dashboard — not a real or secured admin panel
        </p>
        <p className="mt-1 text-sm text-amber-700">
          All requests are mock data. Action buttons update local state in your
          browser only — nothing is saved, sent, or shared. In a real pilot this
          would live behind authentication.
        </p>
      </div>

      <MockDashboard />
    </div>
  );
}
