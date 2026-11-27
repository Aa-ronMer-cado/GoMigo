import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_shared_widgets/device_location.dart';
import 'package:gomigo_shared_widgets/meetup.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets(
    'map retries a denied location and centers on the device marker',
    (tester) async {
      final controller = MapController();
      const device = LatLng(10.32, 123.89);
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeetupMap(
              center: const LatLng(10.27, 123.94),
              markers: const [],
              controller: controller,
              locateDevice: (requestPermission) async {
                expect(requestPermission, isTrue);
                if (attempts++ == 0) {
                  throw const DeviceLocationException(
                    'Location permission was denied.',
                  );
                }
                return device;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Location permission was denied.'), findsOneWidget);
      await tester.tap(find.byTooltip('Recenter on your current location'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Your current location on this device'),
        findsOneWidget,
      );
      expect(controller.camera.center, device);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
