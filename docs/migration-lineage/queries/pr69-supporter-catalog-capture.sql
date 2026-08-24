-- SWP-016 / PR #69 sanitized, read-only catalog capture.
--
-- This query is deliberately limited to definitions for three public tables
-- and public.heha_set_updated_at(). It reads pg_catalog and
-- information_schema only; it does not read table rows, Auth/storage objects,
-- Vault values, provider payloads, or configuration secrets.
--
-- Deterministic capture command (only after separate read-only authorization):
--
--   psql -XAt -P footer=off -v ON_ERROR_STOP=1 \
--     -f docs/migration-lineage/queries/pr69-supporter-catalog-capture.sql \
--     > docs/migration-lineage/pr69-supporter-catalog-YYYY-MM-DD.jsonl
--
-- Each output line is one JSON object. SQL ordering is part of the contract;
-- preserve UTF-8 bytes and LF line endings. A new capture receives a new hash.

with target_tables(table_name) as (
  values
    ('supporter_payments'::text),
    ('supporter_subscriptions'::text),
    ('vibe_settings'::text)
),
catalog_rows(record_type, object_identity, ordinal, metadata) as (
  select
    'column'::text,
    pg_catalog.format('%I.%I.%I', c.table_schema, c.table_name, c.column_name),
    c.ordinal_position::integer,
    pg_catalog.jsonb_build_object(
      'data_type', c.data_type,
      'udt_schema', c.udt_schema,
      'udt_name', c.udt_name,
      'is_nullable', c.is_nullable,
      'column_default', c.column_default,
      'is_identity', c.is_identity,
      'identity_generation', c.identity_generation,
      'is_generated', c.is_generated,
      'generation_expression', c.generation_expression,
      'collation_schema', c.collation_schema,
      'collation_name', c.collation_name
    )
  from information_schema.columns c
  join target_tables tt on tt.table_name = c.table_name
  where c.table_schema = 'public'

  union all

  select
    'constraint',
    pg_catalog.format('%I.%I.%I', n.nspname, tbl.relname, con.conname),
    0,
    pg_catalog.jsonb_build_object(
      'constraint_type', con.contype,
      'definition', pg_catalog.pg_get_constraintdef(con.oid, true)
    )
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class tbl on tbl.oid = con.conrelid
  join pg_catalog.pg_namespace n on n.oid = tbl.relnamespace
  join target_tables tt on tt.table_name = tbl.relname
  where n.nspname = 'public'

  union all

  select
    'index',
    pg_catalog.format('%I.%I.%I', n.nspname, tbl.relname, idx.relname),
    0,
    pg_catalog.jsonb_build_object(
      'definition', pg_catalog.pg_get_indexdef(i.indexrelid)
    )
  from pg_catalog.pg_index i
  join pg_catalog.pg_class tbl on tbl.oid = i.indrelid
  join pg_catalog.pg_class idx on idx.oid = i.indexrelid
  join pg_catalog.pg_namespace n on n.oid = tbl.relnamespace
  join target_tables tt on tt.table_name = tbl.relname
  where n.nspname = 'public'

  union all

  select
    'trigger',
    pg_catalog.format('%I.%I.%I', n.nspname, tbl.relname, trg.tgname),
    0,
    pg_catalog.jsonb_build_object(
      'enabled', trg.tgenabled,
      'definition', pg_catalog.pg_get_triggerdef(trg.oid, true)
    )
  from pg_catalog.pg_trigger trg
  join pg_catalog.pg_class tbl on tbl.oid = trg.tgrelid
  join pg_catalog.pg_namespace n on n.oid = tbl.relnamespace
  join target_tables tt on tt.table_name = tbl.relname
  where n.nspname = 'public'
    and not trg.tgisinternal

  union all

  select
    'policy',
    pg_catalog.format('%I.%I.%I', p.schemaname, p.tablename, p.policyname),
    0,
    pg_catalog.jsonb_build_object(
      'permissive', p.permissive,
      'roles', p.roles,
      'command', p.cmd,
      'using_expression', p.qual,
      'with_check_expression', p.with_check
    )
  from pg_catalog.pg_policies p
  join target_tables tt on tt.table_name = p.tablename
  where p.schemaname = 'public'

  union all

  select
    'rls_state',
    pg_catalog.format('%I.%I', n.nspname, tbl.relname),
    0,
    pg_catalog.jsonb_build_object(
      'row_security_enabled', tbl.relrowsecurity,
      'row_security_forced', tbl.relforcerowsecurity,
      'owner', pg_catalog.pg_get_userbyid(tbl.relowner)
    )
  from pg_catalog.pg_class tbl
  join pg_catalog.pg_namespace n on n.oid = tbl.relnamespace
  join target_tables tt on tt.table_name = tbl.relname
  where n.nspname = 'public'
    and tbl.relkind in ('r', 'p')

  union all

  select
    'function',
    pg_catalog.format(
      '%I.%I(%s)',
      n.nspname,
      proc.proname,
      pg_catalog.pg_get_function_identity_arguments(proc.oid)
    ),
    0,
    pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(proc.proowner),
      'language', lang.lanname,
      'security_definer', proc.prosecdef,
      'volatility', proc.provolatile,
      'parallel', proc.proparallel,
      'configuration', proc.proconfig,
      'definition', pg_catalog.pg_get_functiondef(proc.oid)
    )
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace n on n.oid = proc.pronamespace
  join pg_catalog.pg_language lang on lang.oid = proc.prolang
  where n.nspname = 'public'
    and proc.proname = 'heha_set_updated_at'
    and pg_catalog.pg_get_function_identity_arguments(proc.oid) = ''
)
select pg_catalog.jsonb_build_object(
  'record_type', cr.record_type,
  'object_identity', cr.object_identity,
  'ordinal', cr.ordinal,
  'metadata', cr.metadata
)::text as normalized_row
from catalog_rows cr
order by
  cr.record_type collate "C",
  cr.object_identity collate "C",
  cr.ordinal,
  cr.metadata::text collate "C";
