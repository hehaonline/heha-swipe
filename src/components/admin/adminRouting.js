export const ROLE_PRIORITY = ["super_admin", "developer_admin", "pm_admin", "community_events_admin", "som_admin"];

export function areaFromPath() {
  const path = window.location.pathname;
  if (path.includes("/scout")) return "scout";
  if (path.includes("/som")) return "som";
  if (path.includes("/community")) return "community";
  if (path.includes("/pm")) return "pm";
  return "home";
}

export function pathForArea(area) {
  if (area === "scout") return "/admin/scout";
  if (area === "som") return "/admin/som";
  if (area === "community") return "/admin/community";
  if (area === "pm") return "/admin/pm";
  return "/admin";
}

export function accessForRole(role) {
  const admin = role === "super_admin" || role === "developer_admin";
  return {
    internal: ROLE_PRIORITY.includes(role),
    pm: admin || role === "pm_admin",
    community: admin || role === "community_events_admin",
    som: admin || role === "som_admin",
    scout: ROLE_PRIORITY.includes(role),
    final: role === "super_admin",
  };
}
