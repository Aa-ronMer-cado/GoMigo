import 'dart:async';
import 'dart:typed_data';

import 'package:amigo/features/profile/edit_profile_screen.dart';
import 'package:amigo/features/profile/profile_repository.dart';
import 'package:amigo/features/verification/verification_repository.dart';
import 'package:amigo/features/verification/verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_shared_widgets/device_location.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('profile creation validates and saves on a narrow phone', (
    tester,
  ) async {
    final repository = _ProfileRepository(_UnusedClient());
    var saved = false;
    var locationAttempts = 0;
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: AmigoEditProfileScreen(
          repository: repository,
          profile: null,
          name: 'Demo Amigo',
          gender: 'woman',
          detectArea: () async {
            if (locationAttempts++ == 0) {
              throw const DeviceLocationException(
                'Location permission was denied.',
              );
            }
            return (name: 'Cebu City', point: const LatLng(10.32, 123.89));
          },
          onSaved: () => saved = true,
        ),
      ),
    );

    final save = find.widgetWithText(FilledButton, 'Save profile');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.sent, isNull);
    expect(find.text('Write at least 30 words.'), findsOneWidget);
    expect(find.text('Demo Amigo'), findsOneWidget);
    expect(find.text('Woman'), findsOneWidget);
    expect(find.text('Languages'), findsNothing);

    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    final locate = find.text('Use Current Location');
    await tester.ensureVisible(locate);
    await tester.tap(locate);
    await tester.pumpAndSettle();
    expect(find.text('Location permission was denied.'), findsOneWidget);
    await tester.tap(locate);
    await tester.pumpAndSettle();
    expect(find.text('Cebu City'), findsOneWidget);
    for (final interest in ['Photography', 'Local Culture']) {
      final chip = find.widgetWithText(FilterChip, interest);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
    }
    await fill(
      'About you',
      'I enjoy helping visitors explore the city markets and local food with time to take photos near the waterfront and discover favorite places together at a comfortable pace for everyone.',
    );
    await fill('Hourly rate (₱)', '275.50');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(repository.sent, {
      'area': 'Cebu City',
      'interests': ['Photography', 'Local Culture'],
      'rate': 27550,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification shows saved decisions and approved continuation', (
    tester,
  ) async {
    final rows = StreamController<List<Map<String, dynamic>>>.broadcast();
    addTearDown(rows.close);
    final repository = _VerificationRepository(_UnusedClient(), rows.stream);
    var continued = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AmigoVerificationScreen(
          repository: repository,
          onApproved: () => continued = true,
        ),
      ),
    );
    rows.add([
      {'status': 'pending'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Verification in progress'), findsOneWidget);
    expect(find.text('Submit test ID'), findsNothing);

    rows.add([
      {'status': 'rejected', 'rejection_reason': 'Back photo is blurred.'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Back photo is blurred.'), findsOneWidget);
    expect(find.text('Front of ID'), findsOneWidget);
    expect(find.text('Back of ID'), findsOneWidget);

    rows.add([
      {
        'status': 'approved',
        'reviewed_display_name': 'Demo Amigo',
        'reviewed_gender': 'woman',
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Verification Complete'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Done');
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('verification accepts JPG and PNG signatures only', () {
    expect(
      AmigoVerificationRepository.imageType(
        Uint8List.fromList([255, 216, 255, 0, 0, 0, 0, 0]),
      ),
      'image/jpeg',
    );
    expect(
      AmigoVerificationRepository.imageType(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      'image/png',
    );
    expect(AmigoVerificationRepository.imageType(Uint8List(10)), isNull);
  });
}

class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileRepository extends AmigoProfileRepository {
  _ProfileRepository(super.client);
  Map<String, Object>? sent;

  @override
  Future<void> save({
    required String description,
    required String area,
    required List<String> interests,
    required int rateCentavos,
    required String? photoPath,
    required double latitude,
    required double longitude,
  }) async {
    sent = {'area': area, 'interests': interests, 'rate': rateCentavos};
  }
}

class _VerificationRepository extends AmigoVerificationRepository {
  _VerificationRepository(super.client, this.rows);
  final Stream<List<Map<String, dynamic>>> rows;

  @override
  Stream<List<Map<String, dynamic>>> submissions() => rows;
}
