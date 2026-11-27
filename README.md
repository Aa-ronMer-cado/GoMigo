# GoMigo

GoMigo connects travelers exploring the Philippines with local companions called Amigos. Travelers choose their own plans, and Amigos can accompany them and share local recommendations.

| App | Flutter directory | Android application ID and iOS bundle ID |
| --- | --- | --- |
| GoMigo Traveler | `apps/traveler` | `com.gomigo.traveler` |
| GoMigo Amigo | `apps/amigo` | `com.gomigo.amigo` |

Traveler, Amigo, and ID Review share one GoMigo Supabase project. Each account has one role and uses its own email address. Sign up in the app for the role you want. ID Review accounts are assigned by a project administrator.

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

## Run Amigo

Give `apps/amigo` its own ignored `.env.demo.json` with the same GoMigo URL and publishable key as Traveler. The hosted GoMigo project has the discovery coordinates and Amigo migrations applied. The repository migration filenames match the hosted history. Apply the repository migrations in order when setting up another authorized environment. [Supabase migration guide](https://supabase.com/docs/guides/deployment/database-migrations)

Use an email address that can receive the project’s confirmation mail.

```powershell
cd apps/amigo
$env:FLUTTER_WINDOWS = 'false'
flutter pub get
flutter run --dart-define-from-file=.env.demo.json
```

1. Create a separate Amigo account and confirm its email. Submit the front and back of a fictional test ID. The reviewer enters the verified full name and gender when approving it. For an older approval missing those fields, use **Approved → Complete Amigo details** in the reviewer site.
2. Choose **Done** after approval to open profile setup. On Android or iOS, select **Use Current Location** to detect the approximate public service area. Add your interests, hourly rate, and bio, then save and switch on availability. Use a separate verified Traveler account to request a booking.
3. In Amigo, accept the request. Check the same booking in Traveler, complete sandbox checkout, and use chat and the meetup map. Start the session within the scheduled window, opt in to location sharing or route recording if desired, and complete the trip. Both participants can leave their own review.
4. Open **Earnings** in Amigo to view completed sandbox bookings. A fictional payout method and simulated withdrawal can be recorded in the demo. No money is disbursed.

Availability controls new requests and acceptance. The database rejects overlapping accepted bookings on the shared schedule. Location sharing and route recording are foreground features and require explicit opt-in for each participant.

## Run ID review

Serve `sites/gomigo-id-review/dist` over HTTP locally or HTTPS on a deployed site. Copy `supabase-config.example.json` to the ignored `supabase-config.json` beside it, and set the same GoMigo URL and publishable key as Traveler. Use fictional or authorized test ID images for the demo.

Create a dedicated, confirmed Supabase Auth account for each reviewer. A project administrator sets its profile role and grants ID Review access using its Auth UID. The update below is for a staff-only account with no booking history or Amigo profile. A role assignment preserves past ID submissions and decisions. An optional demo grant lets a separate Traveler discover the fictional Amigo profiles and simulate a reply on those demo bookings.

```sql
begin;
update public.profiles set role = 'reviewer'
where id = '<reviewer-auth-uuid>' and role = 'traveler'
  and not exists (select from public.bookings where traveler_id = profiles.id)
  and not exists (select from private.amigo_accounts where user_id = profiles.id);
insert into private.verification_reviewers (user_id)
select id from public.profiles where id = '<reviewer-auth-uuid>' and role = 'reviewer'
on conflict do nothing;
commit;

insert into private.demo_travelers (user_id)
values ('<traveler-auth-uuid>') on conflict do nothing;
```

The built-in Supabase mail service restricts recipients to project team email addresses. Configure project SMTP to send signup confirmations to other addresses. Before opening ID review to real applicants, set the retention and deletion process, provision authorized reviewer accounts, and serve the site over HTTPS. [Supabase Auth SMTP](https://supabase.com/docs/guides/auth/auth-smtp)

## Enable Xendit Test Checkout

1. In the GoMigo Xendit dashboard, select Test Mode and generate a development secret key with the permissions needed for payment sessions and payment requests. Xendit may require two-factor authentication. [Xendit API keys](https://help.xendit.co/hc/en-us/articles/16516398053273-What-is-API-Key-and-How-Do-I-Create-Them)
2. Save the values below as Supabase Edge Function secrets. Keep the keys out of Flutter and Git. [GoMigo Edge Function Secrets](https://supabase.com/dashboard/project/gkwdczvsmyrnqkaqjnfc/functions/secrets) [Supabase secrets guide](https://supabase.com/docs/guides/functions/secrets)

| Secret | Value |
| --- | --- |
| `XENDIT_TEST_SECRET_KEY` | Xendit Test Mode secret key beginning with `xnd_development_` |
| `XENDIT_WEBHOOK_TOKEN` | Xendit Test Mode webhook verification token |

The hosted checkout returns to GoMigo’s `xendit-checkout` function. The app refreshes the payment state when it resumes.

3. In Xendit Test Mode under **Settings → Developers → Webhooks**, set the Payment Session Completed and Payment Session Expired URLs to `https://gkwdczvsmyrnqkaqjnfc.supabase.co/functions/v1/xendit-webhook`. [Xendit webhook guidance](https://docs.xendit.co/v1/docs/handling-webhooks)
4. In Traveler, open an accepted demo booking and choose **Prepare test checkout → Continue to test checkout**. Use Xendit test details on the hosted page. Return to Traveler and choose **Refresh payment** if needed. GoMigo verifies the session and payment through Xendit's API before updating the booking. [Xendit test mode](https://docs.xendit.co/v1/docs/create-account)

Existing Maya checkouts remain available for reconciliation. New Maya checkouts are disabled after the Xendit migration. An interrupted Xendit creation without a provider session ID remains reserved until a verified webhook or manual reconciliation confirms its outcome.

## Demo rules and verification

The demo prorates the configured hourly rate by the minute, uses a zero service fee, and accepts durations from one minute to eight hours. Participants can start a paid and accepted session from 15 minutes before its start through the scheduled end. Either participant can complete an active session. Paid demo bookings require a separate refund decision before cancellation can be offered.

To exercise the database locally, start Supabase from the repository root with the CLI and Docker, then run `supabase test db`. Run the Node tests from the repository root.

```text
node --test supabase/functions/_shared/*.test.mjs sites/gomigo-id-review/test/review-api.test.mjs
```
