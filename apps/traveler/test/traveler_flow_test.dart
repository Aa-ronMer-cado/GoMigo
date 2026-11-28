import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traveler/features/booking/booking_history_screen.dart';
import 'package:traveler/features/booking/booking_repository.dart';
import 'package:traveler/features/onboarding/start_screen.dart';
import 'package:traveler/features/onboarding/walkthrough_screen.dart';
import 'package:traveler/features/verification/verification_repository.dart';
import 'package:traveler/main.dart' as traveler;

class _HistoryClient extends Fake implements SupabaseClient {}

class _HistoryRepository extends BookingRepository {
  _HistoryRepository() : super(_HistoryClient());

  @override
  Stream<List<BookingRow>> history() => Stream.value([
    for (final status in ['accepted', 'declined', 'cancelled'])
      {
        'id': status,
        'amigo_id': 'amigo',
        'status': status,
        'starts_at': '2026-11-28T00:30:00Z',
        'ends_at': '2026-11-28T00:40:00Z',
        'meeting_label': '$status meeting point',
        'total_centavos': 8333,
      },
  ]);

  @override
  Future<List<BookingRow>> amigos() async => [
    {'id': 'amigo', 'display_name': 'Amigo With A Long Display Name'},
  ];

  @override
  Future<bool> demoEnabled() async => false;

  @override
  Future<Map<String, double>> amigoRatings() async => {'amigo': 4.5};
}

void main() {
  testWidgets('normal entry requires access and validates account fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = tester.binding.defaultBinaryMessenger;
    var servicesEnabled = false;
    var openedSettings = false;
    messenger.setMockMethodCallHandler(locationChannel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return servicesEnabled;
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'openLocationSettings':
          openedSettings = true;
          servicesEnabled = true;
          return true;
        default:
          throw UnsupportedError(call.method);
      }
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(locationChannel, null),
    );

    await traveler.main();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'GoMigo Traveler',
    );
    await tester.tap(find.byType(StartScreen));
    await tester.pumpAndSettle();

    expect(find.text('Continue without location'), findsNothing);
    expect(find.text('Email Address'), findsNothing);
    await tester.tap(find.text('Open location settings'));
    await tester.pumpAndSettle();
    expect(openedSettings, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Email Address'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.tap(find.text('Don’t have an account? Sign Up'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    for (final (index, value) in [
      'Demo Traveler',
      'traveler@example.invalid',
      '',
      'demo-testing',
      'different',
    ].indexed) {
      await tester.ensureVisible(fields.at(index));
      await tester.enterText(fields.at(index), value);
    }
    final submit = find.widgetWithText(FilledButton, 'Sign Up');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Passwords must match.'), findsOneWidget);
    await tester.enterText(fields.last, 'demo-testing');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'GoMigo is not configured on this build. Contact the demo organizer.',
      ),
      findsOneWidget,
    );
    expect(find.text('Find a Migo'), findsNothing);
  });

  testWidgets('walkthrough fits a narrow phone with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalkthroughScreen(onContinue: () => completed = true),
        ),
      ),
    );
    for (final (title, label) in [
      ('Find a Local Buddy', 'Next'),
      ('Book and Explore', 'Next'),
      ('Travel with Confidence', 'Get Started'),
    ]) {
      expect(find.text(title), findsOneWidget);
      final button = find.widgetWithText(OutlinedButton, label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(completed, true);
  });

  testWidgets(
    'booking history shows actual statuses and totals on a narrow phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _HistoryRepository();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: BookingHistoryScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('accepted meeting point'), findsOneWidget);
      expect(find.text('₱83.33'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Declined'));
      await tester.pumpAndSettle();
      expect(find.text('declined meeting point'), findsOneWidget);
      expect(find.text('accepted meeting point'), findsNothing);
      await tester.tap(find.byTooltip('More booking statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('cancelled meeting point'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('booking date and time always use Philippine wall time', () {
    final utc = philippineBookingTime(DateTime(2026, 11, 28), 1, 15);
    expect(utc, DateTime.utc(2026, 11, 27, 17, 15));
    expect(philippineWallTime(utc), DateTime.utc(2026, 11, 28, 1, 15));
  });

  test('verification accepts JPEG and PNG signatures only', () {
    expect(
      verificationImageType(
        Uint8List.fromList([255, 216, 255, 224, 0, 0, 0, 0]),
      ),
      'image/jpeg',
    );
    expect(
      verificationImageType(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      'image/png',
    );
    expect(
      verificationImageType(Uint8List.fromList([137, 80, 78, 71])),
      isNull,
    );
    expect(
      verificationImageType(
        Uint8List.fromList([37, 80, 68, 70, 13, 10, 26, 10]),
      ),
      isNull,
    );
  });
}
