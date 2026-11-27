import 'package:flutter/material.dart';

import '../../navigation/traveler_ui.dart';
import 'amigo_photo.dart';
import 'discovery_repository.dart';

class AmigoProfileScreen extends StatefulWidget {
  const AmigoProfileScreen({
    super.key,
    required this.amigo,
    required this.repository,
    required this.favorite,
    required this.onRequest,
    required this.onFavorite,
  });
  final Map<String, dynamic> amigo;
  final DiscoveryRepository repository;
  final bool favorite;
  final VoidCallback onRequest;
  final Future<void> Function(bool) onFavorite;

  @override
  State<AmigoProfileScreen> createState() => _AmigoProfileScreenState();
}

class _AmigoProfileScreenState extends State<AmigoProfileScreen> {
  late bool _favorite = widget.favorite;
  bool _changing = false;
  late Future<List<Map<String, dynamic>>> _reviews = widget.repository.reviews(
    widget.amigo['id'] as String,
  );

  Future<void> _toggle() async {
    setState(() => _changing = true);
    try {
      await widget.onFavorite(!_favorite);
      if (mounted) setState(() => _favorite = !_favorite);
    } catch (_) {
      if (mounted)
        notifyTraveler(context, 'Could not update favorites. Try again.');
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amigo = widget.amigo;
    final interests = List<String>.from(amigo['interests'] as List);
    return Scaffold(
      appBar: travelerHeader('Amigo profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(23, 32, 23, 24),
        children: [
          AmigoPhoto(amigo, width: double.infinity, height: 231, radius: 38),
          Row(
            children: [
              Expanded(
                child: Text(
                  amigo['display_name'] as String,
                  style: const TextStyle(
                    color: travelerInk,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: _favorite
                    ? 'Remove from favorites'
                    : 'Save to favorites',
                onPressed: _changing ? null : _toggle,
                icon: _favorite
                    ? const Icon(Icons.favorite, color: travelerRust)
                    : const TravelerAsset('finding_heart'),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(amigo['area'] as String),
              Text(
                amigo['verified'] == true
                    ? 'Verified Amigo'
                    : 'Verification pending',
              ),
              if (amigo['is_test'] == true) const Text('Demo profile'),
              Text('${pesos(amigo['rate_centavos'])}/hr'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const TravelerAsset('finding_language', size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text((amigo['languages'] as List).join(', '))),
            ],
          ),
          const Divider(),
          Text('About', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(amigo['description'] as String),
          const SizedBox(height: 20),
          Text('Interests', style: Theme.of(context).textTheme.titleLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final interest in interests)
                Chip(label: Text(interest), backgroundColor: travelerSage),
            ],
          ),
          const SizedBox(height: 20),
          TravelerButton(
            'Request a Migo',
            amigo['verified'] == true ? widget.onRequest : null,
          ),
          const SizedBox(height: 20),
          Text('Reviews', style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder(
            future: _reviews,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return TravelerError(
                  'Could not load reviews.',
                  onRetry: () {
                    setState(
                      () => _reviews = widget.repository.reviews(
                        amigo['id'] as String,
                      ),
                    );
                  },
                );
              final reviews = snapshot.data;
              if (reviews == null) return const LinearProgressIndicator();
              if (reviews.isEmpty) return const Text('No reviews yet.');
              final average =
                  reviews.fold<int>(
                    0,
                    (sum, row) => sum + (row['rating'] as int),
                  ) /
                  reviews.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('★ ${average.toStringAsFixed(1)} (${reviews.length})'),
                  for (final review in reviews)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${review['rating']}/5 stars'),
                      subtitle: review['body'] == null
                          ? null
                          : Text(review['body'] as String),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
