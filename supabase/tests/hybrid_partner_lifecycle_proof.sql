\set ON_ERROR_STOP on
begin;

create temporary table hybrid_results(label text primary key, ok boolean not null, detail text not null) on commit drop;

create or replace function pg_temp.set_auth(p_user uuid,p_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user::text,'role',p_role)::text,true);
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('request.jwt.claim.role',p_role,true);
  perform set_config('app.hybrid_partner_context','',true);
end $$;

create or replace function pg_temp.clear_auth()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims','',true);
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.role','',true);
  perform set_config('app.hybrid_partner_context','',true);
end $$;

create or replace function pg_temp.expect_state(p_label text,p_expected text,p_sql text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception '% expected SQLSTATE %, statement succeeded',p_label,p_expected;
exception when others then
  if sqlstate=p_expected then
    insert into hybrid_results values(p_label,true,'denied with SQLSTATE '||p_expected);
  else
    raise exception '% expected SQLSTATE %, got %: %',p_label,p_expected,sqlstate,sqlerrm;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Metadata + deterministic ACL matrix.
-- ---------------------------------------------------------------------------
do $$
declare priv text; public_grants integer; begin
  assert to_regclass('public.partner_claim_invites') is not null;
  assert to_regclass('public.partner_interest_requests') is not null;
  assert to_regclass('public.partner_lifecycle_events') is not null;
  assert to_regprocedure('public.create_partner_claim_invite(uuid,interval,text,uuid,text)') is not null;
  assert to_regprocedure('public.claim_partner_profile(text)') is not null;
  assert to_regprocedure('public.approve_heha_partnership(uuid)') is not null;

  select count(*) into public_grants
  from pg_class c,cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
  where c.oid='public.partner_claim_invites'::regclass and a.grantee=0;
  assert public_grants=0,'PUBLIC has claim-table privileges';

  foreach priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
    if priv='SELECT' then
      assert has_table_privilege('authenticated','public.partner_claim_invites',priv);
      assert has_table_privilege('service_role','public.partner_claim_invites',priv);
    elsif priv in ('INSERT','UPDATE','DELETE') then
      assert not has_table_privilege('authenticated','public.partner_claim_invites',priv);
      assert has_table_privilege('service_role','public.partner_claim_invites',priv);
    else
      assert not has_table_privilege('authenticated','public.partner_claim_invites',priv);
      assert not has_table_privilege('service_role','public.partner_claim_invites',priv);
    end if;
    assert not has_table_privilege('anon','public.partner_claim_invites',priv);
  end loop;

  assert not has_function_privilege('anon','public.claim_partner_profile(text)','execute');
  assert has_function_privilege('authenticated','public.claim_partner_profile(text)','execute');
  assert not exists(select 1 from information_schema.sequences where sequence_schema='public' and sequence_name like 'partner_lifecycle_events%');
  insert into hybrid_results values('acl matrix',true,'PUBLIC/anon/authenticated/service_role seven-privilege matrix and no lifecycle identity sequence verified');
end $$;

-- Ambiguous legacy HEHA Partner evidence fails closed: under_review, not official.
do $$ declare p public.partners; begin
  select * into p from public.partners where id='44444444-4444-4444-8444-444444444444';
  assert p.partnership_status='under_review';
  assert p.contract_status='not_signed';
  assert p.heha_partner=false;
  assert not exists(select 1 from public.public_swipe_partners where id=p.id and heha_partner=true);
  insert into hybrid_results values('legacy partner fail closed',true,'legacy heha_partner=true maps to under_review/not_signed and never renders Official Partner');
end $$;

-- ---------------------------------------------------------------------------
-- Claim issuance / recipient binding.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select raw_token as unverified_token
from public.create_partner_claim_invite(
  '11111111-1111-4111-8111-111111111111',interval '1 day','proof',null,'unverified@example.invalid'
) \gset

do $$ declare i public.partner_claim_invites; begin
  select * into i from public.partner_claim_invites where partner_id='11111111-1111-4111-8111-111111111111' and consumed_at is null and revoked_at is null;
  assert i.intended_user_id is null;
  assert i.intended_email_normalized='unverified@example.invalid';
  assert (select claim_status from public.partners where id=i.partner_id)='claim_invited';
  insert into hybrid_results values('unverified email stays email bound',true,'pre-existing unverified account was not converted to user-id binding');
end $$;

select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select pg_temp.expect_state('unverified preview denied','42501',format('select * from public.preview_partner_claim(%L)',:'unverified_token'));
select pg_temp.expect_state('unverified claim denied','42501',format('select * from public.claim_partner_profile(%L)',:'unverified_token'));

do $$ begin
  assert (select owner_id is null from public.partners where id='11111111-1111-4111-8111-111111111111');
  assert (select consumed_at is null from public.partner_claim_invites where partner_id='11111111-1111-4111-8111-111111111111' and revoked_at is null);
  assert not exists(select 1 from public.partner_lifecycle_events where partner_id='11111111-1111-4111-8111-111111111111' and event_type='claim_redeemed');
end $$;

-- Verify same account, then claim once.
reset role;
update auth.users set email_confirmed_at=now() where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select * from public.preview_partner_claim(:'unverified_token');
select * from public.claim_partner_profile(:'unverified_token');
select pg_temp.expect_state('reused token denied','P0002',format('select * from public.claim_partner_profile(%L)',:'unverified_token'));

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.owner_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert p.claim_status='claimed';
  assert p.partnership_status='not_requested';
  assert p.contract_status='not_required';
  assert p.id='11111111-1111-4111-8111-111111111111';
  assert exists(select 1 from public.saves where partner_id=p.id);
  assert exists(select 1 from public.swipes where partner_id=p.id);
  assert (select count(*) from public.partner_lifecycle_events where partner_id=p.id and event_type='claim_redeemed')=1;
  insert into hybrid_results values('claim preserves canonical identity',true,'same partners.id, saves and swipes retained; claimed does not imply partnership');
end $$;

-- Direct protected self-promotion is denied.
select pg_temp.expect_state('owner self promotion denied','42501',
  $$update public.partners set partnership_status='official_partner',contract_status='signed',heha_partner=true where id='11111111-1111-4111-8111-111111111111'$$);

-- Direct backend owner assignment outside the private verified-claim context is denied.
reset role;
select pg_temp.clear_auth();
select pg_temp.expect_state('direct backend owner assignment denied','42501',
  $$update public.partners set owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',claim_status='claimed' where id='22222222-2222-4222-8222-222222222222'$$);

-- Wrong account cannot use a verified-user-bound invite.
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select raw_token as b_token
from public.create_partner_claim_invite(
  '22222222-2222-4222-8222-222222222222',interval '1 day','proof','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null
) \gset
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select pg_temp.expect_state('wrong recipient denied','42501',format('select * from public.claim_partner_profile(%L)',:'b_token'));

-- Recipient deletion creates a tombstone; recreating same email cannot inherit old link.
reset role;
delete from auth.users where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous,created_at,updated_at)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','authenticated','authenticated','owner-a@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now());
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state('deleted recipient tombstone denies recreated account','42501',format('select * from public.claim_partner_profile(%L)',:'b_token'));

do $$ declare i public.partner_claim_invites; begin
  select * into i from public.partner_claim_invites where partner_id='22222222-2222-4222-8222-222222222222' and consumed_at is null and revoked_at is null;
  assert i.intended_user_id is null and i.intended_email_normalized is null;
  insert into hybrid_results values('recipient deletion tombstone',true,'deleted verified recipient cannot be replaced by account recreation with same email');
end $$;

-- ---------------------------------------------------------------------------
-- Partnership-interest evidence and internal approval.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
insert into public.partner_interest_requests(partner_id,owner_id,contact_consent,swipe_card_interest,heha_local_interest,starter_items)
values('11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',true,true,false,'[]'::jsonb);

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.partnership_status='requested'; assert p.contract_status='not_signed'; assert p.heha_partner=false;
  insert into hybrid_results values('partnership request evidence',true,'consent-bearing request advances claimed listing to requested/not_signed only');
end $$;

-- BOLA: another ordinary user cannot see or update owner A's request.
set local role authenticated;
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
do $$ begin
  assert (select count(*) from public.partner_interest_requests)=0;
  insert into hybrid_results values('partner request BOLA',true,'Business B owner cannot see Business A partnership request');
end $$;
reset role;

-- Internal review, then super-admin approval.
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select public.review_partner_partnership('11111111-1111-4111-8111-111111111111','under_review');
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111');

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.partnership_status='official_partner'; assert p.contract_status='signed'; assert p.heha_partner=true;
  assert exists(select 1 from public.public_swipe_partners where id=p.id and heha_partner=true);
  insert into hybrid_results values('official approval',true,'only reviewed+claimed profile becomes official/signed and public compatibility badge is true');
end $$;

-- Owner opt-out immediately removes the public projection without deleting ID.
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select public.opt_out_partner_listing('11111111-1111-4111-8111-111111111111');
do $$ begin
  assert not exists(select 1 from public.public_swipe_partners where id='11111111-1111-4111-8111-111111111111');
  assert exists(select 1 from public.partners where id='11111111-1111-4111-8111-111111111111');
  insert into hybrid_results values('opt out public removal',true,'listing disappears immediately while canonical Partner ID remains');
end $$;

-- Owner deletion/release resets claim provenance and downgrades official status.
reset role;
delete from auth.users where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.owner_id is null; assert p.claim_status='unclaimed'; assert p.claimed_at is null; assert p.claimed_by is null;
  assert p.partnership_status='under_review'; assert p.contract_status='signed'; assert p.heha_partner=false;
  insert into hybrid_results values('owner deletion lifecycle',true,'account deletion clears claim provenance and downgrades Official Partner to review while retaining signed-contract evidence');
end $$;

-- Exact public compatibility: no claimed/under_review row may render official.
do $$ begin
  assert not exists(select 1 from public.public_swipe_partners where partnership_status<>'official_partner' and heha_partner=true);
  insert into hybrid_results values('public compatibility',true,'public heha_partner is derived only from official_partner');
end $$;

select label,ok,detail from hybrid_results order by label;
rollback;
