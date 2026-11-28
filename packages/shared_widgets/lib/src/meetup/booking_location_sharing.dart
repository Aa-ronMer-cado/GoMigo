import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../device_location.dart';
import 'meetup_repository.dart';

/// Owns consent and location updates for the signed-in app, across routes.
class BookingLocationScope extends StatefulWidget {
  const BookingLocationScope({
    super.key,
    required this.client,
    required this.child,
  });
  final SupabaseClient client;
  final Widget child;

  static _BookingLocationSharing? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SharingState>()?.notifier;

  @override
  State<BookingLocationScope> createState() => _BookingLocationScopeState();
}

class _BookingLocationScopeState extends State<BookingLocationScope> {
  late final _sharing = _BookingLocationSharing(widget.client);

  @override
  void dispose() {
    _sharing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SharingState(notifier: _sharing, child: widget.child);
}

class _SharingState extends InheritedNotifier<_BookingLocationSharing> {
  const _SharingState({required super.notifier, required super.child});
}

class _Consent {
  _Consent(this.booking, this.repository);
  Map<String, dynamic> booking;
  final MeetupRepository repository;
  StreamSubscription<List<Map<String, dynamic>>>? updates;
  DateTime? lastSent;
  Future<void>? write;
  bool uploaded = false;
}

class _BookingLocationSharing extends ChangeNotifier
    with WidgetsBindingObserver {
  _BookingLocationSharing(this.client) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SupabaseClient client;
  final _consents = <String, _Consent>{};
  final _clearing = <String, Future<void>>{};
  final _needsClear = <String, MeetupRepository>{};
  final _messages = <String, String>{};
  StreamSubscription<Position>? _positions;
  Timer? _timer;
  bool _busy = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _disposed = false;

  bool enabled(String id) => _consents.containsKey(id);
  bool active(String id) {
    final consent = _consents[id];
    return _positions != null &&
        consent != null &&
        isMeetupSharingWindow(consent.booking, DateTime.now());
  }

  String? message(String id) => _messages[id];

  Future<void> enable(Map<String, dynamic> booking) async {
    final id = booking['id'] as String;
    if (_disposed || enabled(id)) return;
    await _clearing[id];
    if (_disposed || enabled(id)) return;
    if (_needsClear.containsKey(id)) {
      _messages[id] = 'Reconnect to finish clearing the earlier location.';
      notifyListeners();
      return;
    }
    _messages.remove(id);
    final entry = _Consent(booking, MeetupRepository(client, id));
    _consents[id] = entry;
    entry.updates = client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .listen(
          (rows) {
            if (!identical(_consents[id], entry)) return;
            if (rows.isEmpty) {
              unawaited(stop(id));
              return;
            }
            _bookingChanged(id, entry, rows.first);
          },
          onError: (Object _) {
            // The status poll and trusted location RPC also check the booking.
          },
        );
    _timer ??= Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(_tick()),
    );
    notifyListeners();
    unawaited(_syncPositionStream());
  }

  void _bookingChanged(String id, _Consent entry, Map<String, dynamic> row) {
    entry.booking = row;
    final status = row['status'];
    final ends = DateTime.tryParse(row['ends_at'] as String? ?? '');
    if ((status != 'pending' && status != 'accepted') ||
        (ends != null &&
            DateTime.now().isAfter(ends.add(const Duration(hours: 1))))) {
      unawaited(stop(id));
    } else {
      unawaited(_syncPositionStream());
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _tick() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      final shares = _consents.entries.toList();
      if (shares.isNotEmpty) {
        if (_positions != null) {
          try {
            await requireDeviceLocation(requestPermission: false);
          } on DeviceLocationException catch (error) {
            for (final share in shares) {
              _messages[share.key] = error.message;
              unawaited(stop(share.key));
            }
            return;
          }
        }
        try {
          final rows = await client
              .from('bookings')
              .select('id,status,starts_at,ends_at')
              .inFilter('id', shares.map((share) => share.key).toList())
              .timeout(const Duration(seconds: 8));
          for (final share in shares) {
            if (!identical(_consents[share.key], share.value)) continue;
            final row = rows.where((row) => row['id'] == share.key).firstOrNull;
            if (row == null) {
              unawaited(stop(share.key));
            } else {
              _bookingChanged(share.key, share.value, row);
            }
          }
        } catch (_) {
          // Supabase still authorizes every location write. Stale markers expire.
        }
      }
      for (final id in _needsClear.keys.toList()) {
        if (!_clearing.containsKey(id)) {
          final operation = _clear(id).whenComplete(() => _clearing.remove(id));
          _clearing[id] = operation;
          unawaited(operation);
        }
      }
      await _syncPositionStream();
    } finally {
      _busy = false;
      _cancelIdleTimer();
    }
  }

  bool _starting = false;
  Future<void> _syncPositionStream() async {
    if (_disposed) return;
    bool eligible() => _consents.values.any(
      (c) => isMeetupSharingWindow(c.booking, DateTime.now()),
    );
    if (!eligible()) {
      final positions = _positions;
      _positions = null;
      await positions?.cancel();
      return;
    }
    // While-in-use permissions can start the Android location service from a visible activity.
    if (_positions != null || _starting || !_foreground) return;
    _starting = true;
    try {
      await requireDeviceLocation(requestPermission: false);
      if (_disposed || !_foreground || !eligible()) return;
      _positions = Geolocator.getPositionStream(locationSettings: _settings())
          .listen(
            _publish,
            onError: (Object _) {
              for (final id in _consents.keys.where(active).toList()) {
                _messages[id] =
                    'Location access stopped. Check device settings to share again.';
                unawaited(stop(id));
              }
            },
          );
      notifyListeners();
    } on DeviceLocationException catch (error) {
      for (final entry in _consents.entries.toList()) {
        if (isMeetupSharingWindow(entry.value.booking, DateTime.now())) {
          _messages[entry.key] = error.message;
          unawaited(stop(entry.key));
        }
      }
    } catch (_) {
      for (final id in _consents.keys.toList()) {
        _messages[id] =
            'Could not start location sharing. Check device settings and try again.';
        unawaited(stop(id));
      }
    } finally {
      _starting = false;
    }
  }

  LocationSettings _settings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: const Duration(seconds: 12),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'GoMigo location sharing',
          notificationText: 'Your location is visible to your meetup partner.',
          notificationChannelName: 'GoMigo meetup location',
          setOngoing: true,
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  void _publish(Position position) {
    if (_disposed || _positions == null) return;
    final now = DateTime.now();
    if (!position.accuracy.isFinite ||
        position.accuracy > 100 ||
        position.timestamp.difference(now).abs() > const Duration(seconds: 30))
      return;
    for (final entry in _consents.entries) {
      final share = entry.value;
      if (!isMeetupSharingWindow(share.booking, now) ||
          share.write != null ||
          (share.lastSent != null &&
              now.difference(share.lastSent!) < const Duration(seconds: 10)))
        continue;
      share.lastSent = now;
      share.uploaded = true;
      share.write = share.repository
          .setLocation(LatLng(position.latitude, position.longitude))
          .then((_) => _messages.remove(entry.key))
          .then<void>(
            (_) {},
            onError: (Object _) {
              if (identical(_consents[entry.key], share)) {
                _messages[entry.key] =
                    'Location update could not be sent. GoMigo will retry.';
              }
            },
          )
          .whenComplete(() {
            share.write = null;
            if (!_disposed) notifyListeners();
          });
    }
  }

  Future<void> stop(String id) async {
    final entry = _consents.remove(id);
    if (entry == null) return;
    unawaited(entry.updates?.cancel());
    if (!_disposed) notifyListeners();
    unawaited(_syncPositionStream());
    if (entry.uploaded) {
      _clearing[id] = () async {
        await entry.write;
        _needsClear[id] = entry.repository;
        await _clear(id);
      }();
      await _clearing[id];
      _clearing.remove(id);
    }
    _cancelIdleTimer();
  }

  Future<void> _clear(String id) async {
    final repository = _needsClear.remove(id);
    if (repository == null) return;
    try {
      await repository.setLocation(null);
    } catch (_) {
      if (!_disposed) {
        _needsClear[id] = repository;
        _messages[id] =
            'Sharing stopped. The last visible location will expire shortly.';
      }
    }
    if (!_disposed) notifyListeners();
  }

  void _cancelIdleTimer() {
    if (_consents.isEmpty && _clearing.isEmpty && _needsClear.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_tick());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_positions?.cancel());
    for (final id in _consents.keys.toList()) {
      unawaited(stop(id));
    }
    super.dispose();
  }
}

class BookingLocationConsent extends StatelessWidget {
  const BookingLocationConsent({
    super.key,
    required this.booking,
    required this.amigoView,
  });
  final Map<String, dynamic> booking;
  final bool amigoView;

  static String description(String partner) =>
      'Only your $partner can see it near the time of this accepted meetup, '
      'including while you use other apps. You can stop sharing from the booking or map.';

  static Future<void> optIn(
    BuildContext context,
    Map<String, dynamic> booking,
  ) async {
    final sharing = context
        .getInheritedWidgetOfExactType<_SharingState>()
        ?.notifier;
    if (sharing == null) return;
    try {
      await requireDeviceLocation();
      if (context.mounted) await sharing.enable(booking);
    } on DeviceLocationException catch (error) {
      if (!context.mounted) return;
      final settings = error.settings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          action: settings == null
              ? null
              : SnackBarAction(
                  label: 'Settings',
                  onPressed: () =>
                      unawaited(openDeviceLocationSettings(settings)),
                ),
        ),
      );
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start location sharing. Try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharing = BookingLocationScope._of(context);
    final id = booking['id'] as String;
    final enabled = sharing?.enabled(id) == true;
    final status = booking['status'];
    if (sharing == null || (status != 'pending' && status != 'accepted')) {
      return const SizedBox.shrink();
    }
    final partner = amigoView ? 'Traveler' : 'Amigo';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            sharing.active(id)
                ? 'Live location sharing is on'
                : 'Share my location',
          ),
          subtitle: Text(description(partner)),
          value: enabled,
          onChanged: (value) async {
            if (!value) {
              await sharing.stop(id);
              return;
            }
            await optIn(context, booking);
          },
        ),
        if (enabled && !sharing.active(id))
          const Text(
            'Sharing will start near the time of your accepted meetup.',
          ),
        if (sharing.message(id) case final message?)
          Semantics(liveRegion: true, child: Text(message)),
      ],
    );
  }
}
