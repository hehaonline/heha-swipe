-- HEHA partner onboarding V1 — release and actual-surface activation gate.
--
-- REVIEW ONLY / DISPOSABLE POSTGRESQL ONLY. A release authorizes activation;
-- it does not claim that Swipe is public or Local is orderable. Each target
-- surface must return its own exact activation receipt first.

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

create table if not exists public.partner_public_cards_v1 (
  partner_id uuid not null references public.partners(id) on delete cascade,
  surface text not null check (surface in ('swipe', 'website', 'local_orderability')),
  release_receipt_id uuid not null references partner_onboarding_private.partner_release_receipts(id) on delete restrict,
  activation_receipt_id uuid not null references partner_onboarding_private.partner_surface_activation_receipts(id) on delete restrict,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  name text not null,
  category text,
  categories text[] not null default '{}'::text[],
  location text,
  instagram text,
  website text,
  bio text,
  tags text[] not null default '{}'::text[],
  rating numeric not null default 0,
  review_count integer not null default 0,
  distance_text text,
  color text,
  photo_emoji text,
  heha_partner boolean not null default true,
  status text not null default 'live',
  complete_pct integer not null default 100,
  hours jsonb not null default '{}'::jsonb,
  business_type text,
  offerings text[] not null default '{}'::text[],
  neighborhood text,
  tagline text,
  items jsonb not null default '[]'::jsonb,
  image_url text,
  price_range text,
  gallery_urls jsonb not null default '[]'::jsonb,
  partner_type text,
  delivery_days text[] not null default '{}'::text[],
  pricing_notes text,
  heha_pillar text,
  swipe_eligible boolean not null default false,
  local_eligible boolean not null default false,
  local_lane text,
  primary_cta_destination text,
  primary_cta_label text,
  primary_cta_path text,
  primary key (partner_id, surface)
);

alter table public.partner_public_cards_v1 enable row level security;
alter table public.partner_public_cards_v1 force row level security;
revoke all on table public.partner_public_cards_v1
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select (
  partner_id, surface, created_at, updated_at, name, category, categories,
  location, instagram, website, bio, tags, rating, review_count, distance_text,
  color, photo_emoji, heha_partner, status, complete_pct, hours, business_type,
  offerings, neighborhood, tagline, items, image_url, price_range, gallery_urls,
  partner_type, delivery_days, pricing_notes, heha_pillar, swipe_eligible,
  local_eligible, local_lane, primary_cta_destination, primary_cta_label,
  primary_cta_path
) on table public.partner_public_cards_v1 to anon, authenticated;

create or replace function partner_onboarding_private.epoch_release_receipt_id_v1(
  p_partner_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select receipt.id
  from partner_onboarding_private.partner_release_receipts receipt
  join partner_onboarding_private.partner_state state
    on state.partner_id = receipt.partner_id
   and state.relationship_epoch = receipt.relationship_epoch
   and state.release_epoch = receipt.release_epoch
  where receipt.partner_id = p_partner_id
    and not exists (
      select 1
      from partner_onboarding_private.partner_release_revocations revocation
      where revocation.release_receipt_id = receipt.id
    )
  order by receipt.released_at desc, receipt.id
  limit 1;
$function$;

create or replace function partner_onboarding_private.invalidate_release_after_partner_change_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_release_id uuid;
begin
  if old.created_at is not distinct from new.created_at
     and old.name is not distinct from new.name
     and old.legal_name is not distinct from new.legal_name
     and old.postal_code is not distinct from new.postal_code
     and old.category is not distinct from new.category
     and old.categories is not distinct from new.categories
     and old.location is not distinct from new.location
     and old.instagram is not distinct from new.instagram
     and old.website is not distinct from new.website
     and old.bio is not distinct from new.bio
     and old.tags is not distinct from new.tags
     and old.rating is not distinct from new.rating
     and old.review_count is not distinct from new.review_count
     and old.distance_text is not distinct from new.distance_text
     and old.color is not distinct from new.color
     and old.photo_emoji is not distinct from new.photo_emoji
     and old.complete_pct is not distinct from new.complete_pct
     and old.hours is not distinct from new.hours
     and old.business_type is not distinct from new.business_type
     and old.offerings is not distinct from new.offerings
     and old.neighborhood is not distinct from new.neighborhood
     and old.tagline is not distinct from new.tagline
     and old.items is not distinct from new.items
     and old.image_url is not distinct from new.image_url
     and old.price_range is not distinct from new.price_range
     and old.gallery_urls is not distinct from new.gallery_urls
     and old.partner_type is not distinct from new.partner_type
     and old.delivery_days is not distinct from new.delivery_days
     and old.pricing_notes is not distinct from new.pricing_notes
     and old.heha_pillar is not distinct from new.heha_pillar
     and old.local_lane is not distinct from new.local_lane
     and old.primary_cta_destination is not distinct from new.primary_cta_destination
     and old.primary_cta_label is not distinct from new.primary_cta_label
     and old.primary_cta_path is not distinct from new.primary_cta_path
     and old.is_test_record is not distinct from new.is_test_record then
    return new;
  end if;

  v_release_id := partner_onboarding_private.epoch_release_receipt_id_v1(new.id);
  if v_release_id is null then
    return new;
  end if;

  update partner_onboarding_private.partner_state
  set release_epoch = release_epoch + 1
  where partner_id = new.id;

  delete from public.partner_public_cards_v1
  where partner_id = new.id;

  update public.partners
  set status = 'paused',
      heha_partner = false,
      website_eligible = false,
      swipe_eligible = false,
      local_eligible = false,
      updated_at = pg_catalog.now()
  where id = new.id;

  insert into partner_onboarding_private.audit_events (
    partner_id, actor_id, event_type, receipt_id, event_data
  ) values (
    new.id,
    auth.uid(),
    'partner_release_invalidated_by_profile_change',
    v_release_id,
    pg_catalog.jsonb_build_object('new_release_epoch_required', true)
  );

  return new;
end;
$function$;

drop trigger if exists invalidate_partner_release_after_reviewed_change on public.partners;
create trigger invalidate_partner_release_after_reviewed_change
after update of
  created_at, name, legal_name, postal_code, category, categories, location,
  instagram, website, bio, tags, rating, review_count, distance_text, color,
  photo_emoji, complete_pct, hours, business_type, offerings, neighborhood,
  tagline, items, image_url, price_range, gallery_urls, partner_type,
  delivery_days, pricing_notes, heha_pillar, local_lane,
  primary_cta_destination, primary_cta_label, primary_cta_path, is_test_record
on public.partners
for each row
execute function partner_onboarding_private.invalidate_release_after_partner_change_v1();

create or replace function partner_onboarding_private.current_release_receipt_id_v1(
  p_partner_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select release_receipt.id
  from partner_onboarding_private.partner_release_receipts release_receipt
  join partner_onboarding_private.partner_state state
    on state.partner_id = release_receipt.partner_id
   and state.relationship_epoch = release_receipt.relationship_epoch
   and state.release_epoch = release_receipt.release_epoch
  join partner_onboarding_private.runtime_config runtime
    on runtime.singleton
   and runtime.environment = 'test'
   and runtime.release_enabled
  join partner_onboarding_private.partner_claims claim
    on claim.id = release_receipt.claim_evidence_id
   and claim.partner_id = state.partner_id
   and claim.relationship_epoch = state.relationship_epoch
   and claim.claim_epoch = state.claim_epoch
   and claim.accepted_by = state.operator_user_id
  join partner_onboarding_private.partner_agreement_acceptances acceptance
    on acceptance.id = release_receipt.agreement_acceptance_id
   and acceptance.partner_id = state.partner_id
   and acceptance.relationship_epoch = state.relationship_epoch
   and acceptance.id = partner_onboarding_private.current_acceptance_receipt_id_v1(state.partner_id)
  join partner_onboarding_private.current_agreement_versions current_agreement
    on current_agreement.legal_relationship_type = state.legal_relationship_type
   and current_agreement.agreement_version_id = acceptance.agreement_version_id
  join partner_onboarding_private.partner_evidence_receipts profile
    on profile.id = release_receipt.profile_evidence_id
   and profile.partner_id = state.partner_id
   and profile.relationship_epoch = state.relationship_epoch
   and profile.evidence_type = 'profile'
  join partner_onboarding_private.partner_evidence_receipts media
    on media.id = release_receipt.media_evidence_id
   and media.partner_id = state.partner_id
   and media.relationship_epoch = state.relationship_epoch
   and media.evidence_type = 'media'
  join partner_onboarding_private.partner_evidence_receipts compliance
    on compliance.id = release_receipt.compliance_evidence_id
   and compliance.partner_id = state.partner_id
   and compliance.relationship_epoch = state.relationship_epoch
   and compliance.evidence_type = 'compliance'
  join partner_onboarding_private.partner_evidence_receipts local_identity
    on local_identity.id = release_receipt.local_identity_evidence_id
   and local_identity.partner_id = state.partner_id
   and local_identity.relationship_epoch = state.relationship_epoch
   and local_identity.evidence_type = 'local_identity'
  join partner_onboarding_private.partner_evidence_receipts smoke_test
    on smoke_test.id = release_receipt.smoke_test_evidence_id
   and smoke_test.partner_id = state.partner_id
   and smoke_test.relationship_epoch = state.relationship_epoch
   and smoke_test.evidence_type = 'smoke_test'
  join partner_onboarding_private.partner_evidence_receipts partner_consent
    on partner_consent.id = release_receipt.partner_consent_evidence_id
   and partner_consent.partner_id = state.partner_id
   and partner_consent.relationship_epoch = state.relationship_epoch
   and partner_consent.evidence_type = 'partner_consent'
  join partner_onboarding_private.partner_evidence_receipts heha_review
    on heha_review.id = release_receipt.heha_review_evidence_id
   and heha_review.partner_id = state.partner_id
   and heha_review.relationship_epoch = state.relationship_epoch
   and heha_review.evidence_type = 'heha_review'
  join public.partners partner on partner.id = state.partner_id
  where release_receipt.partner_id = p_partner_id
    and partner.is_test_record is not true
    and partner_onboarding_private.partner_business_identity_is_current_v1(
      state.partner_id,
      state.business_key_sha256
    )
    and state.legal_relationship_type =
      partner_onboarding_private.relationship_type_for_application_v1(
        pg_catalog.jsonb_build_object(
          'category', partner.category,
          'categories', pg_catalog.to_jsonb(partner.categories),
          'business_type', partner.business_type
        )
      )
    and release_receipt.profile_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'profile')
    and release_receipt.media_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'media')
    and release_receipt.compliance_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'compliance')
    and release_receipt.local_identity_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'local_identity')
    and release_receipt.smoke_test_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'smoke_test')
    and release_receipt.partner_consent_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'partner_consent')
    and release_receipt.heha_review_evidence_id = partner_onboarding_private.current_evidence_receipt_id_v1(state.partner_id, 'heha_review')
    and release_receipt.preview_sha256 = partner_onboarding_private.partner_preview_sha256(state.partner_id)
    and profile.subject_sha256 = partner_onboarding_private.partner_profile_sha256(state.partner_id)
    and media.subject_sha256 = partner_onboarding_private.partner_media_sha256(state.partner_id)
    and partner_consent.subject_sha256 = release_receipt.preview_sha256
    and heha_review.subject_sha256 = release_receipt.preview_sha256
    and local_identity.evidence_snapshot ->> 'primary_cta_destination' = 'local'
    and local_identity.evidence_snapshot ->> 'local_lane' = case state.legal_relationship_type
      when 'restaurant' then 'meals'
      when 'vendor' then 'vendors'
      when 'market' then 'market'
      when 'catering' then 'group_orders'
      when 'solo_chef' then 'chef'
      else null
    end
    and local_identity.evidence_snapshot ->> 'primary_cta_path' = partner.primary_cta_path
    and local_identity.evidence_snapshot ->> 'local_partner_id' ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and partner.primary_cta_destination = 'local'
    and partner.local_lane = case state.legal_relationship_type
      when 'restaurant' then 'meals'
      when 'vendor' then 'vendors'
      when 'market' then 'market'
      when 'catering' then 'group_orders'
      when 'solo_chef' then 'chef'
      else null
    end
    and partner.primary_cta_path ~
      '^/(restaurants|vendors|market|chef|group-orders)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and pg_catalog.split_part(partner.primary_cta_path, '/', 2) = case state.legal_relationship_type
      when 'restaurant' then 'restaurants'
      when 'vendor' then 'vendors'
      when 'market' then 'market'
      when 'catering' then 'group-orders'
      when 'solo_chef' then 'chef'
      else null
    end
    and pg_catalog.split_part(partner.primary_cta_path, '/', 3) =
      local_identity.evidence_snapshot ->> 'local_partner_id'
    and smoke_test.evidence_snapshot @> '{"passed":true,"order_path_passed":true}'::jsonb
    and smoke_test.evidence_snapshot ->> 'local_partner_id' =
      local_identity.evidence_snapshot ->> 'local_partner_id'
    and nullif(smoke_test.evidence_snapshot ->> 'customer_order_receipt_id', '') is not null
    and nullif(smoke_test.evidence_snapshot ->> 'partner_acceptance_receipt_id', '') is not null
    and nullif(smoke_test.evidence_snapshot ->> 'driver_receipt_id', '') is not null
    and nullif(smoke_test.evidence_snapshot ->> 'delivery_receipt_id', '') is not null
    and not exists (
      select 1 from partner_onboarding_private.partner_release_revocations revocation
      where revocation.release_receipt_id = release_receipt.id
    )
    and not exists (
      select 1 from partner_onboarding_private.partner_claim_revocations revocation
      where revocation.claim_id = claim.id
    )
    and not exists (
      select 1 from partner_onboarding_private.partner_agreement_acceptance_revocations revocation
      where revocation.acceptance_id = acceptance.id
    )
    and not exists (
      select 1
      from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id in (
        profile.id,
        media.id,
        compliance.id,
        local_identity.id,
        smoke_test.id,
        partner_consent.id,
        heha_review.id
      )
    )
  order by release_receipt.released_at desc, release_receipt.id
  limit 1;
$function$;

create or replace function partner_onboarding_private.surface_activation_receipt_id_v1(
  p_partner_id uuid,
  p_surface text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select activation.id
  from partner_onboarding_private.partner_surface_activation_receipts activation
  join partner_onboarding_private.partner_release_receipts release_receipt
    on release_receipt.id = activation.release_receipt_id
  join partner_onboarding_private.runtime_config runtime on runtime.singleton
  join partner_onboarding_private.partner_evidence_receipts local_identity
    on local_identity.id = release_receipt.local_identity_evidence_id
  where activation.partner_id = p_partner_id
    and activation.surface = p_surface
    and release_receipt.id = partner_onboarding_private.current_release_receipt_id_v1(p_partner_id)
    and activation.activation_snapshot @> '{"activated":true}'::jsonb
    and activation.activation_snapshot ->> 'release_receipt_id' = release_receipt.id::text
    and activation.activation_snapshot ->> 'target_partner_id' = activation.target_partner_id::text
    and activation.activation_snapshot ->> 'target_receipt_id' = activation.target_receipt_id
    and activation.activation_snapshot ->> 'surface' = activation.surface
    and activation.activation_snapshot ->> 'environment' = 'test'
    and case p_surface
      when 'swipe' then
        runtime.swipe_publication_enabled
        and release_receipt.swipe_publication_authorized
        and activation.target_partner_id = p_partner_id
      when 'website' then
        runtime.swipe_publication_enabled
        and release_receipt.website_publication_authorized
        and activation.target_partner_id = p_partner_id
      when 'local_orderability' then
        runtime.local_ordering_enabled
        and release_receipt.local_orderability_authorized
        and activation.target_partner_id::text = local_identity.evidence_snapshot ->> 'local_partner_id'
      else false
    end
    and not exists (
      select 1
      from partner_onboarding_private.partner_surface_activation_revocations revocation
      where revocation.activation_receipt_id = activation.id
    )
  order by activation.activated_at desc, activation.id
  limit 1;
$function$;

create or replace function public.partner_has_current_release_v1(
  p_partner_id uuid,
  p_surface text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select partner_onboarding_private.surface_activation_receipt_id_v1(
    p_partner_id,
    p_surface
  ) is not null;
$function$;

create or replace function public.partner_card_is_current_v1(
  p_partner_id uuid,
  p_surface text,
  p_release_receipt_id uuid,
  p_activation_receipt_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_release_receipt_id is not distinct from
      partner_onboarding_private.current_release_receipt_id_v1(p_partner_id)
    and p_activation_receipt_id is not distinct from
      partner_onboarding_private.surface_activation_receipt_id_v1(
        p_partner_id,
        p_surface
      );
$function$;

revoke all on function public.partner_has_current_release_v1(uuid, text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.partner_has_current_release_v1(uuid, text)
  to anon, authenticated;
revoke all on function public.partner_card_is_current_v1(uuid, text, uuid, uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.partner_card_is_current_v1(uuid, text, uuid, uuid)
  to anon, authenticated;

drop policy if exists "Released public partner cards only" on public.partner_public_cards_v1;
create policy "Released public partner cards only"
on public.partner_public_cards_v1
for select
to anon, authenticated
using (
  public.partner_card_is_current_v1(
    partner_id,
    surface,
    release_receipt_id,
    activation_receipt_id
  )
);

-- The raw compatibility table is private to the owner. Public consumers use the
-- allowlisted card table and receipt-backed views below.
drop policy if exists "Synthetic legacy public status visibility" on public.partners;
revoke select on table public.partners from anon;

drop view if exists public.public_swipe_partners;
drop view if exists public.public_local_partners;
drop view if exists public.public_partner_directory;

create view public.public_partner_directory
with (security_invoker = true)
as
select
  card.partner_id as id,
  card.created_at,
  card.updated_at,
  card.name,
  card.category,
  card.categories,
  card.location,
  card.instagram,
  card.website,
  card.bio,
  card.tags,
  card.rating,
  card.review_count,
  card.distance_text,
  card.color,
  card.photo_emoji,
  card.heha_partner,
  card.status,
  card.complete_pct,
  card.hours,
  card.business_type,
  card.offerings,
  card.neighborhood,
  card.tagline,
  card.items,
  card.image_url,
  card.price_range,
  card.gallery_urls,
  card.partner_type,
  card.delivery_days,
  card.pricing_notes,
  card.heha_pillar,
  card.swipe_eligible,
  coalesce(local_card.local_eligible, false) as local_eligible,
  local_card.local_lane,
  local_card.primary_cta_destination,
  local_card.primary_cta_label,
  local_card.primary_cta_path
from public.partner_public_cards_v1 card
left join public.partner_public_cards_v1 local_card
  on local_card.partner_id = card.partner_id
 and local_card.surface = 'local_orderability'
where card.surface = 'website';

create view public.public_swipe_partners
with (security_invoker = true)
as
select * from public.public_partner_directory where false
union all
select
  card.partner_id as id,
  card.created_at,
  card.updated_at,
  card.name,
  card.category,
  card.categories,
  card.location,
  card.instagram,
  card.website,
  card.bio,
  card.tags,
  card.rating,
  card.review_count,
  card.distance_text,
  card.color,
  card.photo_emoji,
  card.heha_partner,
  card.status,
  card.complete_pct,
  card.hours,
  card.business_type,
  card.offerings,
  card.neighborhood,
  card.tagline,
  card.items,
  card.image_url,
  card.price_range,
  card.gallery_urls,
  card.partner_type,
  card.delivery_days,
  card.pricing_notes,
  card.heha_pillar,
  card.swipe_eligible,
  coalesce(local_card.local_eligible, false) as local_eligible,
  local_card.local_lane,
  local_card.primary_cta_destination,
  local_card.primary_cta_label,
  local_card.primary_cta_path
from public.partner_public_cards_v1 card
left join public.partner_public_cards_v1 local_card
  on local_card.partner_id = card.partner_id
 and local_card.surface = 'local_orderability'
where card.surface = 'swipe';

create view public.public_local_partners
with (security_invoker = true)
as
select * from public.public_partner_directory where false
union all
select
  card.partner_id as id,
  card.created_at,
  card.updated_at,
  card.name,
  card.category,
  card.categories,
  card.location,
  card.instagram,
  card.website,
  card.bio,
  card.tags,
  card.rating,
  card.review_count,
  card.distance_text,
  card.color,
  card.photo_emoji,
  card.heha_partner,
  card.status,
  card.complete_pct,
  card.hours,
  card.business_type,
  card.offerings,
  card.neighborhood,
  card.tagline,
  card.items,
  card.image_url,
  card.price_range,
  card.gallery_urls,
  card.partner_type,
  card.delivery_days,
  card.pricing_notes,
  card.heha_pillar,
  card.swipe_eligible,
  card.local_eligible,
  card.local_lane,
  card.primary_cta_destination,
  card.primary_cta_label,
  card.primary_cta_path
from public.partner_public_cards_v1 card
where card.surface = 'local_orderability';

revoke all on table public.public_partner_directory
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on table public.public_swipe_partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on table public.public_local_partners
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select on table public.public_partner_directory to anon, authenticated;
grant select on table public.public_swipe_partners to anon, authenticated;
grant select on table public.public_local_partners to anon, authenticated;

create or replace function partner_onboarding_private.finalize_partner_release_v1(
  p_partner_id uuid,
  p_expected_preview_sha256 text,
  p_request_key uuid,
  p_released_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_runtime partner_onboarding_private.runtime_config%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_partner public.partners%rowtype;
  v_existing partner_onboarding_private.partner_release_receipts%rowtype;
  v_claim partner_onboarding_private.partner_claims%rowtype;
  v_acceptance partner_onboarding_private.partner_agreement_acceptances%rowtype;
  v_profile partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_media partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_compliance partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_local partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_smoke partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_consent partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_review partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_expected_local_lane text;
  v_expected_route_segment text;
  v_preview_sha256 text;
  v_fingerprint text;
  v_release_id uuid;
begin
  if p_partner_id is null or p_request_key is null or p_released_by is null
     or coalesce(p_expected_preview_sha256, '') !~ '^[a-f0-9]{64}$' then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  -- The reviewer is the authenticated actor, not a UUID asserted by a broad
  -- backend role. This helper also takes the staff-authority registry lock
  -- before validating the actor's current verified-email-backed authority.
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_released_by,
    'release_reviewer'
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('heha-partner-release:' || p_partner_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('partner-onboarding:agreement-registry', 0)
  );

  select runtime.* into v_runtime
  from partner_onboarding_private.runtime_config runtime
  where runtime.singleton
  for share;

  if v_runtime.singleton is null
     or v_runtime.environment is distinct from 'test'
     or v_runtime.release_enabled is not true then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select partner.* into v_partner
  from public.partners partner
  where partner.id = p_partner_id
  for update;

  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = p_partner_id
  for update;

  if v_partner.id is null
     or v_state.partner_id is null
     or v_state.legal_relationship_type not in ('restaurant', 'vendor', 'market', 'catering', 'solo_chef')
     or partner_onboarding_private.partner_business_identity_is_current_v1(
          p_partner_id,
          v_state.business_key_sha256
        ) is not true
     or v_state.legal_relationship_type is distinct from
       partner_onboarding_private.relationship_type_for_application_v1(
         pg_catalog.jsonb_build_object(
           'category', v_partner.category,
           'categories', pg_catalog.to_jsonb(v_partner.categories),
           'business_type', v_partner.business_type
         )
       )
     or v_state.operator_user_id is null
     or v_partner.is_test_record then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  v_expected_local_lane := case v_state.legal_relationship_type
    when 'restaurant' then 'meals'
    when 'vendor' then 'vendors'
    when 'market' then 'market'
    when 'catering' then 'group_orders'
    when 'solo_chef' then 'chef'
    else null
  end;
  v_expected_route_segment := case v_state.legal_relationship_type
    when 'restaurant' then 'restaurants'
    when 'vendor' then 'vendors'
    when 'market' then 'market'
    when 'catering' then 'group-orders'
    when 'solo_chef' then 'chef'
    else null
  end;

  v_preview_sha256 := partner_onboarding_private.partner_preview_sha256(p_partner_id);
  if v_preview_sha256 is distinct from p_expected_preview_sha256 then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select claim.* into v_claim
  from partner_onboarding_private.partner_claims claim
  where claim.partner_id = p_partner_id
    and claim.relationship_epoch = v_state.relationship_epoch
    and claim.claim_epoch = v_state.claim_epoch
    and claim.accepted_by = v_state.operator_user_id
    and not exists (
      select 1 from partner_onboarding_private.partner_claim_revocations revocation
      where revocation.claim_id = claim.id
    )
  order by claim.accepted_at desc
  limit 1;

  if not found then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select acceptance.* into v_acceptance
  from partner_onboarding_private.partner_agreement_acceptances acceptance
  join partner_onboarding_private.current_agreement_versions current_agreement
    on current_agreement.legal_relationship_type = v_state.legal_relationship_type
   and current_agreement.agreement_version_id = acceptance.agreement_version_id
  where acceptance.partner_id = p_partner_id
    and acceptance.relationship_epoch = v_state.relationship_epoch
    and acceptance.id = partner_onboarding_private.current_acceptance_receipt_id_v1(p_partner_id)
    and not exists (
      select 1 from partner_onboarding_private.partner_agreement_acceptance_revocations revocation
      where revocation.acceptance_id = acceptance.id
    )
  order by acceptance.accepted_at desc
  limit 1;

  if not found then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select evidence.* into v_profile
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'profile'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'profile')
    and evidence.subject_sha256 = partner_onboarding_private.partner_profile_sha256(p_partner_id)
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  select evidence.* into v_media
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'media'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'media')
    and evidence.subject_sha256 = partner_onboarding_private.partner_media_sha256(p_partner_id)
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  select evidence.* into v_compliance
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'compliance'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'compliance')
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  select evidence.* into v_local
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'local_identity'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'local_identity')
    and evidence.evidence_snapshot ->> 'primary_cta_destination' = 'local'
    and evidence.evidence_snapshot ->> 'local_lane' = v_expected_local_lane
    and evidence.evidence_snapshot ->> 'primary_cta_path' = v_partner.primary_cta_path
    and evidence.evidence_snapshot ->> 'local_partner_id' ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  if v_partner.primary_cta_destination is distinct from 'local'
     or v_partner.local_lane is distinct from v_expected_local_lane
     or coalesce(v_partner.primary_cta_path, '') !~
       '^/(restaurants|vendors|market|chef|group-orders)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or pg_catalog.split_part(v_partner.primary_cta_path, '/', 2) is distinct from
       v_expected_route_segment
     or pg_catalog.split_part(v_partner.primary_cta_path, '/', 3) is distinct from
       v_local.evidence_snapshot ->> 'local_partner_id' then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select evidence.* into v_smoke
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'smoke_test'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'smoke_test')
    and evidence.evidence_snapshot @> '{"passed":true,"order_path_passed":true}'::jsonb
    and evidence.evidence_snapshot ->> 'local_partner_id' =
      v_local.evidence_snapshot ->> 'local_partner_id'
    and nullif(evidence.evidence_snapshot ->> 'customer_order_receipt_id', '') is not null
    and nullif(evidence.evidence_snapshot ->> 'partner_acceptance_receipt_id', '') is not null
    and nullif(evidence.evidence_snapshot ->> 'driver_receipt_id', '') is not null
    and nullif(evidence.evidence_snapshot ->> 'delivery_receipt_id', '') is not null
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  select evidence.* into v_consent
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'partner_consent'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'partner_consent')
    and evidence.subject_sha256 = v_preview_sha256
    and evidence.evidence_snapshot @> '{"approved":true}'::jsonb
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  select evidence.* into v_review
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.partner_id = p_partner_id
    and evidence.relationship_epoch = v_state.relationship_epoch
    and evidence.evidence_type = 'heha_review'
    and evidence.id = partner_onboarding_private.current_evidence_receipt_id_v1(p_partner_id, 'heha_review')
    and evidence.subject_sha256 = v_preview_sha256
    and evidence.evidence_snapshot @> '{"approved":true}'::jsonb
    and not exists (
      select 1 from partner_onboarding_private.partner_evidence_revocations revocation
      where revocation.evidence_id = evidence.id
    )
  order by evidence.issued_at desc, evidence.id limit 1;

  if v_profile.id is null or v_media.id is null or v_compliance.id is null
     or v_local.id is null or v_smoke.id is null or v_consent.id is null or v_review.id is null then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  v_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p_partner_id,
        'preview_sha256', v_preview_sha256,
        'claim_evidence_id', v_claim.id,
        'agreement_acceptance_id', v_acceptance.id,
        'profile_evidence_id', v_profile.id,
        'media_evidence_id', v_media.id,
        'compliance_evidence_id', v_compliance.id,
        'local_identity_evidence_id', v_local.id,
        'smoke_test_evidence_id', v_smoke.id,
        'partner_consent_evidence_id', v_consent.id,
        'heha_review_evidence_id', v_review.id,
        'request_key', p_request_key
      )
    )
  );

  select receipt.* into v_existing
  from partner_onboarding_private.partner_release_receipts receipt
  where receipt.released_by = p_released_by and receipt.request_key = p_request_key;

  if found then
    if v_existing.partner_id is distinct from p_partner_id
       or v_existing.request_fingerprint is distinct from v_fingerprint
       or partner_onboarding_private.current_release_receipt_id_v1(p_partner_id) is distinct from v_existing.id then
      raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
    end if;
    return pg_catalog.jsonb_build_object(
      'release_receipt_id', v_existing.id,
      'partner_id', v_existing.partner_id,
      'preview_sha256', v_existing.preview_sha256,
      'released_at', v_existing.released_at,
      'receipt_status', 'verified',
      'swipe_publication_authorized', v_existing.swipe_publication_authorized,
      'website_publication_authorized', v_existing.website_publication_authorized,
      'local_orderability_authorized', v_existing.local_orderability_authorized,
      'public_swipe_visible', false,
      'local_orderable', false
    );
  end if;

  insert into partner_onboarding_private.partner_release_receipts (
    partner_id,
    relationship_epoch,
    claim_evidence_id,
    agreement_acceptance_id,
    profile_evidence_id,
    media_evidence_id,
    compliance_evidence_id,
    local_identity_evidence_id,
    smoke_test_evidence_id,
    partner_consent_evidence_id,
    heha_review_evidence_id,
    preview_sha256,
    swipe_publication_authorized,
    website_publication_authorized,
    local_orderability_authorized,
    release_epoch,
    request_key,
    request_fingerprint,
    released_by
  ) values (
    p_partner_id,
    v_state.relationship_epoch,
    v_claim.id,
    v_acceptance.id,
    v_profile.id,
    v_media.id,
    v_compliance.id,
    v_local.id,
    v_smoke.id,
    v_consent.id,
    v_review.id,
    v_preview_sha256,
    true,
    true,
    true,
    v_state.release_epoch,
    p_request_key,
    v_fingerprint,
    p_released_by
  ) returning id into v_release_id;

  if partner_onboarding_private.current_release_receipt_id_v1(p_partner_id)
       is distinct from v_release_id then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  insert into partner_onboarding_private.audit_events (
    partner_id, actor_id, event_type, receipt_id, event_data
  ) values (
    p_partner_id,
    p_released_by,
    'partner_release_authorized',
    v_release_id,
    pg_catalog.jsonb_build_object('preview_sha256', v_preview_sha256)
  );

  return pg_catalog.jsonb_build_object(
    'release_receipt_id', v_release_id,
    'partner_id', p_partner_id,
    'preview_sha256', v_preview_sha256,
    'released_at', pg_catalog.now(),
    'receipt_status', 'verified',
    'swipe_publication_authorized', true,
    'website_publication_authorized', true,
    'local_orderability_authorized', true,
    'public_swipe_visible', false,
    'local_orderable', false
  );
exception when others then
  raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
end;
$function$;

create or replace function partner_onboarding_private.record_partner_surface_activation_v1(
  p_partner_id uuid,
  p_release_receipt_id uuid,
  p_surface text,
  p_target_partner_id uuid,
  p_target_receipt_id text,
  p_activation_snapshot jsonb,
  p_request_key uuid,
  p_activated_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_runtime partner_onboarding_private.runtime_config%rowtype;
  v_release partner_onboarding_private.partner_release_receipts%rowtype;
  v_existing partner_onboarding_private.partner_surface_activation_receipts%rowtype;
  v_partner public.partners%rowtype;
  v_local partner_onboarding_private.partner_evidence_receipts%rowtype;
  v_fingerprint text;
  v_activation_sha256 text;
  v_activation_id uuid;
  v_expected_authority text;
  v_expected_target_system text;
begin
  if p_partner_id is null or p_release_receipt_id is null or p_target_partner_id is null
     or p_request_key is null or p_activated_by is null
     or p_surface is null
     or p_surface not in ('swipe', 'website', 'local_orderability')
     or nullif(pg_catalog.btrim(coalesce(p_target_receipt_id, '')), '') is null
     or pg_catalog.jsonb_typeof(p_activation_snapshot) <> 'object' then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  v_expected_authority := case p_surface
    when 'swipe' then 'swipe_attestor'
    when 'website' then 'website_attestor'
    when 'local_orderability' then 'local_attestor'
  end;
  v_expected_target_system := case p_surface
    when 'swipe' then 'heha-swipe'
    when 'website' then 'heha-website'
    when 'local_orderability' then 'heha-local'
  end;

  -- Each target attestor is a dedicated authenticated service-principal user.
  -- The supplied actor must equal auth.uid(), retain a verified email, and
  -- hold the exact current surface authority under the registry lock.
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_activated_by,
    v_expected_authority
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('heha-partner-release:' || p_partner_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'heha-partner-target:' || p_surface || ':' || p_target_partner_id::text,
      0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('heha-partner-surface:' || p_partner_id::text || ':' || p_surface, 0)
  );

  select runtime.* into v_runtime
  from partner_onboarding_private.runtime_config runtime
  where runtime.singleton
  for share;

  select partner.* into v_partner
  from public.partners partner
  where partner.id = p_partner_id
  for update;

  if v_runtime.singleton is null
     or v_runtime.environment is distinct from 'test'
     or v_runtime.release_enabled is not true
     or v_partner.id is null then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from partner_onboarding_private.partner_surface_activation_receipts other_activation
    where other_activation.surface = p_surface
      and other_activation.target_partner_id = p_target_partner_id
      and other_activation.partner_id <> p_partner_id
      and other_activation.id = partner_onboarding_private.surface_activation_receipt_id_v1(
        other_activation.partner_id,
        other_activation.surface
      )
  ) then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select receipt.* into v_release
  from partner_onboarding_private.partner_release_receipts receipt
  where receipt.id = p_release_receipt_id and receipt.partner_id = p_partner_id
  for share;

  if not found
     or partner_onboarding_private.current_release_receipt_id_v1(p_partner_id) is distinct from p_release_receipt_id
     or p_activation_snapshot ->> 'release_receipt_id' is distinct from p_release_receipt_id::text
     or p_activation_snapshot ->> 'target_partner_id' is distinct from p_target_partner_id::text
     or p_activation_snapshot ->> 'target_receipt_id' is distinct from p_target_receipt_id
     or p_activation_snapshot ->> 'surface' is distinct from p_surface
     or p_activation_snapshot ->> 'environment' is distinct from 'test'
     or p_activation_snapshot ->> 'attestation_version' is distinct from 'heha-target-activation-v1'
     or p_activation_snapshot ->> 'target_system' is distinct from v_expected_target_system
     or p_activation_snapshot ->> 'attested_by' is distinct from p_activated_by::text
     or not (p_activation_snapshot @> '{"activated":true}'::jsonb) then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  if p_surface in ('swipe', 'website') then
    if p_target_partner_id is distinct from p_partner_id
       or v_runtime.swipe_publication_enabled is not true
       or (p_surface = 'swipe' and not v_release.swipe_publication_authorized)
       or (p_surface = 'website' and not v_release.website_publication_authorized) then
      raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
    end if;
  else
    select evidence.* into v_local
    from partner_onboarding_private.partner_evidence_receipts evidence
    where evidence.id = v_release.local_identity_evidence_id;

    if p_target_partner_id::text is distinct from v_local.evidence_snapshot ->> 'local_partner_id'
       or not v_release.local_orderability_authorized
       or v_runtime.local_ordering_enabled is not true then
      raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
    end if;
  end if;

  v_activation_sha256 := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(p_activation_snapshot)
  );
  v_fingerprint := partner_onboarding_private.sha256_text(
    partner_onboarding_private.canonical_json(
      pg_catalog.jsonb_build_object(
        'partner_id', p_partner_id,
        'release_receipt_id', p_release_receipt_id,
        'surface', p_surface,
        'target_partner_id', p_target_partner_id,
        'target_receipt_id', p_target_receipt_id,
        'activation_sha256', v_activation_sha256,
        'request_key', p_request_key
      )
    )
  );

  select activation.* into v_existing
  from partner_onboarding_private.partner_surface_activation_receipts activation
  where activation.activated_by = p_activated_by and activation.request_key = p_request_key;

  if found then
    if v_existing.request_fingerprint is distinct from v_fingerprint
       or partner_onboarding_private.surface_activation_receipt_id_v1(p_partner_id, p_surface) is distinct from v_existing.id then
      raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
    end if;
    return pg_catalog.jsonb_build_object(
      'activation_receipt_id', v_existing.id,
      'release_receipt_id', v_existing.release_receipt_id,
      'partner_id', v_existing.partner_id,
      'surface', v_existing.surface,
      'target_partner_id', v_existing.target_partner_id,
      'target_receipt_id', v_existing.target_receipt_id,
      'activation_sha256', v_existing.activation_sha256,
      'activated_at', v_existing.activated_at,
      'receipt_status', 'verified'
    );
  end if;

  insert into partner_onboarding_private.partner_surface_activation_receipts (
    partner_id,
    release_receipt_id,
    surface,
    target_partner_id,
    target_receipt_id,
    activation_snapshot,
    activation_sha256,
    request_key,
    request_fingerprint,
    activated_by
  ) values (
    p_partner_id,
    p_release_receipt_id,
    p_surface,
    p_target_partner_id,
    p_target_receipt_id,
    p_activation_snapshot,
    v_activation_sha256,
    p_request_key,
    v_fingerprint,
    p_activated_by
  ) returning id into v_activation_id;

  insert into public.partner_public_cards_v1 (
    partner_id,
    surface,
    release_receipt_id,
    activation_receipt_id,
    created_at,
    updated_at,
    name,
    category,
    categories,
    location,
    instagram,
    website,
    bio,
    tags,
    rating,
    review_count,
    distance_text,
    color,
    photo_emoji,
    heha_partner,
    status,
    complete_pct,
    hours,
    business_type,
    offerings,
    neighborhood,
    tagline,
    items,
    image_url,
    price_range,
    gallery_urls,
    partner_type,
    delivery_days,
    pricing_notes,
    heha_pillar,
    swipe_eligible,
    local_eligible,
    local_lane,
    primary_cta_destination,
    primary_cta_label,
    primary_cta_path
  ) values (
    v_partner.id,
    p_surface,
    p_release_receipt_id,
    v_activation_id,
    v_partner.created_at,
    pg_catalog.now(),
    v_partner.name,
    v_partner.category,
    v_partner.categories,
    v_partner.location,
    v_partner.instagram,
    v_partner.website,
    v_partner.bio,
    v_partner.tags,
    v_partner.rating,
    v_partner.review_count,
    v_partner.distance_text,
    v_partner.color,
    v_partner.photo_emoji,
    true,
    'live',
    v_partner.complete_pct,
    v_partner.hours,
    v_partner.business_type,
    v_partner.offerings,
    v_partner.neighborhood,
    v_partner.tagline,
    v_partner.items,
    v_partner.image_url,
    v_partner.price_range,
    v_partner.gallery_urls,
    v_partner.partner_type,
    v_partner.delivery_days,
    v_partner.pricing_notes,
    v_partner.heha_pillar,
    p_surface = 'swipe',
    p_surface = 'local_orderability',
    case when p_surface = 'local_orderability' then v_partner.local_lane end,
    case when p_surface = 'local_orderability' then v_partner.primary_cta_destination end,
    case when p_surface = 'local_orderability' then v_partner.primary_cta_label end,
    case when p_surface = 'local_orderability' then v_partner.primary_cta_path end
  )
  on conflict (partner_id, surface) do update
  set release_receipt_id = excluded.release_receipt_id,
      activation_receipt_id = excluded.activation_receipt_id,
      updated_at = excluded.updated_at,
      name = excluded.name,
      category = excluded.category,
      categories = excluded.categories,
      location = excluded.location,
      instagram = excluded.instagram,
      website = excluded.website,
      bio = excluded.bio,
      tags = excluded.tags,
      rating = excluded.rating,
      review_count = excluded.review_count,
      distance_text = excluded.distance_text,
      color = excluded.color,
      photo_emoji = excluded.photo_emoji,
      heha_partner = excluded.heha_partner,
      status = excluded.status,
      complete_pct = excluded.complete_pct,
      hours = excluded.hours,
      business_type = excluded.business_type,
      offerings = excluded.offerings,
      neighborhood = excluded.neighborhood,
      tagline = excluded.tagline,
      items = excluded.items,
      image_url = excluded.image_url,
      price_range = excluded.price_range,
      gallery_urls = excluded.gallery_urls,
      partner_type = excluded.partner_type,
      delivery_days = excluded.delivery_days,
      pricing_notes = excluded.pricing_notes,
      heha_pillar = excluded.heha_pillar,
      swipe_eligible = excluded.swipe_eligible,
      local_eligible = excluded.local_eligible,
      local_lane = excluded.local_lane,
      primary_cta_destination = excluded.primary_cta_destination,
      primary_cta_label = excluded.primary_cta_label,
      primary_cta_path = excluded.primary_cta_path;

  update public.partners
  set status = case when p_surface = 'swipe' then 'live' else status end,
      heha_partner = case when p_surface = 'swipe' then true else heha_partner end,
      swipe_eligible = case when p_surface = 'swipe' then true else swipe_eligible end,
      website_eligible = case when p_surface = 'website' then true else website_eligible end,
      local_eligible = case when p_surface = 'local_orderability' then true else local_eligible end,
      updated_at = pg_catalog.now()
  where id = p_partner_id;

  if partner_onboarding_private.surface_activation_receipt_id_v1(
       p_partner_id,
       p_surface
     ) is distinct from v_activation_id then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  insert into partner_onboarding_private.audit_events (
    partner_id, actor_id, event_type, receipt_id, event_data
  ) values (
    p_partner_id,
    p_activated_by,
    'partner_surface_activated',
    v_activation_id,
    pg_catalog.jsonb_build_object('surface', p_surface, 'target_receipt_id', p_target_receipt_id)
  );

  return pg_catalog.jsonb_build_object(
    'activation_receipt_id', v_activation_id,
    'release_receipt_id', p_release_receipt_id,
    'partner_id', p_partner_id,
    'surface', p_surface,
    'target_partner_id', p_target_partner_id,
    'target_receipt_id', p_target_receipt_id,
    'activation_sha256', v_activation_sha256,
    'activated_at', pg_catalog.now(),
    'receipt_status', 'verified'
  );
exception when others then
  raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_release_v1(
  p_release_receipt_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_receipt partner_onboarding_private.partner_release_receipts%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_partner public.partners%rowtype;
begin
  if p_release_receipt_id is null
     or p_revoked_by is null
     or nullif(pg_catalog.btrim(coalesce(p_reason_code, '')), '') is null then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by,
    'release_reviewer'
  );

  select receipt.* into v_receipt
  from partner_onboarding_private.partner_release_receipts receipt
  where receipt.id = p_release_receipt_id;

  if v_receipt.id is null then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from partner_onboarding_private.partner_release_revocations revocation
    where revocation.release_receipt_id = p_release_receipt_id
  ) then
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('heha-partner-release:' || v_receipt.partner_id::text, 0)
  );

  select partner.* into v_partner
  from public.partners partner
  where partner.id = v_receipt.partner_id
  for update;

  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = v_receipt.partner_id
  for update;

  select receipt.* into v_receipt
  from partner_onboarding_private.partner_release_receipts receipt
  where receipt.id = p_release_receipt_id
  for share;

  if exists (
    select 1
    from partner_onboarding_private.partner_release_revocations revocation
    where revocation.release_receipt_id = p_release_receipt_id
  ) then
    return;
  end if;

  if v_receipt.id is null
     or v_partner.id is null
     or v_state.partner_id is null
     or partner_onboarding_private.epoch_release_receipt_id_v1(v_receipt.partner_id)
          is distinct from v_receipt.id then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  insert into partner_onboarding_private.partner_release_revocations (
    release_receipt_id, revoked_by, reason_code
  ) values (
    p_release_receipt_id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  );

  update partner_onboarding_private.partner_state
  set release_epoch = release_epoch + 1
  where partner_id = v_receipt.partner_id;

  delete from public.partner_public_cards_v1
  where partner_id = v_receipt.partner_id
    and release_receipt_id = v_receipt.id;
  update public.partners
  set status = 'paused',
      heha_partner = false,
      website_eligible = false,
      swipe_eligible = false,
      local_eligible = false,
      updated_at = pg_catalog.now()
  where id = v_receipt.partner_id;
exception when others then
  raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
end;
$function$;

create or replace function partner_onboarding_private.revoke_partner_surface_activation_v1(
  p_activation_receipt_id uuid,
  p_revoked_by uuid,
  p_reason_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_activation partner_onboarding_private.partner_surface_activation_receipts%rowtype;
  v_state partner_onboarding_private.partner_state%rowtype;
  v_partner public.partners%rowtype;
  v_expected_authority text;
begin
  if p_activation_receipt_id is null
     or p_revoked_by is null
     or nullif(pg_catalog.btrim(coalesce(p_reason_code, '')), '') is null then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select activation.* into v_activation
  from partner_onboarding_private.partner_surface_activation_receipts activation
  where activation.id = p_activation_receipt_id;

  v_expected_authority := case v_activation.surface
    when 'swipe' then 'swipe_attestor'
    when 'website' then 'website_attestor'
    when 'local_orderability' then 'local_attestor'
  end;

  if v_activation.id is null or v_expected_authority is null then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  -- Only the dedicated authenticated target principal may revoke its surface
  -- acknowledgement. A release reviewer can instead revoke the whole release,
  -- which atomically invalidates every target surface.
  perform partner_onboarding_private.require_active_staff_authority_v1(
    p_revoked_by,
    v_expected_authority
  );

  if exists (
    select 1
    from partner_onboarding_private.partner_surface_activation_revocations revocation
    where revocation.activation_receipt_id = p_activation_receipt_id
  ) then
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('heha-partner-release:' || v_activation.partner_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'heha-partner-surface:' || v_activation.partner_id::text || ':' || v_activation.surface,
      0
    )
  );

  select partner.* into v_partner
  from public.partners partner
  where partner.id = v_activation.partner_id
  for update;

  select state.* into v_state
  from partner_onboarding_private.partner_state state
  where state.partner_id = v_activation.partner_id
  for update;

  select activation.* into v_activation
  from partner_onboarding_private.partner_surface_activation_receipts activation
  where activation.id = p_activation_receipt_id
  for share;

  if exists (
    select 1
    from partner_onboarding_private.partner_surface_activation_revocations revocation
    where revocation.activation_receipt_id = p_activation_receipt_id
  ) then
    return;
  end if;

  if v_activation.id is null
     or v_partner.id is null
     or v_state.partner_id is null
     or partner_onboarding_private.epoch_release_receipt_id_v1(v_activation.partner_id)
          is distinct from v_activation.release_receipt_id
     or exists (
       select 1
       from partner_onboarding_private.partner_surface_activation_revocations revocation
       where revocation.activation_receipt_id = v_activation.id
     ) then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  insert into partner_onboarding_private.partner_surface_activation_revocations (
    activation_receipt_id, revoked_by, reason_code
  ) values (
    p_activation_receipt_id, p_revoked_by, pg_catalog.btrim(p_reason_code)
  );

  insert into partner_onboarding_private.partner_release_revocations (
    release_receipt_id, revoked_by, reason_code
  ) values (
    v_activation.release_receipt_id,
    p_revoked_by,
    'surface_activation_revoked:' || v_activation.surface
  );

  update partner_onboarding_private.partner_state
  set release_epoch = release_epoch + 1
  where partner_id = v_activation.partner_id;

  delete from public.partner_public_cards_v1
  where partner_id = v_activation.partner_id;

  update public.partners
  set status = 'paused',
      heha_partner = false,
      swipe_eligible = false,
      website_eligible = false,
      local_eligible = false,
      updated_at = pg_catalog.now()
  where id = v_activation.partner_id;
exception when others then
  raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
end;
$function$;

create or replace function public.get_partner_orderability_receipt_v1(p_local_partner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_activation partner_onboarding_private.partner_surface_activation_receipts%rowtype;
  v_release partner_onboarding_private.partner_release_receipts%rowtype;
  v_local partner_onboarding_private.partner_evidence_receipts%rowtype;
begin
  select activation.* into v_activation
  from partner_onboarding_private.partner_surface_activation_receipts activation
  where activation.surface = 'local_orderability'
    and activation.target_partner_id = p_local_partner_id
    and activation.id = partner_onboarding_private.surface_activation_receipt_id_v1(
      activation.partner_id,
      'local_orderability'
    );

  if not found then
    raise exception 'HEHA_PARTNER_REQUEST_DENIED' using errcode = 'P0001';
  end if;

  select receipt.* into v_release
  from partner_onboarding_private.partner_release_receipts receipt
  where receipt.id = v_activation.release_receipt_id;

  select evidence.* into v_local
  from partner_onboarding_private.partner_evidence_receipts evidence
  where evidence.id = v_release.local_identity_evidence_id;

  return pg_catalog.jsonb_build_object(
    'receipt_status', 'verified',
    'swipe_partner_id', v_activation.partner_id,
    'local_partner_id', v_activation.target_partner_id,
    'release_receipt_id', v_release.id,
    'activation_receipt_id', v_activation.id,
    'local_path', v_local.evidence_snapshot ->> 'primary_cta_path',
    'target_receipt_id', v_activation.target_receipt_id,
    'activated_at', v_activation.activated_at,
    'local_orderable', true
  );
end;
$function$;

revoke all on function partner_onboarding_private.finalize_partner_release_v1(uuid, text, uuid, uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function partner_onboarding_private.record_partner_surface_activation_v1(uuid, uuid, text, uuid, text, jsonb, uuid, uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function partner_onboarding_private.revoke_partner_release_v1(uuid, uuid, text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function partner_onboarding_private.revoke_partner_surface_activation_v1(uuid, uuid, text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function public.get_partner_orderability_receipt_v1(uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;

grant execute on function partner_onboarding_private.finalize_partner_release_v1(uuid, text, uuid, uuid)
  to authenticated;
grant execute on function partner_onboarding_private.record_partner_surface_activation_v1(uuid, uuid, text, uuid, text, jsonb, uuid, uuid)
  to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_release_v1(uuid, uuid, text)
  to authenticated;
grant execute on function partner_onboarding_private.revoke_partner_surface_activation_v1(uuid, uuid, text)
  to authenticated;
grant execute on function public.get_partner_orderability_receipt_v1(uuid)
  to service_role;

revoke all on function partner_onboarding_private.current_release_receipt_id_v1(uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function partner_onboarding_private.surface_activation_receipt_id_v1(uuid, text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function partner_onboarding_private.epoch_release_receipt_id_v1(uuid)
  from public, anon, authenticated, service_role, supabase_auth_admin;
revoke all on function partner_onboarding_private.invalidate_release_after_partner_change_v1()
  from public, anon, authenticated, service_role, supabase_auth_admin;

commit;
