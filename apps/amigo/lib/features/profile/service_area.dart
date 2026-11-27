import 'package:geocoding/geocoding.dart';
import 'package:gomigo_shared_widgets/device_location.dart';
import 'package:latlong2/latlong.dart';

typedef ServiceArea = ({String name, LatLng point});

Future<ServiceArea> detectServiceArea() async {
  await requireDeviceLocation();
  final position = await readDevicePosition();
  try {
    final places = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 12));
    final place = places.firstOrNull;
    final name =
        [
              place?.locality,
              place?.subAdministrativeArea,
              place?.administrativeArea,
            ]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (name.isNotEmpty) {
      // Publish an approximate area center for discovery, not the exact device location.
      return (
        name: name,
        point: LatLng(
          double.parse(position.latitude.toStringAsFixed(2)),
          double.parse(position.longitude.toStringAsFixed(2)),
        ),
      );
    }
  } catch (_) {
    // Some devices have no available native geocoder.
  }
  throw const DeviceLocationException(
    'Could not identify your service area. Try again on an Android or iOS device with location services enabled.',
  );
}
