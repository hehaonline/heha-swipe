-- SWP-016 read-only deep-structure manifest capture.
--
-- PREPARED ONLY. Execution requires a separate, explicit metadata-read approval.
--
-- Reads PostgreSQL catalog metadata for the `public` and `app_private`
-- application schemas. It does not select from application/Auth/storage rows,
-- read Vault/provider payloads, inspect function bodies or policy expressions,
-- alter configuration, or execute DDL/DML.
--
-- Output: deterministic UTF-8 JSONL ordered under C collation. Raw defaults,
-- constraint/index expressions, comments, enum labels, and role names are
-- withheld inside PostgreSQL; only allowlisted structural flags leave it.
--
-- This query is still blocked until its private/no-log execution path and
-- server-side redaction boundary receive independent approval.

begin;
set transaction read only;
set local search_path = pg_catalog;

with target_schemas(schema_name) as (
  values ('public'::name), ('app_private'::name)
),
catalog_rows(record_type, schema_name, object_name, object_identity, metadata) as (
  select
    'column'::text,
    n.nspname::text,
    att.attname::text,
    pg_catalog.format('%I.%I.%I', n.nspname, rel.relname, att.attname),
    pg_catalog.jsonb_build_object(
      'table_identity', pg_catalog.format('%I.%I', n.nspname, rel.relname),
      'ordinal', att.attnum,
      'data_type', pg_catalog.format_type(att.atttypid, att.atttypmod),
      'not_null', att.attnotnull,
      'identity', att.attidentity::text,
      'generated', att.attgenerated::text,
      'collation', case
        when att.attcollation = 0 then null
        else pg_catalog.format('%I.%I', coll_n.nspname, coll.collname)
      end,
      'default_present', def.oid is not null,
      'default_expression_withheld', def.oid is not null,
      'comment_present', pg_catalog.col_description(att.attrelid, att.attnum) is not null,
      'comment_withheld', pg_catalog.col_description(att.attrelid, att.attnum) is not null
    )
  from pg_catalog.pg_attribute att
  join pg_catalog.pg_class rel on rel.oid = att.attrelid
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  join target_schemas target on target.schema_name = n.nspname
  left join pg_catalog.pg_attrdef def
    on def.adrelid = att.attrelid
   and def.adnum = att.attnum
  left join pg_catalog.pg_collation coll on coll.oid = att.attcollation
  left join pg_catalog.pg_namespace coll_n on coll_n.oid = coll.collnamespace
  where rel.relkind in ('r', 'p')
    and att.attnum > 0
    and not att.attisdropped

  union all

  select
    'table_comment',
    n.nspname::text,
    rel.relname::text,
    pg_catalog.format('%I.%I', n.nspname, rel.relname),
    pg_catalog.jsonb_build_object(
      'table_identity', pg_catalog.format('%I.%I', n.nspname, rel.relname),
      'comment_present', pg_catalog.obj_description(rel.oid, 'pg_class') is not null,
      'comment_withheld', pg_catalog.obj_description(rel.oid, 'pg_class') is not null
    )
  from pg_catalog.pg_class rel
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  join target_schemas target on target.schema_name = n.nspname
  where rel.relkind in ('r', 'p')

  union all

  select
    'constraint',
    n.nspname::text,
    con.conname::text,
    pg_catalog.format('%I.%I.%I', n.nspname, rel.relname, con.conname),
    pg_catalog.jsonb_build_object(
      'table_identity', pg_catalog.format('%I.%I', n.nspname, rel.relname),
      'constraint_type', con.contype::text,
      'deferrable', con.condeferrable,
      'initially_deferred', con.condeferred,
      'validated', con.convalidated,
      'no_inherit', con.connoinherit,
      'definition_present', true,
      'definition_withheld', true
    )
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class rel on rel.oid = con.conrelid
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  join target_schemas target on target.schema_name = n.nspname
  where con.conrelid <> 0

  union all

  select
    'index',
    n.nspname::text,
    index_rel.relname::text,
    pg_catalog.format('%I.%I', n.nspname, index_rel.relname),
    pg_catalog.jsonb_build_object(
      'table_identity', pg_catalog.format('%I.%I', n.nspname, table_rel.relname),
      'unique', idx.indisunique,
      'primary', idx.indisprimary,
      'exclusion', idx.indisexclusion,
      'immediate', idx.indimmediate,
      'valid', idx.indisvalid,
      'ready', idx.indisready,
      'live', idx.indislive,
      'clustered', idx.indisclustered,
      'replica_identity', idx.indisreplident,
      'definition_present', true,
      'definition_withheld', true
    )
  from pg_catalog.pg_index idx
  join pg_catalog.pg_class index_rel on index_rel.oid = idx.indexrelid
  join pg_catalog.pg_class table_rel on table_rel.oid = idx.indrelid
  join pg_catalog.pg_namespace n on n.oid = table_rel.relnamespace
  join target_schemas target on target.schema_name = n.nspname

  union all

  select
    'enum_label',
    n.nspname::text,
    '[withheld]'::text,
    pg_catalog.format('%I.%I.%s', n.nspname, typ.typname, enum.enumsortorder),
    pg_catalog.jsonb_build_object(
      'type_identity', pg_catalog.format('%I.%I', n.nspname, typ.typname),
      'sort_order', enum.enumsortorder,
      'label_present', true,
      'label_withheld', true
    )
  from pg_catalog.pg_type typ
  join pg_catalog.pg_namespace n on n.oid = typ.typnamespace
  join target_schemas target on target.schema_name = n.nspname
  join pg_catalog.pg_enum enum on enum.enumtypid = typ.oid
  where typ.typtype = 'e'

  union all

  select
    'domain',
    n.nspname::text,
    typ.typname::text,
    pg_catalog.format('%I.%I', n.nspname, typ.typname),
    pg_catalog.jsonb_build_object(
      'base_type', pg_catalog.format_type(typ.typbasetype, typ.typtypmod),
      'not_null', typ.typnotnull,
      'collation', case
        when typ.typcollation = 0 then null
        else pg_catalog.format('%I.%I', coll_n.nspname, coll.collname)
      end,
      'default_present', typ.typdefault is not null,
      'default_expression_withheld', typ.typdefault is not null
    )
  from pg_catalog.pg_type typ
  join pg_catalog.pg_namespace n on n.oid = typ.typnamespace
  join target_schemas target on target.schema_name = n.nspname
  left join pg_catalog.pg_collation coll on coll.oid = typ.typcollation
  left join pg_catalog.pg_namespace coll_n on coll_n.oid = coll.collnamespace
  where typ.typtype = 'd'

  union all

  select
    'domain_constraint',
    n.nspname::text,
    con.conname::text,
    pg_catalog.format('%I.%I.%I', n.nspname, typ.typname, con.conname),
    pg_catalog.jsonb_build_object(
      'domain_identity', pg_catalog.format('%I.%I', n.nspname, typ.typname),
      'validated', con.convalidated,
      'definition_present', true,
      'definition_withheld', true
    )
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_type typ on typ.oid = con.contypid
  join pg_catalog.pg_namespace n on n.oid = typ.typnamespace
  join target_schemas target on target.schema_name = n.nspname
  where con.contypid <> 0

  union all

  select
    'sequence',
    n.nspname::text,
    rel.relname::text,
    pg_catalog.format('%I.%I', n.nspname, rel.relname),
    pg_catalog.jsonb_build_object(
      'owner_present', rel.relowner <> 0,
      'owner_withheld', true,
      'data_type', pg_catalog.format_type(seq.seqtypid, null),
      'start_value', seq.seqstart,
      'increment', seq.seqincrement,
      'minimum', seq.seqmin,
      'maximum', seq.seqmax,
      'cache', seq.seqcache,
      'cycle', seq.seqcycle
    )
  from pg_catalog.pg_sequence seq
  join pg_catalog.pg_class rel on rel.oid = seq.seqrelid
  join pg_catalog.pg_namespace n on n.oid = rel.relnamespace
  join target_schemas target on target.schema_name = n.nspname
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

commit;
