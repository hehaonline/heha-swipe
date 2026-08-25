# HEHA Swipe — Managed-Schema Sidecar Manifest (read-only capture, 2026-08-06)

Source: production `rqpdvgmewoyaigzquqmj` via read-only MCP catalog queries. Fresh-default reference: `uqdxzcgnqzveofgzpzii` (fresh project, Local staging). NO managed-schema tables or data were dumped. This manifest ships with the Swipe canonical-baseline PR; its objects replay ONLY after the fresh staging project's managed tables exist (they exist from project creation).

## HEHA-OWNED objects in managed schemas (present in prod, ABSENT in a fresh project)

### 1. Trigger on auth.users (exact definition)
```sql
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user()
```
Backing function (lives in `public`, will also be in the schema dump; captured verbatim):
```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (id, email)
    VALUES (new.id, new.email)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.customer_profiles (user_id)
    VALUES (new.id)
    ON CONFLICT (user_id) DO NOTHING;

  RETURN new;
END;
$function$
```
Note: confirms Swipe `public.profiles` carries an `email` column and `customer_profiles(user_id)` has a unique constraint — baseline must match.

### 2. Five HEHA policies on storage.objects (exact cmd/roles/USING/WITH CHECK)
```sql
CREATE POLICY "Internal users can manage pending partner media" ON storage.objects AS PERMISSIVE FOR ALL TO authenticated
  USING ((bucket_id = 'partner-media-pending'::text) AND app_private.has_internal_role(ARRAY['super_admin'::text, 'developer_admin'::text, 'pm_admin'::text]))
  WITH CHECK ((bucket_id = 'partner-media-pending'::text) AND app_private.has_internal_role(ARRAY['super_admin'::text, 'developer_admin'::text, 'pm_admin'::text]));

CREATE POLICY "Internal users can view pending partner media" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING ((bucket_id = 'partner-media-pending'::text) AND app_private.has_internal_role(ARRAY['super_admin'::text, 'developer_admin'::text, 'pm_admin'::text]));

CREATE POLICY "Owners can delete own pending partner media" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'partner-media-pending'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.owner_id = auth.uid()) AND ((p.id)::text = (storage.foldername(p.name))[2])))));

CREATE POLICY "Owners can upload own pending partner media" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'partner-media-pending'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.owner_id = auth.uid()) AND ((p.id)::text = (storage.foldername(p.name))[2])))));

CREATE POLICY "Owners can view own pending partner media" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING ((bucket_id = 'partner-media-pending'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.owner_id = auth.uid()) AND ((p.id)::text = (storage.foldername(p.name))[2])))));
```
(Quality note for review, not altered here: the two owner USING/WITH CHECK expressions call `storage.foldername(p.name)` on the PARTNER name — likely intended `storage.foldername(objects.name)`; flagged to Geronimo as a pre-existing prod oddity, reproduced verbatim for parity.)

### 3. Storage bucket CONFIGURATION (no object rows)
| id | public | file_size_limit | allowed_mime_types |
|---|---|---|---|
| `green-events` | **true** | null | null |
| `partner-media-pending` | false | 8388608 | image/jpeg, image/png, image/webp |

DRIFT FINDING: bucket `green-events` has NO repo migration (only partner-media-pending does), and the repo migration for partner-media-pending lacks the size/mime config. Both belong in the canonical baseline.

### 4. Required extensions and versions (prod Swipe)
`pg_net@0.20.3 (schema public)` ⚠ non-default location, `pg_stat_statements@1.11 (extensions)`, `pgcrypto@1.3 (extensions)`, `plpgsql@1.0 (pg_catalog)`, `supabase_vault@0.3.1 (vault)`, `uuid-ossp@1.1 (extensions)`.

### 5. Realtime publication membership
`supabase_realtime` = EMPTY in production (no HEHA tables added); `supabase_realtime_messages_publication` contains only platform-managed `realtime.messages_*` partitions. **No HEHA-owned realtime membership to replay.**

### 6. Auth hooks / auth-server configuration
No custom functions exist in the `auth` schema and no DB-visible auth hooks. Auth-server config (OAuth providers google/apple/facebook, email settings) lives in the Supabase platform dashboard, not the database — staging replicates only email/password auth for QA; OAuth stays unconfigured in staging (documented limitation).

## Supabase-provided DEFAULTS (present in BOTH prod and fresh project — must NOT enter the baseline)
Managed triggers: `storage.objects:update_objects_updated_at`, `storage.buckets:enforce_bucket_name_length_trigger`, `storage.buckets:protect_buckets_delete`, `storage.objects:protect_objects_delete`, `realtime.subscription:tr_check_filters`. Default publication shell `supabase_realtime[empty]`. No custom functions in auth/storage on either side.

## Replay ordering rule
Sidecar objects apply LAST, after: (1) fresh project managed schemas exist (automatic at creation), (2) baseline creates `public` + `app_private` objects (`handle_new_user`'s targets `profiles`/`customer_profiles`, and `app_private.has_internal_role` used by the storage policies), (3) buckets created/configured. Only then: the auth trigger + 5 storage policies.

## CORRECTIONS (Geronimo review, 2026-08-06 — binding)

1. **`public.handle_new_user()` exact ACL (verified live)**: `{postgres=X/postgres,service_role=X/postgres}` — EXECUTE restricted to `postgres` and `service_role` only. The baseline/sidecar MUST reproduce this exactly; never grant to PUBLIC/anon/authenticated.
2. **Security flag (separate hardening item, do NOT silently change prod)**: `handle_new_user()` is SECURITY DEFINER with **no fixed search_path** (`proconfig` empty) — documented for a separate reviewed hardening migration.
3. **RECLASSIFIED P1 — probable functional defect**: the three "Owners can …" storage policies use `storage.foldername(p.name)` (the PARTNER/business name) where `storage.foldername(objects.name)` (the storage object path) was almost certainly intended — the ownership condition likely always evaluates false, blocking partner owners from uploading/viewing/deleting their own pending media. Plan: reproduce with synthetic data in Swipe STAGING once it exists, add a focused test, and prepare any fix as a SEPARATE reviewed migration/PR. Production is not altered; the parity baseline reproduces production verbatim with this exception documented.
4. The fresh-default comparison used the Local staging project as reference and is **provisional**: every sidecar object gets revalidated against the actual Swipe staging project after creation.
