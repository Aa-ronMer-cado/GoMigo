import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../discovery/amigo_photo.dart';
import '../discovery/discovery_repository.dart';

typedef BookingRow = Map<String, dynamic>;

class BookingRepository {
  BookingRepository(this.client);
  final SupabaseClient client;

  String get userId => client.auth.currentUser!.id;

  Stream<List<BookingRow>> history() => client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('traveler_id', userId)
      .order('created_at', ascending: false);

  Stream<List<BookingRow>> watch(String id) =>
      client.from('bookings').stream(primaryKey: ['id']).eq('id', id);

  Stream<List<BookingRow>> session(String id) => client
      .from('booking_sessions')
      .stream(primaryKey: ['booking_id'])
      .eq('booking_id', id);

  Future<BookingRow?> review(String id) async {
    final rows = await client.from('reviews').select().eq('booking_id', id);
    return rows.where((row) => row['author_role'] != 'amigo').firstOrNull;
  }

  Future<List<BookingRow>> amigos() async {
    final rows = await client.from('amigo_profiles').select();
    return rows.map((row) => resolveAmigoPhoto(client, row)).toList();
  }

  Future<Map<String, double>> amigoRatings() async {
    try {
      final rows = await DiscoveryRepository(client).reviews();
      final ratings = <String, List<num>>{};
      for (final row in rows) {
        if (row['amigo_id'] case final String id) {
          if (row['rating'] case final num value) {
            (ratings[id] ??= []).add(value);
          }
        }
      }
      return {
        for (final entry in ratings.entries)
          entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
      };
    } catch (_) {
      return {};
    }
  }

  Future<bool> verified() async {
    final row = await client
        .from('verification_submissions')
        .select('id')
        .eq('traveler_id', userId)
        .eq('status', 'approved')
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  Map<String, dynamic> _times(String amigo, DateTime start, DateTime end) => {
    'p_amigo_id': amigo,
    'p_starts_at': start.toUtc().toIso8601String(),
    'p_ends_at': end.toUtc().toIso8601String(),
  };

  Future<BookingRow> quote(String amigo, DateTime start, DateTime end) => client
      .rpc<BookingRow>('quote_booking', params: _times(amigo, start, end));

  Future<BookingRow> create({
    required String amigo,
    required DateTime start,
    required DateTime end,
    required String label,
    required LatLng pin,
    required String notes,
    required String requestId,
  }) => client.rpc<BookingRow>(
    'create_booking',
    params: {
      ..._times(amigo, start, end),
      'p_meeting_label': label,
      'p_meeting_lat': pin.latitude,
      'p_meeting_lng': pin.longitude,
      'p_notes': notes.isEmpty ? null : notes,
      'p_request_id': requestId,
    },
  );

  Future<void> action(
    String name,
    String id, [
    Map<String, dynamic> extra = const {},
  ]) async {
    await client.rpc(name, params: {'p_booking_id': id, ...extra});
  }

  Future<bool> demoEnabled() => client.rpc<bool>('is_booking_demo_enabled');

  Future<void> reviewTrip(
    String id,
    String amigo,
    int rating,
    String text,
  ) async {
    await client.from('reviews').insert({
      'booking_id': id,
      'amigo_id': amigo,
      'rating': rating,
      'body': text.isEmpty ? null : text,
    });
  }
}

DateTime philippineWallTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));
DateTime philippineBookingTime(DateTime date, int hour, int minute) =>
    DateTime.utc(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).subtract(const Duration(hours: 8));
