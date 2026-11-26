# GoMigo

GoMigo connects travelers exploring the Philippines with local companions called Amigos. Travelers choose their own plans, and Amigos can accompany them and share local recommendations.

| App | Flutter directory | Android application ID and iOS bundle ID |
| --- | --- | --- |
| GoMigo Traveler | `apps/traveler` | `com.gomigo.traveler` |
| GoMigo Amigo | `apps/amigo` | `com.gomigo.amigo` |

The Traveler app and ID reviewer site share the GoMigo Supabase demo project. The Amigo app remains at its existing skeleton. The backend already has shared records for the future Amigo app.

## Run Traveler

From `apps/traveler`, create an ignored `.env.demo.json` with the existing GoMigo project's API URL and publishable key. The local demo configuration is already set up in the development workspace. [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)

```json
{
  "SUPABASE_URL": "https://gkwdczvsmyrnqkaqjnfc.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "<GoMigo publishable key>"
}
```

```powershell
# For Android or web work on Windows without Developer Mode.
$env:FLUTTER_WINDOWS = 'false'
flutter pub get
flutter run --dart-define-from-file=.env.demo.json
flutter analyze
flutter test
```

Add `-d chrome` for web. Build and run on a phone to exercise the native camera and GPS. iOS builds require macOS and Xcode. Location sharing and route recording run while the meetup map is open in the foreground. Live markers expire after two minutes without an update. Long outages can leave gaps in recorded routes. The map uses OpenStreetMap tiles and draws recorded points. [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/)

**Find a Migo** uses the Traveler’s location on-device to show verified Amigos whose public service area is within 20 km, closest first. Choose **Browse all areas** to search without location. The fictional demo profiles use approximate centers in Manila, Cebu City, and Puerto Princesa.

## Run ID review

Serve `sites/gomigo-id-review/dist` over HTTP locally or HTTPS on a deployed site. Copy `supabase-config.example.json` to the ignored `supabase-config.json` beside it, and set the same GoMigo URL and publishable key as Traveler. Use fictional or authorized test ID images for the demo.

Use two distinct confirmed Supabase Auth accounts. A project administrator assigns the reviewer and enables the optional simulated Amigo controls for the demo Traveler using their respective Auth UUIDs. Demo accounts can discover the three fictional Amigo profiles and simulate a reply on their own demo bookings.

```sql
insert into private.verification_reviewers (user_id)
values ('<reviewer-auth-uuid>') on conflict do nothing;

insert into private.demo_travelers (user_id)
values ('<traveler-auth-uuid>') on conflict do nothing;
```

The built-in Supabase mail service restricts recipients to project team email addresses. Configure project SMTP to send signup confirmations to other addresses. Before opening ID review to real applicants, set the retention and deletion process, provision authorized reviewer accounts, and serve the site over HTTPS. [Supabase Auth SMTP](https://supabase.com/docs/guides/auth/auth-smtp)

## Enable PayMongo test checkout

The checkout and webhook functions are deployed to the GoMigo demo project. An authorized PayMongo account owner needs to configure these server-side secrets on the project.

| Secret | Value |
| --- | --- |
| `PAYMONGO_TEST_SECRET_KEY` | PayMongo test secret key beginning with `sk_test_` |
| `PAYMONGO_WEBHOOK_SECRET` | Signing secret for the PayMongo test webhook |
| `PAYMONGO_RETURN_URL` | `https://gkwdczvsmyrnqkaqjnfc.supabase.co/functions/v1/paymongo-checkout` |

In PayMongo test mode, register `checkout_session.payment.paid` at `https://gkwdczvsmyrnqkaqjnfc.supabase.co/functions/v1/paymongo-webhook`. Enter test card details in the hosted checkout. The app reads the backend payment result, which is confirmed by a signed webhook. [PayMongo test setup](https://docs.paymongo.com/docs/account-settings-troubleshooting) [Webhook setup](https://docs.paymongo.com/docs/developer-tools-webhook-setup-management)

## Demo rules and verification

The demo prorates the configured hourly rate by the minute, uses a zero service fee, and accepts durations from one minute to eight hours. Participants can start a paid and accepted session from 15 minutes before its start through the scheduled end. Either participant can complete an active session. Paid demo bookings require a separate refund decision before cancellation can be offered.

The migrations match the hosted GoMigo migration history. To exercise the database locally, start Supabase from the repository root with the CLI and Docker, then run `supabase test db`. Run the Node tests from the repository root.

```text
node --test supabase/functions/_shared/paymongo.test.mjs sites/gomigo-id-review/test/review-api.test.mjs
```
