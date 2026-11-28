import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../device_location.dart';
import 'booking_location_sharing.dart';
import 'meetup_map.dart';
import 'meetup_repository.dart';

class BookingMeetupScreen extends StatefulWidget {
  const BookingMeetupScreen({
    super.key,
    required this.client,
    required this.booking,
    required this.companionName,
    required this.avatar,
    required this.header,
    this.amigoView = false,
    this.tripControls,
    this.showSessionFirst = false,
    this.onChat,
    this.navigation,
  });

  final SupabaseClient client;
  final Map<String, dynamic> booking;
  final String companionName;
  final Widget avatar;
  final PreferredSizeWidget Function(String title) header;
  final bool amigoView;
  final Widget Function(
    Map<String, dynamic> booking,
    Map<String, dynamic>? session,
    VoidCallback refresh,
  )?
  tripControls;
  final bool showSessionFirst;
  final VoidCallback? onChat;
  final Widget? navigation;

  @override
  State<BookingMeetupScreen> createState() => _BookingMeetupScreenState();
}

class _BookingMeetupScreenState extends State<BookingMeetupScreen>
    with WidgetsBindingObserver {
  static const _sampleInterval = Duration(seconds: 12);
  static const _amigoColor = Color(0xFF436B46);
  static const _travelerColor = Color(0xFF245E87);

  late final _repository = MeetupRepository(
    widget.client,
    widget.booking['id'] as String,
    topic: widget.amigoView ? 'amigo' : 'traveler',
  );
  late Map<String, dynamic> _booking = widget.booking;
  late final _viewer = widget.amigoView
      ? widget.booking['amigo_id'] as String
      : widget.booking['traveler_id'] as String;
  final _mapController = MapController();
  final _scrollController = ScrollController();
  final _locations = <String, Map<String, dynamic>>{};
  final _routePoints = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? _session;
  RealtimeChannel? _channel;
  Timer? _timer;
  Future<void>? _captureInFlight;
  bool _liveConnected = false;
  bool _refreshing = false;
  bool _loaded = false;
  bool _available = true;
  bool _disposed = false;
  bool _foreground = true;
  bool _recording = false;
  bool _enabling = false;
  bool _syncingStops = false;
  bool _clearRecording = false;
  int _trackingGeneration = 0;
  int _ticks = 0;
  String? _dataMessage;
  String? _trackingMessage;
  String? _stopMessage;
  LatLng? _lastRecordedPoint;
  ({LatLng point, String id})? _unconfirmedPoint;

  bool get _canShare =>
      _loaded && _available && isMeetupSharingWindow(_booking, DateTime.now());
  bool get _canRecord =>
      _loaded &&
      _available &&
      _booking['status'] == 'accepted' &&
      _session?['started_at'] != null &&
      _session?['ended_at'] == null;
  bool get _canSeeRoute =>
      _available &&
      (_booking['status'] == 'accepted' || _booking['status'] == 'completed');
  bool get _isActive => mounted && !_disposed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel = _repository.watch(
      onChange: _onChange,
      onStatus: (status, _) {
        if (!_isActive) return;
        _liveConnected = status == RealtimeSubscribeStatus.subscribed;
        if (_liveConnected) unawaited(_refresh());
        _redraw();
      },
    );
    unawaited(_refresh());
    _timer = Timer.periodic(_sampleInterval, (_) {
      if (!_foreground) return;
      _enforceBookingState();
      _redraw(); // A remote marker can expire without a database change.
      if (++_ticks % 3 == 0 && (!_liveConnected || _dataMessage != null)) {
        unawaited(_refresh());
      } else if (_canShare) {
        unawaited(_refreshLocations());
      }
      if (_clearRecording) unawaited(_syncStops());
      _capture();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(_refresh());
      if (_clearRecording) unawaited(_syncStops());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stop();
    if (_channel case final channel?)
      unawaited(widget.client.removeChannel(channel));
    _mapController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _redraw() {
    if (_isActive) setState(() {});
  }

  Future<void> _refresh() async {
    if (_refreshing || !_isActive) return;
    _refreshing = true;
    _redraw();
    try {
      final snapshot = await _repository.load();
      if (!_isActive) return;
      _loaded = true;
      _available = snapshot.booking != null;
      if (snapshot.booking case final booking?) _booking = booking;
      _session = snapshot.session;
      if (_canShare) {
        for (final row in snapshot.locations) {
          _updateLocation(row);
        }
      } else {
        _locations.clear();
      }
      _enforceBookingState();
      if (_canSeeRoute) {
        final points = await _repository.routePoints();
        if (!_isActive) return;
        if (_canSeeRoute) {
          for (final point in points) {
            _routePoints[point['id'] as String] = point;
          }
        }
      } else {
        _routePoints.clear();
      }
      _dataMessage = null;
    } catch (_) {
      _dataMessage =
          'Could not refresh meetup details. Check your connection and try again.';
    } finally {
      _refreshing = false;
      _redraw();
    }
  }

  Future<void> _refreshLocations() async {
    try {
      for (final row in await _repository.locations()) {
        if (_isActive && _canShare) _updateLocation(row);
      }
      _redraw();
    } catch (_) {
      // Realtime and later polls can refresh the markers. Stale markers expire.
    }
  }

  void _onChange(String table, Map<String, dynamic> row) {
    if (!_isActive || !_available || row.isEmpty) return;
    switch (table) {
      case 'bookings':
        _booking = row;
        if (!_canShare) _locations.clear();
        if (!_canSeeRoute) _routePoints.clear();
        _enforceBookingState();
      case 'booking_sessions':
        _session = row;
        _enforceBookingState();
      case 'booking_locations':
        if (_canShare) _updateLocation(row);
      case 'booking_route_points':
        if (_canSeeRoute) _routePoints[row['id'] as String] = row;
    }
    _redraw();
  }

  void _updateLocation(Map<String, dynamic> row) {
    final id = row['participant_id'] as String;
    final previous = _locations[id];
    final stamp = DateTime.parse(row['updated_at'] as String);
    if (previous == null ||
        !stamp.isBefore(DateTime.parse(previous['updated_at'] as String))) {
      _locations[id] = row;
    }
  }

  void _enforceBookingState() {
    if (_recording && !_canRecord) _stop();
  }

  Future<void> _toggleRecording(bool enabled) async {
    if (!enabled) {
      _stop();
      return;
    }
    if (_enabling || !_foreground || !_canRecord) return;
    final generation = _trackingGeneration;
    _enabling = true;
    _trackingMessage = null;
    _redraw();
    bool stillAllowed() =>
        _isActive &&
        _foreground &&
        generation == _trackingGeneration &&
        _canRecord;
    try {
      await _syncStops();
      if (!stillAllowed()) return;
      if (_clearRecording || _syncingStops) {
        _trackingMessage =
            'Reconnect to finish stopping the previous route recording.';
        return;
      }
      await requireDeviceLocation();
      if (!stillAllowed()) return;
      try {
        await _repository.setRecording(true);
      } catch (_) {
        _clearRecording = true;
        unawaited(_syncStops());
        rethrow;
      }
      if (!stillAllowed()) {
        _clearRecording = true;
        unawaited(_syncStops());
        return;
      }
      _recording = true;
      _lastRecordedPoint = null;
      _capture();
    } on DeviceLocationException catch (error) {
      if (stillAllowed()) _trackingMessage = error.message;
    } catch (_) {
      if (stillAllowed()) {
        _trackingMessage =
            'Could not start route recording. Check your connection and try again.';
      }
    } finally {
      _enabling = false;
      _redraw();
    }
  }

  void _stop() {
    _trackingGeneration++;
    if (_recording) {
      _recording = false;
      _clearRecording = true;
      _unconfirmedPoint = null;
    }
    _trackingMessage = null;
    _redraw();
    if (_clearRecording) unawaited(_syncStops());
  }

  Future<void> _syncStops() async {
    if (_syncingStops || !_clearRecording) return;
    _syncingStops = true;
    try {
      await _captureInFlight;
      await _repository.setRecording(false);
      _clearRecording = false;
      _stopMessage = null;
    } catch (_) {
      _stopMessage =
          'Recording stopped on this device. The stop will sync when you reconnect.';
    } finally {
      _syncingStops = false;
      _redraw();
    }
  }

  void _capture() {
    if (!_foreground || _captureInFlight != null || !_recording) {
      return;
    }
    _captureInFlight = _saveCurrentPosition().whenComplete(
      () => _captureInFlight = null,
    );
    unawaited(_captureInFlight);
  }

  Future<void> _saveCurrentPosition() async {
    Position position;
    try {
      await requireDeviceLocation(requestPermission: false);
      position = await readDevicePosition();
    } catch (_) {
      if (_isActive && _recording) {
        _trackingMessage =
            'Waiting for GPS. Check location access or move into an open area.';
        _redraw();
      }
      return;
    }
    if (!_isActive || !_foreground || !_recording) return;
    if (!position.accuracy.isFinite ||
        position.accuracy > 100 ||
        position.timestamp.difference(DateTime.now()).abs() >
            const Duration(seconds: 30)) {
      _trackingMessage = 'GPS is weak. Waiting for a more accurate position.';
      _redraw();
      return;
    }

    final point = LatLng(position.latitude, position.longitude);
    var networkError = false;
    if (_isActive && _foreground && _recording && _canRecord) {
      final previous = _lastRecordedPoint;
      if (_unconfirmedPoint == null &&
          (previous == null ||
              const Distance().as(LengthUnit.Meter, previous, point) >= 10)) {
        _unconfirmedPoint = (point: point, id: const Uuid().v4());
      }
      if (_unconfirmedPoint case final sample?) {
        try {
          await _repository.appendPoint(sample.point, sample.id);
          _lastRecordedPoint = sample.point;
          _unconfirmedPoint = null;
        } catch (_) {
          networkError = true;
        }
      }
    }
    if (_isActive && _recording) {
      _trackingMessage = networkError
          ? 'Could not send the location update. Retrying while this map is open.'
          : null;
      _redraw();
    }
  }

  bool get _showsSharedSelf {
    final row = _locations[_viewer];
    return _canShare &&
        row != null &&
        meetupCoordinates(row) != null &&
        DateTime.now().difference(DateTime.parse(row['updated_at'] as String)) <
            livePositionLifetime;
  }

  List<Marker> _markers(LatLng meeting) {
    final now = DateTime.now();
    final live = {
      if (_canShare)
        for (final row in _locations.values)
          if (now.difference(DateTime.parse(row['updated_at'] as String)) <
              livePositionLifetime)
            if (meetupCoordinates(row) case final point?)
              row['participant_id']: point,
    };
    final markers = [
      meetupMarker(meeting, Icons.location_on, _rust, 'Meeting point'),
    ];
    for (final entry in live.entries) {
      final traveler = entry.key == _booking['traveler_id'];
      final overlaps =
          entry.value == meeting ||
          live.entries.any(
            (other) => other.key != entry.key && other.value == entry.value,
          );
      markers.add(
        meetupMarker(
          entry.value,
          traveler ? Icons.person_pin_circle : Icons.explore,
          traveler ? _travelerColor : _amigoColor,
          entry.key == _viewer
              ? 'Your location'
              : traveler
              ? 'Traveler location'
              : 'Amigo location',
          alignment: overlaps
              ? traveler
                    ? Alignment.centerLeft
                    : Alignment.centerRight
              : null,
        ),
      );
    }
    return markers;
  }

  List<Polyline> _routes() {
    if (!_canSeeRoute) return [];
    final ordered = _routePoints.values.toList()
      ..sort(
        (a, b) =>
            (a['recorded_at'] as String).compareTo(b['recorded_at'] as String),
      );
    final grouped = <String, List<LatLng>>{};
    for (final row in ordered) {
      if (meetupCoordinates(row) case final point?) {
        (grouped[row['participant_id'] as String] ??= []).add(point);
      }
    }
    return [
      for (final entry in grouped.entries)
        if (entry.value.length >= 2)
          Polyline(
            points: entry.value,
            strokeWidth: 5,
            color: entry.key == _booking['traveler_id']
                ? _travelerColor
                : _amigoColor,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final completed = _booking['status'] == 'completed';
    final meeting = meetupCoordinates(
      _booking,
      latitude: 'meeting_lat',
      longitude: 'meeting_lng',
    );
    final routes = _routes();
    final controls = widget.tripControls?.call(_booking, _session, _refresh);
    return Scaffold(
      appBar: widget.header(completed ? 'Trip route' : 'Meetup map'),
      bottomNavigationBar: widget.navigation,
      backgroundColor: _cream,
      body: SafeArea(
        child: !_available || meeting == null
            ? const _MeetupError('This meetup is not available.')
            : LayoutBuilder(
                builder: (context, constraints) => ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (widget.showSessionFirst && controls != null) controls,
                    _mapSurface(context, constraints, meeting, routes),
                    const SizedBox(height: 12),
                    if (!widget.amigoView || !_useMapOverlays(context))
                      _summary(context, meeting, routes),
                    if (!widget.showSessionFirst && controls != null) controls,
                    if (_dataMessage case final message?)
                      _MeetupError(
                        message,
                        onRetry: _refreshing ? null : _refresh,
                      ),
                    if (!completed) ...[
                      const SizedBox(height: 12),
                      _trackingControls(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  bool _useMapOverlays(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 360 &&
      MediaQuery.textScalerOf(context).scale(20) <= 24;

  Widget _mapSurface(
    BuildContext context,
    BoxConstraints constraints,
    LatLng meeting,
    List<Polyline> routes,
  ) {
    final map = MeetupMap(
      center: meeting,
      controller: _mapController,
      markers: _markers(meeting),
      showDeviceMarker: !_showsSharedSelf,
      routes: routes,
      locationRequired: widget.amigoView && _booking['status'] == 'accepted',
      locationControlsTop:
          widget.amigoView &&
              _session == null &&
              _booking['status'] == 'accepted'
          ? 115
          : 10,
      userAgentPackageName: widget.amigoView
          ? 'com.gomigo.amigo'
          : 'com.gomigo.traveler',
    );
    final withOverlays = widget.amigoView && _useMapOverlays(context);
    final height = withOverlays
        ? (constraints.maxHeight * .8).clamp(460.0, 650.0)
        : (constraints.maxHeight * .57).clamp(260.0, 560.0);
    return SizedBox(
      height: height.toDouble(),
      child: withOverlays
          ? Stack(
              fit: StackFit.expand,
              children: [
                map,
                if (_booking['status'] == 'accepted' && _session == null)
                  Positioned(
                    left: 9,
                    right: 9,
                    top: 14,
                    child: _MeetupCard(
                      color: Colors.white,
                      child: Text(
                        'Meet ${widget.companionName}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                Positioned(
                  left: 9,
                  right: 9,
                  bottom: 25,
                  child: _summary(context, meeting, routes),
                ),
              ],
            )
          : map,
    );
  }

  Widget _summary(BuildContext context, LatLng meeting, List<Polyline> routes) {
    final localizations = MaterialLocalizations.of(context);
    DateTime bookingTime(String key) {
      final instant = DateTime.parse(_booking[key] as String);
      return widget.amigoView
          ? instant.toUtc().add(const Duration(hours: 8))
          : instant.toLocal();
    }

    final start = bookingTime('starts_at');
    final end = bookingTime('ends_at');
    return _MeetupCard(
      color: widget.amigoView ? Colors.white : _cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.companionName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(_booking['meeting_label'] as String),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(localizations.formatFullDate(start)),
          Text(
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start))} – '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end))}',
          ),
          Text(
            '${_pesos(_booking['total_centavos'])} · Booking total',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (_booking['status'] == 'accepted' && widget.amigoView)
            Wrap(
              spacing: 8,
              children: [
                if (widget.onChat case final chat?)
                  FilledButton(
                    onPressed: () {
                      _stop();
                      chat();
                    },
                    style: FilledButton.styleFrom(backgroundColor: _rust),
                    child: Text('Say hi to ${widget.companionName}'),
                  ),
                TextButton(
                  onPressed: () => _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  ),
                  child: const Text('Location and route'),
                ),
              ],
            ),
          if (_booking['status'] == 'completed' &&
              _loaded &&
              _routePoints.isEmpty)
            const Text('No route was recorded for this trip.'),
          if (routes.isNotEmpty)
            TextButton.icon(
              onPressed: () => _mapController.fitCamera(
                CameraFit.coordinates(
                  coordinates: [
                    meeting,
                    for (final route in routes) ...route.points,
                  ],
                  padding: const EdgeInsets.all(48),
                  maxZoom: 16,
                ),
              ),
              icon: const Icon(Icons.route),
              label: const Text('Show recorded route'),
            ),
        ],
      ),
    );
  }

  Widget _trackingControls() => _MeetupCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_loaded && _refreshing) const LinearProgressIndicator(),
        if (_loaded && _available)
          BookingLocationConsent(
            booking: _booking,
            amigoView: widget.amigoView,
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Record my trip route'),
          subtitle: Text(
            _canRecord
                ? 'Saves your route to trip history while this map is open.'
                : 'Available during an active session.',
          ),
          value: _recording,
          onChanged: _enabling || !_canRecord ? null : _toggleRecording,
        ),
        if (_enabling) const LinearProgressIndicator(),
        if (!_liveConnected && _loaded)
          const Text('Live updates interrupted. Checking for changes…'),
        if (_trackingMessage case final message?)
          Semantics(liveRegion: true, child: Text(message)),
        if (_stopMessage case final message?)
          Semantics(liveRegion: true, child: Text(message)),
      ],
    ),
  );
}

const _cream = Color(0xFFFFF8F0);
const _rust = Color(0xFFA1472E);

String _pesos(Object? cents) =>
    '₱${((cents as num? ?? 0) / 100).toStringAsFixed(2)}';

class _MeetupCard extends StatelessWidget {
  const _MeetupCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = _cream,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: const Color(0xFFD9C7B6)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class _MeetupError extends StatelessWidget {
  const _MeetupError(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
