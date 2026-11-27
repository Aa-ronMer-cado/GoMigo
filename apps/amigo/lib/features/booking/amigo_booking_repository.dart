import 'package:supabase_flutter/supabase_flutter.dart';

class AmigoBooking {
  const AmigoBooking(
    this.row, {
    required this.travelerName,
    required this.travelerVerified,
  });

  final Map<String, dynamic> row;
  final String travelerName;
  final bool travelerVerified;

  String get id => row['id'] as String;
  String get travelerId => row['traveler_id'] as String;
  String get status => row['status'] as String;
  String get paymentStatus => row['payment_status'] as String;
  String get meetingPoint => row['meeting_label'] as String;
  String get notes => row['notes'] as String;
  String? get declineReason => row['decline_reason'] as String?;
  DateTime get startsAt => DateTime.parse(row['starts_at'] as String);
  DateTime get endsAt => DateTime.parse(row['ends_at'] as String);
  int get subtotalCentavos => row['subtotal_centavos'] as int;
  int get feeCentavos => row['fee_centavos'] as int;
  int get totalCentavos => row['total_centavos'] as int;

  bool get hasConversation => status == 'accepted' || status == 'completed';

  AmigoBooking withRow(Map<String, dynamic> updated) => AmigoBooking(
    updated,
    travelerName: travelerName,
    travelerVerified: travelerVerified,
  );
}

class AmigoBookingRepository {
  AmigoBookingRepository(this.client, this.amigoId);

  final SupabaseClient client;
  final String amigoId;

  Stream<List<AmigoBooking>> history() => client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('amigo_id', amigoId)
      .order('created_at', ascending: false)
      .asyncMap(_includeTravelerNames);

  Stream<AmigoBooking?> watch(AmigoBooking initial) => client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('id', initial.id)
      .map((rows) => rows.isEmpty ? null : initial.withRow(rows.first));

  Future<List<AmigoBooking>> _includeTravelerNames(
    List<Map<String, dynamic>> bookings,
  ) async {
    if (bookings.isEmpty) return [];
    final travelers = await client.rpc<List<dynamic>>(
      'get_amigo_booking_travelers',
      params: {'p_booking_ids': bookings.map((row) => row['id']).toList()},
    );
    final byBooking = {
      for (final traveler in travelers)
        (traveler as Map<String, dynamic>)['booking_id']: traveler,
    };
    return [
      for (final booking in bookings)
        AmigoBooking(
          booking,
          travelerName:
              byBooking[booking['id']]?['display_name'] as String? ??
              'Traveler',
          travelerVerified: byBooking[booking['id']]?['verified'] == true,
        ),
    ];
  }

  Future<AmigoBooking> respond(
    AmigoBooking booking, {
    required bool accept,
    String? reason,
  }) async {
    final updated = await client.rpc<Map<String, dynamic>>(
      'respond_to_booking',
      params: {
        'p_booking_id': booking.id,
        'p_decision': accept ? 'accepted' : 'declined',
        'p_reason': reason,
      },
    );
    return booking.withRow(updated);
  }

  Future<Map<String, dynamic>?> availability() => client
      .from('amigo_profiles')
      .select('available,area')
      .eq('id', amigoId)
      .maybeSingle();

  Future<bool> setAvailable(bool available) => client.rpc<bool>(
    'set_amigo_availability',
    params: {'p_available': available},
  );
}
