\set ON_ERROR_STOP on
begin;

create temporary table hybrid_results(label text primary key, ok boolean not null, detail text not null) on commit drop;
grant select,insert on table hybrid_results to authenticated,service_role;

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

create or replace function pg_temp.expect_state_detail(
  p_label text,
  p_expected_state text,
  p_expected_detail text,
  p_sql text
) returns void language plpgsql as $$
declare got_detail text;
begin
  execute p_sql;
  raise exception '% expected SQLSTATE % / DETAIL %, statement succeeded',
    p_label,p_expected_state,p_expected_detail;
exception when others then
  get stacked diagnostics got_detail = pg_exception_detail;
  if sqlstate=p_expected_state and got_detail=p_expected_detail then
    insert into hybrid_results values(
      p_label,
      true,
      'denied with SQLSTATE '||p_expected_state||' and DETAIL '||p_expected_detail
    );
  else
    raise exception '% expected SQLSTATE % / DETAIL %, got % / %: %',
      p_label,p_expected_state,p_expected_detail,sqlstate,coalesce(got_detail,'<empty>'),sqlerrm;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Metadata + deterministic ACL matrix.
-- ---------------------------------------------------------------------------
do $$
declare priv text; public_grants integer; tbl text; begin
  assert to_regclass('public.partner_claim_invites') is not null;
  assert to_regclass('public.partner_interest_requests') is not null;
  assert to_regclass('public.partner_lifecycle_events') is not null;
  assert to_regclass('public.partner_agreement_versions') is not null;
  assert to_regclass('public.partner_agreement_acceptances') is not null;
  assert to_regclass('app_private.partner_lifecycle_mutation_capabilities') is not null;
  assert to_regprocedure('public.create_partner_claim_invite(uuid,interval,text,uuid,text)') is not null;
  assert to_regprocedure('public.claim_partner_profile(text)') is not null;
  assert to_regprocedure('public.record_partner_agreement_acceptance(uuid,text,text,bytea)') is not null;
  assert to_regprocedure('public.approve_heha_partnership(uuid,uuid)') is not null;
  assert to_regprocedure('app_private.verified_permanent_claim_email(uuid)') is not null;
  assert to_regprocedure('app_private.is_service_role_request()') is not null;

  -- The evidence-free approval entry point must not exist at all.
  assert to_regprocedure('public.approve_heha_partnership(uuid)') is null,
    'evidence-free approve_heha_partnership(uuid) still callable';

  select count(*) into public_grants
  from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
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

  -- Agreement evidence is append-only through RPCs: nobody gets direct DML,
  -- including service_role, and anon gets nothing at all.
  foreach tbl in array array['public.partner_agreement_versions','public.partner_agreement_acceptances'] loop
    select count(*) into public_grants
    from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
    where c.oid=tbl::regclass and a.grantee=0;
    assert public_grants=0, 'PUBLIC has agreement-evidence privileges on '||tbl;

    assert has_table_privilege('authenticated',tbl,'SELECT');
    assert has_table_privilege('service_role',tbl,'SELECT');
    foreach priv in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
      assert not has_table_privilege('authenticated',tbl,priv), 'authenticated has '||priv||' on '||tbl;
      assert not has_table_privilege('service_role',tbl,priv), 'service_role has '||priv||' on '||tbl;
    end loop;
    foreach priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
      assert not has_table_privilege('anon',tbl,priv), 'anon has '||priv||' on '||tbl;
    end loop;
    assert relrowsecurity from pg_class where oid=tbl::regclass;
  end loop;

  assert not has_function_privilege('anon','public.claim_partner_profile(text)','execute');
  assert has_function_privilege('authenticated','public.claim_partner_profile(text)','execute');
  assert not has_function_privilege('anon','public.record_partner_agreement_acceptance(uuid,text,text,bytea)','execute');
  assert not has_function_privilege('anon','public.approve_heha_partnership(uuid,uuid)','execute');
  assert not has_function_privilege('authenticated','app_private.authorize_partner_lifecycle_mutation(uuid,text)','execute');
  assert not has_function_privilege('service_role','app_private.authorize_partner_lifecycle_mutation(uuid,text)','execute');
  assert not has_function_privilege('authenticated','app_private.partner_lifecycle_capability(uuid)','execute');
  assert not has_function_privilege('service_role','app_private.partner_lifecycle_capability(uuid)','execute');
  assert not has_function_privilege('authenticated','app_private.verified_permanent_claim_email(uuid)','execute');
  assert not has_function_privilege('service_role','app_private.verified_permanent_claim_email(uuid)','execute');
  assert not has_function_privilege('authenticated','app_private.is_service_role_request()','execute');
  assert not has_function_privilege('service_role','app_private.is_service_role_request()','execute');
  assert not has_table_privilege('authenticated','app_private.partner_lifecycle_mutation_capabilities','SELECT');
  assert not has_table_privilege('authenticated','app_private.partner_lifecycle_mutation_capabilities','INSERT');
  assert not has_table_privilege('service_role','app_private.partner_lifecycle_mutation_capabilities','INSERT');
  assert not exists(
    select 1 from pg_trigger
    where tgrelid='public.partners'::regclass
      and not tgisinternal
      and tgenabled='D'
  ), 'a public.partners user trigger remained disabled';
  assert not exists(select 1 from information_schema.sequences where sequence_schema='public' and sequence_name like 'partner_lifecycle_events%');
  insert into hybrid_results values('acl matrix',true,'claim + agreement-evidence ACLs, private single-use capability boundary and no lifecycle identity sequence verified');
end $$;

-- Structural evidence requirement exists at the constraint layer, not only in RPCs.
do $$ begin
  assert exists(select 1 from pg_constraint where conname='partners_signed_requires_evidence' and convalidated);
  assert exists(select 1 from pg_constraint where conname='partners_official_requires_evidence' and convalidated);
  assert exists(select 1 from pg_constraint where conname='partners_contract_evidence_fk');
  assert exists(
    select 1 from pg_constraint
    where conname='partner_agreement_acceptances_live_signer_check' and convalidated
  );
  insert into hybrid_results values('evidence constraints validated',true,'signed and official_partner are unreachable without a partner-matched acceptance row, enforced by validated CHECK plus composite FK');
end $$;

-- Ambiguous legacy HEHA Partner evidence fails closed: under_review, not official.
do $$ declare p public.partners; begin
  select * into p from public.partners where id='44444444-4444-4444-8444-444444444444';
  assert p.partnership_status='under_review';
  assert p.contract_status='not_signed';
  assert p.heha_partner=false;
  assert p.contract_evidence_id is null;
  assert not exists(select 1 from public.public_swipe_partners where id=p.id and heha_partner=true);
  insert into hybrid_results values('legacy partner fail closed',true,'legacy heha_partner=true maps to under_review/not_signed with no evidence and never renders Official Partner');
end $$;

-- ---------------------------------------------------------------------------
-- Claim issuance / recipient binding.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');

select pg_temp.expect_state_detail(
  'missing UUID recipient denied',
  '42501',
  'HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  $$select * from public.create_partner_claim_invite(
    '22222222-2222-4222-8222-222222222222',interval '1 day','proof',
    '88888888-8888-4888-8888-888888888888',null
  )$$
);
select pg_temp.expect_state_detail(
  'unverified UUID recipient denied',
  '42501',
  'HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  $$select * from public.create_partner_claim_invite(
    '22222222-2222-4222-8222-222222222222',interval '1 day','proof',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',null
  )$$
);
select pg_temp.expect_state_detail(
  'anonymous UUID recipient denied',
  '42501',
  'HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  $$select * from public.create_partner_claim_invite(
    '22222222-2222-4222-8222-222222222222',interval '1 day','proof',
    'ffffffff-ffff-4fff-8fff-ffffffffffff',null
  )$$
);
select pg_temp.expect_state_detail(
  'blank email UUID recipient denied',
  '42501',
  'HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  $$select * from public.create_partner_claim_invite(
    '22222222-2222-4222-8222-222222222222',interval '1 day','proof',
    '99999999-9999-4999-8999-999999999999',null
  )$$
);

do $$ begin
  assert not exists(
    select 1 from public.partner_claim_invites
    where partner_id='22222222-2222-4222-8222-222222222222'
  );
  assert (
    select claim_status='unclaimed' and owner_id is null
    from public.partners
    where id='22222222-2222-4222-8222-222222222222'
  );
  assert not exists(
    select 1 from public.partner_lifecycle_events
    where partner_id='22222222-2222-4222-8222-222222222222'
      and event_type in ('claim_invite_created','claim_redeemed')
  );
  insert into hybrid_results values(
    'ineligible UUID issuance leaves no residue',
    true,
    'missing, unverified, anonymous and blank-email UUID recipients create no invite, owner or success audit state'
  );
end $$;

select pg_temp.expect_state_detail(
  'already claimed profile code',
  '23505',
  'HEHA_CLAIM_ALREADY_CLAIMED',
  $$select * from public.create_partner_claim_invite(
    '33333333-3333-4333-8333-333333333333',interval '1 day','proof',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null
  )$$
);

select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state_detail(
  'unrecognized claim link code',
  'P0002',
  'HEHA_CLAIM_NOT_RECOGNIZED',
  $$select * from public.preview_partner_claim('not-a-real-token')$$
);

select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select raw_token as expired_token
from public.create_partner_claim_invite(
  '55555555-5555-4555-8555-555555555555',interval '1 day','proof',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null
) \gset
reset role;
update public.partner_claim_invites
set created_at=now()-interval '2 days', expires_at=now()-interval '1 day'
where partner_id='55555555-5555-4555-8555-555555555555'
  and consumed_at is null and revoked_at is null;
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state_detail(
  'expired claim link code','P0002','HEHA_CLAIM_EXPIRED',
  format('select * from public.preview_partner_claim(%L)',:'expired_token')
);

select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select invite_id as revoked_invite, raw_token as revoked_token
from public.create_partner_claim_invite(
  '55555555-5555-4555-8555-555555555555',interval '1 day','proof',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null
) \gset
select public.revoke_partner_claim_invite(:'revoked_invite');
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state_detail(
  'revoked claim link code','P0002','HEHA_CLAIM_REVOKED',
  format('select * from public.preview_partner_claim(%L)',:'revoked_token')
);

select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select raw_token as unavailable_token
from public.create_partner_claim_invite(
  '55555555-5555-4555-8555-555555555555',interval '1 day','proof',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null
) \gset
select public.set_partner_listing_status(
  '55555555-5555-4555-8555-555555555555','removed'
);
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state_detail(
  'unavailable profile code','42501','HEHA_CLAIM_PROFILE_UNAVAILABLE',
  format('select * from public.preview_partner_claim(%L)',:'unavailable_token')
);

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
select pg_temp.expect_state_detail(
  'unverified preview denied','42501','HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  format('select * from public.preview_partner_claim(%L)',:'unverified_token')
);
select pg_temp.expect_state_detail(
  'unverified claim denied','42501','HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  format('select * from public.claim_partner_profile(%L)',:'unverified_token')
);

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
select pg_temp.expect_state_detail(
  'reused token denied','P0002','HEHA_CLAIM_ALREADY_USED',
  format('select * from public.claim_partner_profile(%L)',:'unverified_token')
);

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.owner_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert p.claim_status='claimed';
  assert p.partnership_status='not_requested';
  assert p.contract_status='not_required';
  assert p.contract_evidence_id is null;
  assert p.id='11111111-1111-4111-8111-111111111111';
  assert exists(select 1 from public.saves where partner_id=p.id);
  assert exists(select 1 from public.swipes where partner_id=p.id);
  assert (select count(*) from public.partner_lifecycle_events where partner_id=p.id and event_type='claim_redeemed')=1;
  insert into hybrid_results values('claim preserves canonical identity',true,'same partners.id, saves and swipes retained; claimed does not imply partnership or contract');
end $$;

-- Direct protected self-promotion is denied after the claim capability is consumed.
select pg_temp.expect_state('owner self promotion denied','42501',
  $$update public.partners set partnership_status='official_partner',contract_status='signed',heha_partner=true where id='11111111-1111-4111-8111-111111111111'$$);

-- A caller-supplied GUC is not a capability and cannot bypass the owner guard.
select set_config('app.hybrid_partner_context','claim',true);
select pg_temp.expect_state('spoofed lifecycle context denied','42501',
  $$update public.partners set rating=5 where id='11111111-1111-4111-8111-111111111111'$$);
select set_config('app.hybrid_partner_context','',true);

-- Direct backend owner assignment outside the private verified-claim context is denied.
reset role;
select pg_temp.clear_auth();
select pg_temp.expect_state('direct backend owner assignment denied','42501',
  $$update public.partners set owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',claim_status='claimed' where id='22222222-2222-4222-8222-222222222222'$$);

-- ---------------------------------------------------------------------------
-- Regression: caller-supplied lifecycle contexts (PR #120 review P1).
-- Partner 6666 is owned by Business B and is in a pre-approval status, so main's
-- owner UPDATE policy admits the row and the owner guard is the last line.
-- Each context string is tried in turn; none may widen owner self-service.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
set local role authenticated;

-- Owner INSERT is normalized before constraints: caller-supplied relationship,
-- contract, listing and historical provenance can never survive the guard.
insert into public.partners(
  id,owner_id,name,category,categories,status,
  claim_status,claimed_at,claimed_by,
  partnership_status,partnership_requested_at,official_partner_since,
  contract_status,contract_evidence_id,contract_signed_at,
  listing_status,opted_out_at,opted_out_by,heha_partner
) values (
  '77777777-7777-4777-8777-777777777777',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'Owner Insert Provenance Proof',
  'Nourish',array['Nourish']::text[],'live',
  'claimed',timestamp with time zone '2000-01-01 00:00:00+00',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'official_partner',timestamp with time zone '2000-01-02 00:00:00+00',
  timestamp with time zone '2000-01-03 00:00:00+00',
  'signed','00000000-0000-4000-8000-000000000000',
  timestamp with time zone '2000-01-04 00:00:00+00',
  'opted_out',timestamp with time zone '2000-01-05 00:00:00+00',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',true
);

do $$ declare p public.partners; begin
  select * into p from public.partners
  where id='77777777-7777-4777-8777-777777777777';
  assert p.status='pending';
  assert p.owner_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  assert p.claim_status='claimed';
  assert p.claimed_by=p.owner_id;
  assert p.claimed_at > timestamp with time zone '2026-01-01 00:00:00+00';
  assert p.partnership_status='not_requested';
  assert p.partnership_requested_at is null;
  assert p.official_partner_since is null;
  assert p.contract_status='not_required';
  assert p.contract_evidence_id is null;
  assert p.contract_signed_at is null;
  assert p.listing_status='hidden';
  assert p.opted_out_at is null;
  assert p.opted_out_by is null;
  assert p.heha_partner=false;
  insert into hybrid_results values(
    'owner insert provenance normalized',true,
    'owner INSERT cannot forge lifecycle status, evidence, timestamps, opt-out actors or publication state'
  );
end $$;

-- Control: the same write is denied with no context at all.
select pg_temp.expect_state('owner protected field denied without context','42501',
  $$update public.partners set rating=5 where id='66666666-6666-4666-8666-666666666666'$$);

do $$
declare ctx text; begin
  foreach ctx in array array['owner_release','claim','partnership_request','partnership_review','listing_change','anything'] loop
    begin
      perform set_config('app.hybrid_partner_context',ctx,true);
      update public.partners set rating=5, routing_status='approved'
      where id='66666666-6666-4666-8666-666666666666';
      raise exception 'context % allowed a protected owner write',ctx;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  perform set_config('app.hybrid_partner_context','',true);
  insert into hybrid_results values('caller context never authorizes',true,
    'every caller-supplied app.hybrid_partner_context value, owner_release included, is rejected without a private capability');
end $$;

-- Regression: owner may not erase claim provenance (PR #120 review P2).
select pg_temp.expect_state('owner cannot erase claimed_by','42501',
  $$update public.partners set claimed_by=null where id='66666666-6666-4666-8666-666666666666'$$);
select pg_temp.expect_state('owner cannot erase claimed_by under owner_release','42501',
  $$select set_config('app.hybrid_partner_context','owner_release',true); update public.partners set claimed_by=null where id='66666666-6666-4666-8666-666666666666'$$);
select set_config('app.hybrid_partner_context','',true);

do $$ declare p public.partners; begin
  select * into p from public.partners where id='66666666-6666-4666-8666-666666666666';
  assert p.claim_status='claimed';
  assert p.claimed_by='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  assert p.owner_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  assert p.rating=0;
  assert p.routing_status='suggested';
  assert not exists(select 1 from public.partner_lifecycle_events where partner_id=p.id and event_type='owner_released');
  insert into hybrid_results values('claim provenance not owner erasable',true,
    'owner-authored claimed_by NULL writes are denied and never audited as an owner release while the row stays claimed');
end $$;
reset role;

-- Genuine FK cleanup still succeeds: a deleted Auth account releases its own
-- provenance reference. Partner 33333333 is owned by Business B, so a separate
-- opted_out_by reference is used here to exercise the pure-cleanup path.
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select public.opt_out_partner_listing('33333333-3333-4333-8333-333333333333');
reset role;
select pg_temp.clear_auth();

-- ---------------------------------------------------------------------------
-- Wrong account cannot use a verified-user-bound invite.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select raw_token as b_token
from public.create_partner_claim_invite(
  '22222222-2222-4222-8222-222222222222',interval '1 day','proof','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null
) \gset

-- UUID eligibility is rechecked after issuance, not trusted as a one-time fact.
reset role;
update auth.users
set email_confirmed_at=null
where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state_detail(
  'recipient verification downgrade blocks preview',
  '42501','HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  format('select * from public.preview_partner_claim(%L)',:'b_token')
);
select pg_temp.expect_state_detail(
  'recipient verification downgrade blocks claim',
  '42501','HEHA_CLAIM_RECIPIENT_INELIGIBLE',
  format('select * from public.claim_partner_profile(%L)',:'b_token')
);
do $$ begin
  assert (
    select consumed_at is null and consumed_by is null
    from public.partner_claim_invites
    where partner_id='22222222-2222-4222-8222-222222222222'
      and revoked_at is null
  );
  assert (
    select owner_id is null
    from public.partners
    where id='22222222-2222-4222-8222-222222222222'
  );
  assert not exists(
    select 1 from public.partner_lifecycle_events
    where partner_id='22222222-2222-4222-8222-222222222222'
      and event_type='claim_redeemed'
  );
  insert into hybrid_results values(
    'post-issuance recipient downgrade leaves no residue',true,
    'verification loss blocks preview and redemption without consuming the invite or assigning ownership'
  );
end $$;

reset role;
update auth.users
set email_confirmed_at=now()
where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select pg_temp.expect_state_detail(
  'wrong recipient denied','42501','HEHA_CLAIM_RECIPIENT_MISMATCH',
  format('select * from public.claim_partner_profile(%L)',:'b_token')
);

-- Recipient deletion creates a tombstone; recreating same email cannot inherit old link.
reset role;
delete from auth.users where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous,created_at,updated_at)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','authenticated','authenticated','owner-a@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}',false,false,now(),now());
select pg_temp.set_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.expect_state_detail(
  'deleted recipient tombstone denies recreated account',
  '42501','HEHA_CLAIM_REVOKED',
  format('select * from public.claim_partner_profile(%L)',:'b_token')
);

do $$ declare i public.partner_claim_invites; begin
  select * into i from public.partner_claim_invites where partner_id='22222222-2222-4222-8222-222222222222' and consumed_at is null and revoked_at is null;
  assert i.intended_user_id is null and i.intended_email_normalized is null;
  insert into hybrid_results values('recipient deletion tombstone',true,'deleted verified recipient cannot be replaced by account recreation with same email');
end $$;

-- ---------------------------------------------------------------------------
-- Partnership-interest evidence.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
insert into public.partner_interest_requests(partner_id,owner_id,contact_consent,swipe_card_interest,heha_local_interest,starter_items)
values('11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',true,true,false,'[]'::jsonb);

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.partnership_status='requested'; assert p.contract_status='not_signed'; assert p.heha_partner=false;
  assert p.contract_evidence_id is null;
  insert into hybrid_results values('partnership request evidence',true,'consent-bearing request advances claimed listing to requested/not_signed only, with no contract evidence');
end $$;

-- Internal review moves Business A into the reviewed state used by every
-- approval case below.
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select public.review_partner_partnership('11111111-1111-4111-8111-111111111111','under_review');

-- ---------------------------------------------------------------------------
-- Business A / Business B authorization matrix.
-- Business A profile = 11111111 (owner E). Business B profile = 33333333 (owner B).
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

do $$ begin
  assert (select count(*) from public.partner_interest_requests)=0;
  insert into hybrid_results values('partner request BOLA',true,'Business B owner cannot see Business A partnership request');
end $$;

do $$ begin
  assert (select count(*) from public.partner_lifecycle_events)=0;
  insert into hybrid_results values('lifecycle audit BOLA',true,'Business B owner cannot read any partner lifecycle audit row');
end $$;

select pg_temp.expect_state('B cannot opt out A listing','42501',
  $$select public.opt_out_partner_listing('11111111-1111-4111-8111-111111111111')$$);
select pg_temp.expect_state('B cannot review A partnership','42501',
  $$select public.review_partner_partnership('11111111-1111-4111-8111-111111111111','under_review')$$);
select pg_temp.expect_state('B cannot set A listing status','42501',
  $$select public.set_partner_listing_status('11111111-1111-4111-8111-111111111111','listed')$$);
select pg_temp.expect_state('B cannot issue A claim invite','42501',
  $$select * from public.create_partner_claim_invite('11111111-1111-4111-8111-111111111111',interval '1 day','bola',null,'owner-b@example.invalid')$$);
select pg_temp.expect_state('B cannot register agreement version','42501',
  $$select public.register_partner_agreement_version('BOLA-ATTEMPT',extensions.digest('bola','sha256'))$$);

-- A caller-writable JWT claim is not service authority. The active database role
-- remains authenticated, so the forged claim cannot cross the admin boundary.
select set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"service_role"}',
  true
);
select pg_temp.expect_state('forged JWT service role denied','42501',
  $$select public.register_partner_agreement_version(
    'FORGED-SERVICE-ROLE',extensions.digest('forged','sha256')
  )$$
);
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

-- Business B cannot write Business A's partner row at all: RLS denies the row,
-- so the UPDATE matches nothing rather than mutating protected state.
do $$ declare touched integer; begin
  update public.partners set bio='bola' where id='11111111-1111-4111-8111-111111111111';
  get diagnostics touched = row_count;
  assert touched=0, 'Business B UPDATE reached Business A row';
  insert into hybrid_results values('cross business write BOLA',true,'Business B owner UPDATE against Business A partner row matches zero rows under RLS');
end $$;
reset role;

-- Positive control: the PostgREST-selected database role itself is accepted,
-- even without a user JWT. A missing version makes this a no-op authorization
-- proof rather than a state mutation.
select pg_temp.clear_auth();
set local role service_role;
do $$ begin
  assert public.retire_partner_agreement_version(
    '00000000-0000-4000-8000-000000000000'
  )=false;
  insert into hybrid_results values(
    'database service role authority',true,
    'service authority is derived from the active database role, not request.jwt.claims'
  );
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Agreement evidence: versions, acceptance, and every negative approval case.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select public.register_partner_agreement_version('HEHA-PARTNER-2026-01',extensions.digest('heha-partner-agreement-2026-01','sha256')) as v1_id \gset

select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select public.record_partner_agreement_acceptance(
  '11111111-1111-4111-8111-111111111111','HEHA-PARTNER-2026-01','in_app_acceptance',
  extensions.digest('acceptance-a-v1','sha256')) as acc_v1 \gset

do $$ declare a public.partner_agreement_acceptances; p public.partners; begin
  select * into a from public.partner_agreement_acceptances where partner_id='11111111-1111-4111-8111-111111111111';
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert a.accepted_owner_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert a.accepted_by='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert a.acceptance_status='accepted';
  -- Recording acceptance is evidence only: it does not itself sign or promote.
  assert p.contract_status='not_signed';
  assert p.partnership_status='under_review';
  assert p.contract_evidence_id is null;
  assert exists(select 1 from public.partner_lifecycle_events
                where partner_id=p.id and event_type='agreement_accepted'
                  and after_state->>'agreement_acceptance_id'=a.id::text);
  -- The audit row references evidence by ID only.
  assert not exists(select 1 from public.partner_lifecycle_events
                    where event_type='agreement_accepted'
                      and (after_state ? 'evidence_sha256' or after_state ? 'document_sha256'));
  insert into hybrid_results values('acceptance evidence recorded',true,'owner acceptance stores version, signer, owner snapshot and source without signing the contract, and audits by evidence ID only');
end $$;

-- Evidence is immutable: no direct update or delete, by anyone.
reset role;
select pg_temp.expect_state('acceptance evidence immutable','42501',
  format($$update public.partner_agreement_acceptances set evidence_sha256=extensions.digest('tampered','sha256') where id=%L$$,:'acc_v1'));
select pg_temp.expect_state('acceptance evidence undeletable','42501',
  format($$delete from public.partner_agreement_acceptances where id=%L$$,:'acc_v1'));
select pg_temp.expect_state('agreement version immutable','42501',
  format($$update public.partner_agreement_versions set version='REWRITTEN' where id=%L$$,:'v1_id'));

-- NEGATIVE 1: missing evidence.
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select pg_temp.expect_state('approval denied: null evidence','22023',
  $$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',null)$$);
select pg_temp.expect_state('approval denied: missing evidence','P0002',
  $$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111','00000000-0000-4000-8000-000000000000')$$);

-- NEGATIVE 2: evidence belonging to a different partner.
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select public.record_partner_agreement_acceptance(
  '33333333-3333-4333-8333-333333333333','HEHA-PARTNER-2026-01','in_app_acceptance',
  extensions.digest('acceptance-b-v1','sha256')) as acc_other \gset
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select pg_temp.expect_state('approval denied: wrong partner evidence','42501',
  format($$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',%L)$$,:'acc_other'));

-- NEGATIVE 3: stale evidence for a superseded agreement version.
select public.register_partner_agreement_version('HEHA-PARTNER-2026-02',extensions.digest('heha-partner-agreement-2026-02','sha256')) as v2_id \gset
do $$ begin
  assert (select retired_at is not null from public.partner_agreement_versions where version='HEHA-PARTNER-2026-01');
  assert (select count(*) from public.partner_agreement_versions where retired_at is null)=1;
  assert not exists(
    select 1 from public.partner_agreement_acceptances
    where agreement_version_id=(
      select id from public.partner_agreement_versions
      where version='HEHA-PARTNER-2026-01'
    ) and acceptance_status='accepted'
  );
  insert into hybrid_results values(
    'agreement version supersession',true,
    'registering a new version retires the prior version, terminalizes its live acceptances and leaves exactly one current version'
  );
end $$;
select pg_temp.expect_state('approval denied: stale agreement version','42501',
  format($$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',%L)$$,:'acc_v1'));

-- Accepting a superseded version is refused at acceptance time too.
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select pg_temp.expect_state('acceptance denied: superseded version','42501',
  $$select public.record_partner_agreement_acceptance('11111111-1111-4111-8111-111111111111','HEHA-PARTNER-2026-01','in_app_acceptance',extensions.digest('late','sha256'))$$);

-- NEGATIVE 4: evidence signed by a different owner than the current one.
reset role;
insert into public.partner_agreement_acceptances(
  partner_id,agreement_version_id,accepted_owner_id,accepted_by,signature_source,evidence_sha256)
values('11111111-1111-4111-8111-111111111111',:'v2_id',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'recorded_offline',extensions.digest('wrong-owner','sha256'))
returning id as acc_wrong_owner \gset
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select pg_temp.expect_state('approval denied: wrong owner evidence','42501',
  format($$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',%L)$$,:'acc_wrong_owner'));
select public.revoke_partner_agreement_acceptance(:'acc_wrong_owner','revoked','proof cleanup');
do $$ begin
  assert (
    select acceptance_status='revoked' and revoked_at is not null
    from public.partner_agreement_acceptances
    where evidence_sha256=extensions.digest('wrong-owner','sha256')
  );
end $$;
select pg_temp.expect_state('approval denied: revoked evidence','42501',
  format($$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',%L)$$,:'acc_wrong_owner'));

-- NEGATIVE 5: live evidence cannot identify a different signer from the
-- immutable accepting-owner snapshot.
reset role;
select pg_temp.expect_state(
  'acceptance denied: signer differs from owner',
  '23514',
  format(
    $$insert into public.partner_agreement_acceptances(
      partner_id,agreement_version_id,accepted_owner_id,accepted_by,
      signature_source,evidence_sha256
    ) values (
      '11111111-1111-4111-8111-111111111111',%L,
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'recorded_offline',extensions.digest('mismatched-signer','sha256')
    )$$,
    :'v2_id'
  )
);

-- NEGATIVE 6: terminal evidence cannot be approved or reused.
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select public.record_partner_agreement_acceptance(
  '11111111-1111-4111-8111-111111111111','HEHA-PARTNER-2026-02',
  'in_app_acceptance',extensions.digest('terminated-evidence','sha256')
) as acc_terminated \gset
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select public.revoke_partner_agreement_acceptance(
  :'acc_terminated','terminated','terminated during proof'
);
select pg_temp.expect_state('approval denied: terminated evidence','42501',
  format($$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',%L)$$,:'acc_terminated'));

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.partnership_status='under_review';
  assert p.contract_status='not_signed';
  assert p.contract_evidence_id is null;
  assert p.heha_partner=false;
  assert not exists(select 1 from public.partner_lifecycle_events where partner_id=p.id and event_type='partnership_approved');
  assert not exists(select 1 from public.public_swipe_partners where id=p.id and heha_partner=true);
  insert into hybrid_results values('evidence negatives leave no residue',true,'missing, wrong-partner, stale, revoked, wrong-owner, mismatched-signer and terminated evidence all fail closed with no signed state and no approval audit row');
end $$;

-- Direct SQL cannot manufacture a signed contract either.
reset role;
select pg_temp.clear_auth();
select pg_temp.expect_state('direct signed state denied','42501',
  $$update public.partners set contract_status='signed',partnership_status='official_partner',heha_partner=true where id='11111111-1111-4111-8111-111111111111'$$);

-- ---------------------------------------------------------------------------
-- POSITIVE: current evidence, current owner, current version.
-- ---------------------------------------------------------------------------
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select public.record_partner_agreement_acceptance(
  '11111111-1111-4111-8111-111111111111','HEHA-PARTNER-2026-02','in_app_acceptance',
  extensions.digest('acceptance-a-v2','sha256')) as acc_v2 \gset

select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',:'acc_v2');

do $$ declare p public.partners; a public.partner_agreement_acceptances; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  select * into a from public.partner_agreement_acceptances where id=p.contract_evidence_id;
  assert p.partnership_status='official_partner'; assert p.contract_status='signed'; assert p.heha_partner=true;
  assert p.contract_evidence_id is not null;
  -- contract_signed_at is derived from the evidence, never invented by the RPC.
  assert p.contract_signed_at=a.accepted_at;
  assert a.partner_id=p.id;
  assert a.accepted_owner_id=p.owner_id;
  assert exists(select 1 from public.partner_lifecycle_events
                where partner_id=p.id and event_type='partnership_approved'
                  and after_state->>'agreement_acceptance_id'=a.id::text
                  and after_state->>'agreement_version_id'=a.agreement_version_id::text);
  assert exists(select 1 from public.public_swipe_partners where id=p.id and heha_partner=true);
  insert into hybrid_results values('official approval',true,'only a reviewed, claimed profile with current, owner-matched, unrevoked acceptance evidence becomes official/signed, and contract_signed_at is taken from the evidence');
end $$;

-- Partnership termination is an evidence terminal state, not merely a partner
-- status change. It clears the live pointer and frees the one-live-acceptance
-- index so a later, separately reviewed relationship can collect fresh evidence.
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select public.review_partner_partnership(
  '11111111-1111-4111-8111-111111111111','terminated'
);
do $$ declare p public.partners; a public.partner_agreement_acceptances; begin
  select * into p from public.partners
  where id='11111111-1111-4111-8111-111111111111';
  select * into a from public.partner_agreement_acceptances
  where evidence_sha256=extensions.digest('acceptance-a-v2','sha256');
  assert p.partnership_status='terminated';
  assert p.contract_status='terminated';
  assert p.contract_evidence_id is null;
  assert p.contract_signed_at is null;
  assert p.official_partner_since is null;
  assert p.heha_partner=false;
  assert a.acceptance_status='terminated';
  assert a.revoked_at is not null;
  insert into hybrid_results values(
    'partnership termination invalidates evidence',true,
    'termination clears signed partner state and terminalizes the live acceptance in one transaction'
  );
end $$;

update public.partner_interest_requests
set status='converted'
where partner_id='11111111-1111-4111-8111-111111111111'
  and status in ('submitted','reviewing','needs_info');
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
insert into public.partner_interest_requests(
  partner_id,owner_id,contact_consent,swipe_card_interest,heha_local_interest,starter_items
) values (
  '11111111-1111-4111-8111-111111111111',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',true,true,false,'[]'::jsonb
);
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select public.review_partner_partnership(
  '11111111-1111-4111-8111-111111111111','under_review'
);
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select public.record_partner_agreement_acceptance(
  '11111111-1111-4111-8111-111111111111','HEHA-PARTNER-2026-02',
  'in_app_acceptance',extensions.digest('acceptance-a-v2-reactivated','sha256')
) as acc_v2_reactivated \gset
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select public.approve_heha_partnership(
  '11111111-1111-4111-8111-111111111111',:'acc_v2_reactivated'
);
do $$ begin
  assert (
    select partnership_status='official_partner'
      and contract_status='signed'
      and contract_evidence_id is not null
    from public.partners
    where id='11111111-1111-4111-8111-111111111111'
  );
  assert (
    select acceptance_status='accepted'
    from public.partner_agreement_acceptances
    where evidence_sha256=extensions.digest('acceptance-a-v2-reactivated','sha256')
  );
  insert into hybrid_results values(
    'fresh evidence after termination',true,
    'a new reviewed relationship can record and approve fresh evidence after the prior acceptance was terminalized'
  );
end $$;

-- Revoking the in-use evidence immediately unwinds the signed contract.
select pg_temp.expect_state('cannot leave signed without evidence','42501',
  $$update public.partners set contract_evidence_id=null where id='11111111-1111-4111-8111-111111111111'$$);

-- Owner opt-out immediately removes the public projection without deleting ID.
select pg_temp.set_auth('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select public.opt_out_partner_listing('11111111-1111-4111-8111-111111111111');
do $$ begin
  assert not exists(select 1 from public.public_swipe_partners where id='11111111-1111-4111-8111-111111111111');
  assert exists(select 1 from public.partners where id='11111111-1111-4111-8111-111111111111');
  insert into hybrid_results values('opt out public removal',true,'listing disappears immediately while canonical Partner ID remains');
end $$;

-- Owner deletion/release resets claim provenance, unwinds signed state and
-- terminalizes the immutable acceptance record while preserving its snapshot.
reset role;
delete from auth.users where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
do $$ declare p public.partners; a public.partner_agreement_acceptances; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  select * into a from public.partner_agreement_acceptances
  where evidence_sha256=extensions.digest('acceptance-a-v2-reactivated','sha256');
  assert p.owner_id is null; assert p.claim_status='unclaimed'; assert p.claimed_at is null; assert p.claimed_by is null;
  assert p.partnership_status='under_review'; assert p.contract_status='not_signed'; assert p.heha_partner=false;
  assert p.contract_evidence_id is null;
  assert p.contract_signed_at is null;
  assert p.official_partner_since is null;
  -- The immutable owner snapshot survives; the live signer and acceptance do not.
  assert a.accepted_owner_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert a.accepted_by is null;
  assert a.acceptance_status='terminated';
  assert a.revoked_at is not null;
  insert into hybrid_results values(
    'owner deletion lifecycle',true,
    'account deletion clears claim and signed provenance, releases the live signer and terminalizes acceptance while retaining the immutable owner snapshot'
  );
end $$;

-- That released evidence is now unusable for a future approval. An internal
-- listing reset is required first: an opted-out listing is not invite eligible.
select pg_temp.set_auth('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select public.set_partner_listing_status('11111111-1111-4111-8111-111111111111','hidden');
select raw_token as reclaim_token
from public.create_partner_claim_invite(
  '11111111-1111-4111-8111-111111111111',interval '1 day','proof','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',null
) \gset
select pg_temp.set_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select * from public.claim_partner_profile(:'reclaim_token');
select pg_temp.set_auth('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
-- The prior owner's evidence is terminal and can never be inherited.
select pg_temp.expect_state('deleted owner evidence unusable after reclaim','42501',
  format($$select public.approve_heha_partnership('11111111-1111-4111-8111-111111111111',%L)$$,:'acc_v2_reactivated'));

do $$ declare p public.partners; begin
  select * into p from public.partners where id='11111111-1111-4111-8111-111111111111';
  assert p.owner_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  assert p.claim_status='claimed';
  assert p.partnership_status='under_review';
  insert into hybrid_results values('reclaim cannot inherit prior evidence',true,'a new owner cannot be promoted on the previous owner deleted acceptance evidence');
end $$;

-- Exact public compatibility: no claimed/under_review row may render official.
do $$ begin
  assert not exists(
    select 1
    from public.public_swipe_partners as public_partner
    join public.partners as partner_row on partner_row.id=public_partner.id
    where partner_row.partnership_status<>'official_partner'
      and public_partner.heha_partner=true
  );
  assert not exists(select 1 from public.partners where contract_status='signed' and contract_evidence_id is null);
  assert not exists(select 1 from public.partners where partnership_status='official_partner' and contract_evidence_id is null);
  insert into hybrid_results values('public compatibility',true,'public heha_partner is derived only from official_partner and no signed/official row exists without evidence');
end $$;

select label,ok,detail from hybrid_results order by label;
rollback;
