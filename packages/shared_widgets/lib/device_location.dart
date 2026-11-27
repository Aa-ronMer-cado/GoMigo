import 'package:geolocator/geolocator.dart';

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);
  final String message;
}

Future<void> requireDeviceLocation() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.unableToDetermine) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const DeviceLocationException(
        'Enable GoMigo location access in your device settings.');
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw const DeviceLocationException(
        'Location permission was denied. You can try again.');
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const DeviceLocationException(
        'Turn on device location services and try again.');
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
  } catch (_) {
    throw const DeviceLocationException(
        'Could not get your current location. Move into an open area and try again.');
  }
}
