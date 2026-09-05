-- REVIEW ONLY. Do not apply through migration automation.
-- Trusted administrator fulfillment for an already-authenticated deletion
-- request. This packet permanently deletes a Supabase Auth identity and is
-- intentionally blocked on explicit action-time production approval.
begin;
create table if not exists public.account_deletion_fulfillment_receipts (
  request_id uuid primary key,
  requested_at timestamptz not null,
  completed_at timestamptz not null,
  receipt_version smallint not null default 1 check (receipt_version = 1),
  deleted_counts jsonb not null check (jsonb_typeof(deleted_counts) = 'object')
);
alter table public.account_deletion_fulfillment_receipts enable row level security;
revoke all on table public.account_deletion_fulfillment_receipts
  from public, anon, authenticated, service_role;
grant select on table public.account_deletion_fulfillment_receipts
  to service_role;
comment on table public.account_deletion_fulfillment_receipts is
  'De-identified, immutable proof that a trusted administrator fulfilled an account deletion request.';
create or replace function public.fulfill_account_deletion_request(
  p_request_id uuid
)
returns table (
  request_id uuid,
  requested_at timestamptz,
  completed_at timestamptz,
  deleted_counts jsonb,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row public.account_deletion_requests%rowtype;
  existing_receipt public.account_deletion_fulfillment_receipts%rowtype;
  target_user_id uuid;
  completion_time timestamptz;
  affected integer;
  counts jsonb := '{}'::jsonb;
begin
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'request id required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('heha:account-deletion:' || p_request_id::text, 0)
  );
  select *
  into existing_receipt
  from public.account_deletion_fulfillment_receipts as receipt
  where receipt.request_id = p_request_id;
  if found then
    return query select
      existing_receipt.request_id,
      existing_receipt.requested_at,
      existing_receipt.completed_at,
      existing_receipt.deleted_counts,
      true;
    return;
  end if;
  select *
  into request_row
  from public.account_deletion_requests as deletion_request
  where deletion_request.id = p_request_id
  for update;
  if not found or request_row.status <> 'requested' then
    raise exception using errcode = '22023', message = 'pending deletion request required';
  target_user_id := request_row.user_id;
  -- Accounts with partner ownership or records subject to commercial/financial
  -- retention need a case-specific reviewed plan; never cascade them here.
  if exists (
      select 1 from public.partners as partner
      where partner.owner_id = target_user_id
    )
    or exists (
      select 1 from public.orders as customer_order
      where customer_order.user_id = target_user_id
    )
    or exists (
      select 1 from public.contributions as contribution
      where contribution.user_id = target_user_id
    )
    or exists (
      select 1 from public.supporter_payments as payment
      where payment.user_id = target_user_id
    )
    or exists (
      select 1 from public.supporter_subscriptions as subscription
      where subscription.user_id = target_user_id
    )
  then
    raise exception using
      errcode = 'P0001',
      message = 'retained commercial or partner records require case review';
  end if;
  delete from public.community_offer_redemptions where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('community_offer_redemptions', affected);
  delete from public.discount_interest_requests where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('discount_interest_requests', affected);
  delete from public.in_app_messages where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('in_app_messages', affected);
  delete from public.notifications where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('notifications', affected);
  delete from public.reviews where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('reviews', affected);
  delete from public.saves where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('saves', affected);
  delete from public.swipe_events where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('swipe_events', affected);
  delete from public.user_roles where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('user_roles', affected);
  delete from public.vibe_settings where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('vibe_settings', affected);
  delete from public.customer_profiles where user_id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('customer_profiles', affected);
  delete from public.profiles where id = target_user_id;
  get diagnostics affected = row_count;
  counts := counts || pg_catalog.jsonb_build_object('profiles', affected);
  completion_time := pg_catalog.clock_timestamp();
  insert into public.account_deletion_fulfillment_receipts (
    request_id,
    requested_at,
    completed_at,
    deleted_counts
  ) values (
    request_row.id,
    request_row.created_at,
    completion_time,
    counts
  );
  -- The live request FK uses ON DELETE CASCADE, so the request row disappears
  -- with the Auth identity while the de-identified receipt above remains.
  delete from auth.users where id = target_user_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'Auth identity was not deleted';
  end if;
  return query select
    request_row.id,
    request_row.created_at,
    completion_time,
    counts,
    false;
end;
$$;
revoke all on function public.fulfill_account_deletion_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.fulfill_account_deletion_request(uuid)
  to service_role;
comment on function public.fulfill_account_deletion_request(uuid) is
  'Irreversible trusted-admin deletion. Rejects retained commercial/partner records and preserves a de-identified idempotent receipt.';
commit;
