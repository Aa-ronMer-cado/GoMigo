import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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

class _FindingMigoScreenState extends State<FindingMigoScreen> {
  DiscoveryRepository get _repository => widget.repository;
  late Future<List<Map<String, dynamic>>> _loading;
  Set<String> _favorites = {};
  final _updating = <String>{};
  List<Map<String, dynamic>> _reviews = [];
  String? _activity;
  String? _area;
  String? _gender;
  RangeValues _ages = const RangeValues(18, 120);
  bool _savedOnly = false;
  bool _nearby = true;
  bool _locating = false;
  LatLng? _origin;
  String? _locationMessage;

  @override
  void initState() {
    super.initState();
    _loading = _load();
    unawaited(_findLocation());
  }

  Future<void> _findLocation({bool requestPermission = false}) async {
    if (_locating) return;
    setState(() {
      _nearby = true;
      _locating = true;
      _origin = null;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationMessage = 'Location services are off.');
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        setState(() {
          _locationMessage = permission == LocationPermission.deniedForever
              ? 'Allow location in your app or browser settings to search nearby.'
              : 'Allow location to see nearby Amigos.';
        });
        return;
      }
      final location = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) {
        setState(() => _origin = LatLng(location.latitude, location.longitude));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationMessage =
              'Could not get your location. Try again or browse all areas.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
        final filtered = all.where((amigo) {
          final age = amigo['age'] as int?;
          return (!_savedOnly || _favorites.contains(amigo['id'])) &&
              (_activity == null ||
                  (amigo['interests'] as List).contains(_activity)) &&
              (_area == null || amigo['area'] == _area) &&
              (_gender == null || amigo['gender'] == _gender) &&
              (age == null
                  ? _ages.start == 18 && _ages.end == 120
                  : age >= _ages.start && age <= _ages.end);
        });
        final needsLocation = _nearby && _origin == null;
        final shown = needsLocation
            ? const <DiscoveryResult>[]
            : discoveryResults(filtered, origin: _nearby ? _origin : null);
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
                      _options(all.expand((a) => a['interests'] as List)),
                      (value) => setState(() => _activity = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _filter(
                      'Area',
                      _area,
                      _options(all.map((a) => a['area'])),
                      (value) => setState(() => _area = value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _filter(
                      'Gender',
                      _gender,
                      _options(all.map((a) => a['gender'])),
                      (value) => setState(() => _gender = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilterChip(
                      label: const Text('Favorites'),
                      selected: _savedOnly,
                      onSelected: (value) => setState(() => _savedOnly = value),
                    ),
                  ),
                ],
              ),
              Text(
                'Age ${_ages.start.round()}–${_ages.end.round()}',
                style: const TextStyle(color: travelerInk),
              ),
              RangeSlider(
                values: _ages,
                min: 18,
                max: 120,
                divisions: 102,
                labels: RangeLabels(
                  '${_ages.start.round()}',
                  '${_ages.end.round()}',
                ),
                onChanged: (value) => setState(() => _ages = value),
              ),
              if (shown.isEmpty && !needsLocation)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    all.isEmpty
                        ? 'There are no Amigo profiles yet.'
                        : _nearby
                        ? 'No Amigos within $discoveryRadiusKm km match these filters.'
                        : _savedOnly
                        ? 'No saved Amigos match these filters.'
                        : 'No Amigos match these filters.',
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
        Text(
          _nearby ? 'Within $discoveryRadiusKm km' : 'Showing all areas',
          style: const TextStyle(
            color: travelerInk,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (_nearby && _locating)
          const LinearProgressIndicator(
            semanticsLabel: 'Finding your location',
          ),
        if (_nearby && _locationMessage != null) Text(_locationMessage!),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _locating
                  ? null
                  : () => _findLocation(requestPermission: true),
              child: Text(
                _nearby && _origin != null
                    ? 'Update location'
                    : 'Use my location',
              ),
            ),
            if (_nearby)
              TextButton(
                onPressed: () => setState(() => _nearby = false),
                child: const Text('Browse all areas'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _card(Map<String, dynamic> amigo, double? meters) {
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
                  if (meters != null)
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
