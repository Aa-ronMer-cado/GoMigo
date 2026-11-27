import '../booking/booking_repository.dart';

extension BookingChat on BookingRepository {
  Stream<List<BookingRow>> messages(String bookingId) => client
      .from('booking_messages')
      .stream(primaryKey: ['id'])
      .eq('booking_id', bookingId)
      .order('created_at', ascending: false);

  Future<void> sendMessage(
    String bookingId,
    String messageId,
    String body,
  ) async {
    await client
        .from('booking_messages')
        .upsert(
          {'id': messageId, 'booking_id': bookingId, 'body': body},
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }
}
