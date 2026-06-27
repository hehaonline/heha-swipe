# Admin dashboard review fixes

Based on Claude's PR #16 review, Nova applied the following live Supabase fixes:

- Added updated_at triggers for the five new Community / Events tables.
- Added write access for community_events_admin to community content and approval request workflows.
- Kept final approval/publish/schedule states restricted to super_admin/developer_admin.
- Tightened Niña-owned table writes so pm_admin is primarily read/coordination, not the owner of Niña's workflow.

Frontend fixes added on this branch:

- Added Community Outreach tab and data loading.
- Added browser back-button popstate handling.
- Tightened admin route gate so production public /admin path does not automatically become admin unless hosted on admin.* or VITE_APP_MODE=admin.
- Dynamically loads admin-dashboard.css only for admin mode.
- Namespaced risky utility classes such as metric, guard, empty, and back-button.

Still tracked for later:

- Split AdminApp.jsx into smaller components.
- Add edit/update/detail drawer workflows.
- Create an AdminLoginScreen instead of reusing AuthScreen.
- Add deeper loading states and per-table error handling.
