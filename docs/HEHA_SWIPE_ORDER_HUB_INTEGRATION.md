# HEHA Swipe + HEHA Order Hub Integration Plan

**Purpose:** This document keeps HEHA Swipe connected to the larger HEHA app ecosystem while protecting the current MVP from scope creep.

HEHA Swipe is the discovery and marketing layer. HEHA Order Hub is the operational fulfillment layer.

They should connect over time, but they should not be merged too early.

---

## 1. Product Separation

| Product | Primary purpose | Build timing |
|---|---|---|
| HEHA Order Hub | Orders, operations, restaurants/vendors, drivers/shoppers, SOM, admin | Build first |
| HEHA Swipe | Discovery, partner saves, local offers, SuperSwoop, Community Pass interest | Build in parallel but keep lightweight |
| Customer App | Reorders, tracking, Route Match Savings, customer account layer | Later |

---

## 2. HEHA Swipe Role

HEHA Swipe should help customers discover and save:

- healthy restaurants
- clean food vendors
- wellness partners
- markets
- private chefs
- local service partners
- Community Pass offers
- future Deal of the Day / SuperSwoop promotions

The app should feel modern, clean, earthy, vibrant, and simple.

---

## 3. Order Hub Role

HEHA Order Hub should handle:

- real order intake
- restaurant/vendor confirmations
- driver/shopper assignments
- SOM dispatch
- issue handling
- admin oversight
- payout visibility
- Make.com notification handoffs
- Supabase source-of-truth data

Order Hub is the operations engine. Swipe is the discovery engine.

---

## 4. Integration Vision

The future connection should look like this:

```text
Customer discovers partner in HEHA Swipe
  ↓
Customer saves partner or offer
  ↓
Partner/offer data becomes useful for outreach and recommendations
  ↓
If partner is orderable, customer is sent to HEHA Order Hub / Wix / Customer App order path
  ↓
Order Hub handles checkout, dispatch, fulfillment, and status tracking
```

---

## 5. What HEHA Swipe Should Not Do Yet

Do not add these too early:

- full checkout
- restaurant order management
- driver dispatch
- payouts
- complex admin finance
- live delivery tracking
- full Community Pass payment logic
- native app packaging before the web flow is stable

Those belong to Order Hub or later customer app phases.

---

## 6. Partner Data Relationship

HEHA Swipe and Order Hub may eventually share partner records.

Recommended future shared partner fields:

| Field | Purpose |
|---|---|
| partner_id | Shared unique partner ID |
| name | Business name |
| category | Restaurant, vendor, wellness, market, service |
| status | pending, approved, active, paused |
| orderable | true/false |
| swipe_visible | true/false |
| order_hub_visible | true/false |
| community_pass_eligible | true/false |
| super_swoop_enabled | true/false |
| city | Local search/filter |
| neighborhood | Tampa Bay targeting |
| website_url | Public profile |
| instagram_url | Social proof |
| google_maps_url | Location |
| approved_by_admin | Governance |

---

## 7. Customer UX Connection

Swipe customer path:

```text
Open HEHA Swipe
↓
See partner card
↓
Swipe right to save
↓
Tap partner profile
↓
If orderable: show Order / View Menu button
↓
Button routes to the correct HEHA order path
```

Important: If a partner is not ready for ordering, the CTA should be:

- Save for later
- Follow updates
- Request this partner
- Join newsletter

Do not create fake ordering paths.

---

## 8. SuperSwoop / Super Swipe Logic

SuperSwoop is a future high-intent signal.

Possible meaning:

- customer strongly wants this partner/offer
- partner Deal of the Day promotion
- Freebird Fund-linked engagement
- future paid boost or credit-based promotion

MVP rule:

Record SuperSwoop as interest first. Do not create payment logic until the discovery flow and partner approval flow are stable.

---

## 9. Community Pass Relationship

Community Pass should eventually connect both apps:

| In HEHA Swipe | In Order Hub / Customer App |
|---|---|
| Discover partner offers | Redeem or apply eligible offers |
| Save discounts | Track member benefits |
| View local healthy partners | Connect to ordering or booking |
| SuperSwoop a deal | Route to order/offer path |

MVP rule: Community Pass can be shown as coming soon or interest capture until the operational order system is stable.

---

## 10. Data Flow Priorities

### Phase 1

Keep Swipe lightweight:

- partner cards
- swipe/save events
- pending partner submissions
- admin-approved partner visibility
- newsletter / interest capture

### Phase 2

Connect partner IDs and categories between Swipe and Order Hub.

### Phase 3

Route orderable partner cards into the correct HEHA ordering flow.

### Phase 4

Add Community Pass offer visibility.

### Phase 5

Add SuperSwoop campaigns, offer analytics, and partner reporting.

---

## 11. Recommended CTAs

### For orderable partner

- Order from this partner
- View HEHA menu
- Schedule delivery

### For non-orderable partner

- Save this partner
- Request this business on HEHA
- Follow updates
- Join launch list

### For wellness/service partner

- View profile
- Request intro
- Save for later
- Join Community Pass updates

---

## 12. Admin / Approval Logic

Partner submissions should remain pending until reviewed.

Recommended statuses:

| Status | Meaning |
|---|---|
| pending | Submitted but not reviewed |
| review_needed | Needs more information |
| approved | Approved for public Swipe visibility |
| active | Live and promoted |
| paused | Temporarily hidden |
| rejected | Not accepted |

Admin approval should happen outside the public UI until the admin dashboard is secure.

---

## 13. Main Build Warning

Do not let HEHA Swipe delay Order Hub.

Order Hub proves real operations.

Swipe creates discovery, interest, partner demand, and community visibility.

Both matter, but the fulfillment engine must work before the discovery engine drives real demand into it.
