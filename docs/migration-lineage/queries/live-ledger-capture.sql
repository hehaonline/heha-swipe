-- SWP-016 read-only migration-ledger capture.
--
-- Boundary: migration version/name metadata only. This statement reads no
-- application, Auth, storage, provider, or business row.
--
-- Deterministic capture command (run only in an independently authorized,
-- read-only session against the named environment):
--
--   psql -X --csv -P footer=off -v ON_ERROR_STOP=1 \
--     -f docs/migration-lineage/queries/live-ledger-capture.sql \
--     > docs/migration-lineage/live-ledger-YYYY-MM-DD.csv
--
-- Preserve UTF-8 bytes and LF line endings. Do not edit the captured rows.

select
  sm.version::text as version,
  sm.name::text as name,
  'LP'::text as evidence
from supabase_migrations.schema_migrations sm
order by sm.version::text, sm.name::text;
