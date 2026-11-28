import 'package:latlong2/latlong.dart';

const discoveryRadiusKm = 20;
const _distance = DistanceHaversine(roundResult: false);

typedef DiscoveryResult = ({Map<String, dynamic> profile, double meters});

List<DiscoveryResult> discoveryResults(
  Iterable<Map<String, dynamic>> profiles, {
  required LatLng? origin,
}) {
  if (origin == null) return [];

  final results = <DiscoveryResult>[];
  for (final profile in profiles) {
    final center = _discoveryCenter(profile);
    if (center == null) continue;
    final meters = _distance(origin, center);
    if (meters <= discoveryRadiusKm * 1000) {
      results.add((profile: profile, meters: meters));
    }
  }
  results.sort((a, b) => a.meters.compareTo(b.meters));
  return results;
}

LatLng? _discoveryCenter(Map<String, dynamic> profile) {
  final latitude = profile['discovery_latitude'];
  final longitude = profile['discovery_longitude'];
  if (latitude is num &&
      longitude is num &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180) {
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  return null;
}
