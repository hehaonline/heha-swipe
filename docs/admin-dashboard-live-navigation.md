# Admin dashboard live navigation

The shared admin workspace now treats overview metrics and recent-record panels as navigation controls. Selecting a card opens its full dashboard lane. Dashboard data refreshes on initial load, every 30 seconds while visible, when the browser regains focus, and after Supabase realtime changes on the tables used by the active workspace.

This keeps role and RLS boundaries unchanged. Realtime events only trigger a normal protected reload through the existing Supabase client.