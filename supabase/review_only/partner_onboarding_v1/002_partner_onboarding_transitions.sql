-- HEHA partner onboarding V1 -- protected transition contract.
--
-- REVIEW ONLY / DISPOSABLE POSTGRESQL ONLY. This file is intentionally kept
-- outside supabase/migrations. It does not publish a partner, enable ordering,
-- or change a hosted Supabase project.

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

-- ---------------------------------------------------------------------------
-- Shared authorization, normalization, and current-evidence helpers.
-- ---------------------------------------------------------------------------

create or replace function partner_onboarding_private.raise_partner_request_denied_v1()
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  raise exception using
    errcode = 'P0001',
    message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.verified_auth_email_v1(
  p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select pg_catalog.lower(pg_catalog.btrim(u.email))
  from auth.users u
  where u.id = p_user_id
    and u.email_confirmed_at is not null
    and nullif(pg_catalog.btrim(u.email), '') is not null
    and pg_catalog.strpos(pg_catalog.btrim(u.email), '@') > 1;
$function$;

create or replace function partner_onboarding_private.normalized_person_text_v1(
  p_value text
)
returns text
language sql
immutable
set search_path = ''
as $function$
  select pg_catalog.lower(
    pg_catalog.regexp_replace(
      pg_catalog.btrim(coalesce(p_value, '')),
      '\s+',
      ' ',
      'g'
    )
  );
$function$;

create or replace function partner_onboarding_private.jsonb_text_array_v1(
  p_value jsonb
)
returns text[]
language sql
immutable
set search_path = ''
as $function$
  select coalesce(
    (
      select pg_catalog.array_agg(item.value order by item.ordinality)
      from pg_catalog.jsonb_array_elements_text(
        case
          when pg_catalog.jsonb_typeof(p_value) = 'array' then p_value
          else '[]'::jsonb
        end
      ) with ordinality as item(value, ordinality)
    ),
    array[]::text[]
  );
$function$;

create or replace function partner_onboarding_private.relationship_type_for_application_v1(
  p_application jsonb
)
returns text
language sql
immutable
set search_path = ''
as $function$
  with input_categories as (
    select pg_catalog.lower(
      pg_catalog.regexp_replace(pg_catalog.btrim(item.value), '\s+', ' ', 'g')
    ) as value
    from pg_catalog.jsonb_array_elements_text(
      case
        when pg_catalog.jsonb_typeof(p_application -> 'categories') = 'array' then
          case
            when pg_catalog.jsonb_array_length(p_application -> 'categories') > 0
              then p_application -> 'categories'
            else pg_catalog.jsonb_build_array(p_application ->> 'category')
          end
        else pg_catalog.jsonb_build_array(p_application ->> 'category')
      end
    ) as item(value)
    where nullif(pg_catalog.btrim(item.value), '') is not null
  ), candidates as (
    select 'restaurant'::text as relationship_type
    where exists (select 1 from input_categories where value = 'restaurant')

    union

    select 'catering'::text
    where exists (select 1 from input_categories where value = 'catering')

    union

    select 'solo_chef'::text
    where exists (
      select 1
      from input_categories
      where value in (
        'privatechef', 'private chef', 'solochef', 'solo chef', 'mealprep', 'meal prep'
      )
    )

    union

    select 'driver'::text
    where exists (select 1 from input_categories where value = 'driver')

    union

    select 'som'::text
    where exists (select 1 from input_categories where value = 'som')

    union

    select 'market'::text
    where exists (
      select 1
      from input_categories
      where value in ('grocery', 'farmersmarket', 'market', 'markets')
    )

    union

    select case
      when pg_catalog.lower(coalesce(p_application ->> 'business_type', '')) ~
        'grocery|farmers?\s*market|produce market'
        then 'market'::text
      else 'vendor'::text
    end
    where exists (select 1 from input_categories where value = 'vendor')
  )
  select case
    when pg_catalog.count(distinct candidates.relationship_type) = 1
      then pg_catalog.min(candidates.relationship_type)
    else null
  end
  from candidates;
$function$;

create or replace function partner_onboarding_private.has_active_staff_authority_v1(
  p_user_id uuid,
  p_authority_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select partner_onboarding_private.verified_auth_email_v1(p_user_id) is not null
    and exists (
    select 1
    from partner_onboarding_private.staff_authority_grants g
    where g.user_id = p_user_id
      and g.authority_type = p_authority_type
      and not exists (
        select 1
        from partner_onboarding_private.staff_authority_revocations r
        where r.authority_grant_id = g.id
      )
    );
$function$;

create or replace function partner_onboarding_private.require_active_staff_authority_v1(
  p_user_id uuid,
  p_authority_type text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or auth.uid() is distinct from p_user_id
     or partner_onboarding_private.verified_auth_email_v1(auth.uid()) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff-authority-registry', 0)
  );
  if partner_onboarding_private.has_active_staff_authority_v1(
       p_user_id, p_authority_type
     ) is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
end;
$function$;

create or replace function partner_onboarding_private.current_claim_receipt_id_v1(
  p_partner_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select c.id
  from partner_onboarding_private.partner_state s
  join partner_onboarding_private.partner_claims c
    on c.partner_id = s.partner_id
   and c.relationship_epoch = s.relationship_epoch
   and c.claim_epoch = s.claim_epoch
   and c.legal_relationship_type = s.legal_relationship_type
   and c.accepted_by = s.operator_user_id
   and c.accepted_owner_id = s.operator_user_id
  where s.partner_id = p_partner_id
    and s.operator_user_id is not null
    and not exists (
      select 1
      from partner_onboarding_private.partner_claim_revocations r
      where r.claim_id = c.id
    )
  order by c.accepted_at desc, c.id
  limit 1;
$function$;

create or replace function partner_onboarding_private.current_acceptance_receipt_id_v1(
  p_partner_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select a.id
  from partner_onboarding_private.partner_state s
  join partner_onboarding_private.partner_claims c
   on c.partner_id = s.partner_id
   and c.relationship_epoch = s.relationship_epoch
   and c.claim_epoch = s.claim_epoch
   and c.legal_relationship_type = s.legal_relationship_type
   and c.accepted_by = s.operator_user_id
   and c.accepted_owner_id = s.operator_user_id
  join partner_onboarding_private.current_agreement_versions cv
    on cv.legal_relationship_type = s.legal_relationship_type
  join partner_onboarding_private.partner_agreement_acceptances a
    on a.partner_id = s.partner_id
   and a.relationship_epoch = s.relationship_epoch
   and a.legal_relationship_type = s.legal_relationship_type
   and a.agreement_version_id = cv.agreement_version_id
   and a.accepted_owner_id = c.accepted_owner_id
   and a.accepted_at >= cv.selected_at
  join partner_onboarding_private.partner_actor_authority_grants g
    on g.partner_id = s.partner_id
   and g.user_id = a.accepted_by
   and g.authority_type = 'authorized_signer'
   and g.relationship_epoch = s.relationship_epoch
   and g.verified_email = a.signer_email
  where s.partner_id = p_partner_id
    and s.operator_user_id is not null
    and partner_onboarding_private.verified_auth_email_v1(a.accepted_by) = a.signer_email
    and not exists (
      select 1
      from partner_onboarding_private.partner_claim_revocations cr
      where cr.claim_id = c.id
    )
    and not exists (
      select 1
      from partner_onboarding_private.partner_actor_authority_revocations ar
      where ar.authority_grant_id = g.id
    )
    and not exists (
      select 1
      from partner_onboarding_private.partner_agreement_acceptance_revocations r
      where r.acceptance_id = a.id
    )
  order by a.accepted_at desc, a.id
  limit 1;
$function$;

create or replace function partner_onboarding_private.current_evidence_receipt_id_v1(
  p_partner_id uuid,
  p_evidence_type text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select e.id
  from partner_onboarding_private.partner_state s
  join lateral (
    select candidate.*
    from partner_onboarding_private.partner_evidence_receipts candidate
    where candidate.partner_id = s.partner_id
      and candidate.relationship_epoch = s.relationship_epoch
      and candidate.evidence_type = p_evidence_type
    order by candidate.issued_at desc, candidate.id desc
    limit 1
  ) e on true
  where s.partner_id = p_partner_id
    and not exists (
      select 1
      from partner_onboarding_private.partner_evidence_revocations r
      where r.evidence_id = e.id
    );
$function$;

create or replace function partner_onboarding_private.current_partner_business_key_v1(
  p_partner_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (
      select key_correction.corrected_business_key_sha256
      from partner_onboarding_private.partner_business_key_corrections key_correction
      join partner_onboarding_private.partner_application_corrections application_correction
        on application_correction.id = key_correction.application_correction_id
       and application_correction.application_id = key_correction.application_id
       and application_correction.partner_id = key_correction.partner_id
      where key_correction.partner_id = registry.partner_id
      order by application_correction.correction_number desc,
               application_correction.created_at desc,
               application_correction.id desc
      limit 1
    ),
    registry.business_key_sha256
  )
  from partner_onboarding_private.partner_business_registry registry
  where registry.partner_id = p_partner_id;
$function$;

create or replace function partner_onboarding_private.guard_partner_business_key_correction_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_business_key text;
  v_first_lock_key text;
  v_second_lock_key text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:business-registry', 0)
  );
  v_first_lock_key := least(
    new.previous_business_key_sha256,
    new.corrected_business_key_sha256
  );
  v_second_lock_key := greatest(
    new.previous_business_key_sha256,
    new.corrected_business_key_sha256
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:business:' || v_first_lock_key,
      0
    )
  );
  if v_second_lock_key is distinct from v_first_lock_key then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:business:' || v_second_lock_key,
        0
      )
    );
  end if;

  v_current_business_key :=
    partner_onboarding_private.current_partner_business_key_v1(new.partner_id);
  if v_current_business_key is distinct from new.previous_business_key_sha256
     or not exists (
       select 1
       from partner_onboarding_private.partner_business_registry registry
       where registry.partner_id = new.partner_id
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_business_registry conflicting_registry
       where conflicting_registry.partner_id <> new.partner_id
         and conflicting_registry.business_key_sha256 in (
           new.previous_business_key_sha256,
           new.corrected_business_key_sha256
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_business_key_corrections conflicting_key
       where conflicting_key.partner_id <> new.partner_id
         and (
           conflicting_key.previous_business_key_sha256 in (
             new.previous_business_key_sha256,
             new.corrected_business_key_sha256
           )
           or conflicting_key.corrected_business_key_sha256 in (
             new.previous_business_key_sha256,
             new.corrected_business_key_sha256
           )
         )
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  return new;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

drop trigger if exists guard_partner_business_key_correction_v1
  on partner_onboarding_private.partner_business_key_corrections;
create trigger guard_partner_business_key_correction_v1
before insert on partner_onboarding_private.partner_business_key_corrections
for each row execute function
  partner_onboarding_private.guard_partner_business_key_correction_v1();

create or replace function partner_onboarding_private.partner_business_identity_is_current_v1(
  p_partner_id uuid,
  p_root_business_key_sha256 text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (
      select registry.business_key_sha256 is not distinct from
               p_root_business_key_sha256
         and partner_onboarding_private.current_partner_business_key_v1(partner.id)
               is not distinct from partner_onboarding_private.normalized_business_key(
                 partner.name,
                 coalesce(partner.location, partner.neighborhood, partner.postal_code)
               )
      from public.partners partner
      join partner_onboarding_private.partner_business_registry registry
        on registry.partner_id = partner.id
      where partner.id = p_partner_id
        and partner.is_test_record is not true
        and nullif(pg_catalog.btrim(partner.name), '') is not null
        and nullif(
          pg_catalog.btrim(
            coalesce(partner.location, partner.neighborhood, partner.postal_code)
          ),
          ''
        ) is not null
    ),
    false
  );
$function$;

create or replace function partner_onboarding_private.guard_partner_business_identity_update_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_business_key text;
  v_requested_business_key text;
  v_location_key text;
begin
  if new.name is not distinct from old.name
     and new.location is not distinct from old.location
     and new.neighborhood is not distinct from old.neighborhood
     and new.postal_code is not distinct from old.postal_code then
    return new;
  end if;

  v_current_business_key :=
    partner_onboarding_private.current_partner_business_key_v1(old.id);
  v_location_key := coalesce(new.location, new.neighborhood, new.postal_code);
  if v_current_business_key is null
     or nullif(pg_catalog.btrim(new.name), '') is null
     or nullif(pg_catalog.btrim(v_location_key), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  v_requested_business_key := partner_onboarding_private.normalized_business_key(
    new.name,
    v_location_key
  );
  if v_requested_business_key is distinct from v_current_business_key then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  return new;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

drop trigger if exists guard_partner_business_identity_update_v1 on public.partners;
create trigger guard_partner_business_identity_update_v1
before update of name, location, neighborhood, postal_code on public.partners
for each row execute function
  partner_onboarding_private.guard_partner_business_identity_update_v1();

-- ---------------------------------------------------------------------------
-- Confirmed staff-authenticated review controls and evidence administration.
-- Raw invitation tokens are generated outside PostgreSQL and supplied once;
-- only their SHA-256 verifier is retained.
-- ---------------------------------------------------------------------------

create or replace function partner_onboarding_private.bootstrap_staff_authority_v1(
  p_user_id uuid,
  p_authority_type text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_authorization partner_onboarding_private.staff_bootstrap_authorizations%rowtype;
  v_existing partner_onboarding_private.staff_authority_grants%rowtype;
  v_id uuid;
begin
  if auth.uid() is null
     or auth.uid() is distinct from p_user_id
     or p_authority_type is distinct from 'security_admin'
     or partner_onboarding_private.verified_auth_email_v1(p_user_id) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- A database owner must pre-seed the immutable authorization row. There is
  -- no client/service insertion path and no service-callable break glass.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff-authority-registry', 0)
  );
  select bootstrap_auth.* into v_authorization
  from partner_onboarding_private.staff_bootstrap_authorizations bootstrap_auth
  where bootstrap_auth.user_id = p_user_id
    and bootstrap_auth.authority_type = 'security_admin'
  for share;
  if not found
     or nullif(pg_catalog.btrim(v_authorization.authorization_reference), '') is null
     or nullif(
       pg_catalog.btrim(v_authorization.authorized_by_database_role), ''
     ) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff:' || p_user_id::text, 0)
  );

  select g.*
  into v_existing
  from partner_onboarding_private.staff_authority_grants g
  where g.user_id = p_user_id
    and g.authority_type = 'security_admin'
    and not exists (
      select 1
      from partner_onboarding_private.staff_authority_revocations r
      where r.authority_grant_id = g.id
    )
  order by g.granted_at, g.id
  limit 1;

  if found then
    if v_existing.granted_by is distinct from p_user_id
       or exists (
      select 1
      from partner_onboarding_private.staff_authority_grants earlier
      where (earlier.granted_at, earlier.id) < (v_existing.granted_at, v_existing.id)
    ) then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
    return v_existing.id;
  end if;

  if exists (
    select 1 from partner_onboarding_private.staff_authority_grants
  ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.staff_authority_grants (
    user_id, authority_type, granted_by, granted_at
  ) values (
    p_user_id, 'security_admin', p_user_id, pg_catalog.clock_timestamp()
  ) returning id into v_id;

  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.grant_staff_authority_v1(
  p_user_id uuid,
  p_authority_type text,
  p_granted_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_existing partner_onboarding_private.staff_authority_grants%rowtype;
  v_id uuid;
begin
  if auth.uid() is null
     or auth.uid() is distinct from p_granted_by
     or p_authority_type is null
     or p_authority_type not in (
       'security_admin',
       'legal_admin',
       'evidence_reviewer',
       'release_reviewer',
       'swipe_attestor',
       'website_attestor',
       'local_attestor'
     )
     or partner_onboarding_private.verified_auth_email_v1(p_user_id) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff-authority-registry', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff:' || p_user_id::text, 0)
  );

  if partner_onboarding_private.has_active_staff_authority_v1(
       p_granted_by, 'security_admin'
     ) is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- Separation of duties is a state invariant, not a UI convention. A staff
  -- identity may hold exactly one active role, and a security administrator
  -- may not self-assign an operational review/attestation role.
  if p_granted_by = p_user_id
     and p_authority_type is distinct from 'security_admin' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select g.* into v_existing
  from partner_onboarding_private.staff_authority_grants g
  where g.user_id = p_user_id
    and g.authority_type = p_authority_type
    and not exists (
      select 1
      from partner_onboarding_private.staff_authority_revocations r
      where r.authority_grant_id = g.id
    )
  order by g.granted_at desc, g.id desc
  limit 1;
  if found then
    if exists (
      select 1
      from partner_onboarding_private.staff_authority_grants other_grant
      where other_grant.user_id = p_user_id
        and other_grant.id is distinct from v_existing.id
        and not exists (
          select 1
          from partner_onboarding_private.staff_authority_revocations other_revocation
          where other_revocation.authority_grant_id = other_grant.id
        )
    ) then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
    return v_existing.id;
  end if;

  if exists (
    select 1
    from partner_onboarding_private.staff_authority_grants active_grant
    where active_grant.user_id = p_user_id
      and not exists (
        select 1
        from partner_onboarding_private.staff_authority_revocations active_revocation
        where active_revocation.authority_grant_id = active_grant.id
      )
  ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.staff_authority_grants (
    user_id, authority_type, granted_by, granted_at
  ) values (
    p_user_id, p_authority_type, p_granted_by, pg_catalog.clock_timestamp()
  ) returning id into v_id;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revoke_staff_authority_v1(
  p_authority_grant_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_grant partner_onboarding_private.staff_authority_grants%rowtype;
  v_existing_id uuid;
  v_existing_revoked_by uuid;
  v_existing_reason_code text;
  v_id uuid;
begin
  if auth.uid() is null
     or auth.uid() is distinct from p_revoked_by
     or partner_onboarding_private.verified_auth_email_v1(p_revoked_by) is null
     or nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff-authority-registry', 0)
  );
  select g.* into v_grant
  from partner_onboarding_private.staff_authority_grants g
  where g.id = p_authority_grant_id;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff:' || v_grant.user_id::text, 0)
  );

  if partner_onboarding_private.has_active_staff_authority_v1(
       p_revoked_by, 'security_admin'
     ) is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select g.* into v_grant
  from partner_onboarding_private.staff_authority_grants g
  where g.id = p_authority_grant_id
  for update;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select r.id, r.revoked_by, r.reason_code
  into v_existing_id, v_existing_revoked_by, v_existing_reason_code
  from partner_onboarding_private.staff_authority_revocations r
  where r.authority_grant_id = v_grant.id;
  if found then
    if v_existing_revoked_by is not distinct from p_revoked_by
       and v_existing_reason_code is not distinct from pg_catalog.btrim(p_reason_code) then
      return v_existing_id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if v_grant.authority_type = 'security_admin'
     and (
       select pg_catalog.count(*)
       from partner_onboarding_private.staff_authority_grants active_admin
       where active_admin.authority_type = 'security_admin'
         and not exists (
           select 1
           from partner_onboarding_private.staff_authority_revocations revocation
           where revocation.authority_grant_id = active_admin.id
         )
     ) <= 1 then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.staff_authority_revocations (
    authority_grant_id, revoked_by, reason_code
  ) values (
    v_grant.id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  ) returning id into v_id;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.reconcile_partner_business_registry_v1(
  p_reconciled_by uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_partner public.partners%rowtype;
  v_registry_by_partner partner_onboarding_private.partner_business_registry%rowtype;
  v_business_key text;
  v_current_business_key text;
  v_eligible_count integer := 0;
  v_inserted_count integer := 0;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_reconciled_by, 'security_admin'
  );

  -- This global lock is the root of every business-identity transition. It is
  -- acquired after the staff-authority registry and before any partner row.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:business-registry', 0)
  );

  -- Fail closed before writing if two legacy rows normalize to one identity.
  if exists (
    select 1
    from (
      select partner_onboarding_private.normalized_business_key(
               partner.name,
               coalesce(partner.location, partner.neighborhood, partner.postal_code)
             ) as business_key_sha256
      from public.partners partner
      where partner.is_test_record is not true
        and nullif(pg_catalog.btrim(partner.name), '') is not null
        and nullif(
          pg_catalog.btrim(
            coalesce(partner.location, partner.neighborhood, partner.postal_code)
          ),
          ''
        ) is not null
      group by partner_onboarding_private.normalized_business_key(
        partner.name,
        coalesce(partner.location, partner.neighborhood, partner.postal_code)
      )
      having pg_catalog.count(*) <> 1
    ) duplicate_identity
  ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  for v_partner in
    select partner.*
    from public.partners partner
    where partner.is_test_record is not true
      and nullif(pg_catalog.btrim(partner.name), '') is not null
      and nullif(
        pg_catalog.btrim(
          coalesce(partner.location, partner.neighborhood, partner.postal_code)
        ),
        ''
      ) is not null
    order by partner.id
    for update
  loop
    v_eligible_count := v_eligible_count + 1;
    v_business_key := partner_onboarding_private.normalized_business_key(
      v_partner.name,
      coalesce(v_partner.location, v_partner.neighborhood, v_partner.postal_code)
    );
    select registry.* into v_registry_by_partner
    from partner_onboarding_private.partner_business_registry registry
    where registry.partner_id = v_partner.id
    for update;
    if v_registry_by_partner.partner_id is null then
      if exists (
        select 1
        from partner_onboarding_private.partner_business_registry conflicting_registry
        where conflicting_registry.business_key_sha256 = v_business_key
      )
         or exists (
           select 1
           from partner_onboarding_private.partner_business_key_corrections conflicting_key
           where conflicting_key.corrected_business_key_sha256 = v_business_key
         )
         or exists (
           select 1
           from partner_onboarding_private.partner_business_key_corrections orphan_key
           where orphan_key.partner_id = v_partner.id
         ) then
        perform partner_onboarding_private.raise_partner_request_denied_v1();
      end if;
      insert into partner_onboarding_private.partner_business_registry (
        partner_id,
        business_key_sha256,
        registration_source,
        registered_by,
        registered_at
      ) values (
        v_partner.id,
        v_business_key,
        'baseline',
        null,
        pg_catalog.clock_timestamp()
      );
      v_inserted_count := v_inserted_count + 1;
      v_current_business_key := v_business_key;
    else
      v_current_business_key :=
        partner_onboarding_private.current_partner_business_key_v1(v_partner.id);
    end if;

    if v_current_business_key is distinct from v_business_key
       or exists (
         select 1
         from partner_onboarding_private.partner_business_registry conflicting_registry
         where conflicting_registry.business_key_sha256 = v_current_business_key
           and conflicting_registry.partner_id <> v_partner.id
       )
       or exists (
         select 1
         from partner_onboarding_private.partner_business_key_corrections conflicting_key
         where conflicting_key.corrected_business_key_sha256 = v_current_business_key
           and conflicting_key.partner_id <> v_partner.id
       ) then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
  end loop;

  return pg_catalog.jsonb_build_object(
    'projection_version', 'heha-partner-business-registry-reconciliation-v1',
    'reconciled_by', p_reconciled_by,
    'eligible_partner_count', v_eligible_count,
    'inserted_reservation_count', v_inserted_count,
    'status', 'verified'
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.set_runtime_config_v1(
  p_claim_enabled boolean,
  p_application_enabled boolean,
  p_acceptance_enabled boolean,
  p_release_enabled boolean,
  p_swipe_publication_enabled boolean,
  p_local_ordering_enabled boolean,
  p_config_version text,
  p_updated_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_config partner_onboarding_private.runtime_config%rowtype;
  v_release_invalidation_required boolean := false;
  v_invalidated_partner_count integer := 0;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_updated_by, 'security_admin'
  );
  if p_claim_enabled is null
     or p_application_enabled is null
     or p_acceptance_enabled is null
     or p_release_enabled is null
     or p_swipe_publication_enabled is null
     or p_local_ordering_enabled is null
     or nullif(pg_catalog.btrim(p_config_version), '') is null
     or (p_release_enabled and (not p_claim_enabled or not p_acceptance_enabled))
     or (p_swipe_publication_enabled and not p_release_enabled)
     or (p_local_ordering_enabled and not p_release_enabled) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:business-registry', 0)
  );
  if p_application_enabled
     and (
       pg_catalog.has_table_privilege(
         'authenticated', 'public.partners', 'INSERT'
       )
       or pg_catalog.has_table_privilege(
         'authenticated', 'public.partners', 'UPDATE'
       )
       or exists (
       select 1
       from public.partners partner
       where partner.is_test_record is not true
         and nullif(pg_catalog.btrim(partner.name), '') is not null
         and nullif(
           pg_catalog.btrim(
             coalesce(partner.location, partner.neighborhood, partner.postal_code)
           ),
           ''
         ) is not null
         and (
           not exists (
             select 1
             from partner_onboarding_private.partner_business_registry registry
             where registry.partner_id = partner.id
           )
           or partner_onboarding_private.current_partner_business_key_v1(partner.id)
                is distinct from partner_onboarding_private.normalized_business_key(
                  partner.name,
                  coalesce(partner.location, partner.neighborhood, partner.postal_code)
                )
         )
       )
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select rc.* into v_config
  from partner_onboarding_private.runtime_config rc
  where rc.singleton
  for update;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_release_invalidation_required :=
    (v_config.claim_enabled and not p_claim_enabled)
    or (v_config.acceptance_enabled and not p_acceptance_enabled)
    or (v_config.release_enabled and not p_release_enabled)
    or (v_config.swipe_publication_enabled and not p_swipe_publication_enabled)
    or (v_config.local_ordering_enabled and not p_local_ordering_enabled);

  -- A gate shutdown is a release-generation boundary. Because every release
  -- and surface receipt is bound to release_epoch, a later re-enable cannot
  -- resurrect receipts that existed before the shutdown. Runtime config is
  -- locked before partner_state, matching the release finalizer's order.
  if v_release_invalidation_required then
    update partner_onboarding_private.partner_state
    set release_epoch = release_epoch + 1;
    get diagnostics v_invalidated_partner_count = row_count;
  end if;

  update partner_onboarding_private.runtime_config
  set claim_enabled = p_claim_enabled,
      application_enabled = p_application_enabled,
      acceptance_enabled = p_acceptance_enabled,
      release_enabled = p_release_enabled,
      swipe_publication_enabled = p_swipe_publication_enabled,
      local_ordering_enabled = p_local_ordering_enabled,
      config_version = pg_catalog.btrim(p_config_version),
      updated_by = p_updated_by
  where singleton;

  return pg_catalog.jsonb_build_object(
    'claim_enabled', p_claim_enabled,
    'application_enabled', p_application_enabled,
    'acceptance_enabled', p_acceptance_enabled,
    'release_enabled', p_release_enabled,
    'swipe_publication_enabled', p_swipe_publication_enabled,
    'local_ordering_enabled', p_local_ordering_enabled,
    'config_version', pg_catalog.btrim(p_config_version),
    'config_generation', pg_catalog.btrim(p_config_version),
    'release_epoch_invalidation_applied', v_release_invalidation_required,
    'release_epoch_invalidated_partner_count', v_invalidated_partner_count
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.list_pending_partner_applications_v1(
  p_reviewer uuid,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_applications jsonb;
begin
  if auth.uid() is null
     or auth.uid() is distinct from p_reviewer
     or partner_onboarding_private.verified_auth_email_v1(p_reviewer) is null
     or p_limit is null
     or p_limit < 1
     or p_limit > 100 then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:staff-authority-registry', 0)
  );
  if partner_onboarding_private.has_active_staff_authority_v1(
       p_reviewer, 'evidence_reviewer'
     ) is not true
     and partner_onboarding_private.has_active_staff_authority_v1(
       p_reviewer, 'security_admin'
     ) is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'application_id', application.id,
        'correction_receipt_id', application.correction_receipt_id,
        'partner_id', application.partner_id,
        'owner_id', application.owner_id,
        'candidate_relationship_type', application.candidate_relationship_type,
        'application_snapshot', application.application_snapshot,
        'application_sha256', application.application_sha256,
        'status', application.status,
        'created_at', application.created_at
      )
      order by application.created_at, application.id
    ),
    '[]'::jsonb
  ) into v_applications
  from (
    select
      pending.id,
      pending.partner_id,
      pending.owner_id,
      coalesce(
        correction.candidate_relationship_type,
        pending.candidate_relationship_type
      ) as candidate_relationship_type,
      coalesce(
        correction.corrected_application_snapshot,
        pending.application_snapshot
      ) as application_snapshot,
      coalesce(
        correction.corrected_application_sha256,
        pending.application_sha256
      ) as application_sha256,
      pending.status,
      pending.created_at,
      correction.id as correction_receipt_id
    from partner_onboarding_private.partner_applications pending
    left join lateral (
      select latest.*
      from partner_onboarding_private.partner_application_corrections latest
      where latest.application_id = pending.id
      order by latest.correction_number desc, latest.created_at desc, latest.id desc
      limit 1
    ) correction on true
    where pending.status in ('draft', 'submitted', 'pending', 'missing_info')
      and not exists (
        select 1
        from partner_onboarding_private.partner_state state
        where state.partner_id = pending.partner_id
      )
    order by pending.created_at, pending.id
    limit p_limit
  ) application;

  return pg_catalog.jsonb_build_object(
    'projection_version', 'heha-partner-application-review-queue-v1',
    'reviewer_id', p_reviewer,
    'applications', v_applications
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.issue_partner_invitation_v1(
  p_partner_id uuid,
  p_recipient_user_id uuid,
  p_legal_relationship_type text,
  p_claim_role text,
  p_raw_token text,
  p_expires_at timestamptz,
  p_issued_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_partner public.partners%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_application partner_onboarding_private.partner_applications%rowtype;
  v_existing partner_onboarding_private.partner_invites%rowtype;
  v_registry_by_partner partner_onboarding_private.partner_business_registry%rowtype;
  v_initial_business_key text;
  v_initial_profile_relationship_type text;
  v_business_key text;
  v_root_business_key text;
  v_application_relationship_type text;
  v_profile_relationship_type text;
  v_token_sha256 text;
  v_id uuid;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_issued_by, 'security_admin'
  );
  if partner_onboarding_private.verified_auth_email_v1(p_recipient_user_id) is null
     or p_legal_relationship_type is null
     or p_legal_relationship_type not in (
       'restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som'
     )
     or p_claim_role is distinct from 'operator_only'
     or p_raw_token is null
     or pg_catalog.octet_length(p_raw_token) not between 32 and 512
     or p_raw_token !~ '^[A-Za-z0-9_-]+$'
     or p_expires_at is null
     or p_expires_at <= pg_catalog.clock_timestamp()
     or p_expires_at > pg_catalog.clock_timestamp() + interval '30 days' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_token_sha256 := partner_onboarding_private.sha256_text(p_raw_token);

  -- Read only enough identity data to determine the global/per-key lock. The
  -- same row is re-read and revalidated after those locks are held.
  select p.* into v_partner
  from public.partners p
  where p.id = p_partner_id;
  if not found
     or nullif(pg_catalog.btrim(v_partner.name), '') is null
     or nullif(
       pg_catalog.btrim(
         coalesce(v_partner.location, v_partner.neighborhood, v_partner.postal_code)
       ),
       ''
     ) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_initial_business_key := partner_onboarding_private.normalized_business_key(
    v_partner.name,
    coalesce(v_partner.location, v_partner.neighborhood, v_partner.postal_code)
  );
  v_initial_profile_relationship_type :=
    partner_onboarding_private.relationship_type_for_application_v1(
      pg_catalog.jsonb_build_object(
        'category', v_partner.category,
        'categories', pg_catalog.to_jsonb(v_partner.categories),
        'business_type', v_partner.business_type
      )
    );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:business-registry', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:business:' || v_initial_business_key,
      0
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select p.* into v_partner
  from public.partners p
  where p.id = p_partner_id
  for update;
  if not found
     or nullif(pg_catalog.btrim(v_partner.name), '') is null
     or nullif(
       pg_catalog.btrim(
         coalesce(v_partner.location, v_partner.neighborhood, v_partner.postal_code)
       ),
       ''
     ) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_business_key := partner_onboarding_private.normalized_business_key(
    v_partner.name,
    coalesce(v_partner.location, v_partner.neighborhood, v_partner.postal_code)
  );
  v_profile_relationship_type :=
    partner_onboarding_private.relationship_type_for_application_v1(
      pg_catalog.jsonb_build_object(
        'category', v_partner.category,
        'categories', pg_catalog.to_jsonb(v_partner.categories),
        'business_type', v_partner.business_type
      )
    );
  if v_business_key is distinct from v_initial_business_key
     or v_profile_relationship_type is distinct from
       v_initial_profile_relationship_type then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- Raw public rows are part of the collision check so a legacy/bypass row
  -- can never be silently shadowed by an invitation.
  if exists (
    select 1
    from public.partners conflicting_partner
    where conflicting_partner.id <> v_partner.id
      and conflicting_partner.is_test_record is not true
      and nullif(pg_catalog.btrim(conflicting_partner.name), '') is not null
      and nullif(
        pg_catalog.btrim(
          coalesce(
            conflicting_partner.location,
            conflicting_partner.neighborhood,
            conflicting_partner.postal_code
          )
        ),
        ''
      ) is not null
      and partner_onboarding_private.normalized_business_key(
            conflicting_partner.name,
            coalesce(
              conflicting_partner.location,
              conflicting_partner.neighborhood,
              conflicting_partner.postal_code
            )
          ) = v_business_key
  ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select registry.* into v_registry_by_partner
  from partner_onboarding_private.partner_business_registry registry
  where registry.partner_id = v_partner.id
  for update;
  if v_registry_by_partner.partner_id is null then
    if exists (
      select 1
      from partner_onboarding_private.partner_business_registry conflicting_registry
      where conflicting_registry.business_key_sha256 = v_business_key
    )
       or exists (
         select 1
         from partner_onboarding_private.partner_business_key_corrections conflicting_key
         where conflicting_key.corrected_business_key_sha256 = v_business_key
            or conflicting_key.partner_id = v_partner.id
       ) then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
    insert into partner_onboarding_private.partner_business_registry (
      partner_id,
      business_key_sha256,
      registration_source,
      registered_by,
      registered_at
    ) values (
      v_partner.id,
      v_business_key,
      'invitation',
      p_issued_by,
      pg_catalog.clock_timestamp()
    );
    v_root_business_key := v_business_key;
  else
    v_root_business_key := v_registry_by_partner.business_key_sha256;
    if partner_onboarding_private.current_partner_business_key_v1(v_partner.id)
         is distinct from v_business_key then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
  end if;

  if exists (
    select 1
    from partner_onboarding_private.partner_business_registry conflicting_registry
    where conflicting_registry.business_key_sha256 = v_business_key
      and conflicting_registry.partner_id <> v_partner.id
  )
     or exists (
       select 1
       from partner_onboarding_private.partner_business_key_corrections conflicting_key
       where conflicting_key.corrected_business_key_sha256 = v_business_key
         and conflicting_key.partner_id <> v_partner.id
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if exists (
    select 1
    from partner_onboarding_private.partner_state conflicting_state
    where conflicting_state.business_key_sha256 = v_root_business_key
      and conflicting_state.partner_id <> v_partner.id
  )
     or exists (
       select 1
       from partner_onboarding_private.partner_applications conflicting_application
       where conflicting_application.business_key_sha256 = v_root_business_key
         and conflicting_application.partner_id <> v_partner.id
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select application.* into v_application
  from partner_onboarding_private.partner_applications application
  where application.partner_id = v_partner.id;
  if v_application.id is not null then
    if v_application.business_key_sha256 is distinct from v_root_business_key then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
    select correction.candidate_relationship_type
    into v_application_relationship_type
    from partner_onboarding_private.partner_application_corrections correction
    where correction.application_id = v_application.id
    order by correction.correction_number desc, correction.created_at desc, correction.id desc
    limit 1;
    if not found then
      v_application_relationship_type := v_application.candidate_relationship_type;
    end if;
  end if;
  if v_profile_relationship_type is distinct from p_legal_relationship_type
     or (
       v_application.id is not null
       and v_application_relationship_type is distinct from
         p_legal_relationship_type
     )
     or (
       v_application.id is not null
       and (
         v_application.owner_id is distinct from p_recipient_user_id
         or (
           v_partner.owner_id is not null
           and v_partner.owner_id is distinct from v_application.owner_id
         )
       )
     )
     or (
       v_application.id is null
       and v_partner.owner_id is not null
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_state (
    partner_id, legal_relationship_type, business_key_sha256
  ) values (
    v_partner.id, p_legal_relationship_type, v_root_business_key
  )
  on conflict (partner_id) do nothing;

  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = v_partner.id
  for update;
  if not found
     or v_state.legal_relationship_type is distinct from p_legal_relationship_type
     or v_state.business_key_sha256 is distinct from v_root_business_key
     or v_state.reclassification_pending is true
     or v_state.operator_user_id is not null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select i.* into v_existing
  from partner_onboarding_private.partner_invites i
  where i.token_sha256 = v_token_sha256;
  if found then
    if v_existing.partner_id = v_partner.id
       and v_existing.recipient_user_id = p_recipient_user_id
       and v_existing.legal_relationship_type = p_legal_relationship_type
       and v_existing.relationship_epoch = v_state.relationship_epoch
       and v_existing.claim_epoch = v_state.claim_epoch
       and v_existing.claim_role = p_claim_role
       and v_existing.expires_at = p_expires_at
       and v_existing.issued_by = p_issued_by then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if exists (
    select 1
    from partner_onboarding_private.partner_invites i
    where i.partner_id = v_partner.id
      and i.relationship_epoch = v_state.relationship_epoch
      and i.claim_epoch = v_state.claim_epoch
      and not exists (
        select 1
        from partner_onboarding_private.partner_invite_revocations r
        where r.invite_id = i.id
      )
      and not exists (
        select 1
        from partner_onboarding_private.partner_claims c
        where c.invite_id = i.id
      )
  ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_invites (
    partner_id,
    recipient_user_id,
    legal_relationship_type,
    relationship_epoch,
    claim_epoch,
    claim_role,
    token_sha256,
    expires_at,
    issued_by
  ) values (
    v_partner.id,
    p_recipient_user_id,
    p_legal_relationship_type,
    v_state.relationship_epoch,
    v_state.claim_epoch,
    p_claim_role,
    v_token_sha256,
    p_expires_at,
    p_issued_by
  ) returning id into v_id;

  insert into partner_onboarding_private.audit_events (
    partner_id, actor_id, event_type, receipt_id, event_data
  ) values (
    v_partner.id,
    p_issued_by,
    'partner_invitation_issued_v1',
    v_id,
    pg_catalog.jsonb_build_object(
      'recipient_user_id', p_recipient_user_id,
      'relationship_epoch', v_state.relationship_epoch,
      'claim_epoch', v_state.claim_epoch,
      'expires_at', p_expires_at
    )
  );

  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_invitation_v1(
  p_invite_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_invite partner_onboarding_private.partner_invites%rowtype;
  v_existing partner_onboarding_private.partner_invite_revocations%rowtype;
  v_id uuid;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by, 'security_admin'
  );
  if nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select i.* into v_invite
  from partner_onboarding_private.partner_invites i
  where i.id = p_invite_id
  for update;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select r.* into v_existing
  from partner_onboarding_private.partner_invite_revocations r
  where r.invite_id = v_invite.id;
  if found then
    if v_existing.revoked_by is not distinct from p_revoked_by
       and v_existing.reason_code is not distinct from pg_catalog.btrim(p_reason_code) then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_invite_revocations (
    invite_id, revoked_by, reason_code
  ) values (
    v_invite.id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  ) returning id into v_id;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  p_partner_id uuid,
  p_reason_code text,
  p_request_key uuid,
  p_reset_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_partner public.partners%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_application partner_onboarding_private.partner_applications%rowtype;
  v_existing partner_onboarding_private.partner_reclassification_resets%rowtype;
  v_request_fingerprint text;
  v_reset_id uuid;
  v_prior_legal_relationship_type text;
  v_profile_relationship_type text;
  v_reset_mode text;
  v_replacement_legal_relationship_type text;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_reset_by,
    'legal_admin'
  );
  if p_partner_id is null
     or p_request_key is null
     or nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p_partner_id,
        'reason_code', pg_catalog.btrim(p_reason_code),
        'reset_by', p_reset_by
      )
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:reclassification-reset-request:' ||
      p_reset_by::text || ':' || p_request_key::text,
      0
    )
  );

  select reset_receipt.* into v_existing
  from partner_onboarding_private.partner_reclassification_resets reset_receipt
  where reset_receipt.reset_by = p_reset_by
    and reset_receipt.request_key = p_request_key;
  if found then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:partner:' || v_existing.partner_id::text,
        0
      )
    );
    select partner.* into v_partner
    from public.partners partner
    where partner.id = v_existing.partner_id
    for update;
    select state.* into v_state
    from partner_onboarding_private.partner_state state
    where state.partner_id = v_existing.partner_id
    for update;
    if v_existing.request_fingerprint is not distinct from v_request_fingerprint
       and v_existing.partner_id is not distinct from p_partner_id
       and v_partner.id is not null
       and v_state.partner_id is not null
       and v_state.reclassification_pending is not distinct from
         (v_existing.reset_mode = 'owner_revision_required')
       and (
         v_existing.reset_mode is distinct from 'profile_relationship_repaired'
         or v_state.legal_relationship_type is not distinct from
           v_existing.replacement_legal_relationship_type
       )
       and v_state.relationship_epoch = v_existing.prior_relationship_epoch + 1
       and v_state.claim_epoch = v_existing.prior_claim_epoch + 1
       and v_state.release_epoch = v_existing.prior_release_epoch + 1 then
      return pg_catalog.jsonb_build_object(
        'reset_receipt_id', v_existing.id,
        'partner_id', v_existing.partner_id,
        'request_key', v_existing.request_key,
        'relationship_epoch', v_state.relationship_epoch,
        'claim_epoch', v_state.claim_epoch,
        'release_epoch', v_state.release_epoch,
        'status', case v_existing.reset_mode
          when 'owner_revision_required' then 'reclassification_pending'
          else 'ready_for_invitation'
        end,
        'receipt_status', 'verified'
      );
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select partner.* into v_partner
  from public.partners partner
  where partner.id = p_partner_id
  for update;
  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = p_partner_id
  for update;
  select application.* into v_application
  from partner_onboarding_private.partner_applications application
  where application.partner_id = p_partner_id
  for share;

  v_profile_relationship_type :=
    partner_onboarding_private.relationship_type_for_application_v1(
      pg_catalog.jsonb_build_object(
        'category', v_partner.category,
        'categories', pg_catalog.to_jsonb(v_partner.categories),
        'business_type', v_partner.business_type
      )
    );
  if v_application.id is not null then
    v_reset_mode := 'owner_revision_required';
    v_replacement_legal_relationship_type := null;
  else
    v_reset_mode := 'profile_relationship_repaired';
    v_replacement_legal_relationship_type := v_profile_relationship_type;
  end if;

  if v_partner.id is null
     or v_state.partner_id is null
     or partner_onboarding_private.partner_business_identity_is_current_v1(
          p_partner_id,
          v_state.business_key_sha256
        ) is not true
     or (
       v_application.id is not null
       and v_application.owner_id is distinct from v_partner.owner_id
     )
     or (
       v_application.id is null
       and (
         v_partner.owner_id is not null
         or v_profile_relationship_type is null
       )
     )
     or v_state.operator_user_id is not null
     or v_state.reclassification_pending is true
     or exists (
       select 1
       from partner_onboarding_private.partner_invites invitation
       where invitation.partner_id = p_partner_id
         and invitation.relationship_epoch = v_state.relationship_epoch
         and invitation.claim_epoch = v_state.claim_epoch
         and invitation.expires_at > pg_catalog.clock_timestamp()
         and not exists (
           select 1
           from partner_onboarding_private.partner_invite_revocations revocation
           where revocation.invite_id = invitation.id
         )
         and not exists (
           select 1
           from partner_onboarding_private.partner_claims claim
           where claim.invite_id = invitation.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_claims claim
       where claim.partner_id = p_partner_id
         and claim.relationship_epoch = v_state.relationship_epoch
         and claim.claim_epoch = v_state.claim_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_claim_revocations revocation
           where revocation.claim_id = claim.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_agreement_acceptances acceptance
       where acceptance.partner_id = p_partner_id
         and acceptance.relationship_epoch = v_state.relationship_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_agreement_acceptance_revocations revocation
           where revocation.acceptance_id = acceptance.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_evidence_receipts evidence
       where evidence.partner_id = p_partner_id
         and evidence.relationship_epoch = v_state.relationship_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_evidence_revocations revocation
           where revocation.evidence_id = evidence.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_release_receipts release_receipt
       where release_receipt.partner_id = p_partner_id
         and release_receipt.release_epoch = v_state.release_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_release_revocations revocation
           where revocation.release_receipt_id = release_receipt.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_surface_activation_receipts activation
       join partner_onboarding_private.partner_release_receipts release_receipt
         on release_receipt.id = activation.release_receipt_id
        and release_receipt.partner_id = activation.partner_id
       where activation.partner_id = p_partner_id
         and release_receipt.release_epoch = v_state.release_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_surface_activation_revocations revocation
           where revocation.activation_receipt_id = activation.id
         )
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_reclassification_resets (
    partner_id,
    prior_legal_relationship_type,
    prior_relationship_epoch,
    prior_claim_epoch,
    prior_release_epoch,
    reset_mode,
    replacement_legal_relationship_type,
    reset_by,
    reason_code,
    request_key,
    request_fingerprint,
    reset_at
  ) values (
    p_partner_id,
    v_state.legal_relationship_type,
    v_state.relationship_epoch,
    v_state.claim_epoch,
    v_state.release_epoch,
    v_reset_mode,
    v_replacement_legal_relationship_type,
    p_reset_by,
    pg_catalog.btrim(p_reason_code),
    p_request_key,
    v_request_fingerprint,
    pg_catalog.clock_timestamp()
  ) returning id into v_reset_id;

  v_prior_legal_relationship_type := v_state.legal_relationship_type;

  update partner_onboarding_private.partner_state
  set legal_relationship_type = case
        when v_reset_mode = 'profile_relationship_repaired'
          then v_replacement_legal_relationship_type
        else legal_relationship_type
      end,
      relationship_epoch = relationship_epoch + 1,
      claim_epoch = claim_epoch + 1,
      release_epoch = release_epoch + 1,
      reclassification_pending = (v_reset_mode = 'owner_revision_required'),
      operator_user_id = null
  where partner_id = p_partner_id;
  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = p_partner_id;

  update public.partners
  set status = 'pending',
      heha_partner = false,
      website_eligible = false,
      swipe_eligible = false,
      local_eligible = false,
      updated_at = pg_catalog.clock_timestamp()
  where id = p_partner_id;

  insert into partner_onboarding_private.audit_events (
    partner_id,
    actor_id,
    event_type,
    receipt_id,
    event_data
  ) values (
    p_partner_id,
    p_reset_by,
    'partner_reclassification_reset_v1',
    v_reset_id,
    pg_catalog.jsonb_build_object(
      'prior_legal_relationship_type', v_prior_legal_relationship_type,
      'reset_mode', v_reset_mode,
      'replacement_legal_relationship_type', v_replacement_legal_relationship_type,
      'relationship_epoch', v_state.relationship_epoch,
      'claim_epoch', v_state.claim_epoch,
      'release_epoch', v_state.release_epoch
    )
  );

  return pg_catalog.jsonb_build_object(
    'reset_receipt_id', v_reset_id,
    'partner_id', p_partner_id,
    'request_key', p_request_key,
    'relationship_epoch', v_state.relationship_epoch,
    'claim_epoch', v_state.claim_epoch,
    'release_epoch', v_state.release_epoch,
    'status', case v_reset_mode
      when 'owner_revision_required' then 'reclassification_pending'
      else 'ready_for_invitation'
    end,
    'receipt_status', 'verified'
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_claim_v1(
  p_claim_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claim partner_onboarding_private.partner_claims%rowtype;
  v_partner public.partners%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_existing partner_onboarding_private.partner_claim_revocations%rowtype;
  v_id uuid;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by, 'security_admin'
  );
  if nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select c.* into v_claim
  from partner_onboarding_private.partner_claims c
  where c.id = p_claim_id;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || v_claim.partner_id::text,
      0
    )
  );
  select p.* into v_partner
  from public.partners p
  where p.id = v_claim.partner_id
  for update;
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = v_claim.partner_id
  for update;
  select c.* into v_claim
  from partner_onboarding_private.partner_claims c
  where c.id = p_claim_id
  for update;
  if v_partner.id is null or v_state.partner_id is null or v_claim.id is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select r.* into v_existing
  from partner_onboarding_private.partner_claim_revocations r
  where r.claim_id = v_claim.id;
  if found then
    if v_existing.revoked_by is not distinct from p_revoked_by
       and v_existing.reason_code is not distinct from pg_catalog.btrim(p_reason_code) then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_claim_revocations (
    claim_id, revoked_by, reason_code
  ) values (
    v_claim.id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  ) returning id into v_id;

  if v_state.claim_epoch = v_claim.claim_epoch then
    update partner_onboarding_private.partner_state
    set operator_user_id = null,
        relationship_epoch = relationship_epoch + 1,
        claim_epoch = claim_epoch + 1,
        release_epoch = release_epoch + 1
    where partner_id = v_claim.partner_id;

    update public.partners
    set owner_id = case
          when owner_id = v_claim.accepted_by then null
          else owner_id
        end,
        updated_at = pg_catalog.clock_timestamp()
    where id = v_claim.partner_id;
  end if;

  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.grant_partner_signer_authority_v1(
  p_partner_id uuid,
  p_user_id uuid,
  p_verified_legal_name text,
  p_verified_title text,
  p_verified_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state partner_onboarding_private.partner_state%rowtype;
  v_existing partner_onboarding_private.partner_actor_authority_grants%rowtype;
  v_email text;
  v_id uuid;
begin
  v_email := partner_onboarding_private.verified_auth_email_v1(p_user_id);
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_verified_by, 'legal_admin'
  );
  if v_email is null
     or nullif(pg_catalog.btrim(p_verified_legal_name), '') is null
     or nullif(pg_catalog.btrim(p_verified_title), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = p_partner_id
  for update;
  if not found
     or partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id) is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select g.* into v_existing
  from partner_onboarding_private.partner_actor_authority_grants g
  where g.partner_id = p_partner_id
    and g.user_id = p_user_id
    and g.authority_type = 'authorized_signer'
    and g.relationship_epoch = v_state.relationship_epoch;
  if found then
    if exists (
      select 1
      from partner_onboarding_private.partner_actor_authority_revocations r
      where r.authority_grant_id = v_existing.id
    )
       or v_existing.verified_email is distinct from v_email
       or partner_onboarding_private.normalized_person_text_v1(
         v_existing.verified_legal_name
       ) is distinct from partner_onboarding_private.normalized_person_text_v1(
         p_verified_legal_name
       )
       or partner_onboarding_private.normalized_person_text_v1(
         v_existing.verified_title
       ) is distinct from partner_onboarding_private.normalized_person_text_v1(
         p_verified_title
       ) then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
    return v_existing.id;
  end if;

  insert into partner_onboarding_private.partner_actor_authority_grants (
    partner_id,
    user_id,
    authority_type,
    relationship_epoch,
    verified_email,
    verified_legal_name,
    verified_title,
    verified_by
  ) values (
    p_partner_id,
    p_user_id,
    'authorized_signer',
    v_state.relationship_epoch,
    v_email,
    pg_catalog.regexp_replace(pg_catalog.btrim(p_verified_legal_name), '\s+', ' ', 'g'),
    pg_catalog.regexp_replace(pg_catalog.btrim(p_verified_title), '\s+', ' ', 'g'),
    p_verified_by
  ) returning id into v_id;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_signer_authority_v1(
  p_authority_grant_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_grant partner_onboarding_private.partner_actor_authority_grants%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_existing partner_onboarding_private.partner_actor_authority_revocations%rowtype;
  v_id uuid;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by, 'legal_admin'
  );
  if nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select g.* into v_grant
  from partner_onboarding_private.partner_actor_authority_grants g
  where g.id = p_authority_grant_id;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || v_grant.partner_id::text,
      0
    )
  );
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = v_grant.partner_id
  for update;
  select g.* into v_grant
  from partner_onboarding_private.partner_actor_authority_grants g
  where g.id = p_authority_grant_id
  for update;

  select r.* into v_existing
  from partner_onboarding_private.partner_actor_authority_revocations r
  where r.authority_grant_id = v_grant.id;
  if found then
    if v_existing.revoked_by is not distinct from p_revoked_by
       and v_existing.reason_code is not distinct from pg_catalog.btrim(p_reason_code) then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_actor_authority_revocations (
    authority_grant_id, revoked_by, reason_code
  ) values (
    v_grant.id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  ) returning id into v_id;

  update partner_onboarding_private.partner_state
  set release_epoch = release_epoch + 1
  where partner_id = v_grant.partner_id
    and relationship_epoch = v_grant.relationship_epoch;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.register_partner_agreement_version_v1(
  p_legal_relationship_type text,
  p_agreement_version text,
  p_title text,
  p_effective_at timestamptz,
  p_document_snapshot text,
  p_expected_document_sha256 text,
  p_assent_text text,
  p_incorporated_versions jsonb,
  p_legal_approval_reference text,
  p_legal_approved_by uuid,
  p_legal_approved_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_document_sha256 text;
  v_existing partner_onboarding_private.partner_agreement_versions%rowtype;
  v_id uuid;
begin
  v_document_sha256 := partner_onboarding_private.sha256_text(p_document_snapshot);
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_legal_approved_by, 'legal_admin'
  );
  if p_legal_relationship_type is null
     or p_legal_relationship_type not in (
       'restaurant', 'vendor', 'market', 'catering', 'solo_chef', 'driver', 'som'
     )
     or nullif(pg_catalog.btrim(p_agreement_version), '') is null
     or nullif(pg_catalog.btrim(p_title), '') is null
     or nullif(pg_catalog.btrim(p_document_snapshot), '') is null
     or pg_catalog.lower(coalesce(p_expected_document_sha256, '')) is distinct from v_document_sha256
     or nullif(pg_catalog.btrim(p_assent_text), '') is null
     or pg_catalog.jsonb_typeof(p_incorporated_versions) is distinct from 'object'
     or nullif(pg_catalog.btrim(p_legal_approval_reference), '') is null
     or p_effective_at is null
     or p_legal_approved_at is null
     or p_legal_approved_at > pg_catalog.clock_timestamp() then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:agreement-registry', 0)
  );
  select v.* into v_existing
  from partner_onboarding_private.partner_agreement_versions v
  where v.legal_relationship_type = p_legal_relationship_type
    and v.agreement_version = pg_catalog.btrim(p_agreement_version);
  if found then
    if v_existing.title = pg_catalog.btrim(p_title)
       and v_existing.effective_at = p_effective_at
       and v_existing.document_snapshot = p_document_snapshot
       and v_existing.document_sha256 = v_document_sha256
       and v_existing.assent_text = p_assent_text
       and v_existing.incorporated_versions = p_incorporated_versions
       and v_existing.legal_approval_reference = pg_catalog.btrim(p_legal_approval_reference)
       and v_existing.legal_approved_by = p_legal_approved_by
       and v_existing.legal_approved_at = p_legal_approved_at then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_agreement_versions (
    legal_relationship_type,
    agreement_version,
    title,
    effective_at,
    document_snapshot,
    document_sha256,
    assent_text,
    incorporated_versions,
    legal_approval_reference,
    legal_approved_by,
    legal_approved_at
  ) values (
    p_legal_relationship_type,
    pg_catalog.btrim(p_agreement_version),
    pg_catalog.btrim(p_title),
    p_effective_at,
    p_document_snapshot,
    v_document_sha256,
    p_assent_text,
    p_incorporated_versions,
    pg_catalog.btrim(p_legal_approval_reference),
    p_legal_approved_by,
    p_legal_approved_at
  ) returning id into v_id;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.select_partner_agreement_version_v1(
  p_agreement_version_id uuid,
  p_selected_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_version partner_onboarding_private.partner_agreement_versions%rowtype;
  v_current_version_id uuid;
  v_partner_id uuid;
  v_had_current boolean;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_selected_by, 'legal_admin'
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:agreement-registry', 0)
  );
  select v.* into v_version
  from partner_onboarding_private.partner_agreement_versions v
  where v.id = p_agreement_version_id
  for share;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select current_version.agreement_version_id into v_current_version_id
  from partner_onboarding_private.current_agreement_versions current_version
  where current_version.legal_relationship_type = v_version.legal_relationship_type
  for update;
  v_had_current := found;

  if v_had_current and v_current_version_id = v_version.id then
    return v_version.id;
  end if;

  if v_had_current then
    for v_partner_id in
      select state.partner_id
      from partner_onboarding_private.partner_state state
      where state.legal_relationship_type = v_version.legal_relationship_type
        and exists (
          select 1
          from partner_onboarding_private.partner_release_receipts release_receipt
          where release_receipt.partner_id = state.partner_id
            and release_receipt.relationship_epoch = state.relationship_epoch
            and release_receipt.release_epoch = state.release_epoch
            and not exists (
              select 1
              from partner_onboarding_private.partner_release_revocations revocation
              where revocation.release_receipt_id = release_receipt.id
            )
        )
      order by state.partner_id
      for update
    loop
      update partner_onboarding_private.partner_state
      set release_epoch = release_epoch + 1
      where partner_id = v_partner_id;
    end loop;
  end if;

  insert into partner_onboarding_private.current_agreement_versions (
    legal_relationship_type, agreement_version_id, selected_by
  ) values (
    v_version.legal_relationship_type, v_version.id, p_selected_by
  )
  on conflict (legal_relationship_type) do update
  set agreement_version_id = excluded.agreement_version_id,
      selected_by = excluded.selected_by,
      selected_at = pg_catalog.clock_timestamp();
  return v_version.id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_agreement_acceptance_v1(
  p_acceptance_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_acceptance partner_onboarding_private.partner_agreement_acceptances%rowtype;
  v_partner public.partners%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_existing partner_onboarding_private.partner_agreement_acceptance_revocations%rowtype;
  v_current_acceptance_id uuid;
  v_id uuid;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by, 'legal_admin'
  );
  if p_acceptance_id is null
     or p_revoked_by is null
     or nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select acceptance.* into v_acceptance
  from partner_onboarding_private.partner_agreement_acceptances acceptance
  where acceptance.id = p_acceptance_id;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || v_acceptance.partner_id::text,
      0
    )
  );
  select partner.* into v_partner
  from public.partners partner
  where partner.id = v_acceptance.partner_id
  for update;
  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = v_acceptance.partner_id
  for update;
  select acceptance.* into v_acceptance
  from partner_onboarding_private.partner_agreement_acceptances acceptance
  where acceptance.id = p_acceptance_id
  for update;
  if v_partner.id is null or v_state.partner_id is null or v_acceptance.id is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select revocation.* into v_existing
  from partner_onboarding_private.partner_agreement_acceptance_revocations revocation
  where revocation.acceptance_id = v_acceptance.id;
  if found then
    if v_existing.revoked_by is not distinct from p_revoked_by
       and v_existing.reason_code is not distinct from pg_catalog.btrim(p_reason_code) then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_current_acceptance_id :=
    partner_onboarding_private.current_acceptance_receipt_id_v1(v_acceptance.partner_id);

  insert into partner_onboarding_private.partner_agreement_acceptance_revocations (
    acceptance_id, revoked_by, reason_code
  ) values (
    v_acceptance.id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  ) returning id into v_id;

  if v_current_acceptance_id is not distinct from v_acceptance.id then
    update partner_onboarding_private.partner_state
    set operator_user_id = null,
        relationship_epoch = relationship_epoch + 1,
        claim_epoch = claim_epoch + 1,
        release_epoch = release_epoch + 1
    where partner_id = v_acceptance.partner_id
      and relationship_epoch = v_acceptance.relationship_epoch;

    update public.partners
    set owner_id = null,
        status = 'paused',
        heha_partner = false,
        website_eligible = false,
        swipe_eligible = false,
        local_eligible = false,
        updated_at = pg_catalog.clock_timestamp()
    where id = v_acceptance.partner_id;
  end if;

  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.issue_partner_evidence_v1(
  p_partner_id uuid,
  p_evidence_type text,
  p_subject_sha256 text,
  p_evidence_snapshot jsonb,
  p_request_key uuid,
  p_issued_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state partner_onboarding_private.partner_state%rowtype;
  v_existing partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_evidence_sha256 text;
  v_request_fingerprint text;
  v_expected_subject text;
  v_expected_local_lane text;
  v_expected_route_segment text;
  v_expected_smoke_local_partner_id text;
  v_id uuid;
  v_issued_at timestamptz;
begin
  v_evidence_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_evidence_snapshot)
  );
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p_partner_id,
        'evidence_type', p_evidence_type,
        'subject_sha256', pg_catalog.lower(coalesce(p_subject_sha256, '')),
        'evidence_sha256', v_evidence_sha256,
        'issued_by', p_issued_by
      )
    )
  );

  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_issued_by, 'evidence_reviewer'
  );
  if p_request_key is null
     or p_evidence_type is null
     or p_evidence_type not in (
       'profile', 'media', 'compliance', 'local_identity', 'smoke_test',
       'partner_consent', 'heha_review'
     )
     or pg_catalog.lower(coalesce(p_subject_sha256, '')) !~ '^[a-f0-9]{64}$'
     or pg_catalog.jsonb_typeof(p_evidence_snapshot) is distinct from 'object' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:evidence-request:' || p_issued_by::text || ':' || p_request_key::text,
      0
    )
  );
  select e.* into v_existing
  from partner_onboarding_private.partner_evidence_receipts e
  where e.issued_by = p_issued_by
    and e.request_key = p_request_key;
  if found then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:partner:' || v_existing.partner_id::text,
        0
      )
    );
    select state.* into v_state
    from partner_onboarding_private.partner_state state
    where state.partner_id = v_existing.partner_id
    for update;
    select evidence.* into v_existing
    from partner_onboarding_private.partner_evidence_receipts evidence
    where evidence.id = v_existing.id
    for update;
    if v_existing.request_fingerprint = v_request_fingerprint
       and v_state.partner_id = v_existing.partner_id
       and partner_onboarding_private.partner_business_identity_is_current_v1(
             v_existing.partner_id,
             v_state.business_key_sha256
           )
       and (
         v_existing.evidence_type is distinct from 'smoke_test'
         or (
           (v_existing.evidence_snapshot ->> 'status') is not distinct from 'passed'
           and (v_existing.evidence_snapshot -> 'passed')
             is not distinct from 'true'::jsonb
           and (v_existing.evidence_snapshot -> 'order_path_passed')
             is not distinct from 'true'::jsonb
           and nullif(
             pg_catalog.btrim(v_existing.evidence_snapshot ->> 'local_partner_id'),
             ''
           ) is not null
           and nullif(
             pg_catalog.btrim(
               v_existing.evidence_snapshot ->> 'customer_order_receipt_id'
             ),
             ''
           ) is not null
           and nullif(
             pg_catalog.btrim(
               v_existing.evidence_snapshot ->> 'partner_acceptance_receipt_id'
             ),
             ''
           ) is not null
           and nullif(
             pg_catalog.btrim(v_existing.evidence_snapshot ->> 'driver_receipt_id'),
             ''
           ) is not null
           and nullif(
             pg_catalog.btrim(v_existing.evidence_snapshot ->> 'delivery_receipt_id'),
             ''
           ) is not null
           and (v_existing.evidence_snapshot ->> 'local_partner_id') is not distinct from (
             select local_identity.evidence_snapshot ->> 'local_partner_id'
             from partner_onboarding_private.partner_evidence_receipts local_identity
             where local_identity.id =
               partner_onboarding_private.current_evidence_receipt_id_v1(
                 v_existing.partner_id,
                 'local_identity'
               )
           )
         )
       )
       and (
         v_existing.evidence_type not in ('partner_consent', 'heha_review')
         or (
           (v_existing.evidence_snapshot ->> 'status') is not distinct from 'approved'
           and (v_existing.evidence_snapshot -> 'approved')
             is not distinct from 'true'::jsonb
           and v_existing.subject_sha256 is not distinct from
             partner_onboarding_private.partner_preview_sha256(
               v_existing.partner_id
             )
         )
       )
       and partner_onboarding_private.current_evidence_receipt_id_v1(
         v_existing.partner_id,
         v_existing.evidence_type
       ) is not distinct from v_existing.id
       and not exists (
         select 1
         from partner_onboarding_private.partner_evidence_revocations r
         where r.evidence_id = v_existing.id
       ) then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = p_partner_id
  for update;
  if not found
     or partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id) is null
     or partner_onboarding_private.partner_business_identity_is_current_v1(
          p_partner_id,
          v_state.business_key_sha256
        ) is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_expected_local_lane := case v_state.legal_relationship_type
    when 'restaurant' then 'meals'
    when 'vendor' then 'vendors'
    when 'market' then 'market'
    when 'solo_chef' then 'chef'
    when 'catering' then 'group_orders'
    else null
  end;
  v_expected_route_segment := case v_state.legal_relationship_type
    when 'restaurant' then 'restaurants'
    when 'vendor' then 'vendors'
    when 'market' then 'market'
    when 'solo_chef' then 'chef'
    when 'catering' then 'group-orders'
    else null
  end;

  if p_evidence_type = 'smoke_test' then
    select evidence.evidence_snapshot ->> 'local_partner_id'
    into v_expected_smoke_local_partner_id
    from partner_onboarding_private.partner_evidence_receipts evidence
    where evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(
      p_partner_id,
      'local_identity'
    );
  end if;

  v_expected_subject := case p_evidence_type
    when 'profile' then partner_onboarding_private.partner_profile_sha256(p_partner_id)
    when 'media' then partner_onboarding_private.partner_media_sha256(p_partner_id)
    when 'partner_consent' then partner_onboarding_private.partner_preview_sha256(p_partner_id)
    when 'heha_review' then partner_onboarding_private.partner_preview_sha256(p_partner_id)
    else pg_catalog.lower(p_subject_sha256)
  end;
  if v_expected_subject is distinct from pg_catalog.lower(p_subject_sha256)
     or (p_evidence_type in ('profile', 'media', 'compliance', 'local_identity')
         and (p_evidence_snapshot ->> 'status') is distinct from 'verified')
     or (p_evidence_type = 'smoke_test' and (
       (p_evidence_snapshot ->> 'status') is distinct from 'passed'
       or (p_evidence_snapshot -> 'passed') is distinct from 'true'::jsonb
       or (p_evidence_snapshot -> 'order_path_passed') is distinct from 'true'::jsonb
       or nullif(pg_catalog.btrim(p_evidence_snapshot ->> 'local_partner_id'), '')
         is null
       or (p_evidence_snapshot ->> 'local_partner_id') is distinct from
         v_expected_smoke_local_partner_id
       or nullif(
         pg_catalog.btrim(p_evidence_snapshot ->> 'customer_order_receipt_id'), ''
       ) is null
       or nullif(
         pg_catalog.btrim(p_evidence_snapshot ->> 'partner_acceptance_receipt_id'), ''
       ) is null
       or nullif(
         pg_catalog.btrim(p_evidence_snapshot ->> 'driver_receipt_id'), ''
       ) is null
       or nullif(
         pg_catalog.btrim(p_evidence_snapshot ->> 'delivery_receipt_id'), ''
       ) is null
     ))
     or (p_evidence_type in ('partner_consent', 'heha_review') and (
       (p_evidence_snapshot ->> 'status') is distinct from 'approved'
       or (p_evidence_snapshot -> 'approved') is distinct from 'true'::jsonb
     ))
     or (p_evidence_type = 'local_identity' and (
       v_expected_local_lane is null
       or (p_evidence_snapshot ->> 'local_lane') is distinct from v_expected_local_lane
       or (p_evidence_snapshot ->> 'swipe_partner_id') is distinct from p_partner_id::text
       or coalesce(p_evidence_snapshot ->> 'local_partner_id', '') !~
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or (p_evidence_snapshot ->> 'primary_cta_destination') is distinct from 'local'
       or coalesce(p_evidence_snapshot ->> 'primary_cta_path', '') !~
         '^/(restaurants|vendors|market|chef|group-orders)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or pg_catalog.split_part(
         p_evidence_snapshot ->> 'primary_cta_path',
         '/',
         2
       ) is distinct from v_expected_route_segment
       or pg_catalog.split_part(
         p_evidence_snapshot ->> 'primary_cta_path',
         '/',
         3
       ) is distinct from (p_evidence_snapshot ->> 'local_partner_id')
     )) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- The Local target's existence and orderability are established by the
  -- separately attested Local receipt. Swipe binds that target identifier and
  -- its smoke-test receipts but does not claim cross-database target truth.

  v_issued_at := pg_catalog.clock_timestamp();
  insert into partner_onboarding_private.partner_evidence_receipts (
    partner_id,
    evidence_type,
    relationship_epoch,
    subject_sha256,
    evidence_snapshot,
    evidence_sha256,
    request_key,
    request_fingerprint,
    issued_by,
    issued_at
  ) values (
    p_partner_id,
    p_evidence_type,
    v_state.relationship_epoch,
    pg_catalog.lower(p_subject_sha256),
    p_evidence_snapshot,
    v_evidence_sha256,
    p_request_key,
    v_request_fingerprint,
    p_issued_by,
    v_issued_at
  ) returning id into v_id;

  if exists (
    select 1
    from partner_onboarding_private.partner_release_receipts release_receipt
    where release_receipt.partner_id = v_state.partner_id
      and release_receipt.relationship_epoch = v_state.relationship_epoch
      and release_receipt.release_epoch = v_state.release_epoch
      and not exists (
        select 1
        from partner_onboarding_private.partner_release_revocations revocation
        where revocation.release_receipt_id = release_receipt.id
      )
  ) then
    update partner_onboarding_private.partner_state
    set release_epoch = release_epoch + 1
    where partner_id = v_state.partner_id
      and release_epoch = v_state.release_epoch;
  end if;

  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_evidence_v1(
  p_evidence_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_evidence partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_existing partner_onboarding_private.partner_evidence_revocations%rowtype;
  v_id uuid;
begin
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by, 'evidence_reviewer'
  );
  if nullif(pg_catalog.btrim(p_reason_code), '') is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select e.* into v_evidence
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = p_evidence_id;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || v_evidence.partner_id::text,
      0
    )
  );
  perform 1
  from partner_onboarding_private.partner_state s
  where s.partner_id = v_evidence.partner_id
  for update;
  select e.* into v_evidence
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = p_evidence_id
  for update;

  select r.* into v_existing
  from partner_onboarding_private.partner_evidence_revocations r
  where r.evidence_id = v_evidence.id;
  if found then
    if v_existing.revoked_by is not distinct from p_revoked_by
       and v_existing.reason_code is not distinct from pg_catalog.btrim(p_reason_code) then
      return v_existing.id;
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_evidence_revocations (
    evidence_id, revoked_by, reason_code
  ) values (
    v_evidence.id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  ) returning id into v_id;
  update partner_onboarding_private.partner_state
  set release_epoch = release_epoch + 1
  where partner_id = v_evidence.partner_id
    and relationship_epoch = v_evidence.relationship_epoch;
  return v_id;
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.claim_editable_profile_sha256_v1(
  p_partner_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', partner.id,
        'name', partner.name,
        'category', partner.category,
        'categories', partner.categories,
        'business_type', partner.business_type,
        'location', partner.location,
        'neighborhood', partner.neighborhood,
        'contact', partner.contact,
        'instagram', partner.instagram,
        'website', partner.website,
        'bio', partner.bio,
        'complete_pct', partner.complete_pct,
        'hours', partner.hours,
        'offerings', partner.offerings,
        'tagline', partner.tagline,
        'items', partner.items,
        'phone', partner.phone,
        'photo_emoji', partner.photo_emoji,
        'color', partner.color,
        'delivery_days', partner.delivery_days
      )
    )
  )
  from public.partners partner
  where partner.id = p_partner_id;
$function$;

-- ---------------------------------------------------------------------------
-- Authenticated client RPCs. Every denial is deliberately indistinguishable.
-- ---------------------------------------------------------------------------

create or replace function public.claim_partner_invitation_v1(
  p_invite_token text,
  p_request_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_email text;
  v_config partner_onboarding_private.runtime_config%rowtype;
  v_invite_key record;
  v_invite partner_onboarding_private.partner_invites%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_partner public.partners%rowtype;
  v_existing partner_onboarding_private.partner_claims%rowtype;
  v_token_sha256 text;
  v_request_fingerprint text;
  v_claim_id uuid;
  v_claim_time timestamptz;
begin
  v_actor_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  if v_actor is null
     or v_actor_email is null
     or p_request_key is null
     or p_invite_token is null
     or pg_catalog.octet_length(p_invite_token) not between 32 and 512
     or p_invite_token !~ '^[A-Za-z0-9_-]+$' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_token_sha256 := partner_onboarding_private.sha256_text(p_invite_token);
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'actor_id', v_actor,
        'invite_token_sha256', v_token_sha256
      )
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:claim-request:' || v_actor::text || ':' || p_request_key::text,
      0
    )
  );

  select c.* into v_existing
  from partner_onboarding_private.partner_claims c
  where c.accepted_by = v_actor
    and c.request_key = p_request_key;
  if found then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:partner:' || v_existing.partner_id::text,
        0
      )
    );
    select partner.* into v_partner
    from public.partners partner
    where partner.id = v_existing.partner_id
    for update;
    select state.* into v_state
    from partner_onboarding_private.partner_state state
    where state.partner_id = v_existing.partner_id
    for update;
    select claim.* into v_existing
    from partner_onboarding_private.partner_claims claim
    where claim.id = v_existing.id
    for update;
    if v_existing.request_fingerprint = v_request_fingerprint
       and v_partner.id = v_existing.partner_id
       and v_state.partner_id = v_existing.partner_id
       and partner_onboarding_private.partner_business_identity_is_current_v1(
             v_existing.partner_id,
             v_state.business_key_sha256
           )
       and partner_onboarding_private.current_claim_receipt_id_v1(
         v_existing.partner_id
       ) is not distinct from v_existing.id
       and not exists (
         select 1
         from partner_onboarding_private.partner_claim_revocations r
         where r.claim_id = v_existing.id
       ) then
      return pg_catalog.jsonb_build_object(
        'id', v_existing.partner_id,
        'owner_id', v_actor,
        'claim_evidence_id', v_existing.id,
        'request_key', v_existing.request_key,
        'receipt_status', 'verified',
        'status', 'pending'
      );
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select i.id, i.partner_id into v_invite_key
  from partner_onboarding_private.partner_invites i
  where i.token_sha256 = v_token_sha256;
  if not found then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- Runtime config precedes partner/state locks so a gate shutdown and claim
  -- creation cannot deadlock or cross the release-generation boundary.
  select rc.* into v_config
  from partner_onboarding_private.runtime_config rc
  where rc.singleton
  for share;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || v_invite_key.partner_id::text,
      0
    )
  );
  select p.* into v_partner
  from public.partners p
  where p.id = v_invite_key.partner_id
  for update;
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = v_invite_key.partner_id
  for update;
  select i.* into v_invite
  from partner_onboarding_private.partner_invites i
  where i.id = v_invite_key.id
    and i.token_sha256 = v_token_sha256
  for update;
  v_claim_time := pg_catalog.clock_timestamp();

  if v_partner.id is null
     or v_state.partner_id is null
     or v_invite.id is null
     or partner_onboarding_private.partner_business_identity_is_current_v1(
          v_partner.id,
          v_state.business_key_sha256
        ) is not true
     or v_config.claim_enabled is not true
     or v_invite.recipient_user_id is distinct from v_actor
     or v_invite.legal_relationship_type is distinct from v_state.legal_relationship_type
     or v_invite.relationship_epoch is distinct from v_state.relationship_epoch
     or v_invite.claim_epoch is distinct from v_state.claim_epoch
     or v_invite.expires_at <= v_claim_time
     or v_state.operator_user_id is not null
     or partner_onboarding_private.current_claim_receipt_id_v1(v_partner.id) is not null
     or exists (
       select 1
       from partner_onboarding_private.partner_invite_revocations r
       where r.invite_id = v_invite.id
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_claims c
         where c.invite_id = v_invite.id
            or (c.partner_id = v_partner.id and c.claim_epoch = v_state.claim_epoch)
     )
     -- Claiming may normalize a legacy public row, but it must never rewrite a
     -- partner that already has a protected release or surface activation.
     or exists (
       select 1
       from partner_onboarding_private.partner_release_receipts release_receipt
       where release_receipt.partner_id = v_partner.id
         and release_receipt.relationship_epoch = v_state.relationship_epoch
         and release_receipt.release_epoch = v_state.release_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_release_revocations revocation
           where revocation.release_receipt_id = release_receipt.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_surface_activation_receipts activation
       join partner_onboarding_private.partner_release_receipts release_receipt
         on release_receipt.id = activation.release_receipt_id
        and release_receipt.partner_id = activation.partner_id
       where activation.partner_id = v_partner.id
         and release_receipt.relationship_epoch = v_state.relationship_epoch
         and release_receipt.release_epoch = v_state.release_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_surface_activation_revocations revocation
           where revocation.activation_receipt_id = activation.id
         )
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_claims (
    partner_id,
    invite_id,
    accepted_by,
    accepted_owner_id,
    legal_relationship_type,
    relationship_epoch,
    claim_epoch,
    claim_role,
    request_key,
    invite_token_sha256,
    request_fingerprint,
    accepted_at
  ) values (
    v_partner.id,
    v_invite.id,
    v_actor,
    v_actor,
    v_state.legal_relationship_type,
    v_state.relationship_epoch,
    v_state.claim_epoch,
    v_invite.claim_role,
    p_request_key,
    v_token_sha256,
    v_request_fingerprint,
    v_claim_time
  ) returning id into v_claim_id;

  update partner_onboarding_private.partner_state
  set operator_user_id = v_actor
  where partner_id = v_partner.id;
  -- owner_id/accepted_owner_id are snapshots of the operational profile
  -- controller. They confer neither legal ownership nor signer authority.
  -- A legacy approved/live/paused row is made private in the same locked claim
  -- transaction. This closes every legacy eligibility flag before the new
  -- operator can use the protected profile-correction flow.
  update public.partners
  set owner_id = v_actor,
      status = 'pending',
      heha_partner = false,
      website_eligible = false,
      swipe_eligible = false,
      local_eligible = false,
      updated_at = v_claim_time
  where id = v_partner.id;

  insert into partner_onboarding_private.audit_events (
    partner_id,
    actor_id,
    event_type,
    receipt_id,
    event_data
  ) values (
    v_partner.id,
    v_actor,
    'partner_profile_normalized_for_claim_v1',
    v_claim_id,
    pg_catalog.jsonb_build_object(
      'prior_status', v_partner.status,
      'prior_heha_partner', v_partner.heha_partner,
      'prior_website_eligible', v_partner.website_eligible,
      'prior_swipe_eligible', v_partner.swipe_eligible,
      'prior_local_eligible', v_partner.local_eligible,
      'normalized_status', 'pending'
    )
  );

  return pg_catalog.jsonb_build_object(
    'id', v_partner.id,
    'owner_id', v_actor,
    'claim_evidence_id', v_claim_id,
    'request_key', p_request_key,
    'receipt_status', 'verified',
    'status', 'pending'
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function partner_onboarding_private.revise_claimed_partner_profile_v1(
  p_partner_id uuid,
  p_request_key uuid,
  p_profile_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_runtime partner_onboarding_private.runtime_config%rowtype;
  v_partner public.partners%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_claim partner_onboarding_private.partner_claims%rowtype;
  v_existing partner_onboarding_private.partner_claim_profile_corrections%rowtype;
  v_categories text[];
  v_offerings text[];
  v_delivery_days text[];
  v_hours jsonb;
  v_correction_sha256 text;
  v_request_fingerprint text;
  v_previous_profile_sha256 text;
  v_resulting_profile_sha256 text;
  v_receipt_id uuid;
begin
  if v_actor is null
     or partner_onboarding_private.verified_auth_email_v1(v_actor) is null
     or p_partner_id is null
     or p_request_key is null
     or pg_catalog.jsonb_typeof(p_profile_snapshot) is distinct from 'object'
     or (
       select pg_catalog.array_agg(profile_key order by profile_key)
       from pg_catalog.jsonb_object_keys(p_profile_snapshot) keys(profile_key)
     ) is distinct from array[
       'bio',
       'business_type',
       'categories',
       'category',
       'color',
       'complete_pct',
       'contact',
       'delivery_days',
       'hours',
       'instagram',
       'items',
       'location',
       'name',
       'neighborhood',
       'offerings',
       'phone',
       'photo_emoji',
       'tagline',
       'website'
     ]::text[]
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'name') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'category') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'categories') not in ('array', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'complete_pct') is distinct from 'number'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'offerings') is distinct from 'array'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'delivery_days') is distinct from 'array'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'items') is distinct from 'array'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'photo_emoji') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'color') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'business_type') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'location') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'neighborhood') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'contact') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'instagram') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'website') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'bio') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'hours') not in (
       'object', 'string', 'null'
     )
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'phone') not in ('string', 'null')
     or pg_catalog.jsonb_typeof(p_profile_snapshot -> 'tagline') not in ('string', 'null') then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_categories := partner_onboarding_private.jsonb_text_array_v1(
    p_profile_snapshot -> 'categories'
  );
  v_offerings := partner_onboarding_private.jsonb_text_array_v1(
    p_profile_snapshot -> 'offerings'
  );
  v_delivery_days := partner_onboarding_private.jsonb_text_array_v1(
    p_profile_snapshot -> 'delivery_days'
  );
  v_correction_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_profile_snapshot)
  );
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p_partner_id,
        'actor_id', v_actor,
        'correction_sha256', v_correction_sha256
      )
    )
  );

  -- Runtime config precedes partner/state locks, matching config shutdown and
  -- release finalization. A disabled claim lane cannot mutate claimed data.
  select runtime.* into v_runtime
  from partner_onboarding_private.runtime_config runtime
  where runtime.singleton
  for share;
  if v_runtime.claim_enabled is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:claimed-profile-request:' ||
      v_actor::text || ':' || p_request_key::text,
      0
    )
  );

  select correction.* into v_existing
  from partner_onboarding_private.partner_claim_profile_corrections correction
  where correction.actor_id = v_actor
    and correction.request_key = p_request_key;
  if found then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:partner:' || v_existing.partner_id::text,
        0
      )
    );
    select partner.* into v_partner
    from public.partners partner
    where partner.id = v_existing.partner_id
    for update;
    select state.* into v_state
    from partner_onboarding_private.partner_state state
    where state.partner_id = v_existing.partner_id
    for update;
    select claim.* into v_claim
    from partner_onboarding_private.partner_claims claim
    where claim.id = v_existing.claim_id
    for share;
    select correction.* into v_existing
    from partner_onboarding_private.partner_claim_profile_corrections correction
    where correction.id = v_existing.id
    for update;
    if v_existing.request_fingerprint is not distinct from v_request_fingerprint
       and v_existing.partner_id is not distinct from p_partner_id
       and v_existing.correction_sha256 is not distinct from v_correction_sha256
       and v_state.operator_user_id is not distinct from v_actor
       and v_partner.owner_id is not distinct from v_actor
       and v_claim.accepted_by is not distinct from v_actor
       and v_existing.relationship_epoch is not distinct from v_state.relationship_epoch
       and v_existing.claim_epoch is not distinct from v_state.claim_epoch
       and partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id)
         is not distinct from v_existing.claim_id
       and partner_onboarding_private.claim_editable_profile_sha256_v1(p_partner_id)
         is not distinct from v_existing.resulting_profile_sha256 then
      return pg_catalog.jsonb_build_object(
        'id', v_existing.partner_id,
        'owner_id', v_existing.actor_id,
        'request_key', v_existing.request_key,
        'claim_receipt_id', v_existing.claim_id,
        'profile_correction_receipt_id', v_existing.id,
        'correction_sha256', v_existing.correction_sha256,
        'previous_profile_sha256', v_existing.previous_profile_sha256,
        'resulting_profile_sha256', v_existing.resulting_profile_sha256,
        'receipt_status', 'verified',
        'status', v_partner.status
      );
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select partner.* into v_partner
  from public.partners partner
  where partner.id = p_partner_id
  for update;
  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = p_partner_id
  for update;
  select claim.* into v_claim
  from partner_onboarding_private.partner_claims claim
  where claim.id = partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id)
  for share;

  if v_partner.id is null
     or v_state.partner_id is null
     or v_claim.id is null
     or v_state.reclassification_pending is true
     or v_state.operator_user_id is distinct from v_actor
     or v_partner.owner_id is distinct from v_actor
     or v_claim.accepted_by is distinct from v_actor
     or v_claim.accepted_owner_id is distinct from v_actor
     or v_claim.relationship_epoch is distinct from v_state.relationship_epoch
     or v_claim.claim_epoch is distinct from v_state.claim_epoch
     or v_partner.status not in ('draft', 'submitted', 'pending', 'missing_info')
     or partner_onboarding_private.partner_business_identity_is_current_v1(
          p_partner_id,
          v_state.business_key_sha256
        ) is not true
     or nullif(pg_catalog.btrim(p_profile_snapshot ->> 'name'), '') is distinct from
       nullif(pg_catalog.btrim(v_partner.name), '')
     or partner_onboarding_private.relationship_type_for_application_v1(
          p_profile_snapshot
        ) is distinct from v_state.legal_relationship_type
     -- Classification is locked after claim. Accept legacy NULLs, but bind the
     -- submitted snapshot to the exact stored scalar/array values and never
     -- rewrite those fields from an operational profile correction.
     or (p_profile_snapshot -> 'category') is distinct from coalesce(
          pg_catalog.to_jsonb(v_partner.category),
          'null'::jsonb
        )
     or (p_profile_snapshot -> 'categories') is distinct from coalesce(
          pg_catalog.to_jsonb(v_partner.categories),
          'null'::jsonb
        )
     or (p_profile_snapshot -> 'business_type') is distinct from coalesce(
          pg_catalog.to_jsonb(v_partner.business_type),
          'null'::jsonb
        )
     or nullif(pg_catalog.btrim(p_profile_snapshot ->> 'location'), '') is distinct from
       nullif(pg_catalog.btrim(v_partner.location), '')
     or nullif(pg_catalog.btrim(p_profile_snapshot ->> 'neighborhood'), '') is distinct from
       nullif(pg_catalog.btrim(v_partner.neighborhood), '') then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_previous_profile_sha256 :=
    partner_onboarding_private.claim_editable_profile_sha256_v1(p_partner_id);
  v_hours := case pg_catalog.jsonb_typeof(p_profile_snapshot -> 'hours')
    when 'object' then p_profile_snapshot -> 'hours'
    when 'string' then case
      when coalesce(v_partner.hours - 'summary', '{}'::jsonb) <> '{}'::jsonb
       and (p_profile_snapshot ->> 'hours') is distinct from
         (v_partner.hours ->> 'summary') then null
      when coalesce(v_partner.hours - 'summary', '{}'::jsonb) <> '{}'::jsonb
        then v_partner.hours
      else pg_catalog.jsonb_build_object(
        'summary', p_profile_snapshot ->> 'hours'
      )
    end
    when 'null' then case
      when coalesce(v_partner.hours - 'summary', '{}'::jsonb) <> '{}'::jsonb
        then null
      else '{}'::jsonb
    end
  end;
  if v_hours is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  update public.partners
  set contact = nullif(pg_catalog.btrim(p_profile_snapshot ->> 'contact'), ''),
      instagram = nullif(pg_catalog.btrim(p_profile_snapshot ->> 'instagram'), ''),
      website = nullif(pg_catalog.btrim(p_profile_snapshot ->> 'website'), ''),
      bio = nullif(pg_catalog.btrim(p_profile_snapshot ->> 'bio'), ''),
      complete_pct = least(
        100,
        greatest(0, (p_profile_snapshot ->> 'complete_pct')::integer)
      ),
      hours = v_hours,
      offerings = v_offerings,
      tagline = nullif(pg_catalog.btrim(p_profile_snapshot ->> 'tagline'), ''),
      items = p_profile_snapshot -> 'items',
      phone = nullif(pg_catalog.btrim(p_profile_snapshot ->> 'phone'), ''),
      photo_emoji = pg_catalog.btrim(p_profile_snapshot ->> 'photo_emoji'),
      color = pg_catalog.btrim(p_profile_snapshot ->> 'color'),
      delivery_days = v_delivery_days,
      updated_at = pg_catalog.clock_timestamp()
  where id = p_partner_id;
  v_resulting_profile_sha256 :=
    partner_onboarding_private.claim_editable_profile_sha256_v1(p_partner_id);
  if v_previous_profile_sha256 is null
     or v_resulting_profile_sha256 is null
     or v_previous_profile_sha256 is not distinct from v_resulting_profile_sha256 then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_claim_profile_corrections (
    partner_id,
    claim_id,
    actor_id,
    relationship_epoch,
    claim_epoch,
    previous_profile_sha256,
    correction_snapshot,
    correction_sha256,
    resulting_profile_sha256,
    request_key,
    request_fingerprint,
    created_at
  ) values (
    p_partner_id,
    v_claim.id,
    v_actor,
    v_state.relationship_epoch,
    v_state.claim_epoch,
    v_previous_profile_sha256,
    p_profile_snapshot,
    v_correction_sha256,
    v_resulting_profile_sha256,
    p_request_key,
    v_request_fingerprint,
    pg_catalog.clock_timestamp()
  ) returning id into v_receipt_id;

  update partner_onboarding_private.partner_state
  set release_epoch = release_epoch + 1
  where partner_id = p_partner_id
    and release_epoch = v_state.release_epoch;

  return pg_catalog.jsonb_build_object(
    'id', p_partner_id,
    'owner_id', v_actor,
    'request_key', p_request_key,
    'claim_receipt_id', v_claim.id,
    'profile_correction_receipt_id', v_receipt_id,
    'correction_sha256', v_correction_sha256,
    'previous_profile_sha256', v_previous_profile_sha256,
    'resulting_profile_sha256', v_resulting_profile_sha256,
    'receipt_status', 'verified',
    'status', v_partner.status
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.create_or_resume_partner_application_v1(
  p_request_key uuid,
  p_application jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_email text;
  v_config partner_onboarding_private.runtime_config%rowtype;
  v_existing_request partner_onboarding_private.partner_application_requests%rowtype;
  v_existing_application partner_onboarding_private.partner_applications%rowtype;
  v_existing_registry partner_onboarding_private.partner_business_registry%rowtype;
  v_application_sha256 text;
  v_request_fingerprint text;
  v_business_key text;
  v_legal_name text;
  v_location_key text;
  v_name text;
  v_relationship_type text;
  v_categories text[];
  v_partner_id uuid;
  v_application_id uuid;
  v_hours jsonb;
begin
  v_actor_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  if v_actor is null
     or v_actor_email is null
     or p_request_key is null
     or pg_catalog.jsonb_typeof(p_application) is distinct from 'object' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_name := nullif(pg_catalog.btrim(p_application ->> 'name'), '');
  v_legal_name := coalesce(
    nullif(pg_catalog.btrim(p_application ->> 'legal_name'), ''),
    v_name
  );
  v_location_key := coalesce(
    nullif(pg_catalog.btrim(p_application ->> 'location'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'neighborhood'), '')
  );
  v_relationship_type := partner_onboarding_private.relationship_type_for_application_v1(
    p_application
  );
  v_categories := partner_onboarding_private.jsonb_text_array_v1(
    p_application -> 'categories'
  );
  if coalesce(pg_catalog.cardinality(v_categories), 0) = 0
     and nullif(pg_catalog.btrim(p_application ->> 'category'), '') is not null then
    v_categories := array[pg_catalog.btrim(p_application ->> 'category')];
  end if;
  if v_name is null
     or v_legal_name is null
     or v_location_key is null
     or v_relationship_type is null
     or coalesce(pg_catalog.cardinality(v_categories), 0) = 0 then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_application_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_application)
  );
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'actor_id', v_actor,
        'application_sha256', v_application_sha256
      )
    )
  );
  v_business_key := partner_onboarding_private.normalized_business_key(
    v_name, v_location_key
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:application-request:' || v_actor::text || ':' || p_request_key::text,
      0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:business-registry', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:business:' || v_business_key,
      0
    )
  );
  select r.* into v_existing_request
  from partner_onboarding_private.partner_application_requests r
  where r.actor_id = v_actor
    and r.request_key = p_request_key;
  if found then
    select a.* into v_existing_application
    from partner_onboarding_private.partner_applications a
    where a.id = v_existing_request.application_id;
    select registry.* into v_existing_registry
    from partner_onboarding_private.partner_business_registry registry
    where registry.business_key_sha256 = v_business_key;
    if v_existing_request.request_fingerprint = v_request_fingerprint
       and v_existing_application.owner_id = v_actor
       and v_existing_application.application_sha256 = v_application_sha256
       and v_existing_application.business_key_sha256 = v_business_key
       and v_existing_registry.partner_id = v_existing_application.partner_id
       and v_existing_registry.business_key_sha256 = v_business_key
       and partner_onboarding_private.current_partner_business_key_v1(
             v_existing_application.partner_id
           ) = v_business_key then
      return pg_catalog.jsonb_build_object(
        'id', v_existing_application.partner_id,
        'owner_id', v_actor,
        'request_key', p_request_key,
        'application_receipt_id', v_existing_application.id,
        'application_sha256', v_existing_application.application_sha256,
        'receipt_status', 'verified',
        'status', v_existing_application.status
      );
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select rc.* into v_config
  from partner_onboarding_private.runtime_config rc
  where rc.singleton
  for share;
  if v_config.application_enabled is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if exists (
    select 1
    from partner_onboarding_private.partner_business_registry registry
    where registry.business_key_sha256 = v_business_key
  )
     or exists (
       select 1
       from partner_onboarding_private.partner_business_key_corrections key_correction
       where key_correction.corrected_business_key_sha256 = v_business_key
     )
     or exists (
       select 1
       from public.partners conflicting_partner
       where conflicting_partner.is_test_record is not true
         and nullif(pg_catalog.btrim(conflicting_partner.name), '') is not null
         and nullif(
           pg_catalog.btrim(
             coalesce(
               conflicting_partner.location,
               conflicting_partner.neighborhood,
               conflicting_partner.postal_code
             )
           ),
           ''
         ) is not null
         and partner_onboarding_private.normalized_business_key(
               conflicting_partner.name,
               coalesce(
                 conflicting_partner.location,
                 conflicting_partner.neighborhood,
                 conflicting_partner.postal_code
               )
             ) = v_business_key
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_applications application
       where application.business_key_sha256 = v_business_key
     )
     or exists (
    select 1
    from partner_onboarding_private.partner_state s
    where s.business_key_sha256 = v_business_key
  ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_hours := case pg_catalog.jsonb_typeof(p_application -> 'hours')
    when 'object' then p_application -> 'hours'
    when 'string' then pg_catalog.jsonb_build_object(
      'summary', p_application ->> 'hours'
    )
    else '{}'::jsonb
  end;

  insert into public.partners (
    owner_id,
    name,
    legal_name,
    postal_code,
    category,
    categories,
    location,
    contact,
    instagram,
    website,
    bio,
    status,
    complete_pct,
    hours,
    business_type,
    offerings,
    neighborhood,
    tagline,
    items,
    phone,
    photo_emoji,
    color,
    delivery_days,
    is_test_record
  ) values (
    v_actor,
    v_name,
    v_legal_name,
    null,
    v_categories[1],
    v_categories,
    nullif(pg_catalog.btrim(p_application ->> 'location'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'contact'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'instagram'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'website'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'bio'), ''),
    'pending',
    least(
      100,
      greatest(0, coalesce((p_application ->> 'complete_pct')::integer, 0))
    ),
    v_hours,
    nullif(pg_catalog.btrim(p_application ->> 'business_type'), ''),
    partner_onboarding_private.jsonb_text_array_v1(p_application -> 'offerings'),
    nullif(pg_catalog.btrim(p_application ->> 'neighborhood'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'tagline'), ''),
    case
      when pg_catalog.jsonb_typeof(p_application -> 'items') = 'array'
        then p_application -> 'items'
      else '[]'::jsonb
    end,
    nullif(pg_catalog.btrim(p_application ->> 'phone'), ''),
    coalesce(nullif(pg_catalog.btrim(p_application ->> 'photo_emoji'), ''), '🏪'),
    coalesce(nullif(pg_catalog.btrim(p_application ->> 'color'), ''), '#ff8a24'),
    partner_onboarding_private.jsonb_text_array_v1(p_application -> 'delivery_days'),
    false
  ) returning id into v_partner_id;

  -- Reserve the immutable business identity before the application insert;
  -- partner_applications has a composite FK to this exact binding.
  insert into partner_onboarding_private.partner_business_registry (
    partner_id,
    business_key_sha256,
    registration_source,
    registered_by,
    registered_at
  ) values (
    v_partner_id,
    v_business_key,
    'application',
    v_actor,
    pg_catalog.clock_timestamp()
  );

  insert into partner_onboarding_private.partner_applications (
    partner_id,
    owner_id,
    business_key_sha256,
    candidate_relationship_type,
    application_snapshot,
    application_sha256,
    status
  ) values (
    v_partner_id,
    v_actor,
    v_business_key,
    v_relationship_type,
    p_application,
    v_application_sha256,
    'pending'
  ) returning id into v_application_id;

  insert into partner_onboarding_private.partner_application_requests (
    application_id,
    partner_id,
    actor_id,
    request_key,
    request_fingerprint
  ) values (
    v_application_id,
    v_partner_id,
    v_actor,
    p_request_key,
    v_request_fingerprint
  );

  return pg_catalog.jsonb_build_object(
    'id', v_partner_id,
    'owner_id', v_actor,
    'request_key', p_request_key,
    'application_receipt_id', v_application_id,
    'application_sha256', v_application_sha256,
    'receipt_status', 'verified',
    'status', 'pending'
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.revise_partner_application_v1(
  p_partner_id uuid,
  p_request_key uuid,
  p_application jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_email text;
  v_config partner_onboarding_private.runtime_config%rowtype;
  v_application partner_onboarding_private.partner_applications%rowtype;
  v_partner public.partners%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_registry partner_onboarding_private.partner_business_registry%rowtype;
  v_existing partner_onboarding_private.partner_application_corrections%rowtype;
  v_latest partner_onboarding_private.partner_application_corrections%rowtype;
  v_application_sha256 text;
  v_previous_application_sha256 text;
  v_request_fingerprint text;
  v_business_key text;
  v_initial_current_business_key text;
  v_current_business_key text;
  v_first_lock_key text;
  v_second_lock_key text;
  v_legal_name text;
  v_location_key text;
  v_name text;
  v_relationship_type text;
  v_categories text[];
  v_hours jsonb;
  v_correction_number integer;
  v_correction_id uuid;
begin
  v_actor_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  if v_actor is null
     or v_actor_email is null
     or p_partner_id is null
     or p_request_key is null
     or pg_catalog.jsonb_typeof(p_application) is distinct from 'object' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_name := nullif(pg_catalog.btrim(p_application ->> 'name'), '');
  v_legal_name := coalesce(
    nullif(pg_catalog.btrim(p_application ->> 'legal_name'), ''),
    v_name
  );
  v_location_key := coalesce(
    nullif(pg_catalog.btrim(p_application ->> 'location'), ''),
    nullif(pg_catalog.btrim(p_application ->> 'neighborhood'), '')
  );
  v_relationship_type := partner_onboarding_private.relationship_type_for_application_v1(
    p_application
  );
  v_categories := partner_onboarding_private.jsonb_text_array_v1(
    p_application -> 'categories'
  );
  if coalesce(pg_catalog.cardinality(v_categories), 0) = 0
     and nullif(pg_catalog.btrim(p_application ->> 'category'), '') is not null then
    v_categories := array[pg_catalog.btrim(p_application ->> 'category')];
  end if;
  if v_name is null
     or v_legal_name is null
     or v_location_key is null
     or v_relationship_type is null
     or coalesce(pg_catalog.cardinality(v_categories), 0) = 0 then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_application_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_application)
  );
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'actor_id', v_actor,
        'partner_id', p_partner_id,
        'corrected_application_sha256', v_application_sha256
      )
    )
  );
  v_business_key := partner_onboarding_private.normalized_business_key(
    v_name, v_location_key
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:application-correction-request:' ||
      v_actor::text || ':' || p_request_key::text,
      0
    )
  );
  -- Optimistically resolve the immutable root key, then acquire the global
  -- registry and per-key locks before touching the partner row.
  select application.* into v_application
  from partner_onboarding_private.partner_applications application
  where application.partner_id = p_partner_id;
  if not found
     or v_application.owner_id is distinct from v_actor then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  v_initial_current_business_key :=
    partner_onboarding_private.current_partner_business_key_v1(p_partner_id);
  if v_initial_current_business_key is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:business-registry', 0)
  );
  v_first_lock_key := least(
    v_initial_current_business_key,
    v_business_key
  );
  v_second_lock_key := greatest(
    v_initial_current_business_key,
    v_business_key
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:business:' || v_first_lock_key,
      0
    )
  );
  if v_second_lock_key is distinct from v_first_lock_key then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:business:' || v_second_lock_key,
        0
      )
    );
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select partner.* into v_partner
  from public.partners partner
  where partner.id = p_partner_id
  for update;
  select application.* into v_application
  from partner_onboarding_private.partner_applications application
  where application.partner_id = p_partner_id
  for update;
  select registry.* into v_registry
  from partner_onboarding_private.partner_business_registry registry
  where registry.partner_id = p_partner_id
    and registry.business_key_sha256 = v_application.business_key_sha256
  for update;
  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = p_partner_id
  for update;
  v_current_business_key :=
    partner_onboarding_private.current_partner_business_key_v1(p_partner_id);
  if v_partner.id is null
     or v_application.id is null
     or v_registry.partner_id is null
     or v_application.owner_id is distinct from v_actor
     or v_partner.owner_id is distinct from v_actor
     or v_partner.status not in ('draft', 'submitted', 'pending', 'missing_info')
     or v_partner.is_test_record is true
     or v_application.status not in ('draft', 'submitted', 'pending', 'missing_info')
     or v_current_business_key is distinct from v_initial_current_business_key
     or partner_onboarding_private.normalized_business_key(
          v_partner.name,
          coalesce(v_partner.location, v_partner.neighborhood, v_partner.postal_code)
        ) is distinct from v_current_business_key
     or (
       v_state.partner_id is not null
       and v_state.reclassification_pending is not true
     )
     or exists (
       select 1 from partner_onboarding_private.partner_invites invitation
       where invitation.partner_id = p_partner_id
         and invitation.relationship_epoch = v_state.relationship_epoch
         and invitation.claim_epoch = v_state.claim_epoch
         and invitation.expires_at > pg_catalog.clock_timestamp()
         and not exists (
           select 1
           from partner_onboarding_private.partner_invite_revocations revocation
           where revocation.invite_id = invitation.id
         )
         and not exists (
           select 1
           from partner_onboarding_private.partner_claims invitation_claim
           where invitation_claim.invite_id = invitation.id
         )
     )
     or exists (
       select 1 from partner_onboarding_private.partner_claims claim
       where claim.partner_id = p_partner_id
         and claim.relationship_epoch = v_state.relationship_epoch
         and claim.claim_epoch = v_state.claim_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_claim_revocations revocation
           where revocation.claim_id = claim.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_agreement_acceptances acceptance
       where acceptance.partner_id = p_partner_id
         and acceptance.relationship_epoch = v_state.relationship_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_agreement_acceptance_revocations revocation
           where revocation.acceptance_id = acceptance.id
         )
     )
     or exists (
       select 1
       from partner_onboarding_private.partner_evidence_receipts evidence
       where evidence.partner_id = p_partner_id
         and evidence.relationship_epoch = v_state.relationship_epoch
         and not exists (
           select 1
           from partner_onboarding_private.partner_evidence_revocations revocation
           where revocation.evidence_id = evidence.id
         )
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if exists (
    select 1
    from public.partners conflicting_partner
    where conflicting_partner.id <> p_partner_id
      and conflicting_partner.is_test_record is not true
      and nullif(pg_catalog.btrim(conflicting_partner.name), '') is not null
      and nullif(
        pg_catalog.btrim(
          coalesce(
            conflicting_partner.location,
            conflicting_partner.neighborhood,
            conflicting_partner.postal_code
          )
        ),
        ''
      ) is not null
      and partner_onboarding_private.normalized_business_key(
            conflicting_partner.name,
            coalesce(
              conflicting_partner.location,
              conflicting_partner.neighborhood,
              conflicting_partner.postal_code
            )
          ) = v_business_key
  )
     or (
       v_business_key is distinct from v_current_business_key
       and exists (
         select 1
         from partner_onboarding_private.partner_business_registry conflicting_registry
         where conflicting_registry.business_key_sha256 = v_business_key
           and conflicting_registry.partner_id <> p_partner_id
       )
     )
     or (
       v_business_key is distinct from v_current_business_key
       and exists (
         select 1
         from partner_onboarding_private.partner_business_key_corrections conflicting_key
         where conflicting_key.partner_id <> p_partner_id
           and (
             conflicting_key.previous_business_key_sha256 = v_business_key
             or conflicting_key.corrected_business_key_sha256 = v_business_key
           )
       )
     )
     or exists (
    select 1
    from partner_onboarding_private.partner_applications conflicting_application
    where conflicting_application.business_key_sha256 = v_business_key
      and conflicting_application.partner_id <> p_partner_id
  )
     or exists (
       select 1
       from partner_onboarding_private.partner_state conflicting_state
       where conflicting_state.business_key_sha256 = v_business_key
         and conflicting_state.partner_id <> p_partner_id
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- A correction replay is valid only while the application is still in the
  -- same pre-invite state. This check is now linearized with invitation.
  select correction.* into v_existing
  from partner_onboarding_private.partner_application_corrections correction
  where correction.actor_id = v_actor
    and correction.request_key = p_request_key;
  if found then
    if v_existing.request_fingerprint = v_request_fingerprint
       and v_existing.partner_id = p_partner_id
       and v_existing.owner_id = v_actor
       and v_existing.application_id = v_application.id
       and v_existing.corrected_application_sha256 = v_application_sha256 then
      return pg_catalog.jsonb_build_object(
        'id', v_existing.partner_id,
        'owner_id', v_existing.owner_id,
        'request_key', v_existing.request_key,
        'application_receipt_id', v_existing.application_id,
        'correction_receipt_id', v_existing.id,
        'application_sha256', v_existing.corrected_application_sha256,
        'previous_application_sha256', v_existing.previous_application_sha256,
        'receipt_status', 'verified',
        'status', v_application.status
      );
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select correction.* into v_latest
  from partner_onboarding_private.partner_application_corrections correction
  where correction.application_id = v_application.id
  order by correction.correction_number desc, correction.created_at desc, correction.id desc
  limit 1;
  if found then
    v_previous_application_sha256 := v_latest.corrected_application_sha256;
    v_correction_number := v_latest.correction_number + 1;
  else
    v_previous_application_sha256 := v_application.application_sha256;
    v_correction_number := 1;
  end if;
  if v_previous_application_sha256 is not distinct from v_application_sha256 then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select rc.* into v_config
  from partner_onboarding_private.runtime_config rc
  where rc.singleton
  for share;
  if v_config.application_enabled is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  insert into partner_onboarding_private.partner_application_corrections (
    application_id,
    partner_id,
    owner_id,
    actor_id,
    correction_number,
    candidate_relationship_type,
    previous_application_sha256,
    corrected_application_snapshot,
    corrected_application_sha256,
    request_key,
    request_fingerprint,
    created_at
  ) values (
    v_application.id,
    p_partner_id,
    v_actor,
    v_actor,
    v_correction_number,
    v_relationship_type,
    v_previous_application_sha256,
    p_application,
    v_application_sha256,
    p_request_key,
    v_request_fingerprint,
    pg_catalog.clock_timestamp()
  ) returning id into v_correction_id;

  if v_business_key is distinct from v_current_business_key then
    insert into partner_onboarding_private.partner_business_key_corrections (
      application_id,
      partner_id,
      application_correction_id,
      previous_business_key_sha256,
      corrected_business_key_sha256,
      corrected_by,
      corrected_at
    ) values (
      v_application.id,
      p_partner_id,
      v_correction_id,
      v_current_business_key,
      v_business_key,
      v_actor,
      pg_catalog.clock_timestamp()
    );
  end if;

  if v_state.partner_id is not null then
    update partner_onboarding_private.partner_state
    set legal_relationship_type = v_relationship_type,
        reclassification_pending = false,
        updated_at = pg_catalog.clock_timestamp()
    where partner_id = p_partner_id
      and relationship_epoch = v_state.relationship_epoch
      and claim_epoch = v_state.claim_epoch
      and release_epoch = v_state.release_epoch
      and reclassification_pending;
    if not found then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
  end if;

  v_hours := case pg_catalog.jsonb_typeof(p_application -> 'hours')
    when 'object' then p_application -> 'hours'
    when 'string' then pg_catalog.jsonb_build_object(
      'summary', p_application ->> 'hours'
    )
    else '{}'::jsonb
  end;
  update public.partners
  set name = v_name,
      legal_name = v_legal_name,
      category = v_categories[1],
      categories = v_categories,
      location = nullif(pg_catalog.btrim(p_application ->> 'location'), ''),
      contact = nullif(pg_catalog.btrim(p_application ->> 'contact'), ''),
      instagram = nullif(pg_catalog.btrim(p_application ->> 'instagram'), ''),
      website = nullif(pg_catalog.btrim(p_application ->> 'website'), ''),
      bio = nullif(pg_catalog.btrim(p_application ->> 'bio'), ''),
      complete_pct = least(
        100,
        greatest(0, coalesce((p_application ->> 'complete_pct')::integer, 0))
      ),
      hours = v_hours,
      business_type = nullif(pg_catalog.btrim(p_application ->> 'business_type'), ''),
      offerings = partner_onboarding_private.jsonb_text_array_v1(
        p_application -> 'offerings'
      ),
      neighborhood = nullif(pg_catalog.btrim(p_application ->> 'neighborhood'), ''),
      tagline = nullif(pg_catalog.btrim(p_application ->> 'tagline'), ''),
      items = case
        when pg_catalog.jsonb_typeof(p_application -> 'items') = 'array'
          then p_application -> 'items'
        else '[]'::jsonb
      end,
      phone = nullif(pg_catalog.btrim(p_application ->> 'phone'), ''),
      photo_emoji = coalesce(
        nullif(pg_catalog.btrim(p_application ->> 'photo_emoji'), ''),
        '🏪'
      ),
      color = coalesce(
        nullif(pg_catalog.btrim(p_application ->> 'color'), ''),
        '#ff8a24'
      ),
      delivery_days = partner_onboarding_private.jsonb_text_array_v1(
        p_application -> 'delivery_days'
      ),
      updated_at = pg_catalog.clock_timestamp()
  where id = p_partner_id;

  return pg_catalog.jsonb_build_object(
    'id', p_partner_id,
    'owner_id', v_actor,
    'request_key', p_request_key,
    'application_receipt_id', v_application.id,
    'correction_receipt_id', v_correction_id,
    'application_sha256', v_application_sha256,
    'previous_application_sha256', v_previous_application_sha256,
    'receipt_status', 'verified',
    'status', v_application.status
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.revise_partner_profile_v1(
  p_partner_id uuid,
  p_request_key uuid,
  p_profile_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_state partner_onboarding_private.partner_state%rowtype;
  v_application partner_onboarding_private.partner_applications%rowtype;
  v_claim partner_onboarding_private.partner_claims%rowtype;
  v_existing_request partner_onboarding_private.partner_profile_correction_requests%rowtype;
  v_child_receipt jsonb;
  v_mode text;
  v_provenance_receipt_id uuid;
  v_correction_receipt_id uuid;
  v_submitted_sha256 text;
  v_request_fingerprint text;
  v_payload_sha256 text;
  v_previous_state_sha256 text;
  v_resulting_profile_sha256 text;
  v_private_profile_status text;
begin
  if v_actor is null
     or partner_onboarding_private.verified_auth_email_v1(v_actor) is null
     or p_partner_id is null
     or p_request_key is null
     or pg_catalog.jsonb_typeof(p_profile_snapshot) is distinct from 'object' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_submitted_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_profile_snapshot)
  );
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'contract', 'partner-profile-correction-router-v1',
        'partner_id', p_partner_id,
        'actor_id', v_actor,
        'submitted_sha256', v_submitted_sha256
      )
    )
  );
  -- A request key belongs to exactly one provenance for its entire lifetime.
  -- This outer lock prevents an application correction and a later claim
  -- correction from both accepting the same actor/request pair.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:profile-correction-request:' ||
      v_actor::text || ':' || p_request_key::text,
      0
    )
  );

  select correction_request.* into v_existing_request
  from partner_onboarding_private.partner_profile_correction_requests correction_request
  where correction_request.actor_id = v_actor
    and correction_request.request_key = p_request_key
  for update;
  if found then
    if v_existing_request.partner_id is distinct from p_partner_id
       or v_existing_request.submitted_sha256 is distinct from v_submitted_sha256
       or v_existing_request.request_fingerprint is distinct from v_request_fingerprint then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;

    -- Exact replay returns the immutable router receipt even when the partner
    -- has since moved from application provenance to a claimed relationship.
    -- Re-running the child would incorrectly apply present-day authority and
    -- turn a valid historical replay into a second, cross-provenance request.
    v_provenance_receipt_id := coalesce(
      v_existing_request.application_receipt_id,
      v_existing_request.claim_receipt_id
    );
    v_correction_receipt_id := coalesce(
      v_existing_request.application_correction_receipt_id,
      v_existing_request.claim_profile_correction_receipt_id
    );
    return pg_catalog.jsonb_build_object(
      'id', v_existing_request.partner_id,
      'owner_id', v_existing_request.actor_id,
      'request_key', v_existing_request.request_key,
      'correction_source', v_existing_request.correction_source,
      'source_receipt_id', v_provenance_receipt_id,
      'correction_receipt_id', v_correction_receipt_id,
      'submitted_sha256', v_existing_request.submitted_sha256,
      'previous_sha256', v_existing_request.previous_sha256,
      'resulting_sha256', v_existing_request.resulting_sha256,
      'receipt_status', 'verified',
      'status', v_existing_request.private_profile_status
    );
  end if;

  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = p_partner_id;
  select application.* into v_application
  from partner_onboarding_private.partner_applications application
  where application.partner_id = p_partner_id;

  if v_state.partner_id is not null
     and v_state.operator_user_id is not distinct from v_actor
     and v_state.reclassification_pending is not true
     and partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id) is not null then
    v_mode := 'claim';
    v_child_receipt :=
      partner_onboarding_private.revise_claimed_partner_profile_v1(
        p_partner_id,
        p_request_key,
        p_profile_snapshot
      );
    v_provenance_receipt_id := (v_child_receipt ->> 'claim_receipt_id')::uuid;
    v_correction_receipt_id :=
      (v_child_receipt ->> 'profile_correction_receipt_id')::uuid;
    v_payload_sha256 := v_child_receipt ->> 'correction_sha256';
    v_previous_state_sha256 := v_child_receipt ->> 'previous_profile_sha256';
    v_resulting_profile_sha256 := v_child_receipt ->> 'resulting_profile_sha256';
  elsif v_application.id is not null
        and v_application.owner_id is not distinct from v_actor
        and (
          v_state.partner_id is null
          or v_state.reclassification_pending is true
        ) then
    v_mode := 'application';
    v_child_receipt := public.revise_partner_application_v1(
      p_partner_id,
      p_request_key,
      p_profile_snapshot
    );
    v_provenance_receipt_id :=
      (v_child_receipt ->> 'application_receipt_id')::uuid;
    v_correction_receipt_id := (v_child_receipt ->> 'correction_receipt_id')::uuid;
    v_payload_sha256 := v_child_receipt ->> 'application_sha256';
    v_previous_state_sha256 := v_child_receipt ->> 'previous_application_sha256';
    v_resulting_profile_sha256 :=
      partner_onboarding_private.partner_profile_sha256(p_partner_id);
  else
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;
  v_private_profile_status := v_child_receipt ->> 'status';

  if v_provenance_receipt_id is null
     or v_correction_receipt_id is null
     or coalesce(v_payload_sha256, '') !~ '^[a-f0-9]{64}$'
     or coalesce(v_previous_state_sha256, '') !~ '^[a-f0-9]{64}$'
     or coalesce(v_resulting_profile_sha256, '') !~ '^[a-f0-9]{64}$'
     or (v_child_receipt ->> 'id') is distinct from p_partner_id::text
     or (v_child_receipt ->> 'owner_id') is distinct from v_actor::text
     or (v_child_receipt ->> 'request_key') is distinct from p_request_key::text
     or (v_child_receipt ->> 'receipt_status') is distinct from 'verified'
     or v_payload_sha256 is distinct from v_submitted_sha256
     or v_private_profile_status is null
     or v_private_profile_status not in ('draft', 'submitted', 'pending', 'missing_info') then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if v_mode = 'claim' then
    select claim.* into v_claim
    from partner_onboarding_private.partner_claims claim
    where claim.id = v_provenance_receipt_id
      and claim.partner_id = p_partner_id
      and claim.accepted_by = v_actor
    for share;
    if not found then
      perform partner_onboarding_private.raise_partner_request_denied_v1();
    end if;
  end if;

  insert into partner_onboarding_private.partner_profile_correction_requests (
    partner_id,
    actor_id,
    request_key,
    correction_source,
    application_receipt_id,
    claim_receipt_id,
    relationship_epoch,
    claim_epoch,
    application_correction_receipt_id,
    claim_profile_correction_receipt_id,
    submitted_sha256,
    previous_sha256,
    resulting_sha256,
    request_fingerprint,
    private_profile_status,
    created_at
  ) values (
    p_partner_id,
    v_actor,
    p_request_key,
    v_mode,
    case when v_mode = 'application' then v_provenance_receipt_id else null end,
    case when v_mode = 'claim' then v_provenance_receipt_id else null end,
    case when v_mode = 'claim' then v_claim.relationship_epoch else null end,
    case when v_mode = 'claim' then v_claim.claim_epoch else null end,
    case when v_mode = 'application' then v_correction_receipt_id else null end,
    case when v_mode = 'claim' then v_correction_receipt_id else null end,
    v_payload_sha256,
    v_previous_state_sha256,
    v_resulting_profile_sha256,
    v_request_fingerprint,
    v_private_profile_status,
    pg_catalog.clock_timestamp()
  );

  return pg_catalog.jsonb_build_object(
    'id', p_partner_id,
    'owner_id', v_actor,
    'request_key', p_request_key,
    'correction_source', v_mode,
    'source_receipt_id', v_provenance_receipt_id,
    'correction_receipt_id', v_correction_receipt_id,
    'submitted_sha256', v_payload_sha256,
    'previous_sha256', v_previous_state_sha256,
    'resulting_sha256', v_resulting_profile_sha256,
    'receipt_status', 'verified',
    'status', v_private_profile_status
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.get_partner_agreement_for_acceptance_v1(
  p_partner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_config partner_onboarding_private.runtime_config%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_grant partner_onboarding_private.partner_actor_authority_grants%rowtype;
  v_version partner_onboarding_private.partner_agreement_versions%rowtype;
begin
  v_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  select rc.* into v_config
  from partner_onboarding_private.runtime_config rc
  where rc.singleton;
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = p_partner_id;
  select g.* into v_grant
  from partner_onboarding_private.partner_actor_authority_grants g
  where g.partner_id = p_partner_id
    and g.user_id = v_actor
    and g.authority_type = 'authorized_signer'
    and g.relationship_epoch = v_state.relationship_epoch
    and not exists (
      select 1
      from partner_onboarding_private.partner_actor_authority_revocations r
      where r.authority_grant_id = g.id
    );
  select av.* into v_version
  from partner_onboarding_private.current_agreement_versions cv
  join partner_onboarding_private.partner_agreement_versions av
    on av.id = cv.agreement_version_id
  where cv.legal_relationship_type = v_state.legal_relationship_type;

  if v_actor is null
     or v_email is null
     or v_config.acceptance_enabled is not true
     or v_state.partner_id is null
     or v_state.operator_user_id is null
     or partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id) is null
     or v_grant.id is null
     or v_grant.verified_email is distinct from v_email
     or v_version.id is null
     or v_version.effective_at > pg_catalog.clock_timestamp() then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  return pg_catalog.jsonb_build_object(
    'partner_id', p_partner_id,
    'agreement_version_id', v_version.id,
    'accepted_owner_id', v_state.operator_user_id,
    'authorized_actor_id', v_actor,
    'legal_relationship_type', v_state.legal_relationship_type,
    'agreement_version', v_version.agreement_version,
    'title', v_version.title,
    'legal_approval_reference', v_version.legal_approval_reference,
    'effective_at', v_version.effective_at,
    'document_snapshot', v_version.document_snapshot,
    'document_sha256', v_version.document_sha256,
    'assent_text', v_version.assent_text,
    'signer_email', v_email,
    'acceptance_enabled', true,
    'authorized_signer', true,
    'signer_email_verified', true
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.record_category_partner_agreement_acceptance_v1(
  p_partner_id uuid,
  p_agreement_version_id uuid,
  p_expected_document_sha256 text,
  p_request_key uuid,
  p_assertions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_config partner_onboarding_private.runtime_config%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_claim partner_onboarding_private.partner_claims%rowtype;
  v_grant partner_onboarding_private.partner_actor_authority_grants%rowtype;
  v_current partner_onboarding_private.current_agreement_versions%rowtype;
  v_version partner_onboarding_private.partner_agreement_versions%rowtype;
  v_existing partner_onboarding_private.partner_agreement_acceptances%rowtype;
  v_assertions_sha256 text;
  v_request_fingerprint text;
  v_acceptance_id uuid;
  v_accepted_at timestamptz;
begin
  v_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  if v_actor is null
     or v_email is null
     or p_partner_id is null
     or p_agreement_version_id is null
     or p_request_key is null
     or pg_catalog.lower(coalesce(p_expected_document_sha256, '')) !~ '^[a-f0-9]{64}$'
     or pg_catalog.jsonb_typeof(p_assertions) is distinct from 'object' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  if (
       select pg_catalog.array_agg(assertion_key order by assertion_key)
       from pg_catalog.jsonb_object_keys(p_assertions) as keys(assertion_key)
     ) is distinct from array[
       'assent_text',
       'assertions_version',
       'electronic_records_consent',
       'reviewed_complete_agreement',
       'signer_authority_confirmed',
       'signer_legal_name',
       'signer_title',
       'typed_signature'
     ]::text[]
     or pg_catalog.jsonb_typeof(p_assertions -> 'assertions_version') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_assertions -> 'signer_legal_name') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_assertions -> 'signer_title') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_assertions -> 'typed_signature') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_assertions -> 'assent_text') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_assertions -> 'signer_authority_confirmed') is distinct from 'boolean'
     or pg_catalog.jsonb_typeof(p_assertions -> 'electronic_records_consent') is distinct from 'boolean'
     or pg_catalog.jsonb_typeof(p_assertions -> 'reviewed_complete_agreement') is distinct from 'boolean' then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_assertions_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_assertions)
  );
  v_request_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p_partner_id,
        'agreement_version_id', p_agreement_version_id,
        'expected_document_sha256', pg_catalog.lower(p_expected_document_sha256),
        'assertions_sha256', v_assertions_sha256,
        'actor_id', v_actor
      )
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:agreement-registry', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:acceptance-request:' || v_actor::text || ':' || p_request_key::text,
      0
    )
  );
  select a.* into v_existing
  from partner_onboarding_private.partner_agreement_acceptances a
  where a.accepted_by = v_actor
    and a.request_key = p_request_key;
  if found then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'partner-onboarding:partner:' || v_existing.partner_id::text,
        0
      )
    );
    select state.* into v_state
    from partner_onboarding_private.partner_state state
    where state.partner_id = v_existing.partner_id
    for update;
    select acceptance.* into v_existing
    from partner_onboarding_private.partner_agreement_acceptances acceptance
    where acceptance.id = v_existing.id
    for update;
    if v_existing.request_fingerprint = v_request_fingerprint
       and v_state.partner_id = v_existing.partner_id
       and partner_onboarding_private.partner_business_identity_is_current_v1(
             v_existing.partner_id,
             v_state.business_key_sha256
           )
       and partner_onboarding_private.current_acceptance_receipt_id_v1(
         v_existing.partner_id
       ) is not distinct from v_existing.id
       and not exists (
         select 1
         from partner_onboarding_private.partner_agreement_acceptance_revocations r
         where r.acceptance_id = v_existing.id
       ) then
      return pg_catalog.jsonb_build_object(
        'acceptance_id', v_existing.id,
        'partner_id', v_existing.partner_id,
        'agreement_version_id', v_existing.agreement_version_id,
        'accepted_owner_id', v_existing.accepted_owner_id,
        'accepted_by', v_existing.accepted_by,
        'request_key', v_existing.request_key,
        'legal_relationship_type', v_existing.legal_relationship_type,
        'agreement_version', v_existing.agreement_version,
        'document_sha256', v_existing.document_sha256,
        'assertions_sha256', v_existing.assertions_sha256,
        'assertions_snapshot', v_existing.assertions_snapshot,
        'accepted_at', v_existing.accepted_at,
        'receipt_status', 'verified'
      );
    end if;
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  -- Runtime config precedes partner/state locks so acceptance and a global
  -- gate shutdown serialize in the same order as release finalization.
  select rc.* into v_config
  from partner_onboarding_private.runtime_config rc
  where rc.singleton
  for share;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'partner-onboarding:partner:' || p_partner_id::text,
      0
    )
  );
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = p_partner_id
  for update;
  select c.* into v_claim
  from partner_onboarding_private.partner_claims c
  where c.id = partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id)
  for share;
  select g.* into v_grant
  from partner_onboarding_private.partner_actor_authority_grants g
  where g.partner_id = p_partner_id
    and g.user_id = v_actor
    and g.authority_type = 'authorized_signer'
    and g.relationship_epoch = v_state.relationship_epoch
  for share;
  select cv.* into v_current
  from partner_onboarding_private.current_agreement_versions cv
  where cv.legal_relationship_type = v_state.legal_relationship_type
  for share;
  select av.* into v_version
  from partner_onboarding_private.partner_agreement_versions av
  where av.id = p_agreement_version_id
  for share;

  if v_state.partner_id is null
     or v_claim.id is null
     or partner_onboarding_private.partner_business_identity_is_current_v1(
          p_partner_id,
          v_state.business_key_sha256
        ) is not true
     or partner_onboarding_private.current_acceptance_receipt_id_v1(p_partner_id) is not null
     or v_grant.id is null
     or exists (
       select 1
       from partner_onboarding_private.partner_actor_authority_revocations r
       where r.authority_grant_id = v_grant.id
     )
     or v_grant.verified_email is distinct from v_email
     or v_current.agreement_version_id is distinct from p_agreement_version_id
     or v_version.id is null
     or v_version.legal_relationship_type is distinct from v_state.legal_relationship_type
     or v_version.document_sha256 is distinct from pg_catalog.lower(p_expected_document_sha256)
     or v_version.effective_at > pg_catalog.clock_timestamp()
     or v_config.acceptance_enabled is not true
     or (p_assertions ->> 'assertions_version') is distinct from 'heha-partner-acceptance-v1'
     or (p_assertions -> 'signer_authority_confirmed') is distinct from 'true'::jsonb
     or (p_assertions -> 'electronic_records_consent') is distinct from 'true'::jsonb
     or (p_assertions -> 'reviewed_complete_agreement') is distinct from 'true'::jsonb
     or (p_assertions ->> 'assent_text') is distinct from v_version.assent_text
     or partner_onboarding_private.normalized_person_text_v1(
       p_assertions ->> 'signer_legal_name'
     ) is distinct from partner_onboarding_private.normalized_person_text_v1(
       v_grant.verified_legal_name
     )
     or partner_onboarding_private.normalized_person_text_v1(
       p_assertions ->> 'typed_signature'
     ) is distinct from partner_onboarding_private.normalized_person_text_v1(
       v_grant.verified_legal_name
     )
     or partner_onboarding_private.normalized_person_text_v1(
       p_assertions ->> 'signer_title'
     ) is distinct from partner_onboarding_private.normalized_person_text_v1(
       v_grant.verified_title
     ) then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_accepted_at := pg_catalog.clock_timestamp();
  insert into partner_onboarding_private.partner_agreement_acceptances (
    partner_id,
    agreement_version_id,
    accepted_owner_id,
    accepted_by,
    legal_relationship_type,
    relationship_epoch,
    agreement_version,
    title,
    effective_at,
    document_snapshot,
    document_sha256,
    assent_text,
    incorporated_versions,
    legal_approval_reference,
    legal_approved_at,
    signer_email,
    assertions_snapshot,
    assertions_sha256,
    request_key,
    request_fingerprint,
    request_evidence,
    accepted_at
  ) values (
    p_partner_id,
    v_version.id,
    v_state.operator_user_id,
    v_actor,
    v_state.legal_relationship_type,
    v_state.relationship_epoch,
    v_version.agreement_version,
    v_version.title,
    v_version.effective_at,
    v_version.document_snapshot,
    v_version.document_sha256,
    v_version.assent_text,
    v_version.incorporated_versions,
    v_version.legal_approval_reference,
    v_version.legal_approved_at,
    v_email,
    p_assertions,
    v_assertions_sha256,
    p_request_key,
    v_request_fingerprint,
    pg_catalog.jsonb_build_object(
      'request_evidence_version', 'heha-partner-request-evidence-v1',
      'received_at', v_accepted_at
    ),
    v_accepted_at
  ) returning id into v_acceptance_id;

  return pg_catalog.jsonb_build_object(
    'acceptance_id', v_acceptance_id,
    'partner_id', p_partner_id,
    'agreement_version_id', v_version.id,
    'accepted_owner_id', v_state.operator_user_id,
    'accepted_by', v_actor,
    'request_key', p_request_key,
    'legal_relationship_type', v_state.legal_relationship_type,
    'agreement_version', v_version.agreement_version,
    'document_sha256', v_version.document_sha256,
    'assertions_sha256', v_assertions_sha256,
    'assertions_snapshot', p_assertions,
    'accepted_at', v_accepted_at,
    'receipt_status', 'verified'
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.list_my_partner_onboarding_assignments_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_assignments jsonb;
begin
  v_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  if v_actor is null or v_email is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'partner_id', assignment.partner_id,
        'role', assignment.assignment_role,
        'display_name', assignment.display_name,
        'private_profile_status', assignment.private_profile_status
      )
      order by assignment.partner_id, assignment.assignment_role
    ),
    '[]'::jsonb
  ) into v_assignments
  from (
    select
      state.partner_id,
      'operator'::text as assignment_role,
      partner.name as display_name,
      partner.status as private_profile_status
    from partner_onboarding_private.partner_state state
    join public.partners partner on partner.id = state.partner_id
    where state.operator_user_id = v_actor
      and partner_onboarding_private.current_claim_receipt_id_v1(state.partner_id) is not null

    union all

    select
      state.partner_id,
      'authorized_signer'::text as assignment_role,
      partner.name as display_name,
      partner.status as private_profile_status
    from partner_onboarding_private.partner_state state
    join public.partners partner on partner.id = state.partner_id
    join partner_onboarding_private.partner_actor_authority_grants authority
      on authority.partner_id = state.partner_id
     and authority.user_id = v_actor
     and authority.authority_type = 'authorized_signer'
     and authority.relationship_epoch = state.relationship_epoch
     and authority.verified_email = v_email
    where partner_onboarding_private.current_claim_receipt_id_v1(state.partner_id) is not null
      and not exists (
        select 1
        from partner_onboarding_private.partner_actor_authority_revocations revocation
        where revocation.authority_grant_id = authority.id
      )
  ) assignment;

  return pg_catalog.jsonb_build_object(
    'projection_version', 'heha-partner-assignments-v1',
    'authorized_actor_id', v_actor,
    'assignments', v_assignments
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

create or replace function public.get_partner_onboarding_capabilities_v1(
  p_partner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_partner public.partners%rowtype;
  v_claim_id uuid;
  v_acceptance_id uuid;
  v_profile_id uuid;
  v_media_id uuid;
  v_compliance_id uuid;
  v_local_identity_id uuid;
  v_smoke_test_id uuid;
  v_partner_consent_id uuid;
  v_heha_review_id uuid;
  v_release_id uuid;
  v_swipe_activation_id uuid;
  v_local_activation_id uuid;
  v_acceptance partner_onboarding_private.partner_agreement_acceptances%rowtype;
  v_profile partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_media partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_compliance partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_local_identity partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_smoke_test partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_partner_consent partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_heha_review partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_authorized boolean := false;
  v_expected_local_lane text;
  v_expected_route_segment text;
  v_local_identity_current boolean := false;
  v_smoke_test_current boolean := false;
  v_partner_consent_current boolean := false;
  v_heha_review_current boolean := false;
begin
  v_email := partner_onboarding_private.verified_auth_email_v1(v_actor);
  select s.* into v_state
  from partner_onboarding_private.partner_state s
  where s.partner_id = p_partner_id;

  if v_actor is not null and v_email is not null and v_state.partner_id is not null then
    v_authorized := v_state.operator_user_id = v_actor
      or exists (
        select 1
        from partner_onboarding_private.partner_actor_authority_grants g
        where g.partner_id = p_partner_id
          and g.user_id = v_actor
          and g.authority_type = 'authorized_signer'
          and g.relationship_epoch = v_state.relationship_epoch
          and g.verified_email = v_email
          and not exists (
            select 1
            from partner_onboarding_private.partner_actor_authority_revocations r
            where r.authority_grant_id = g.id
          )
      );
  end if;
  if v_authorized is not true then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  select p.* into v_partner
  from public.partners p
  where p.id = p_partner_id;
  if v_partner.id is null then
    perform partner_onboarding_private.raise_partner_request_denied_v1();
  end if;

  v_expected_local_lane := case v_state.legal_relationship_type
    when 'restaurant' then 'meals'
    when 'vendor' then 'vendors'
    when 'market' then 'market'
    when 'solo_chef' then 'chef'
    when 'catering' then 'group_orders'
    else null
  end;
  v_expected_route_segment := case v_state.legal_relationship_type
    when 'restaurant' then 'restaurants'
    when 'vendor' then 'vendors'
    when 'market' then 'market'
    when 'solo_chef' then 'chef'
    when 'catering' then 'group-orders'
    else null
  end;

  v_claim_id := partner_onboarding_private.current_claim_receipt_id_v1(p_partner_id);
  v_acceptance_id := partner_onboarding_private.current_acceptance_receipt_id_v1(p_partner_id);
  v_profile_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'profile');
  v_media_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'media');
  v_compliance_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'compliance');
  v_local_identity_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'local_identity');
  v_smoke_test_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'smoke_test');
  v_partner_consent_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'partner_consent');
  v_heha_review_id := partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'heha_review');

  select a.* into v_acceptance
  from partner_onboarding_private.partner_agreement_acceptances a
  where a.id = v_acceptance_id;
  select e.* into v_profile
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_profile_id;
  select e.* into v_media
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_media_id;
  select e.* into v_compliance
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_compliance_id;
  select e.* into v_local_identity
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_local_identity_id;
  select e.* into v_smoke_test
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_smoke_test_id;
  select e.* into v_partner_consent
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_partner_consent_id;
  select e.* into v_heha_review
  from partner_onboarding_private.partner_evidence_receipts e
  where e.id = v_heha_review_id;

  v_local_identity_current := coalesce(
    v_local_identity.id is not null
    and v_expected_local_lane is not null
    and (v_local_identity.evidence_snapshot ->> 'status') is not distinct from 'verified'
    and (v_local_identity.evidence_snapshot ->> 'local_lane') is not distinct from v_expected_local_lane
    and (v_local_identity.evidence_snapshot ->> 'swipe_partner_id') is not distinct from p_partner_id::text
    and coalesce(v_local_identity.evidence_snapshot ->> 'local_partner_id', '') ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (v_local_identity.evidence_snapshot ->> 'primary_cta_destination') is not distinct from 'local'
    and v_partner.primary_cta_destination is not distinct from 'local'
    and v_partner.local_lane is not distinct from v_expected_local_lane
    and (v_local_identity.evidence_snapshot ->> 'primary_cta_path') is not distinct from v_partner.primary_cta_path
    and coalesce(v_partner.primary_cta_path, '') ~
      '^/(restaurants|vendors|market|chef|group-orders)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and pg_catalog.split_part(v_partner.primary_cta_path, '/', 2) is not distinct from
      v_expected_route_segment
    and pg_catalog.split_part(v_partner.primary_cta_path, '/', 3) is not distinct from
      (v_local_identity.evidence_snapshot ->> 'local_partner_id'),
    false
  );

  v_smoke_test_current := coalesce(
    v_smoke_test.id is not null
    and v_local_identity_current
    and (v_smoke_test.evidence_snapshot ->> 'status') is not distinct from 'passed'
    and (v_smoke_test.evidence_snapshot -> 'passed') is not distinct from 'true'::jsonb
    and (v_smoke_test.evidence_snapshot -> 'order_path_passed')
      is not distinct from 'true'::jsonb
    and (v_smoke_test.evidence_snapshot ->> 'local_partner_id') is not distinct from
      (v_local_identity.evidence_snapshot ->> 'local_partner_id')
    and nullif(
      pg_catalog.btrim(v_smoke_test.evidence_snapshot ->> 'customer_order_receipt_id'), ''
    ) is not null
    and nullif(
      pg_catalog.btrim(v_smoke_test.evidence_snapshot ->> 'partner_acceptance_receipt_id'), ''
    ) is not null
    and nullif(
      pg_catalog.btrim(v_smoke_test.evidence_snapshot ->> 'driver_receipt_id'), ''
    ) is not null
    and nullif(
      pg_catalog.btrim(v_smoke_test.evidence_snapshot ->> 'delivery_receipt_id'), ''
    ) is not null,
    false
  );
  v_partner_consent_current := coalesce(
    v_partner_consent.id is not null
    and (v_partner_consent.evidence_snapshot ->> 'status') is not distinct from 'approved'
    and (v_partner_consent.evidence_snapshot -> 'approved')
      is not distinct from 'true'::jsonb
    and v_partner_consent.subject_sha256 is not distinct from
      partner_onboarding_private.partner_preview_sha256(p_partner_id),
    false
  );
  v_heha_review_current := coalesce(
    v_heha_review.id is not null
    and (v_heha_review.evidence_snapshot ->> 'status') is not distinct from 'approved'
    and (v_heha_review.evidence_snapshot -> 'approved')
      is not distinct from 'true'::jsonb
    and v_heha_review.subject_sha256 is not distinct from
      partner_onboarding_private.partner_preview_sha256(p_partner_id),
    false
  );

  -- These two helpers are supplied by 003. PL/pgSQL resolves them when this
  -- function is first executed, after the complete review package is applied.
  v_release_id := partner_onboarding_private.current_release_receipt_id_v1(p_partner_id);
  v_swipe_activation_id := partner_onboarding_private.surface_activation_receipt_id_v1(
    p_partner_id, 'swipe'
  );
  v_local_activation_id := partner_onboarding_private.surface_activation_receipt_id_v1(
    p_partner_id, 'local_orderability'
  );

  return pg_catalog.jsonb_build_object(
    'projection_version', 'heha-partner-onboarding-v1',
    'partner_id', p_partner_id,
    'authorized_actor_id', v_actor,
    'claim', pg_catalog.jsonb_build_object(
      'status', case when v_claim_id is not null then 'verified' else 'blocked' end,
      'evidence_id', v_claim_id
    ),
    'profile', pg_catalog.jsonb_build_object(
      'status', case
        when v_profile.id is not null
         and v_profile.subject_sha256 = partner_onboarding_private.partner_profile_sha256(p_partner_id)
          then 'verified'
        else 'blocked'
      end,
      'evidence_id', case
        when v_profile.id is not null
         and v_profile.subject_sha256 = partner_onboarding_private.partner_profile_sha256(p_partner_id)
          then v_profile.id
        else null
      end
    ),
    'agreement', pg_catalog.jsonb_build_object(
      'status', case when v_acceptance.id is not null then 'accepted' else 'blocked' end,
      'acceptance_id', v_acceptance.id,
      'agreement_version_id', v_acceptance.agreement_version_id
    ),
    'media', pg_catalog.jsonb_build_object(
      'status', case
        when v_media.id is not null
         and v_media.subject_sha256 = partner_onboarding_private.partner_media_sha256(p_partner_id)
          then 'approved'
        else 'blocked'
      end,
      'evidence_id', case
        when v_media.id is not null
         and v_media.subject_sha256 = partner_onboarding_private.partner_media_sha256(p_partner_id)
          then v_media.id
        else null
      end
    ),
    'compliance', pg_catalog.jsonb_build_object(
      'status', case
        when v_compliance.id is not null
         and v_compliance.evidence_snapshot ->> 'status' = 'verified'
          then 'verified'
        else 'blocked'
      end,
      'evidence_id', case
        when v_compliance.id is not null
         and v_compliance.evidence_snapshot ->> 'status' = 'verified'
          then v_compliance.id
        else null
      end
    ),
    'local_profile', pg_catalog.jsonb_build_object(
      'status', case when v_local_identity_current then 'verified' else 'blocked' end,
      'evidence_id', case when v_local_identity_current then v_local_identity.id else null end,
      'primary_cta_destination', case
        when v_local_identity_current then v_local_identity.evidence_snapshot ->> 'primary_cta_destination'
        else null
      end,
      'primary_cta_path', case
        when v_local_identity_current then v_local_identity.evidence_snapshot ->> 'primary_cta_path'
        else null
      end
    ),
    'smoke_test', pg_catalog.jsonb_build_object(
      'status', case when v_smoke_test_current then 'passed' else 'blocked' end,
      'evidence_id', case when v_smoke_test_current then v_smoke_test.id else null end
    ),
    'publication', pg_catalog.jsonb_build_object(
      'partner_consent_status', case
        when v_partner_consent_current then 'approved' else 'blocked'
      end,
      'partner_consent_evidence_id', case
        when v_partner_consent_current then v_partner_consent.id else null
      end,
      'heha_review_status', case
        when v_heha_review_current then 'approved' else 'blocked'
      end,
      'heha_review_evidence_id', case
        when v_heha_review_current then v_heha_review.id else null
      end,
      'release_receipt_id', v_release_id,
      'swipe_activation_receipt_id', v_swipe_activation_id,
      'local_activation_receipt_id', v_local_activation_id,
      'public_swipe_visible', v_swipe_activation_id is not null,
      'local_orderable', v_local_activation_id is not null
    )
  );
exception when others then
  raise exception using errcode = 'P0001', message = 'HEHA_PARTNER_REQUEST_DENIED';
end;
$function$;

-- ---------------------------------------------------------------------------
-- Deterministic least-privilege function ACLs.
-- ---------------------------------------------------------------------------

revoke all on all functions in schema partner_onboarding_private
  from public, anon, authenticated, service_role, supabase_auth_admin;

grant execute on function partner_onboarding_private.bootstrap_staff_authority_v1(uuid, text)
  to authenticated;
grant execute on function partner_onboarding_private.grant_staff_authority_v1(uuid, text, uuid)
  to authenticated;
grant execute on function partner_onboarding_private.revoke_staff_authority_v1(uuid, uuid, text)
  to authenticated;
grant execute on function partner_onboarding_private.reconcile_partner_business_registry_v1(uuid)
  to authenticated;
grant execute on function partner_onboarding_private.set_runtime_config_v1(
  boolean, boolean, boolean, boolean, boolean, boolean, text, uuid
) to authenticated;
revoke all on function partner_onboarding_private.list_pending_partner_applications_v1(uuid, integer)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function partner_onboarding_private.list_pending_partner_applications_v1(uuid, integer)
  to authenticated;
grant execute on function partner_onboarding_private.issue_partner_invitation_v1(
  uuid, uuid, text, text, text, timestamptz, uuid
) to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_invitation_v1(uuid, uuid, text)
  to authenticated;
grant execute on function partner_onboarding_private.reset_unclaimed_partner_reclassification_v1(
  uuid, text, uuid, uuid
) to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_claim_v1(uuid, uuid, text)
  to authenticated;
grant execute on function partner_onboarding_private.grant_partner_signer_authority_v1(
  uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_signer_authority_v1(
  uuid, uuid, text
) to authenticated;
grant execute on function partner_onboarding_private.register_partner_agreement_version_v1(
  text, text, text, timestamptz, text, text, text, jsonb, text, uuid, timestamptz
) to authenticated;
grant execute on function partner_onboarding_private.select_partner_agreement_version_v1(uuid, uuid)
  to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_agreement_acceptance_v1(
  uuid, uuid, text
) to authenticated;
grant execute on function partner_onboarding_private.issue_partner_evidence_v1(
  uuid, text, text, jsonb, uuid, uuid
) to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_evidence_v1(uuid, uuid, text)
  to authenticated;

revoke all on function public.claim_partner_invitation_v1(text, uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.create_or_resume_partner_application_v1(uuid, jsonb)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.revise_partner_application_v1(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.revise_partner_profile_v1(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.get_partner_agreement_for_acceptance_v1(uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.record_category_partner_agreement_acceptance_v1(
  uuid, uuid, text, uuid, jsonb
) from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.get_partner_onboarding_capabilities_v1(uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.list_my_partner_onboarding_assignments_v1()
  from public, anon, authenticated, service_role, supabase_auth_admin;

grant execute on function public.claim_partner_invitation_v1(text, uuid)
  to authenticated;
grant execute on function public.create_or_resume_partner_application_v1(uuid, jsonb)
  to authenticated;
grant execute on function public.revise_partner_profile_v1(uuid, uuid, jsonb)
  to authenticated;
grant execute on function public.get_partner_agreement_for_acceptance_v1(uuid)
  to authenticated;
grant execute on function public.record_category_partner_agreement_acceptance_v1(
  uuid, uuid, text, uuid, jsonb
) to authenticated;
grant execute on function public.get_partner_onboarding_capabilities_v1(uuid)
  to authenticated;
grant execute on function public.list_my_partner_onboarding_assignments_v1()
  to authenticated;

commit;
