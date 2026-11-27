import 'package:supabase_flutter/supabase_flutter.dart';

class AmigoChatRepository {
  AmigoChatRepository(this.client, this.bookingId, this.amigoId);
  final SupabaseClient client;
  final String bookingId;

  final String amigoId;

  Stream<List<Map<String, dynamic>>> booking() =>
      client.from('bookings').stream(primaryKey: ['id']).eq('id', bookingId);

  Stream<List<Map<String, dynamic>>> messages() => client
      .from('booking_messages')
      .stream(primaryKey: ['id'])
      .eq('booking_id', bookingId)
      .order('created_at', ascending: false);

  Future<void> send(String id, String body) async {
    await client
        .from('booking_messages')
        .upsert(
          {
            'id': id,
            'booking_id': bookingId,
            'sender_id': amigoId,
            'body': body,
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }
}
