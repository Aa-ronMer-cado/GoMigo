import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traveler/features/discovery/discovery_repository.dart';
import 'package:traveler/features/discovery/finding_migo_screen.dart';
import 'package:traveler/features/discovery/nearby_amigos.dart';

const _locationChannel = MethodChannel('flutter.baseflow.com/geolocator');

Map<String, dynamic> _profile(String name, {double? latitude}) => {
  'id': name,
  'display_name': name,
  'area': 'Test area',
  'languages': ['English'],
  'interests': ['Walking'],
  'gender': 'woman',
  'age': 26,
  'rate_centavos': 30000,
  'discovery_latitude': latitude,
  'discovery_longitude': latitude == null ? null : 0,
};

class _TestRepository extends DiscoveryRepository {
  _TestRepository()
    : super(
        SupabaseClient(
          'https://gomigo.example',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<List<Map<String, dynamic>>> amigos() async => [
    {..._profile('Nearby Amigo', latitude: 0.01), 'age': null},
    _profile('Distant Amigo', latitude: 0.5),
  ];

  @override
  Future<Set<String>> favorites() async => {};

  @override
  Future<List<Map<String, dynamic>>> reviews([String? amigo]) async => [];
}

void main() {
  test('includes only profiles within 20 km and orders the closest first', () {
    double latitudeAt(double meters) => meters * 180 / (earthRadius * math.pi);
    final profiles = [
      _profile('just inside', latitude: latitudeAt(19999.9)),
      _profile('no location'),
      _profile('just outside', latitude: latitudeAt(20000.1)),
      _profile('within 15 km', latitude: latitudeAt(14999.9)),
      _profile('closest', latitude: 0.01),
    ];
    final nearby = discoveryResults(profiles, origin: const LatLng(0, 0));
    expect(nearby.map((result) => result.profile['id']), [
      'closest',
      'within 15 km',
      'just inside',
    ]);
    expect(discoveryResults(profiles, origin: null), isEmpty);
  });

  test('even a known fictional profile requires stored coordinates', () {
    const id = 'ca980000-31d7-4d85-9cc7-e25de13a3003';
    const origin = LatLng(14.6042, 120.9822);
    expect(
      discoveryResults([
        {'id': id, 'is_test': true},
      ], origin: origin),
      isEmpty,
    );
    expect(
      discoveryResults([
        {'id': id, 'is_test': false},
      ], origin: origin),
      isEmpty,
    );
    expect(
      discoveryResults([
        {
          'id': id,
          'is_test': true,
          'discovery_latitude': null,
          'discovery_longitude': null,
        },
      ], origin: origin),
      isEmpty,
    );
  });

  group('Find a Migo screen', () {
    late _TestRepository repository;
    setUp(() => repository = _TestRepository());
    tearDown(() => repository.client.dispose());

    testWidgets('handles nearby profiles without ages', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        _locationChannel,
        (call) async => switch (call.method) {
          'isLocationServiceEnabled' => true,
          'checkPermission' => LocationPermission.whileInUse.index,
          'getCurrentPosition' => {'latitude': 0.0, 'longitude': 0.0},
          _ => throw UnsupportedError(call.method),
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(_locationChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FindingMigoScreen(
            repository: repository,
            request: (_, _) {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Within 20 km'), findsOneWidget);
      expect(find.text('Nearby Amigo'), findsOneWidget);
      expect(find.text('About 1.1 km away'), findsOneWidget);
      expect(find.text('Distant Amigo'), findsNothing);

      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Browse all areas'), findsNothing);
      expect(find.text('Favorites'), findsNothing);
      expect(find.byType(RangeSlider), findsNothing);
    });

    testWidgets('location denial offers Settings and withholds results', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger = tester.binding.defaultBinaryMessenger;
      var permissionRequests = 0;
      messenger.setMockMethodCallHandler(_locationChannel, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return LocationPermission.denied.index;
          case 'requestPermission':
            permissionRequests++;
            return LocationPermission.deniedForever.index;
          default:
            throw UnsupportedError(call.method);
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(_locationChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FindingMigoScreen(
            repository: repository,
            request: (_, _) {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(permissionRequests, 0);
      expect(find.text('Nearby Amigo'), findsNothing);
      await tester.tap(find.text('Check location'));
      await tester.pumpAndSettle();
      expect(permissionRequests, 1);
      expect(
        find.textContaining('Allow it in your app settings'),
        findsOneWidget,
      );
      expect(find.text('Open app settings'), findsOneWidget);
      expect(find.text('Nearby Amigo'), findsNothing);
    });
  });
}
