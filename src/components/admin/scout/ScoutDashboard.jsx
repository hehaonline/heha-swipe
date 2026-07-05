import AdminWorkspace from "../shared/AdminWorkspace";
import { allScoutTab, eventScoutTab, partnerScoutTab } from "./scoutLaneTabs";

function tabFor(role, mode) {
  if (mode === "som") return allScoutTab;
  if (role === "community_events_admin") return eventScoutTab;
  if (role === "pm_admin") return partnerScoutTab;
  return allScoutTab;
}

export default function ScoutDashboard({ role, final = false, mode = "scout" }) {
  const tab = tabFor(role, mode);
  const somMode = mode === "som";
  return (
    <AdminWorkspace
      lane={somMode ? "Sales Operations / Scout" : "Scout / Partner Pipeline"}
      title={somMode ? "SOM Scout Dashboard" : "HEHA Scout & Partner Pipeline"}
      subtitle="Capture a field visit once and feed the shared HEHA partner, event, readiness, and CRM workflow. All intake fields are optional."
      final={final}
      tabs={[tab]}
      overview={[{
        eyebrow: "Shared module",
        title: "One lead. The right HEHA workflow.",
        body: "Partner leads create pending Swipe drafts and readiness records. Event leads feed the Community / Events workflow. Public visibility remains approval-gated.",
      }]}
    />
  );
}
