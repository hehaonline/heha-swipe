-- SWP-016 sanitized, read-only top-level object-manifest capture.
--
-- This query reads catalog metadata only. It does not read application rows,
-- Auth/storage rows, Vault values, function bodies, policy expressions, ACLs,
-- provider payloads, configuration secrets, or migration-ledger contents.
-- It is sufficient only to reproduce the six top-level object counts, names,
-- RLS/FORCE-RLS totals, and the reported extension versions in PR #132.
--
-- Deterministic capture command (only after separate read-only authorization):
--
--   psql -XAtq -P footer=off -v ON_ERROR_STOP=1 \
--     -f docs/migration-lineage/queries/live-object-manifest-capture.sql \
--     > docs/migration-lineage/live-object-manifest-YYYY-MM-DD.jsonl
--
-- Each output line is one JSON object. SQL ordering is part of the contract;
-- preserve UTF-8 bytes and LF line endings. A new capture receives a new hash.

with catalog_rows(record_type, schema_name, object_name, object_identity, metadata) as (
  select
    'table'::text,
    n.nspname::text,
    rel.relname::text,
    pg_catalog.format('%I.%I', n.nspname, rel.relname),
    pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(rel.relowner),
      'relation_kind', case rel.relkind when 'p' then 'partitioned' else 'ordinary' end,
      'rls_enabled', rel.relrowsecurity,
      'rls_forced', rel.relforcerowsecurity
    )
  from pg_catalog.pg_class rel
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  where n.nspname = 'public'
    and rel.relkind in ('r', 'p')

  union all

  select
    'view',
    n.nspname::text,
    rel.relname::text,
    pg_catalog.format('%I.%I', n.nspname, rel.relname),
    pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(rel.relowner),
      'relation_kind', case rel.relkind when 'm' then 'materialized_view' else 'view' end
    )
  from pg_catalog.pg_class rel
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  where n.nspname = 'public'
    and rel.relkind in ('v', 'm')

  union all

  select
    'function',
    n.nspname::text,
    proc.proname::text,
    pg_catalog.format(
      '%I.%I(%s)',
      n.nspname,
      proc.proname,
      pg_catalog.pg_get_function_identity_arguments(proc.oid)
    ),
    pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(proc.proowner),
      'language', lang.lanname,
      'security_definer', proc.prosecdef,
      'volatility', proc.provolatile,
      'parallel', proc.proparallel,
      'return_type', pg_catalog.pg_get_function_result(proc.oid)
    )
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace n on n.oid = proc.pronamespace
  join pg_catalog.pg_language lang on lang.oid = proc.prolang
  where n.nspname = 'public'
    and proc.prokind = 'f'

  union all

  select
    'trigger',
    n.nspname::text,
    trg.tgname::text,
    pg_catalog.format('%I.%I.%I', n.nspname, rel.relname, trg.tgname),
    pg_catalog.jsonb_build_object(
      'enabled', trg.tgenabled,
      'function_identity', pg_catalog.format(
        '%I.%I(%s)',
        fn_n.nspname,
        fn.proname,
        pg_catalog.pg_get_function_identity_arguments(fn.oid)
      ),
      'trigger_type', trg.tgtype,
      'constraint', trg.tgconstraint <> 0::pg_catalog.oid
    )
  from pg_catalog.pg_trigger trg
  join pg_catalog.pg_class rel on rel.oid = trg.tgrelid
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  join pg_catalog.pg_proc fn on fn.oid = trg.tgfoid
  join pg_catalog.pg_namespace fn_n on fn_n.oid = fn.pronamespace
  where n.nspname = 'public'
    and not trg.tgisinternal

  union all

  select
    'policy',
    policy.schemaname::text,
    policy.policyname::text,
    pg_catalog.format('%I.%I.%I', policy.schemaname, policy.tablename, policy.policyname),
    pg_catalog.jsonb_build_object(
      'command', policy.cmd,
      'permissive', policy.permissive,
      'roles', policy.roles
    )
  from pg_catalog.pg_policies policy
  where policy.schemaname = 'public'

  union all

  select
    'extension',
    n.nspname::text,
    ext.extname::text,
    ext.extname::text,
    pg_catalog.jsonb_build_object(
      'version', ext.extversion
    )
  from pg_catalog.pg_extension ext
  join pg_catalog.pg_namespace n on n.oid = ext.extnamespace
)
select pg_catalog.jsonb_build_object(
  'record_type', row.record_type,
  'schema', row.schema_name,
  'name', row.object_name,
  'identity', row.object_identity,
  'metadata', row.metadata
)::text as normalized_row
from catalog_rows row
order by
  row.record_type collate "C",
  row.schema_name collate "C",
  row.object_identity collate "C",
  row.metadata::text collate "C";
