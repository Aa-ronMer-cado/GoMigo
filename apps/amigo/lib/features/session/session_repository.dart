import 'package:supabase_flutter/supabase_flutter.dart';

class AmigoSessionRepository {
  AmigoSessionRepository(this.client, this.bookingId);
  final SupabaseClient client;
  final String bookingId;

  Future<void> start() async {
    await client.rpc(
      'start_booking_session',
      params: {'p_booking_id': bookingId},
    );
  }

  Future<void> complete() async {
    await client.rpc(
      'complete_booking_session',
      params: {'p_booking_id': bookingId},
    );
  }

  Future<Map<String, dynamic>?> review() => client
      .from('reviews')
      .select('rating,body')
      .eq('booking_id', bookingId)
      .eq('author_role', 'amigo')
      .maybeSingle();

  Future<void> rateTraveler(int rating, String body) async {
    await client.rpc(
      'review_traveler',
      params: {
        'p_booking_id': bookingId,
        'p_rating': rating,
        'p_body': body.isEmpty ? null : body,
      },
    );
  }
}
