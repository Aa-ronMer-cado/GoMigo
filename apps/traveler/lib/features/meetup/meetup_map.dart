import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../navigation/traveler_ui.dart';

Future<LatLng?> pickMeetingPoint(BuildContext context, LatLng? initial) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(builder: (_) => _MeetingPointPicker(initial: initial)),
  );
}

Marker meetupMarker(LatLng point, IconData icon, Color color, String label) =>
    Marker(
      point: point,
      width: 44,
      height: 44,
      child: Tooltip(
        message: label,
        child: Icon(
          icon,
          color: color,
          size: 36,
          shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
        ),
      ),
    );

class MeetupMap extends StatefulWidget {
  const MeetupMap({
    super.key,
    required this.center,
    required this.markers,
    this.routes = const [],
    this.controller,
    this.onPointSelected,
  });

  final LatLng center;
  final List<Marker> markers;
  final List<Polyline> routes;
  final MapController? controller;
  final ValueChanged<LatLng>? onPointSelected;

  @override
  State<MeetupMap> createState() => _MeetupMapState();
}

class _MeetupMapState extends State<MeetupMap> {
  final _tiles = NetworkTileProvider();
  bool _tileError = false;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 14,
        maxZoom: 19,
        backgroundColor: const Color(0xFFE6EAD9),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: (_, point) => widget.onPointSelected?.call(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.gomigo.traveler',
          tileProvider: _tiles,
          maxNativeZoom: 19,
          errorTileCallback: (tile, error, stackTrace) {
            if (!mounted || _tileError) return;
            setState(() => _tileError = true);
          },
        ),
        if (widget.routes.isNotEmpty) PolylineLayer(polylines: widget.routes),
        MarkerLayer(markers: widget.markers),
        if (_tileError)
          const Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Chip(label: Text('Some map tiles could not load')),
            ),
          ),
        SimpleAttributionWidget(
          source: const Text('OpenStreetMap contributors'),
          onTap: () async => launchUrl(
            Uri.https('www.openstreetmap.org', '/copyright'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    ),
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
