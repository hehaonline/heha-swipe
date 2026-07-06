# Website embed routing plan

The HEHA website is the broad intentional local-search layer. Primary partner CTAs stay inside the HEHA ecosystem: HEHA Local for food/order utility and HEHA Swipe for discovery.

This plan will replace page-level Wix business logic with source-controlled embed routes hosted by HEHA Swipe:

- `/embed/partners` — searchable partner directory backed by `public_partner_directory`
- `/embed/become-partner` — partner onboarding handoff to `/?becomePartner=1`

The Wix site remains the public shell/SEO layer. It should embed stable URLs and not own partner source-of-truth logic.
