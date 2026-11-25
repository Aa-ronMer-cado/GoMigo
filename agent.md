# GoMigo agent handoff

This file records the GoMigo monorepo migration in commit `3a830a8`. The original single-app prototype is available at `68f7fad`.

## Repository layout

| Location | Purpose |
| --- | --- |
| `apps/traveler` | GoMigo Traveler, with the original traveler flow and 34 screen assets |
| `apps/amigo` | GoMigo Amigo, with its own entry point and branded home screen |
| `packages/design_system` | Shared Flutter theme and system bar styling |
| `packages/shared_widgets` | Shared `GoMigoBrand` widget and the two original brand SVGs |
| `.vscode/launch.json` | Separate launch configurations for Traveler and Amigo |

Each app has its own `lib/main.dart`, `pubspec.yaml`, lockfile, analyzer configuration, Flutter metadata, and widget tests. Both apps contain Android, iOS, web, Linux, macOS, and Windows platform projects. Traveler inherited the original platform files. Amigo's platform projects were created with `flutter create`.

## UI folder structure

Organize UI by app, then by feature.

```text
GoMigo/
├── apps/
│   ├── traveler/
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── navigation/
│   │   │   │   └── traveler_app.dart
│   │   │   └── features/
│   │   │       ├── onboarding/
│   │   │       │   ├── start_screen.dart
│   │   │       │   ├── location_screen.dart
│   │   │       │   └── walkthrough_screen.dart
│   │   │       ├── authentication/
│   │   │       │   └── login_screen.dart
│   │   │       ├── home/
│   │   │       │   └── dashboard_screen.dart
│   │   │       └── discovery/
│   │   │           └── finding_migo_screen.dart
│   │   └── assets/figma/
│   └── amigo/
│       └── lib/
│           ├── main.dart
│           ├── navigation/
│           │   └── amigo_app.dart
│           └── features/
│               └── home/
│                   └── amigo_home_screen.dart
└── packages/
    ├── design_system/       # Shared theme and system bar styling
    └── shared_widgets/      # Widgets and artwork used by both apps
```

### Structure inside a feature

Start with the screen file. As the feature grows, split it by responsibility. This example shows how Traveler discovery could be organized after extracting its widgets and adding data-backed filtering.

```text
apps/traveler/
├── lib/features/discovery/
│   ├── finding_migo_screen.dart
│   ├── widgets/
│   │   ├── migo_card.dart
│   │   └── discovery_filters.dart
│   ├── state/
│   │   └── discovery_controller.dart
│   └── data/
│       └── companion_repository.dart
└── test/features/discovery/
    └── finding_migo_screen_test.dart
```

The screen assembles the UI and passes callbacks to its widgets. Add `widgets/` when extracting a UI section, `state/` when there is state or async behavior to move out of the screen, and `data/` when the feature needs to load or save data. Keep feature tests in the app's `test/` directory. Use the same layout for Amigo features.

Use `packages/shared_widgets/` for widgets used by both apps and `packages/design_system/` for shared styling. Keep screen transitions in the app's `navigation/` folder and screen-specific images in the app's assets.

## Flutter coding conventions

- **Name files and types consistently.** Use `snake_case.dart` for files, `UpperCamelCase` for classes, and `lowerCamelCase` for variables and methods. Format Dart files with `dart format` and follow the app's analyzer settings. [Effective Dart style](https://dart.dev/effective-dart/style)
- **Build small, declarative widgets.** Use `StatelessWidget` when a widget has no mutable local state, and use `StatefulWidget` with `setState` for simple, temporary UI state. Put state as close as practical to the widgets that use it. Use `const` constructors and instances where possible, and keep network calls, writes, and expensive work out of `build()`. [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices)
- **Separate UI, state, and data access.** Pass typed data and callbacks into widgets, and keep one source of truth for each piece of state. Move complex feature state or async workflows into a feature-local controller or view model when needed. Put Firebase and API access behind services or repositories when those integrations are implemented. [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
- **Manage widget lifecycles.** Dispose of controllers and cancel subscriptions that the widget owns. After an `await`, check `context.mounted` before using a `BuildContext`, or check `mounted` before calling `setState` on a `State` object. [State disposal](https://api.flutter.dev/flutter/widgets/State/dispose.html) · [BuildContext.mounted](https://api.flutter.dev/flutter/widgets/BuildContext/mounted.html)
- **Check the UI on a phone-sized viewport.** Use the widget's available space for layout. Check narrow screens, large text, and screens with the keyboard open. Give icon-only actions accessible labels. For async features, handle loading, empty, error, and success states.

### Limits per feature

Give each feature one cohesive user workflow and ownership of its screens, local widgets, and feature-specific state. For example, Traveler discovery owns browsing and filtering companions. Authentication owns sign-up. Use the app's navigation to connect those flows. Keep code used by both apps in the shared packages so Traveler and Amigo can continue to build independently.

Use these GoMigo review thresholds for new or substantially changed Dart code. Count handwritten Dart lines after formatting. For the feature total, sum the files under that feature folder in `lib/features/`, excluding tests and generated code.

| Unit | Review threshold | What to check |
| --- | ---: | --- |
| Screen file | About 250 lines | Extract a distinct UI section, such as a filter panel, into a feature-local widget. |
| Feature widget file | About 150 lines | Split the widget when it owns distinct UI sections or manages state that belongs to the screen. |
| Feature implementation | About 750 lines | Give independently usable workflows their own feature folders. For one cohesive workflow, separate screen composition, state, and data access by responsibility. |

Use the numbers as review points. Keep cohesive code together, and extract components where the split makes the feature easier to read or test.

Run `dart format` on the changed Dart files. From the affected app directory, run `flutter analyze` and `flutter test`, then verify the affected flow through its normal entry point. If a shared UI package changes, check both Traveler and Amigo.

## Traveler migration

Traveler's entry point initializes Flutter and applies shared system bar styling. `apps/traveler/lib/navigation/traveler_app.dart` holds `GoMigoApp` and the original state-driven flow. The screen order and in-app back action were preserved.

| Original screen | Location under `apps/traveler/lib/features` |
| --- | --- |
| Start | `onboarding/start_screen.dart` |
| Location prompt | `onboarding/location_screen.dart` |
| Sign-up UI | `authentication/login_screen.dart` |
| Walkthrough | `onboarding/walkthrough_screen.dart` |
| Dashboard | `home/dashboard_screen.dart` |
| Find a Migo | `discovery/finding_migo_screen.dart` |

The Start screen now uses the shared `GoMigoBrand` widget. The original `start_frame1.svg` and `start_frame2.svg` moved to `packages/shared_widgets/assets/figma`. The other 34 original Figma assets moved to `apps/traveler/assets/figma`. All 36 asset contents matched the original Git versions during verification.

## Amigo and shared code

Amigo starts at `apps/amigo/lib/main.dart`. Its app widget lives in `lib/navigation/amigo_app.dart`, and its home screen lives in `lib/features/home/amigo_home_screen.dart`. The original prototype contained only Traveler workflows.

Both apps depend on the shared packages through local paths in their pubspecs. `gomigo_design_system` exports `goMigoTheme()` and `goMigoSystemUiOverlayStyle`. `gomigo_shared_widgets` renders the shared SVG artwork with `flutter_svg`. Traveler retains its own direct `flutter_svg` dependency for screen assets. Each app declares `flutter_test`, and Amigo uses `flutter_lints`.

## Platform configuration and Git

| App | Android application ID and namespace | iOS bundle ID |
| --- | --- | --- |
| GoMigo Traveler | `com.gomigo.traveler` | `com.gomigo.traveler` |
| GoMigo Amigo | `com.gomigo.amigo` | `com.gomigo.amigo` |

Android IDs are set in each app's `android/app/build.gradle.kts`, with matching Kotlin package paths. iOS IDs are set in each app's `ios/Runner.xcodeproj/project.pbxproj` for Debug, Profile, and Release. Android launcher labels, iOS display names, and web titles and manifests use the app-specific names.

The root Flutter manifests and platform directories moved under the apps. Seven tracked desktop plugin registrant files were removed from source control and are regenerated by Flutter. Root `.gitignore` now covers nested build outputs, generated files, local SDK settings, package lockfiles under `packages`, and common credential files. The app lockfiles and shared VS Code launch configurations are tracked. `.vscode/settings.json` holds machine-specific settings and is ignored.

## Run and build

Open the repository root in VS Code with the Flutter extension installed. Select a device from the status bar, choose **GoMigo Traveler** or **GoMigo Amigo** in **Run and Debug**, and press **F5**.

For Android 11 or later, the phone and computer can connect over the same Wi-Fi network. On the phone, open **Developer options → Wireless debugging → Pair device with pairing code**. Run `adb pair IP:PAIRING_PORT` from the VS Code terminal and enter the code shown on the phone. In PowerShell, you can invoke ADB by its full path with `&` if `adb` is unavailable on PATH. ADB lives in the Android SDK's `platform-tools` directory. [Android wireless debugging](https://developer.android.com/tools/adb?hl=en)

If Flutter cannot see the phone after pairing, use `adb connect IP:DEBUGGING_PORT` with the address on the main Wireless debugging screen, then run `flutter devices`. The second field in the phone's row is the ID used by `flutter run -d DEVICE_ID`.

Run Flutter commands from the selected app directory, `apps/traveler` or `apps/amigo`.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Use `flutter run -d chrome` to run in Chrome. A debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk` inside the selected app directory. iPhone development builds require macOS, Xcode, and signing.

## Migration verification

| Check | Traveler | Amigo |
| --- | --- | --- |
| Dependency resolution and static analysis | Passed | Passed |
| Widget test | Start through onboarding, discovery filter, and return to dashboard | App launch and shared brand |
| Web release build and Chrome smoke test | Passed through discovery | Passed at home screen |
| Android debug build, installation, and emulator launch | Passed | Passed |

Dart formatting and standalone analysis of both shared packages also passed. The Android APK manifests were checked for the app IDs. iOS bundle IDs were checked in the Xcode project files. iOS and desktop builds remain unverified. These are the migration results recorded with Flutter `3.47.1`, before this handoff file was added.

## Firebase and feature scope

Firebase remains unconfigured. The original repository contained no Firebase SDK, project configuration, data model, or rules. The Traveler sign-up, location prompt, and discovery screens are prototype UI.

Firebase integration requires the existing project ID, data model, and security rules. Register each app for its platforms in that same project, configure FlutterFire separately in each app, and connect authentication, bookings, and messaging against the existing backend. The setup notes are in [README.md](README.md).
