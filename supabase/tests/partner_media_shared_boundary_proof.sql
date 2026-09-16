-- Disposable synthetic database only. Every change rolls back.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE media_boundary_results(label text PRIMARY KEY);
GRANT INSERT,SELECT ON media_boundary_results TO authenticated;
CREATE FUNCTION pg_temp.ok(label text, ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
INSERT INTO media_boundary_results VALUES(label); END $$;
CREATE FUNCTION pg_temp.denied(label text, stmt text, wanted text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RAISE EXCEPTION 'Unexpected success: %',label;
EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>wanted THEN RAISE; END IF;
INSERT INTO media_boundary_results VALUES(label); END $$;
CREATE FUNCTION pg_temp.actor(id uuid) RETURNS void LANGUAGE sql AS $$
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true);
SELECT set_config('request.jwt.claim.sub',id::text,true); $$;
CREATE TEMP TABLE partner_before AS SELECT to_jsonb(p) AS row FROM public.partners p;
SELECT pg_temp.actor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SET LOCAL ROLE authenticated;
INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/boundary-1.jpg');
SELECT pg_temp.denied('owner sequential duplicate path',
 $q$INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
 VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cover',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/boundary-1.jpg')$q$,'23505');
INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/boundary-'||n||'.jpg'
FROM generate_series(2,6) n;
SELECT pg_temp.denied('seventh gallery rejected',
 $q$INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
 VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/boundary-7.jpg')$q$,'23514');
INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,change_type,replaces_url)
VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','remove','https://example.invalid/old.jpg');
SELECT pg_temp.ok('removal does not need a free upload slot',true);
INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',kind,
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/boundary-'||kind||'.jpg'
FROM unnest(ARRAY['logo','cover']) kind;
RESET ROLE;
SELECT pg_temp.actor('12121212-1212-4212-8212-121212121212');
SET LOCAL ROLE authenticated;
UPDATE public.partner_media_requests SET status='approved',review_note='Synthetic independent review'
WHERE partner_id='78787878-7878-4787-8787-787878787878' AND change_type='add';
SELECT pg_temp.ok('internal review timestamps and actor retained',
 (SELECT bool_and(reviewed_at IS NOT NULL AND reviewed_by='12121212-1212-4212-8212-121212121212')
 FROM public.partner_media_requests WHERE partner_id='78787878-7878-4787-8787-787878787878' AND change_type='add'));
RESET ROLE;
SELECT pg_temp.actor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied('approved logo still reserves slot',
 $q$INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
 VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','logo',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/second-logo.jpg')$q$,'23505');
SELECT pg_temp.denied('approved cover still reserves slot',
 $q$INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
 VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cover',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/second-cover.jpg')$q$,'23505');
RESET ROLE;
SELECT pg_temp.actor('12121212-1212-4212-8212-121212121212');
SET LOCAL ROLE authenticated;
UPDATE public.partner_media_requests SET status='applied'
WHERE storage_path LIKE '%/boundary-1.jpg';
RESET ROLE;
SELECT pg_temp.actor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SET LOCAL ROLE authenticated;
INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/boundary-7.jpg');
SELECT pg_temp.ok('applied frees gallery capacity despite removal request',true);
RESET ROLE;
SELECT pg_temp.actor('12121212-1212-4212-8212-121212121212');
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied('internal reactivation cannot overfill gallery',
 $q$UPDATE public.partner_media_requests SET status='needs_info' WHERE storage_path LIKE '%/boundary-1.jpg'$q$,'23514');
RESET ROLE;
SELECT set_config('request.jwt.claims','{}',true),set_config('request.jwt.claim.sub','',true);
SELECT pg_temp.denied('backend active writes share capacity',
 $q$INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
 VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','synthetic/backend-active.jpg')$q$,'23514');
INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path,status,review_note)
VALUES('78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery','synthetic/backend-history.jpg','applied','Backend history retained');
SELECT pg_temp.ok('backend terminal-history semantics retained',
 (SELECT status='applied' AND review_note='Backend history retained' FROM public.partner_media_requests WHERE storage_path='synthetic/backend-history.jpg'));
DELETE FROM public.partner_media_requests WHERE partner_id='78787878-7878-4787-8787-787878787878';
SELECT pg_temp.actor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SET LOCAL ROLE authenticated;
SELECT pg_temp.denied('seven-row statement rolls back atomically',
 $q$INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path)
 SELECT '78787878-7878-4787-8787-787878787878','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','gallery',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/78787878-7878-4787-8787-787878787878/bulk-'||n||'.jpg' FROM generate_series(1,7) n$q$,'23514');
SELECT pg_temp.ok('no partial bulk rows',(SELECT count(*)=0 FROM public.partner_media_requests WHERE partner_id='78787878-7878-4787-8787-787878787878'));
RESET ROLE;
SELECT pg_temp.ok('private serialization table has no client privileges',
 NOT has_table_privilege('authenticated','app_private.partner_media_serialization','SELECT,INSERT,UPDATE,DELETE')
 AND NOT has_table_privilege('service_role','app_private.partner_media_serialization','SELECT,INSERT,UPDATE,DELETE'));
SELECT pg_temp.ok('entire partner rows unchanged',
 NOT EXISTS ((SELECT to_jsonb(p) FROM public.partners p EXCEPT SELECT row FROM partner_before)
 UNION ALL (SELECT row FROM partner_before EXCEPT SELECT to_jsonb(p) FROM public.partners p)));
SELECT label FROM media_boundary_results ORDER BY label;
SELECT count(*) AS passing_shared_boundary_checks FROM media_boundary_results;
ROLLBACK;
