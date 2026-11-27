import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const livePositionLifetime = Duration(minutes: 2);

bool isMeetupSharingWindow(Map<String, dynamic> booking, DateTime now) {
  if (booking['status'] != 'accepted') return false;
  final start = DateTime.parse(booking['starts_at'] as String);
  final end = DateTime.parse(booking['ends_at'] as String);
  return !now.isBefore(start.subtract(const Duration(hours: 2))) &&
      !now.isAfter(end.add(const Duration(hours: 1)));
}

LatLng? meetupCoordinates(
  Map<String, dynamic> row, {
  String latitude = 'latitude',
  String longitude = 'longitude',
}) {
  final lat = (row[latitude] as num?)?.toDouble();
  final lng = (row[longitude] as num?)?.toDouble();
  return lat == null || lng == null ? null : LatLng(lat, lng);
}

typedef MeetupSnapshot = ({
  Map<String, dynamic>? booking,
  Map<String, dynamic>? session,
  List<Map<String, dynamic>> locations,
});

class MeetupRepository {
  MeetupRepository(this.client, this.bookingId, {this.topic = 'traveler'});

  final SupabaseClient client;
  final String bookingId;
  final String topic;

  Future<MeetupSnapshot> load() async {
    final results = await Future.wait<Object?>([
      client.from('bookings').select().eq('id', bookingId).maybeSingle(),
      client
          .from('booking_sessions')
          .select('started_at,ended_at')
          .eq('booking_id', bookingId)
          .maybeSingle(),
      client
          .from('booking_locations')
          .select('participant_id,latitude,longitude,updated_at')
          .eq('booking_id', bookingId),
    ]);
    return (
      booking: results[0] as Map<String, dynamic>?,
      session: results[1] as Map<String, dynamic>?,
      locations: results[2] as List<Map<String, dynamic>>,
    );
  }

  Future<List<Map<String, dynamic>>> routePoints() async {
    const pageSize = 400;
    final points = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += pageSize) {
      final page = await client
          .from('booking_route_points')
          .select('id,participant_id,latitude,longitude,recorded_at')
          .eq('booking_id', bookingId)
          .order('recorded_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);
      points.addAll(page);
      if (page.length < pageSize) return points;
    }
  }

  RealtimeChannel watch({
    required void Function(String table, Map<String, dynamic> row) onChange,
    required void Function(RealtimeSubscribeStatus, Object?) onStatus,
  }) {
    final channel = client.channel('$topic:meetup:$bookingId');
    for (final table in [
      'bookings',
      'booking_sessions',
      'booking_locations',
      'booking_route_points',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: table == 'bookings' ? 'id' : 'booking_id',
          value: bookingId,
        ),
        callback: (payload) => onChange(table, payload.newRecord),
      );
    }
    return channel.subscribe(onStatus);
  }

  Future<void> setLocation(LatLng? point) async {
    await client.rpc<void>(
      'set_booking_location',
      params: {
        'p_booking_id': bookingId,
        'p_latitude': point?.latitude,
        'p_longitude': point?.longitude,
      },
    );
  }

  Future<void> setRecording(bool enabled) async {
    await client.rpc<void>(
      'set_route_recording',
      params: {'p_booking_id': bookingId, 'p_enabled': enabled},
    );
  }

  Future<void> appendPoint(LatLng point, String id) async {
    await client.rpc<void>(
      'append_route_point',
      params: {
        'p_booking_id': bookingId,
        'p_latitude': point.latitude,
        'p_longitude': point.longitude,
        'p_point_id': id,
      },
    );
  }
}
