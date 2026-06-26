"use client";

import { useState } from "react";
import {
  bookingRequests as seedRequests,
  bookingStatuses,
  type BookingRequest,
  type BookingStatus,
} from "@/lib/mockData";
import StatusBadge from "./StatusBadge";

const columnAccent: Record<BookingStatus, string> = {
  "New request": "border-t-orange",
  Reviewing: "border-t-amber-400",
  "Sent to partner": "border-t-blue-400",
  Accepted: "border-t-moss",
  Completed: "border-t-emerald-500",
  "Follow-up needed": "border-t-rose-400",
};

function nextStatus(current: BookingStatus): BookingStatus {
  const idx = bookingStatuses.indexOf(current);
  if (current === "Follow-up needed") return "Reviewing";
  return bookingStatuses[Math.min(idx + 1, bookingStatuses.length - 1)];
}

export default function MockDashboard() {
  const [requests, setRequests] = useState<BookingRequest[]>(seedRequests);
  const [view, setView] = useState<"kanban" | "table">("kanban");

  function setStatus(id: string, status: BookingStatus) {
    setRequests((prev) =>
      prev.map((r) => (r.id === id ? { ...r, status } : r)),
    );
  }

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div className="inline-flex rounded-full border border-line bg-white p-1">
          {(["kanban", "table"] as const).map((v) => (
            <button
              key={v}
              type="button"
              onClick={() => setView(v)}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold capitalize transition ${
                view === v
                  ? "bg-orange text-white"
                  : "text-muted hover:text-ink"
              }`}
            >
              {v}
            </button>
          ))}
        </div>
        <p className="text-xs font-medium text-muted">
          {requests.length} demo requests · actions update local state only
        </p>
      </div>

      {view === "kanban" ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
          {bookingStatuses.map((status) => {
            const items = requests.filter((r) => r.status === status);
            return (
              <div
                key={status}
                className={`rounded-2xl border border-t-4 border-line bg-sand/30 p-3 ${columnAccent[status]}`}
              >
                <div className="mb-3 flex items-center justify-between px-1">
                  <h3 className="text-xs font-bold uppercase tracking-wide text-ink">
                    {status}
                  </h3>
                  <span className="rounded-full bg-white px-2 py-0.5 text-[11px] font-semibold text-muted">
                    {items.length}
                  </span>
                </div>
                <div className="space-y-3">
                  {items.map((req) => (
                    <RequestCard
                      key={req.id}
                      req={req}
                      onAdvance={() => setStatus(req.id, nextStatus(req.status))}
                      onAccept={() => setStatus(req.id, "Accepted")}
                      onComplete={() => setStatus(req.id, "Completed")}
                    />
                  ))}
                  {items.length === 0 && (
                    <p className="px-1 py-4 text-center text-xs text-muted/70">
                      No requests
                    </p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-line bg-white">
          <table className="w-full min-w-[820px] text-left text-sm">
            <thead className="bg-sand/50 text-xs uppercase tracking-wide text-muted">
              <tr>
                <th className="px-4 py-3 font-semibold">Request</th>
                <th className="px-4 py-3 font-semibold">Customer</th>
                <th className="px-4 py-3 font-semibold">Pet</th>
                <th className="px-4 py-3 font-semibold">ZIP</th>
                <th className="px-4 py-3 font-semibold">Service</th>
                <th className="px-4 py-3 font-semibold">Pref</th>
                <th className="px-4 py-3 font-semibold">Suggested partner</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {requests.map((req) => (
                <tr key={req.id} className="align-top">
                  <td className="px-4 py-3 font-mono text-xs text-muted">
                    {req.id}
                  </td>
                  <td className="px-4 py-3 font-medium text-ink">
                    {req.customerName}
                  </td>
                  <td className="px-4 py-3 text-ink">{req.petName}</td>
                  <td className="px-4 py-3 text-muted">{req.zip}</td>
                  <td className="px-4 py-3 text-ink">{req.service}</td>
                  <td className="px-4 py-3 text-muted">{req.preference}</td>
                  <td className="px-4 py-3 text-muted">
                    {req.suggestedPartner}
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={req.status} />
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1.5">
                      <RowButton
                        onClick={() =>
                          setStatus(req.id, nextStatus(req.status))
                        }
                      >
                        Advance
                      </RowButton>
                      <RowButton onClick={() => setStatus(req.id, "Accepted")}>
                        Accept
                      </RowButton>
                      <RowButton onClick={() => setStatus(req.id, "Completed")}>
                        Complete
                      </RowButton>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function RequestCard({
  req,
  onAdvance,
  onAccept,
  onComplete,
}: {
  req: BookingRequest;
  onAdvance: () => void;
  onAccept: () => void;
  onComplete: () => void;
}) {
  return (
    <div className="rounded-xl border border-line bg-white p-3 shadow-sm">
      <div className="flex items-center justify-between">
        <span className="font-mono text-[11px] text-muted">{req.id}</span>
        <span className="rounded-full bg-cream px-2 py-0.5 text-[10px] font-semibold text-ink">
          {req.preference}
        </span>
      </div>
      <p className="mt-1.5 text-sm font-bold text-ink">
        {req.customerName} · {req.petName}
      </p>
      <p className="text-xs text-muted">
        {req.service} · {req.zip}
      </p>
      <p className="mt-2 rounded-lg bg-sand/50 px-2 py-1.5 text-[11px] leading-snug text-muted">
        💡 {req.suggestedPartner}
      </p>
      <p className="mt-1.5 text-[11px] leading-snug text-muted/90">
        {req.notes}
      </p>
      <div className="mt-3 flex flex-wrap gap-1.5">
        <RowButton onClick={onAdvance}>Review →</RowButton>
        <RowButton onClick={onAccept}>Accept</RowButton>
        <RowButton onClick={onComplete}>Complete</RowButton>
      </div>
    </div>
  );
}

function RowButton({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-full border border-line bg-white px-2.5 py-1 text-[11px] font-semibold text-ink transition hover:border-orange hover:bg-orange-soft hover:text-orange-deep"
    >
      {children}
    </button>
  );
}
