import 'dart:convert';

import 'package:amigo/features/authentication/login_screen.dart';
import 'package:amigo/features/profile/edit_profile_screen.dart';
import 'package:amigo/navigation/amigo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_shared_widgets/gomigo_shared_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('starts with the shared brand and reaches sign-up on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const location = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = tester.binding.defaultBinaryMessenger;
    final locationCalls = <String>[];
    messenger.setMockMethodCallHandler(location, (call) async {
      locationCalls.add(call.method);
      return switch (call.method) {
        'checkPermission' => 2,
        'isLocationServiceEnabled' => true,
        'getCurrentPosition' => {'latitude': 13.75, 'longitude': 121.05},
        _ => throw StateError('Unexpected location action: ${call.method}'),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(location, null));

    await tester.pumpWidget(const GoMigoAmigoApp());
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'GoMigo Amigo',
    );
    expect(find.byType(GoMigoBrand), findsOneWidget);
    await tester.tap(find.byType(GoMigoBrand));
    await tester.pumpAndSettle();
    expect(find.byType(AmigoLoginScreen), findsOneWidget);
    expect(locationCalls, contains('getCurrentPosition'));
    expect(locationCalls, isNot(contains('requestPermission')));
    expect(find.text('Email Address'), findsOneWidget);
    final signUp = find.text('Don’t have an account? Sign Up');
    await tester.ensureVisible(signUp);
    await tester.tap(signUp);
    await tester.pumpAndSettle();
    expect(find.text('Full Name'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GoMigoBrand), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a staged profile still requires setup after approval', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const approval = {
      'id': 'test-submission',
      'status': 'approved',
      'reviewed_display_name': 'Reviewed Amigo',
      'reviewed_gender': 'woman',
    };
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://gomigo.example',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final Object body = switch (request.url.pathSegments.last) {
            'profiles' => {
              'role': 'amigo',
              'display_name': 'Registration Name',
            },
            'verification_submissions' => [approval],
            'my_amigo_id' => 'staged-amigo',
            'amigo_profiles' => {
              'id': 'staged-amigo',
              'display_name': 'Registration Name',
              'onboarding_completed_at': null,
            },
            _ => throw StateError('Unexpected request: ${request.url.path}'),
          };
          return http.Response(
            jsonEncode(body),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    ))!;
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': 'test-amigo',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        }),
      ),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJub25lIn0.$payload.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {'id': 'test-amigo'},
      }),
    );
    await tester.pumpWidget(GoMigoAmigoApp(client: client));
    await tester.pumpAndSettle();

    Future<void> continueToProfile() async {
      final done = find.widgetWithText(FilledButton, 'Done');
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byType(AmigoEditProfileScreen), findsOneWidget);
      expect(find.text('Reviewed Amigo'), findsOneWidget);
      expect(find.text('Woman'), findsOneWidget);
    }

    await continueToProfile();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AmigoEditProfileScreen), findsNothing);
    await continueToProfile();

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });
}
