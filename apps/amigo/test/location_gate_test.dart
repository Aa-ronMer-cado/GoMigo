import 'package:amigo/features/onboarding/location_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

const _channel = MethodChannel('flutter.baseflow.com/geolocator');

Widget _screen(VoidCallback onContinue) => MaterialApp(
  home: Scaffold(body: AmigoLocationScreen(onContinue: onContinue)),
);

void main() {
  testWidgets('denied location blocks entry and app settings can unblock it', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var permission = LocationPermission.denied;
    var requests = 0;
    var positions = 0;
    var settingsOpened = 0;
    var advances = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return permission.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'requestPermission':
          requests++;
          return requests == 1
              ? LocationPermission.denied.index
              : LocationPermission.deniedForever.index;
        case 'openAppSettings':
          settingsOpened++;
          return true;
        case 'getCurrentPosition':
          positions++;
          return {'latitude': 13.75, 'longitude': 121.05};
        default:
          throw UnsupportedError(call.method);
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(_screen(() => advances++));
    await tester.pumpAndSettle();
    expect(find.text('Continue without location'), findsNothing);
    expect(
      find.text('Location access is required. Allow it to continue.'),
      findsOneWidget,
    );
    expect(requests, 0);
    expect(advances, 0);

    final allow = find.text('Allow location');
    await tester.tap(allow);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(advances, 0);
    await tester.tap(allow);
    await tester.pumpAndSettle();
    final settings = find.text('Open app settings');
    expect(settings, findsOneWidget);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(settings, findsOneWidget);
    expect(requests, 2);

    permission = LocationPermission.whileInUse;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(positions, 1);
    expect(advances, 1);
  });

  testWidgets('granted location fetches a fix once without requesting again', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var advances = 0;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'checkPermission' => LocationPermission.whileInUse.index,
        'isLocationServiceEnabled' => true,
        'getCurrentPosition' => {'latitude': 13.75, 'longitude': 121.05},
        _ => throw UnsupportedError(call.method),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(_screen(() => advances++));
    await tester.pumpAndSettle();
    expect(advances, 1);
    expect(calls, [
      'isLocationServiceEnabled',
      'checkPermission',
      'getCurrentPosition',
    ]);
  });

  testWidgets(
    'disabled GPS offers device settings even when permission exists',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'checkPermission' => LocationPermission.whileInUse.index,
          'isLocationServiceEnabled' => false,
          'openLocationSettings' => true,
          _ => throw UnsupportedError(call.method),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

      await tester.pumpWidget(
        _screen(() => fail('Disabled GPS entered the app')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open location settings'));
      await tester.pumpAndSettle();
      expect(calls, ['isLocationServiceEnabled', 'openLocationSettings']);
    },
  );
}
