# Niña Community / Events Dashboard

This branch starts the internal `admin.hehaswipe.app` structure.

## Dashboard split

- `/admin` = protected internal admin home with two large buttons.
- `/admin/pm` = Myren PM dashboard lane.
- `/admin/community` = Niña Community / Events dashboard lane.

## Access rule

Regular users and business accounts must not access internal admin functions. Internal access is controlled through Supabase `user_roles` and RLS.

## Future business dashboards

- HEHA Swipe business dashboard = marketing profile, photos, offers, discovery stats, event promotion requests, and Swipe/SuperSwoop visibility.
- HEHA Local business dashboard = operational tools, orders, availability, listings, hours, fulfillment, and issue handling.

Business dashboards should not expose Myren PM notes, Niña invite lists, Geronimo approval queues, internal outreach notes, or admin-only approval controls.
