# GoMigo contributor guide

## Product and source of truth

GoMigo connects travelers exploring the Philippines with local companions called Amigos. Travelers decide their own activities and plans. Amigos accompany them and can share personal recommendations and local insights. Preserve this flexible, informal companionship model throughout the product.

The mobile apps use Flutter and Dart. The [Figma Final Design page](https://www.figma.com/design/LdgU1suH7iReK5K5d0jAOZ/amigo?node-id=472-5984) is the visual reference for the Traveler and Amigo screens. Inspect the relevant current frames when implementing a design. Treat names, images, prices, dates, reviews, and other mockup content as sample data.

This guide describes the implementation in the working tree and the rules for changing it. Use [README.md](README.md) for setup and demo walkthroughs. Check Git status, the target environment's configuration, and the deployed migration and function versions before relying on hosted behavior. Follow the user's current instructions when they change an earlier decision.

## Technology stack

| Area | GoMigo implementation |
| --- | --- |
| Traveler and Amigo apps | Flutter and Dart, with separate app entry points |
| Shared UI | Local Flutter packages for the design system and shared widgets |
| Accounts, data, file storage, realtime, and server-side functions | Both apps and the reviewer site use one Supabase project with Auth, PostgreSQL, Storage, Realtime, and Edge Functions |
| Payment demo | Xendit Test Mode for new Traveler checkouts through `xendit-checkout` and `xendit-webhook` |
| Maps and recorded routes | Shared `flutter_map` meetup UI, OpenStreetMap tiles, device location, and Supabase booking data |
| ID review | Separate reviewer website with Supabase Auth, private uploads, and authorized human decisions |

Use the same Supabase URL and publishable key in each client's ignored local configuration. Each account has one role. Use separate email addresses for Traveler and Amigo accounts, and provision dedicated reviewer accounts through a project administrator.

Use test accounts, fictional or authorized test IDs, and test payments for demos. Automated identity verification, real payment collection, live payouts, routing and ETAs, background tracking, and production hosting require separate setup and decisions. Firebase Cloud Messaging is an option if push notifications are needed while the apps are closed.

## Repository and folder placement

```text
GoMigo/
├── apps/
│   ├── traveler/                 # Traveler Flutter app and platform projects
│   │   ├── lib/main.dart
│   │   ├── lib/navigation/       # App entry, routing, and route guards
│   │   ├── lib/features/         # Traveler workflows
│   │   ├── assets/               # Traveler-specific assets
│   │   └── test/                 # Traveler tests
│   └── amigo/                    # Amigo Flutter app and platform projects
│       ├── lib/main.dart
│       ├── lib/navigation/       # App entry, routing, and route guards
│       ├── lib/features/         # Amigo workflows
│       ├── assets/               # Amigo-specific assets
│       └── test/                 # Amigo tests
├── packages/
│   ├── design_system/            # Shared theme, colors, typography, system UI
│   └── shared_widgets/           # Shared widgets, branding, and meetup flow
├── sites/gomigo-id-review/        # Separate Git repository for ID Review
│   ├── dist/                     # Browser app and Supabase client
│   └── test/                     # Reviewer API tests
├── supabase/
│   ├── config.toml
│   ├── migrations/               # Versioned schema, access policies, and database functions
│   ├── functions/                # Payment Edge Functions and shared tests
│   ├── tests/                    # Database regression tests
│   └── seed.sql                   # Local seed data
├── AGENTS.md
└── README.md                     # Setup and demo walkthroughs
```

Organize each app's `lib/features/` around user workflows such as onboarding, authentication, verification, discovery, booking, chat, map, session, profile, and payments or earnings. Add folders only when their code is needed. Keep navigation decisions in `lib/navigation/` and keep app-specific screens and assets in their respective app.

A growing feature may use this shape:

```text
lib/features/booking/
├── booking_screen.dart           # Screen composition and user actions
├── widgets/                      # Parts specific to this feature
├── state/                        # Feature state or controller
└── data/                         # Booking repository and data mapping
```

Keep network and database access behind appropriately scoped services or repositories, and keep screen widgets focused on presentation and user input. Share a component or data contract only when both apps actually use it. Avoid duplicating shared branding, and avoid adding abstractions or dependencies for hypothetical future needs.

Keep schema changes and access policies in `supabase/migrations/`, Edge Functions in `supabase/functions/`, and database tests in `supabase/tests/`. Preserve migration history when making changes. Keep credentials and local configuration out of source control.

Check the ID Review repository's own Git status and deployment configuration before editing or publishing it. Serve the browser app from `sites/gomigo-id-review/dist` and configure it with the same Supabase project as the apps.

## App workflows

Keep navigation predictable and preserve back behavior and session restoration. The app entry points check the signed-in account's role and verification state. Preserve those guards and the backend authorization for booking-specific actions. Handle loading, denied access, and failed requests.

### Traveler

1. Onboarding covers optional location access, account signup or login, front and back ID submission, review status, and a walkthrough.
2. **Find a Migo** uses device location to show verified Amigos whose public service area is within 20 km, closest first. **Browse all areas** supports browsing without location. Discovery includes search, filters, favorites, and Amigo profiles with reviews.
3. Travelers request a date, start and end time, meeting point, and optional activity notes. Supabase calculates the quote. Booking history displays pending, accepted, declined, cancelled, and completed bookings, including decline reasons when supplied. Accepted bookings can open Xendit test checkout.
4. Booking details link to chat, the shared meetup map, session controls with a countdown, and post-trip ratings and reviews. Travelers can edit their display name, open settings and help, or sign out from Profile. The payment methods screen explains test checkout.

### Amigo

1. Onboarding covers optional location access, account signup or login, front and back ID submission, and review status. Approved Amigos can publish a discovery profile with a photo, description, languages, interests, age, gender, hourly rate, and an approximate public service area.
2. The dashboard shows availability and incoming requests. An Amigo can review the Traveler, time, meeting point, notes, and quote, then accept or decline with a reason. Both apps use the same booking records and history.
3. Amigo booking details use the same chat, meetup, session, and trip review data as Traveler. Profile includes received ratings and reviews, settings, help, and logout.
4. Earnings come from completed sandbox bookings. Payout methods, balances, and withdrawals are simulated.

### Admin verification

Both apps upload the front and back images to the private `verification-ids` bucket and display the applicant's review status. The reviewer site fetches those images through authenticated Storage requests and saves decisions through `review_verification`. Supabase records the reviewer and decision time. Rejections require a reason.

The site requires a confirmed reviewer account with the `reviewer` profile role and a grant in `private.verification_reviewers`. Follow the provisioning instructions in [README.md](README.md). Test using fictional or authorized submissions.

## Data, security, and integrations

- Use the same booking and session records for both apps. Validate the actor, state transitions, times, and availability on the trusted backend. Prevent overlapping accepted bookings and account for concurrent requests and retries.
- Current demo quotes prorate the configured hourly rate by the minute, with a zero service fee and durations from one minute to eight hours. Either participant can start a paid, accepted session from 15 minutes before the scheduled start until the scheduled end, or complete an active session. Paid bookings require a refund decision before cancellation can be offered.
- Compute and store authoritative prices and fees on the backend. Handle payment-provider callbacks safely and idempotently. Never mark a booking as paid based solely on a client redirect or a client-provided amount. Use test mode for demos.
- Keep Xendit secrets in Supabase Edge Functions. Preserve reconciliation for existing Maya and PayMongo attempts when changing checkout. Traveler uses Xendit for new checkouts and can refresh existing Maya attempts.
- Keep ID images private and accessible only to authorized reviewers and any explicitly permitted owner access. Protect reviewer actions and record the reviewer and decision time. Do not expose private IDs in public URLs, logs, screenshots, or sample data.
- Apply database and storage access policies to accounts, bookings, messages, reviews, locations, and files. Limit chat and live location access to authorized booking participants. Never rely on hidden UI controls for authorization.
- Never put service-role keys, payment secret keys, or other server credentials in mobile or web clients, source control, logs, or screenshots. Use test and production credentials only in their intended environments.
- Live location sharing and route recording are separate opt-ins on the shared foreground meetup map. Show when each is active and let participants stop either at any time. Live markers expire after two minutes without an update. The map draws recorded GPS points on OpenStreetMap tiles. Keep attribution visible, follow tile usage rules, and handle permission errors, imprecise GPS, and interrupted connectivity.
- Use test payments and visibly simulated payouts in the demo. ID review is a manual decision on submitted images. Define production payment, identity review, and retention workflows before enabling them.
- Avoid inventing unresolved business rules. Confirm the intended rate, service fee, session duration, cancellation behavior, and the conditions for starting and ending a session before treating mockup examples as authoritative.

## Design and code quality

- Reuse the shared theme, widgets, and existing Figma assets where appropriate. Maintain consistent colors, typography, spacing, and interaction patterns across the two apps.
- Build accessible, responsive interfaces. Check phone-sized layouts, narrow screens, larger text, keyboard visibility, readable contrast, focus behavior, and labels for icon-only actions.
- Use clear, concise UI text. Include loading, empty, error, permission-denied, and success states for workflows that need them.
- Follow Dart naming and formatting conventions. Keep network calls and writes out of `build()`. Dispose of owned controllers and subscriptions, and check `mounted` after asynchronous work before updating a widget.
- Keep code readable and changes focused. Reuse existing logic and preserve behavior that callers depend on. Add feature-local files when they improve comprehension, and avoid unnecessary abstraction, formatting churn, and unrelated artifacts.
- Preserve app identifiers and platform configuration unless the task requires a change. Preserve existing user work and inspect the current Git status before editing.

## Verify before reporting completion

1. Check the requested outcome, affected entry points, roles, states, and deliverables against the implementation. Complete any remaining in-scope work before reporting success.
2. Run `dart format` on changed Dart files. From each affected Flutter app, run `flutter analyze` and `flutter test`. Run `flutter pub get` when dependencies need to be resolved. Check both apps when changing a shared package.
3. Exercise the changed flow through its normal entry point when feasible. For UI work, inspect the relevant screen at an appropriate viewport and exercise important interactions, including error or empty states when applicable.
4. For backend changes, start the local Supabase stack and run `supabase test db` from the repository root. For payment or reviewer API changes, run the relevant tests with `node --test supabase/functions/_shared/*.test.mjs sites/gomigo-id-review/test/review-api.test.mjs`. Verify authorized and unauthorized paths, state transitions, retries, and integration boundaries with test data and test credentials.
5. For ID Review changes, check submission from both apps, authorized access to private images, and the resulting status in the applicant's app. For shared booking changes, use separate Traveler and Amigo accounts to verify request, response, test checkout, and session state from both apps.
6. Add targeted regression tests when requested or needed for a meaningful risk. Inspect the final changes for unintended files and disclose any failing or unavailable checks, unconfigured integrations, simulated behavior, and meaningful assumptions in the final response. Never report a feature as tested or completed without evidence.

For documentation-only changes, verify the content against the repository and task. Flutter builds and tests are not required when no executable code changed.
