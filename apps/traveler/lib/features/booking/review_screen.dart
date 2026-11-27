import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/traveler_ui.dart';
import '../discovery/amigo_photo.dart';
import '../discovery/discovery_repository.dart';
import 'booking_repository.dart';

const _muted = Color(0xFF756156);
const _gold = Color(0xFF9F650F);

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.repository,
    required this.booking,
    required this.amigo,
  });

  final BookingRepository repository;
  final BookingRow booking;
  final BookingRow amigo;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _text = TextEditingController();
  late final _bookingId = widget.booking['id'] as String;
  late final _amigoId = widget.booking['amigo_id'] as String;
  late Future<BookingRow?> _review;
  late final Future<List<BookingRow>> _amigoReviews;
  int _rating = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _review = widget.repository.review(_bookingId);
    _amigoReviews = DiscoveryRepository(
      widget.repository.client,
    ).reviews(_amigoId);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.reviewTrip(
        _bookingId,
        _amigoId,
        _rating,
        _text.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      if (error.code == '23505') {
        setState(() => _review = widget.repository.review(_bookingId));
      } else {
        notifyTraveler(context, 'Could not save your review. Try again.');
      }
    } catch (_) {
      if (mounted)
        notifyTraveler(context, 'Could not save your review. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Trip Complete'),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
        children: [
          Center(
            child: Image.asset(
              'assets/figma/review_complete.png',
              width: 191,
              height: 182,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          const Text(
            'You made it!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: travelerInk,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 38),
          _amigoCard(),
          const SizedBox(height: 20),
          FutureBuilder<BookingRow?>(
            future: _review,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return TravelerError(
                  'Could not load your review.',
                  onRetry: () {
                    setState(
                      () => _review = widget.repository.review(_bookingId),
                    );
                  },
                );
              }
              final saved = snapshot.data;
              return saved == null ? _form() : _savedReview(saved);
            },
          ),
        ],
      ),
    ),
  );

  Widget _amigoCard() {
    final amigo = widget.amigo;
    final localizations = MaterialLocalizations.of(context);
    final startsAt = philippineWallTime(
      DateTime.parse(widget.booking['starts_at'] as String),
    );
    final endsAt = philippineWallTime(
      DateTime.parse(widget.booking['ends_at'] as String),
    );
    final date = localizations.formatMediumDate(startsAt);
    final start = TimeOfDay.fromDateTime(startsAt).format(context);
    final end = TimeOfDay.fromDateTime(endsAt).format(context);
    final dateAndTime = DateUtils.isSameDay(startsAt, endsAt)
        ? '$date · $start – $end'
        : '$date · $start – ${localizations.formatMediumDate(endsAt)} · $end';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFF3E6DA)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          AmigoPhoto(amigo, width: 77, height: 77, radius: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amigo['display_name'] as String? ?? 'Amigo',
                  style: const TextStyle(
                    color: travelerInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                FutureBuilder<List<BookingRow>>(
                  future: _amigoReviews,
                  builder: (context, snapshot) {
                    final reviews = snapshot.data;
                    if (reviews == null || reviews.isEmpty)
                      return const SizedBox.shrink();
                    final average =
                        reviews.fold<int>(
                          0,
                          (sum, row) => sum + (row['rating'] as int),
                        ) /
                        reviews.length;
                    final count = reviews.length;
                    return Text(
                      '★ ${average.toStringAsFixed(1)} ($count ${count == 1 ? 'review' : 'reviews'})',
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
                Text(
                  dateAndTime,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (amigo['is_test'] == true)
                  const Text(
                    'Demo profile',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'How was your experience?',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: travelerInk,
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'Your feedback helps other travelers choose an Amigo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ),
      Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (var index = 1; index <= 5; index++)
              Semantics(
                selected: index == _rating,
                child: IconButton(
                  tooltip: index == 1 ? 'Rate 1 star' : 'Rate $index stars',
                  color: _gold,
                  icon: Icon(index <= _rating ? Icons.star : Icons.star_border),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _rating = index),
                ),
              ),
          ],
        ),
      ),
      Semantics(
        liveRegion: true,
        child: Text(
          _rating == 0
              ? 'Tap a star to rate your experience'
              : '$_rating of 5 stars',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Write a review (optional)',
        style: TextStyle(color: travelerInk, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _text,
        enabled: !_saving,
        minLines: 2,
        maxLines: 4,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration:
            travelerField(
              '',
              hint: 'Share what you liked about your trip…',
            ).copyWith(
              fillColor: Colors.white,
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
      ),
      const SizedBox(height: 12),
      TravelerButton(
        _saving ? 'Saving…' : 'Submit Review',
        _rating == 0 || _saving ? null : _submit,
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text(
          'Maybe later',
          style: TextStyle(color: travelerRust, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  Widget _savedReview(BookingRow review) => TravelerCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your review',
          style: TextStyle(
            color: travelerInk,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          '${review['rating']} of 5 stars',
          style: const TextStyle(color: _gold),
        ),
        if (review['body'] case final String text) Text(text),
      ],
    ),
  );
}
