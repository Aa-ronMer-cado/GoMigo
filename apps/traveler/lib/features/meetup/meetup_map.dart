import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/meetup.dart';
import 'package:latlong2/latlong.dart';

import '../../navigation/traveler_ui.dart';

Future<LatLng?> pickMeetingPoint(BuildContext context, LatLng? initial) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(builder: (_) => _MeetingPointPicker(initial: initial)),
  );
}

class _MeetingPointPicker extends StatefulWidget {
  const _MeetingPointPicker({required this.initial});

  final LatLng? initial;

  @override
  State<_MeetingPointPicker> createState() => _MeetingPointPickerState();
}

class _MeetingPointPickerState extends State<_MeetingPointPicker> {
  late LatLng? _point = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Meeting point'),
    backgroundColor: travelerCream,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tap the map to place the meeting pin.'),
            const SizedBox(height: 12),
            Expanded(
              child: MeetupMap(
                center: widget.initial ?? const LatLng(14.5995, 120.9842),
                markers: [
                  if (_point case final point?)
                    meetupMarker(
                      point,
                      Icons.location_on,
                      travelerRust,
                      'Meeting point',
                    ),
                ],
                onPointSelected: (point) => setState(() => _point = point),
              ),
            ),
            const SizedBox(height: 12),
            TravelerButton(
              'Use this meeting point',
              _point == null ? null : () => Navigator.of(context).pop(_point),
            ),
          ],
        ),
      ),
    ),
  );
}
