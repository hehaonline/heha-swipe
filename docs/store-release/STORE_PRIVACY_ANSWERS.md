# HEHA Swipe store privacy-answer draft

Status: working answers for version 0.1.0 (build 1). The release owner must
reconcile these answers with the deployed backend, infrastructure logs, SDK
behavior, and approved retention policy before entering them in either store.

## Developer and policy identity

- Developer: **Healthy Habit LLC**
- App: **HEHA Swipe** (`online.heha.swipe`)
- Privacy contact: `hello@heha.online`
- Privacy URL: `https://hehaswipe.app/privacy`
- Account-deletion URL: `https://hehaswipe.app/account-deletion`

## Data handled by the candidate

| Store category | Candidate behavior | Linked to account | Purpose |
| --- | --- | --- | --- |
| Email address | Required for email/password authentication | Yes | Account management and app functionality |
| User ID | Supabase account identifier | Yes | Account management and app functionality |
| Name | Optional profile field | Yes | Profile and support functionality |
| Phone number | Optional profile field | Yes | Profile and future coordination functionality |
| Physical address / approximate location | Optional manual area or address entry; device geolocation is disabled | Yes | Local discovery and profile functionality |
| Product interaction / app activity | Swipes, saves, and saved businesses | Yes | Discovery and saved-list functionality |
| Network and security logs | May be processed by infrastructure providers | Potentially | Security, fraud prevention, and service reliability |

The candidate does not request precise device location, advertising ID,
contacts, photos, camera, microphone, health data, payment data, or files. It
does not include advertising or cross-app tracking. Confirm these statements
again against the final signed binaries and provider logs.

## Google Play Data safety working answers

- Data is encrypted in transit: **Yes** (HTTPS only).
- Users can request deletion: **Yes**, in Profile and at the public deletion
  URL. This answer remains blocked until the live deletion process is tested.
- Data sold: **No**.
- Data shared for advertising: **No**.
- Service-provider processing: Supabase authentication/database services and
  Vercel web hosting. Confirm contractual service-provider treatment before
  selecting Google's formal "shared" answers.
- Collection is required for email and user ID; name, phone, and manual
  location/address are optional. Swipes and saves are collected when those
  features are used.

## Apple App Privacy working answers

Declare these as linked to the user and used for app functionality:

- Contact Info: name, email address, phone number, physical address;
- Location: coarse location when a general area is entered;
- Identifiers: user ID;
- Usage Data: product interaction.

Tracking: **No**. Advertising: **No**. The checked-in privacy manifest mirrors
these categories, but App Store Connect answers must still be reviewed against
the final build and live operations.

## Retention and deletion rule to verify

Profile, saved-business, and swipe data are kept while the account is active or
while needed to provide and secure HEHA Swipe. After a verified deletion
request is processed, associated application data is deleted or de-identified,
except limited records required for legal compliance, fraud prevention,
security, or dispute resolution. Those exceptions last only while their purpose
or legal requirement applies; backup and security-log copies expire through
normal retention cycles.

Before submission, the policy owner must confirm that the live operational
process actually follows this rule and document any provider-specific maximum
retention periods. Do not promise a numeric deletion deadline until the owner
has approved and operationally validated it.
