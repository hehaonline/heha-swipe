-- REVIEW-ONLY CATALOG INVENTORY FOR ISSUE #121.
-- Forbidden against Production. Run only in an explicitly authorized disposable
-- or non-production database. This is not a migration and never reads application
-- table rows. It emits metadata only and always rolls back.

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '1s';
SET LOCAL idle_in_transaction_session_timeout = '10s';

-- Partner identity/routing columns present in this exact schema.
SELECT
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable
FROM information_schema.columns AS c
WHERE c.table_schema = 'public'
  AND c.table_name = 'partners'
ORDER BY c.ordinal_position;

-- Candidate identity and reference columns throughout the schema.
SELECT
  c.table_schema,
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.is_nullable
FROM information_schema.columns AS c
WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
  AND c.column_name IN (
    'partner_id',
    'related_partner_id',
    'swipe_partner_id',
    'owner_id',
    'google_place_id',
    'website',
    'website_url',
    'phone',
    'contact',
    'email',
    'instagram',
    'name',
    'business_name',
    'location',
    'address',
    'neighborhood'
  )
ORDER BY c.table_schema, c.table_name, c.ordinal_position;

-- Incoming foreign keys to public.partners, including update/delete behavior.
SELECT
  child_ns.nspname AS child_schema,
  child.relname AS child_table,
  child_col.attname AS child_column,
  con.conname AS constraint_name,
  parent_col.attname AS parent_column,
  CASE con.confupdtype
    WHEN 'a' THEN 'no_action'
    WHEN 'r' THEN 'restrict'
    WHEN 'c' THEN 'cascade'
    WHEN 'n' THEN 'set_null'
    WHEN 'd' THEN 'set_default'
    ELSE con.confupdtype::text
  END AS on_update,
  CASE con.confdeltype
    WHEN 'a' THEN 'no_action'
    WHEN 'r' THEN 'restrict'
    WHEN 'c' THEN 'cascade'
    WHEN 'n' THEN 'set_null'
    WHEN 'd' THEN 'set_default'
    ELSE con.confdeltype::text
  END AS on_delete
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS child ON child.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
JOIN pg_catalog.pg_class AS parent ON parent.oid = con.confrelid
JOIN pg_catalog.pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS child_key(attnum, ord) ON true
JOIN LATERAL unnest(con.confkey) WITH ORDINALITY AS parent_key(attnum, ord)
  ON parent_key.ord = child_key.ord
JOIN pg_catalog.pg_attribute AS child_col
  ON child_col.attrelid = child.oid AND child_col.attnum = child_key.attnum
JOIN pg_catalog.pg_attribute AS parent_col
  ON parent_col.attrelid = parent.oid AND parent_col.attnum = parent_key.attnum
WHERE con.contype = 'f'
  AND parent_ns.nspname = 'public'
  AND parent.relname = 'partners'
ORDER BY child_ns.nspname, child.relname, con.conname, child_key.ord;

-- Constraints containing a partner identity column (names/types only; no row
-- values). The EXISTS filter selects relevant constraints without removing the
-- other columns from a composite constraint's ordered column inventory.
SELECT
  ns.nspname AS table_schema,
  rel.relname AS table_name,
  con.conname AS constraint_name,
  con.contype AS constraint_type,
  array_agg(att.attname ORDER BY key.ord) AS columns,
  referenced_ns.nspname AS referenced_schema,
  referenced_rel.relname AS referenced_table,
  array_agg(referenced_att.attname ORDER BY referenced_key.ord)
    FILTER (WHERE con.contype = 'f') AS referenced_columns,
  CASE WHEN con.contype = 'f' THEN
    CASE con.confupdtype
      WHEN 'a' THEN 'no_action'
      WHEN 'r' THEN 'restrict'
      WHEN 'c' THEN 'cascade'
      WHEN 'n' THEN 'set_null'
      WHEN 'd' THEN 'set_default'
      ELSE con.confupdtype::text
    END
  END AS on_update,
  CASE WHEN con.contype = 'f' THEN
    CASE con.confdeltype
      WHEN 'a' THEN 'no_action'
      WHEN 'r' THEN 'restrict'
      WHEN 'c' THEN 'cascade'
      WHEN 'n' THEN 'set_null'
      WHEN 'd' THEN 'set_default'
      ELSE con.confdeltype::text
    END
  END AS on_delete
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS rel ON rel.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS key(attnum, ord) ON true
JOIN pg_catalog.pg_attribute AS att
  ON att.attrelid = rel.oid AND att.attnum = key.attnum
LEFT JOIN pg_catalog.pg_class AS referenced_rel ON referenced_rel.oid = con.confrelid
LEFT JOIN pg_catalog.pg_namespace AS referenced_ns ON referenced_ns.oid = referenced_rel.relnamespace
LEFT JOIN LATERAL unnest(con.confkey) WITH ORDINALITY AS referenced_key(attnum, ord)
  ON referenced_key.ord = key.ord
LEFT JOIN pg_catalog.pg_attribute AS referenced_att
  ON referenced_att.attrelid = referenced_rel.oid
  AND referenced_att.attnum = referenced_key.attnum
WHERE ns.nspname = 'public'
  AND rel.relname = 'partners'
  AND EXISTS (
    SELECT 1
    FROM unnest(con.conkey) AS identity_key(attnum)
    JOIN pg_catalog.pg_attribute AS identity_att
      ON identity_att.attrelid = rel.oid
      AND identity_att.attnum = identity_key.attnum
    WHERE identity_att.attname IN (
      'id',
      'owner_id',
      'google_place_id',
      'website',
      'phone',
      'contact',
      'instagram',
      'name',
      'location'
    )
  )
GROUP BY
  ns.nspname,
  rel.relname,
  con.conname,
  con.contype,
  referenced_ns.nspname,
  referenced_rel.relname,
  con.confupdtype,
  con.confdeltype
ORDER BY con.conname;

-- Index metadata for partner identity columns (never emits indexed values).
SELECT
  ns.nspname AS table_schema,
  rel.relname AS table_name,
  idx.relname AS index_name,
  ind.indisunique AS is_unique,
  ind.indisprimary AS is_primary,
  pg_catalog.pg_get_indexdef(ind.indexrelid, 0, true) AS index_definition,
  pg_catalog.pg_get_expr(ind.indexprs, ind.indrelid, true) AS index_expressions,
  pg_catalog.pg_get_expr(ind.indpred, ind.indrelid, true) AS index_predicate,
  array_agg(att.attname ORDER BY key.ord) FILTER (WHERE att.attname IS NOT NULL) AS columns
FROM pg_catalog.pg_index AS ind
JOIN pg_catalog.pg_class AS rel ON rel.oid = ind.indrelid
JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
JOIN pg_catalog.pg_class AS idx ON idx.oid = ind.indexrelid
JOIN LATERAL unnest(ind.indkey) WITH ORDINALITY AS key(attnum, ord) ON true
LEFT JOIN pg_catalog.pg_attribute AS att
  ON att.attrelid = rel.oid AND att.attnum = key.attnum
WHERE ns.nspname = 'public'
  AND rel.relname = 'partners'
GROUP BY
  ns.nspname,
  rel.relname,
  idx.relname,
  ind.indisunique,
  ind.indisprimary,
  pg_catalog.pg_get_indexdef(ind.indexrelid, 0, true),
  pg_catalog.pg_get_expr(ind.indexprs, ind.indrelid, true),
  pg_catalog.pg_get_expr(ind.indpred, ind.indrelid, true)
ORDER BY idx.relname;

-- Relations/views that declare a catalog dependency on public.partners.
SELECT DISTINCT
  dependent_ns.nspname AS dependent_schema,
  dependent.relname AS dependent_relation,
  dependent.relkind AS dependent_kind
FROM pg_catalog.pg_depend AS dep
JOIN pg_catalog.pg_rewrite AS rewrite
  ON rewrite.oid = dep.objid
  AND dep.classid = 'pg_rewrite'::regclass
JOIN pg_catalog.pg_class AS dependent ON dependent.oid = rewrite.ev_class
JOIN pg_catalog.pg_namespace AS dependent_ns ON dependent_ns.oid = dependent.relnamespace
JOIN pg_catalog.pg_class AS referenced
  ON referenced.oid = dep.refobjid
  AND dep.refclassid = 'pg_class'::regclass
JOIN pg_catalog.pg_namespace AS referenced_ns ON referenced_ns.oid = referenced.relnamespace
WHERE referenced_ns.nspname = 'public'
  AND referenced.relname = 'partners'
ORDER BY dependent_ns.nspname, dependent.relname;

-- Trigger and function names attached directly to public.partners. Function
-- bodies are intentionally excluded because they can contain sensitive text.
SELECT
  table_ns.nspname AS table_schema,
  table_rel.relname AS table_name,
  trigger.tgname AS trigger_name,
  trigger.tgenabled AS trigger_enabled,
  function_ns.nspname AS function_schema,
  function.proname AS function_name
FROM pg_catalog.pg_trigger AS trigger
JOIN pg_catalog.pg_class AS table_rel ON table_rel.oid = trigger.tgrelid
JOIN pg_catalog.pg_namespace AS table_ns ON table_ns.oid = table_rel.relnamespace
JOIN pg_catalog.pg_proc AS function ON function.oid = trigger.tgfoid
JOIN pg_catalog.pg_namespace AS function_ns ON function_ns.oid = function.pronamespace
WHERE NOT trigger.tgisinternal
  AND table_ns.nspname = 'public'
  AND table_rel.relname = 'partners'
ORDER BY trigger.tgname;

ROLLBACK;
