import AdminWorkspace from "../shared/AdminWorkspace";
import { allScoutTab } from "../scout/scoutLaneTabs";

export default function SomDashboard({ final }) {
  return <AdminWorkspace lane="Sales Operations / Scout" title="HEHA Sales Operations Dashboard" subtitle="Scout healthy businesses, venues, events, and potential partners. The shared pipeline routes follow-up to the correct HEHA lane." final={final} tabs={[allScoutTab]} overview={[{ eyebrow: "Scout boundary", title: "Find, capture, and hand off.", body: "Sales Operations can create and enrich scout leads. Public HEHA Swipe approval stays with Admin." }]} />;
}
