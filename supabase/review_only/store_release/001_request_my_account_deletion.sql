-- REVIEW ONLY. Do not apply through migration automation.
-- Purpose: authenticated, no-argument deletion-request receipt for store review.
-- Preconditions (verify against the live schema before approval):
--   * public.account_deletion_requests has id uuid, user_id uuid, email text,
--     reason text, status text not null default, and created_at timestamptz
--     not null default now().
--   * RLS is enabled and SELECT/INSERT policies restrict rows to
--     auth.uid() = user_id.
--   * Existing duplicate user_id rows have been reviewed and reconciled.
--   * Direct table access can be reduced to SELECT and INSERT for authenticated;
--     public and anon require no privileges on this private request queue.

-- Narrow existing broad browser-role grants before exposing the RPC. This is
-- intentionally limited to this table and leaves the owner/service role intact.
revoke all on table public.account_deletion_requests
  from public, anon, authenticated;
grant select, insert on table public.account_deletion_requests
  to authenticated;

-- The unique index is required for global idempotency. The function's advisory
-- lock serializes calls through this RPC; the index also protects against a
-- concurrent/direct insert permitted by the live table policy. Index creation
-- deliberately fails if historical duplicates still need owner review.
create unique index if not exists account_deletion_requests_one_per_user_idx
  on public.account_deletion_requests (user_id);

create or replace function public.request_my_account_deletion()
returns table (
  request_id uuid,
  status text,
  requested_at timestamptz
)
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  caller_id uuid := auth.uid();
  caller_email text := auth.jwt() ->> 'email';
  receipt_id uuid;
  receipt_created_at timestamptz;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Serialize requests for this authenticated identity so repeated taps and
  -- concurrent clients return one durable receipt instead of duplicate rows.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text, 0)
  );

  select request.id, request.created_at
    into receipt_id, receipt_created_at
    from public.account_deletion_requests as request
   where request.user_id = caller_id
   order by request.created_at asc, request.id asc
   limit 1;

  if receipt_id is not null then
    return query
      select receipt_id, 'already_requested'::text, receipt_created_at;
    return;
  end if;

  insert into public.account_deletion_requests (user_id, email, reason)
  values (
    caller_id,
    caller_email,
    'User requested full HEHA Swipe account deletion from the authenticated app.'
  )
  on conflict (user_id) do nothing
  returning id, created_at into receipt_id, receipt_created_at;

  if receipt_id is null then
    select request.id, request.created_at
      into receipt_id, receipt_created_at
      from public.account_deletion_requests as request
     where request.user_id = caller_id;

    if receipt_id is null then
      raise exception 'Could not create or retrieve deletion request receipt';
    end if;

    return query
      select receipt_id, 'already_requested'::text, receipt_created_at;
    return;
  end if;

  return query select receipt_id, 'requested'::text, receipt_created_at;
end;
$$;

revoke all on function public.request_my_account_deletion() from public, anon;
grant execute on function public.request_my_account_deletion() to authenticated;

comment on function public.request_my_account_deletion() is
  'Creates at most one deletion request for auth.uid() and returns its durable receipt. It does not claim deletion is complete.';

-- Reviewer verification (run as an authenticated test user):
-- select * from public.request_my_account_deletion();
-- select * from public.request_my_account_deletion();
-- Expected: the same non-null request_id/requested_at both times; first status
-- is 'requested' and the repeat status is 'already_requested'.
