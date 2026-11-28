import 'package:geolocator/geolocator.dart';

enum DeviceLocationSettings {
  app('Open app settings'),
  locationServices('Open location settings');

  const DeviceLocationSettings(this.label);
  final String label;
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message, {this.settings});
  final String message;
  final DeviceLocationSettings? settings;
}

const _serviceDisabled = DeviceLocationException(
  'Turn on device location services and try again.',
  settings: DeviceLocationSettings.locationServices,
);

Future<void> requireDeviceLocation({bool requestPermission = true}) async {
  if (!await Geolocator.isLocationServiceEnabled()) throw _serviceDisabled;
  var permission = await Geolocator.checkPermission();
  if (requestPermission &&
      (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine)) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const DeviceLocationException(
      'GoMigo needs location access. Allow it in your app settings.',
      settings: DeviceLocationSettings.app,
    );
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw const DeviceLocationException(
      'Location access is required. Allow it to continue.',
    );
  }
}

Future<bool> openDeviceLocationSettings(DeviceLocationSettings settings) async {
  try {
    return await switch (settings) {
      DeviceLocationSettings.app => Geolocator.openAppSettings(),
      DeviceLocationSettings.locationServices =>
        Geolocator.openLocationSettings(),
    };
  } catch (_) {
    return false;
  }
}

Future<Position>? _positionRequest;

Future<Position> readDevicePosition() =>
    _positionRequest ??= _readPosition().whenComplete(() {
      _positionRequest = null;
    });

Future<Position> _readPosition() async {
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  } on LocationServiceDisabledException {
    throw _serviceDisabled;
  } catch (_) {
    throw const DeviceLocationException(
      'Could not get your current location. Move into an open area and try again.',
    );
  }
}
