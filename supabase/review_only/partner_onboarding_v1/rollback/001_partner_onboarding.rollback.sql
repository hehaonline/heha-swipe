-- Disposable teardown for the HEHA partner-onboarding V1 review packet.
--
-- REVIEW ONLY. Run only against the synthetic database assembled from
-- 000_minimal_baseline.sql. This is not a Production rollback and must never be
-- copied into the canonical Supabase migration chain.

begin;

do $review_only_guard$
begin
  if coalesce(pg_catalog.current_setting('heha.review_only', true), '') <> 'on'
     or pg_catalog.current_database() <> 'partner_onboarding_review'
     or coalesce(pg_catalog.host(pg_catalog.inet_server_addr()), '') not in ('127.0.0.1', '::1') then
    raise exception 'HEHA_REVIEW_ONLY_GUARD'
      using errcode = '42501',
            hint = 'Requires loopback database partner_onboarding_review and externally supplied heha.review_only=on.';
  end if;
end;
$review_only_guard$;

-- Remove receipt-backed public surfaces before their helper functions/tables.
drop view if exists public.public_local_partners;
drop view if exists public.public_swipe_partners;
drop view if exists public.public_partner_directory;

drop trigger if exists invalidate_partner_release_after_reviewed_change
  on public.partners;
drop trigger if exists guard_partner_business_identity_update_v1
  on public.partners;
drop trigger if exists guard_partner_business_key_correction_v1
  on partner_onboarding_private.partner_business_key_corrections;

drop policy if exists "Released public partner cards only"
  on public.partner_public_cards_v1;

drop function if exists public.get_partner_orderability_receipt_v1(uuid);
drop function if exists public.partner_card_is_current_v1(uuid, text, uuid, uuid);
drop function if exists public.partner_has_current_release_v1(uuid, text);

drop function if exists public.list_my_partner_onboarding_assignments_v1();
drop function if exists public.get_partner_onboarding_capabilities_v1(uuid);
drop function if exists public.record_category_partner_agreement_acceptance_v1(
  uuid, uuid, text, uuid, jsonb
);
drop function if exists public.get_partner_agreement_for_acceptance_v1(uuid);
drop function if exists public.revise_partner_profile_v1(uuid, uuid, jsonb);
drop function if exists public.revise_partner_application_v1(uuid, uuid, jsonb);
drop function if exists public.create_or_resume_partner_application_v1(uuid, jsonb);
drop function if exists public.claim_partner_invitation_v1(text, uuid);

drop function if exists partner_onboarding_private.revoke_partner_agreement_acceptance_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.revoke_staff_authority_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.grant_staff_authority_v1(
  uuid, text, uuid
);
drop function if exists partner_onboarding_private.bootstrap_staff_authority_v1(
  uuid, text
);
drop function if exists partner_onboarding_private.reconcile_partner_business_registry_v1(uuid);
drop function if exists partner_onboarding_private.set_runtime_config_v1(
  boolean, boolean, boolean, boolean, boolean, boolean, text, uuid
);
drop function if exists partner_onboarding_private.list_pending_partner_applications_v1(
  uuid, integer
);
drop function if exists partner_onboarding_private.issue_partner_invitation_v1(
  uuid, uuid, text, text, text, timestamptz, uuid
);
drop function if exists partner_onboarding_private.revoke_partner_invitation_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  uuid, text, uuid, uuid
);
drop function if exists partner_onboarding_private.revoke_partner_claim_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.revise_claimed_partner_profile_v1(
  uuid, uuid, jsonb
);
drop function if exists partner_onboarding_private.claim_editable_profile_sha256_v1(uuid);
drop function if exists partner_onboarding_private.revoke_partner_signer_authority_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.grant_partner_signer_authority_v1(
  uuid, uuid, text, text, uuid
);
drop function if exists partner_onboarding_private.select_partner_agreement_version_v1(
  uuid, uuid
);
drop function if exists partner_onboarding_private.register_partner_agreement_version_v1(
  text, text, text, timestamptz, text, text, text, jsonb, text, uuid, timestamptz
);
drop function if exists partner_onboarding_private.revoke_partner_evidence_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.issue_partner_evidence_v1(
  uuid, text, text, jsonb, uuid, uuid
);
drop function if exists partner_onboarding_private.revoke_partner_surface_activation_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.revoke_partner_release_v1(
  uuid, uuid, text
);
drop function if exists partner_onboarding_private.record_partner_surface_activation_v1(
  uuid, uuid, text, uuid, text, jsonb, uuid, uuid
);
drop function if exists partner_onboarding_private.finalize_partner_release_v1(
  uuid, text, uuid, uuid
);
drop function if exists partner_onboarding_private.invalidate_release_after_partner_change_v1();
drop function if exists partner_onboarding_private.surface_activation_receipt_id_v1(
  uuid, text
);
drop function if exists partner_onboarding_private.current_release_receipt_id_v1(uuid);
drop function if exists partner_onboarding_private.epoch_release_receipt_id_v1(uuid);
drop function if exists partner_onboarding_private.guard_partner_business_key_correction_v1();
drop function if exists partner_onboarding_private.guard_partner_business_identity_update_v1();
drop function if exists partner_onboarding_private.partner_business_identity_is_current_v1(
  uuid, text
);
drop function if exists partner_onboarding_private.current_partner_business_key_v1(uuid);

-- This internal guard is shared by the remaining private service transitions;
-- CASCADE is bounded to the disposable review namespace immediately before the
-- namespace itself is removed.
drop function if exists partner_onboarding_private.require_active_staff_authority_v1(
  uuid, text
) cascade;

-- Sensitive append-only teardown inventory removed by the one bounded private
-- schema CASCADE below: partner_reclassification_resets,
-- partner_claim_profile_corrections, partner_business_key_corrections, and
-- partner_profile_correction_requests and staff_bootstrap_authorizations.

drop table if exists public.partner_public_cards_v1;

-- CASCADE is intentional only inside this disposable namespace: helper
-- functions, forced-RLS tables, append-only triggers, receipts, and policies
-- all belong exclusively to this review packet.
drop schema if exists partner_onboarding_private cascade;

-- Remove only the fixed IDs created by the two-client synthetic proof. The SQL
-- lifecycle proof itself is transaction-rolled-back and leaves no rows.
delete from public.partners
  where (
    id = '91000000-0000-4000-8000-000000000001'
    and name = 'Synthetic Concurrency One'
    and bio = 'Synthetic concurrency one reviewed profile'
  )
  or (
    id = '91000000-0000-4000-8000-000000000002'
    and name = 'Synthetic Concurrency Two'
  )
  or (
    id = '91000000-0000-4000-8000-000000000003'
    and name = 'Synthetic Concurrency Existing Invite'
  )
  or (
    owner_id in (
      '00000000-0000-4000-8000-0000000000c3',
      '00000000-0000-4000-8000-0000000000d4'
    )
    and pg_catalog.lower(
      pg_catalog.regexp_replace(
        pg_catalog.btrim(name), '[[:space:]]+', ' ', 'g'
      )
    ) = 'synthetic concurrency business race'
    and pg_catalog.lower(
      pg_catalog.regexp_replace(
        pg_catalog.btrim(location), '[[:space:]]+', ' ', 'g'
      )
    ) = 'tampa, fl'
  );

do $concurrency_cleanup_closed$
begin
  if exists (
    select 1
    from public.partners partner
    where partner.id in (
      '91000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000002',
      '91000000-0000-4000-8000-000000000003'
    )
       or (
         partner.owner_id in (
           '00000000-0000-4000-8000-0000000000c3',
           '00000000-0000-4000-8000-0000000000d4'
         )
         and pg_catalog.lower(
           pg_catalog.regexp_replace(
             pg_catalog.btrim(partner.name), '[[:space:]]+', ' ', 'g'
           )
         ) = 'synthetic concurrency business race'
         and pg_catalog.lower(
           pg_catalog.regexp_replace(
             pg_catalog.btrim(partner.location), '[[:space:]]+', ' ', 'g'
           )
         ) = 'tampa, fl'
       )
  ) then
    raise exception 'Synthetic concurrency cleanup left a bounded proof row';
  end if;
end;
$concurrency_cleanup_closed$;

-- Restore the exact status-only compatibility surface from 000. This proves
-- clean teardown/rebuild only; it does not endorse the legacy model.
alter table public.partners enable row level security;
alter table public.partners force row level security;

revoke all on table public.partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select on table public.partners to anon, authenticated;
grant insert, update on table public.partners to authenticated;

drop policy if exists "Legacy partner owner inserts pending profile"
  on public.partners;
create policy "Legacy partner owner inserts pending profile"
on public.partners
for insert
to authenticated
with check (
  (select auth.uid()) = owner_id
  and status in ('draft', 'submitted', 'pending', 'missing_info')
  and is_test_record = false
);

drop policy if exists "Legacy partner owner updates pending profile"
  on public.partners;
create policy "Legacy partner owner updates pending profile"
on public.partners
for update
to authenticated
using (
  (select auth.uid()) = owner_id
  and status in ('draft', 'submitted', 'pending', 'missing_info')
)
with check (
  (select auth.uid()) = owner_id
  and status in ('draft', 'submitted', 'pending', 'missing_info')
  and is_test_record = false
);

drop policy if exists "Synthetic legacy public status visibility"
  on public.partners;
create policy "Synthetic legacy public status visibility"
on public.partners
for select
to anon, authenticated
using (
  status in ('approved', 'live')
  and is_test_record = false
);

drop policy if exists "Synthetic partner owner reads private profile"
  on public.partners;
create policy "Synthetic partner owner reads private profile"
on public.partners
for select
to authenticated
using ((select auth.uid()) = owner_id);

create or replace view public.public_partner_directory
with (security_invoker = true)
as
select p.*
from public.partners p
where p.status in ('approved', 'live')
  and coalesce(p.website_eligible, false)
  and p.is_test_record = false;

create or replace view public.public_swipe_partners
with (security_invoker = true)
as
select p.*
from public.partners p
where p.status in ('approved', 'live')
  and coalesce(p.swipe_eligible, false)
  and p.is_test_record = false;

create or replace view public.public_local_partners
with (security_invoker = true)
as
select p.*
from public.partners p
where p.status in ('approved', 'live')
  and coalesce(p.local_eligible, false)
  and p.local_lane is not null
  and p.is_test_record = false;

revoke all on table public.public_partner_directory
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on table public.public_swipe_partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on table public.public_local_partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

commit;
