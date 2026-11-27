import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traveler/features/booking/booking_repository.dart';
import 'package:traveler/features/onboarding/start_screen.dart';
import 'package:traveler/features/onboarding/walkthrough_screen.dart';
import 'package:traveler/features/verification/verification_repository.dart';
import 'package:traveler/main.dart' as traveler;

void main() {
  testWidgets(
    'normal entry supports location skip and validates account fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await traveler.main();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'GoMigo Traveler',
      );
      await tester.tap(find.byType(StartScreen));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue without location'));
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
    },
  );

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
