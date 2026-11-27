import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/meetup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/traveler_ui.dart';
import '../discovery/amigo_photo.dart';

export 'meetup_map.dart' show pickMeetingPoint;

class MeetupScreen extends StatelessWidget {
  const MeetupScreen({
    super.key,
    required this.client,
    required this.booking,
    required this.amigo,
  });

  final SupabaseClient client;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> amigo;

  @override
  Widget build(BuildContext context) => BookingMeetupScreen(
    client: client,
    booking: booking,
    companionName: amigo['display_name'] as String? ?? 'Amigo',
    avatar: AmigoPhoto(amigo, width: 52, height: 52, radius: 26),
    header: travelerHeader,
  );
}
