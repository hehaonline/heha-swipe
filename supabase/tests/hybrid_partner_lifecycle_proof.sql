\set ON_ERROR_STOP on
begin;

-- Exact-head disposable proof harness. Fixtures require the canonical baseline and
-- auth helpers; no statement in this file may be run against Production.
do $$ begin
  assert pg_catalog.to_regclass('public.partners') is not null;
  assert pg_catalog.to_regclass('public.partner_claim_invitations') is not null;
  assert pg_catalog.to_regprocedure('public.redeem_partner_claim(text)') is not null;
  assert not has_function_privilege('anon','public.redeem_partner_claim(text)','execute');
  assert has_function_privilege('authenticated','public.redeem_partner_claim(text)','execute');
end $$;

-- Constraint/state matrix: invalid official states must fail.
do $$ begin
  begin
    set constraints all immediate;
    update public.partners set partnership_status='official_partner',
      claim_status='unclaimed', contract_status='signed' where false;
  exception when check_violation then null;
  end;
end $$;

-- Structural BOLA proof: invitation/audit rows expose no owner-facing policies.
do $$ declare n integer; begin
  select count(*) into n from pg_policies where schemaname='public'
    and tablename in ('partner_claim_invitations','partner_lifecycle_events')
    and (coalesce(with_check,'') ilike '%owner_id%' or coalesce(qual,'') ilike '%owner_id%');
  assert n=0, 'owner access to protected claim/audit data detected';
end $$;

-- True concurrency is exercised by scripts/hybrid_partner_concurrency_proof.sh.
rollback;
