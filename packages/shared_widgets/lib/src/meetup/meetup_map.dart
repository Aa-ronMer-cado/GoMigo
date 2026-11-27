import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../device_location.dart';

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

Future<LatLng> _devicePoint(bool requestPermission) async {
  if (requestPermission) await requireDeviceLocation();
  final position = await readDevicePosition();
  return LatLng(position.latitude, position.longitude);
}

class MeetupMap extends StatefulWidget {
  const MeetupMap({
    super.key,
    required this.center,
    required this.markers,
    this.routes = const [],
    this.controller,
    this.onPointSelected,
    this.userAgentPackageName = 'com.gomigo.traveler',
    this.locationControlsTop = 10,
    this.locateDevice = _devicePoint,
  });

  final LatLng center;
  final List<Marker> markers;
  final List<Polyline> routes;
  final MapController? controller;
  final ValueChanged<LatLng>? onPointSelected;
  final String userAgentPackageName;
  final double locationControlsTop;
  final Future<LatLng> Function(bool requestPermission) locateDevice;

  @override
  State<MeetupMap> createState() => _MeetupMapState();
}

class _MeetupMapState extends State<MeetupMap> with WidgetsBindingObserver {
  final _tiles = NetworkTileProvider();
  late final _controller = widget.controller ?? MapController();
  late final Timer _locationUpdates;
  bool _tileError = false;
  bool _ready = false;
  bool _locating = false;
  bool _foreground = true;
  LatLng? _currentPosition;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationUpdates = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_currentPosition != null &&
          ModalRoute.isCurrentOf(context) != false) {
        unawaited(_locate());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
    }
  }

  @override
  void dispose() {
    _locationUpdates.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _locate({bool recenter = false}) async {
    if (!_foreground || !_ready || _locating) return;
    setState(() => _locating = true);
    try {
      final point = await widget.locateDevice(recenter);
      if (!mounted || !_foreground) return;
      setState(() {
        _currentPosition = point;
        _locationError = null;
      });
      if (recenter) _controller.move(point, _controller.camera.zoom);
    } on DeviceLocationException catch (error) {
      if (mounted)
        setState(() {
          _currentPosition = null;
          _locationError = error.message;
        });
    } catch (_) {
      if (mounted)
        setState(() => _locationError = 'Location unavailable. Try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: 14,
            maxZoom: 19,
            backgroundColor: const Color(0xFFE6EAD9),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, point) => widget.onPointSelected?.call(point),
            onMapReady: () {
              _ready = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_locate(recenter: true));
              });
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: widget.userAgentPackageName,
              tileProvider: _tiles,
              maxNativeZoom: 19,
              errorTileCallback: (tile, error, stackTrace) {
                if (!mounted || _tileError) return;
                setState(() => _tileError = true);
              },
            ),
            if (widget.routes.isNotEmpty)
              PolylineLayer(polylines: widget.routes),
            MarkerLayer(markers: [
              ...widget.markers,
              if (_currentPosition case final point?)
                meetupMarker(point, Icons.my_location, const Color(0xFF1768A8),
                    'Your current location on this device'),
            ]),
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
            Positioned(
              top: widget.locationControlsTop,
              right: 10,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Recenter on your current location',
                  onPressed: _locating ? null : () => _locate(recenter: true),
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : SvgPicture.asset('assets/figma/locate_fixed.svg',
                          package: 'gomigo_shared_widgets'),
                ),
              ),
            ),
            if (_locationError case final message?)
              Positioned(
                left: 8,
                right: 60,
                top: widget.locationControlsTop,
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                        padding: const EdgeInsets.all(8), child: Text(message)),
                  ),
                ),
              ),
          ],
        ),
      );
}
