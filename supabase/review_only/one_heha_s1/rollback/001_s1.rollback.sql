-- Disposable rollback for the ONE HEHA S1 review package.
--
-- REVIEW ONLY. Use only on a synthetic environment created for this package.
-- Never use this as a Production rollback or to rewrite migration history.

begin;

drop function if exists one_heha_private.revoke_identity_for_canonical_user(
  uuid,
  uuid,
  text,
  text,
  timestamptz
);

drop function if exists community_pass_private.is_active_for_canonical_user(
  uuid,
  timestamptz
);

drop function if exists community_pass_private.start_trial_for_swipe_user(
  uuid,
  timestamptz
);

drop function if exists community_pass_private.create_or_get_account_for_swipe_user(
  uuid,
  text,
  text,
  text,
  timestamptz
);

drop function if exists community_pass_private.resolve_account_for_swipe_user(uuid);
drop function if exists one_heha_private.resolve_canonical_user_for_swipe(uuid, text);
drop function if exists one_heha_private.activate_identity_link(
  uuid,
  uuid,
  uuid,
  timestamptz,
  text,
  timestamptz
);
drop function if exists one_heha_private.begin_link_handshake(
  uuid,
  uuid,
  text,
  timestamptz,
  text,
  timestamptz
);
drop function if exists community_pass_private.current_environment();

drop table if exists public.community_pass_stripe_event_inbox;
drop table if exists public.community_pass_events;
drop table if exists public.community_pass_acceptances;
drop table if exists public.community_pass_entitlements;
drop table if exists public.community_pass_purchases;
drop table if exists public.community_pass_subscriptions;
drop table if exists public.community_pass_accounts;

drop table if exists one_heha_private.identity_events;
drop table if exists one_heha_private.link_handshakes;
drop table if exists one_heha_private.identity_links;
drop table if exists community_pass_private.runtime_config;

drop function if exists community_pass_private.reject_append_only_mutation();
drop function if exists community_pass_private.guard_trial_used_once();
drop function if exists community_pass_private.guard_runtime_config();
drop function if exists community_pass_private.set_updated_at();
drop function if exists one_heha_private.reject_append_only_mutation();
drop function if exists one_heha_private.set_updated_at();

drop schema if exists one_heha_private;
drop schema if exists community_pass_private;

commit;
