import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/device_location.dart';
import 'package:latlong2/latlong.dart';

import '../../navigation/traveler_ui.dart';
import 'amigo_photo.dart';
import 'amigo_profile_screen.dart';
import 'discovery_repository.dart';
import 'nearby_amigos.dart';

class FindingMigoScreen extends StatefulWidget {
  const FindingMigoScreen({
    super.key,
    required this.repository,
    required this.request,
    required this.onBack,
  });
  final DiscoveryRepository repository;
  final void Function(BuildContext, Map<String, dynamic>) request;
  final VoidCallback onBack;

  @override
  State<FindingMigoScreen> createState() => _FindingMigoScreenState();
}

class _FindingMigoScreenState extends State<FindingMigoScreen>
    with WidgetsBindingObserver {
  DiscoveryRepository get _repository => widget.repository;
  late Future<List<Map<String, dynamic>>> _loading;
  Set<String> _favorites = {};
  final _updating = <String>{};
  List<Map<String, dynamic>> _reviews = [];
  String? _activity;
  String? _gender;
  bool _locating = false;
  LatLng? _origin;
  String? _locationMessage;
  DeviceLocationSettings? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loading = _load();
    unawaited(_findLocation());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_findLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _findLocation({bool requestPermission = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _origin = null;
      _locationMessage = null;
    });
    try {
      await requireDeviceLocation(requestPermission: requestPermission);
      final position = await readDevicePosition();
      if (mounted) {
        setState(() {
          _origin = LatLng(position.latitude, position.longitude);
          _settings = null;
        });
      }
    } on DeviceLocationException catch (error) {
      if (mounted) {
        setState(() {
          _locationMessage = error.message;
          _settings = error.settings ?? (requestPermission ? null : _settings);
        });
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _locationMessage = 'Could not get your location. Try again.',
        );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openSettings(DeviceLocationSettings settings) async {
    if (await openDeviceLocationSettings(settings) || !mounted) return;
    setState(
      () => _locationMessage =
          'Enable location in your device or browser settings.',
    );
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final (amigos, favorites, reviews) = await (
      _repository.amigos(),
      _repository.favorites(),
      _repository.reviews(),
    ).wait;
    _favorites = favorites;
    _reviews = reviews;
    return amigos;
  }

  Future<void> _favorite(String id, bool value) async {
    if (_updating.contains(id)) return;
    setState(() => _updating.add(id));
    try {
      await _repository.setFavorite(id, value);
      if (mounted)
        setState(() => value ? _favorites.add(id) : _favorites.remove(id));
    } finally {
      if (mounted) setState(() => _updating.remove(id));
    }
  }

  Set<String> _options(Iterable<dynamic> raw) =>
      (raw.whereType<String>().toSet().toList()..sort()).toSet();

  Widget _filter(
    String label,
    String? current,
    Set<String> options,
    ValueChanged<String?> change,
  ) => PopupMenuButton<String>(
    tooltip: label,
    onSelected: (value) => change(value.isEmpty ? null : value),
    itemBuilder: (_) => [
      PopupMenuItem(value: '', child: Text('Any ${label.toLowerCase()}')),
      for (final name in options) PopupMenuItem(value: name, child: Text(name)),
    ],
    child: TravelerCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(current ?? label, overflow: TextOverflow.ellipsis),
          ),
          const TravelerAsset('finding_chevron_down', size: 16),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Find a Migo', onBack: widget.onBack),
    body: FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return TravelerError(
            'Could not load Amigos.',
            onRetry: () => setState(() => _loading = _load()),
          );
        final all = snapshot.data;
        if (all == null)
          return const Center(child: CircularProgressIndicator());
        final nearby = discoveryResults(all, origin: _origin);
        final shown = nearby.where((result) {
          final amigo = result.profile;
          return (_activity == null ||
                  (amigo['interests'] as List).contains(_activity)) &&
              (_gender == null || amigo['gender'] == _gender);
        });
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _loading = _load());
            try {
              await _loading;
            } catch (_) {
              /* FutureBuilder shows the failure. */
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'What do you want to do today?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: travelerInk,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _locationFilter(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _filter(
                      'Activity',
                      _activity,
                      _options(
                        nearby.expand(
                          (entry) => entry.profile['interests'] as List,
                        ),
                      ),
                      (value) => setState(() => _activity = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _filter(
                      'Gender',
                      _gender,
                      _options(nearby.map((entry) => entry.profile['gender'])),
                      (value) => setState(() => _gender = value),
                    ),
                  ),
                ],
              ),
              if (shown.isEmpty && _origin != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    nearby.isEmpty
                        ? 'No available Amigos within $discoveryRadiusKm km.'
                        : 'No nearby Amigos match these filters.',
                  ),
                ),
              for (final result in shown) _card(result.profile, result.meters),
            ],
          ),
        );
      },
    ),
  );

  Widget _locationFilter() => TravelerCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Within $discoveryRadiusKm km',
          style: TextStyle(color: travelerInk, fontWeight: FontWeight.w800),
        ),
        if (_locating)
          const LinearProgressIndicator(
            semanticsLabel: 'Finding your location',
          ),
        if (_locationMessage case final message?)
          Semantics(liveRegion: true, child: Text(message)),
        if (!_locating)
          TextButton(
            onPressed: () => _findLocation(requestPermission: true),
            child: Text(_origin == null ? 'Check location' : 'Update location'),
          ),
        if (_settings case final settings?)
          TextButton(
            onPressed: _locating ? null : () => _openSettings(settings),
            child: Text(settings.label),
          ),
      ],
    ),
  );

  Widget _card(Map<String, dynamic> amigo, double meters) {
    final id = amigo['id'] as String;
    final rating = _reviews
        .where((review) => review['amigo_id'] == id)
        .toList();
    final stars = rating.isEmpty
        ? 'No reviews yet'
        : '${(rating.fold<int>(0, (sum, review) => sum + (review['rating'] as int)) / rating.length).toStringAsFixed(1)} (${rating.length})';
    final saved = _favorites.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TravelerCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AmigoPhoto(amigo, width: 104, height: 118),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          amigo['display_name'] as String,
                          style: const TextStyle(
                            color: travelerInk,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: saved
                            ? 'Remove from favorites'
                            : 'Save to favorites',
                        onPressed: _updating.contains(id)
                            ? null
                            : () async {
                                try {
                                  await _favorite(id, !saved);
                                } catch (_) {
                                  if (mounted)
                                    notifyTraveler(
                                      context,
                                      'Could not update favorites. Try again.',
                                    );
                                }
                              },
                        icon: saved
                            ? const Icon(Icons.favorite, color: travelerRust)
                            : const TravelerAsset('finding_heart'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const TravelerAsset('finding_star_filled', size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(stars)),
                    ],
                  ),
                  Text(amigo['area'] as String),
                  Text('About ${(meters / 1000).toStringAsFixed(1)} km away'),
                  Text((amigo['languages'] as List).join(', ')),
                  Text(
                    '${pesos(amigo['rate_centavos'])}/hr${amigo['is_test'] == true ? ' · Demo' : ''}',
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: travelerRust,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (profileContext) => AmigoProfileScreen(
                          amigo: amigo,
                          repository: _repository,
                          favorite: saved,
                          onFavorite: (value) => _favorite(id, value),
                          onRequest: () =>
                              widget.request(profileContext, amigo),
                        ),
                      ),
                    ),
                    child: const Text('View Profile'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
