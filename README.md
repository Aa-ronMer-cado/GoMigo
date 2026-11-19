# GoMigo

GoMigo is a mobile application designed to help local and international travelers explore the Philippines by connecting them with local companions who can accompany them while they visit unfamiliar places.

| App | Flutter directory | Android application ID and iOS bundle ID |
| --- | --- | --- |
| GoMigo Traveler | `apps/traveler` | `com.gomigo.traveler` |
| GoMigo Amigo | `apps/amigo` | `com.gomigo.amigo` |

Traveler contains the original onboarding, sign-up UI, home screen, and companion discovery flow. Amigo starts at its own branded home screen. Both apps use local path dependencies for the theme in `packages/design_system` and the branding widget and artwork in `packages/shared_widgets`.

Run these commands from either app directory.

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Use `flutter run -d chrome` for web, `flutter build web` for the web bundle, or `flutter build apk` for Android. iOS builds require macOS and Xcode. VS Code has a launch configuration for each app.

## Firebase

The original prototype has no Firebase SDK, app registrations, rules, or data model in this repository. To connect the apps, register both mobile IDs in the same existing Firebase project and run `flutterfire configure --project=<existing-project-id>` from each app directory. Add the FlutterFire plugins for the services in use and initialize each app with its own generated configuration. Connect authentication, bookings, and messaging to the existing data model and enforce role permissions in the backend rules. Keep the project's Firestore rules, indexes, and Storage rules under `backend/firebase/` when they are brought into the repository. [Firebase setup for Flutter](https://firebase.google.com/docs/flutter/setup)
