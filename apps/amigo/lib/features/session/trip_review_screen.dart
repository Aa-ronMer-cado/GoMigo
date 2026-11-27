import 'package:flutter/material.dart';

import '../../navigation/amigo_ui.dart';
import 'session_repository.dart';

class AmigoTripReviewScreen extends StatefulWidget {
  const AmigoTripReviewScreen({
    super.key,
    required this.repository,
    required this.travelerName,
    required this.startsAt,
    required this.endsAt,
    this.navigation,
  });
  final AmigoSessionRepository repository;
  final String travelerName;
  final DateTime startsAt;
  final DateTime endsAt;
  final Widget? navigation;

  @override
  State<AmigoTripReviewScreen> createState() => _AmigoTripReviewScreenState();
}

class _AmigoTripReviewScreenState extends State<AmigoTripReviewScreen> {
  final _body = TextEditingController();
  late var _review = widget.repository.review();
  int _rating = 0;
  bool _saving = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating == 0 || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.rateTraveler(_rating, _body.text.trim());
      if (mounted) setState(() => _review = widget.repository.review());
    } catch (_) {
      if (mounted) {
        amigoNotice(context, 'Could not save your review. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = manilaTime(widget.startsAt);
    final end = manilaTime(widget.endsAt);
    final localizations = MaterialLocalizations.of(context);
    final dates = DateUtils.isSameDay(start, end)
        ? localizations.formatMediumDate(start)
        : '${localizations.formatMediumDate(start)} – ${localizations.formatMediumDate(end)}';
    final times =
        '${TimeOfDay.fromDateTime(start).format(context)} – ${TimeOfDay.fromDateTime(end).format(context)}';
    return Scaffold(
      appBar: amigoHeader('Trip Complete', leading: const AmigoBackButton()),
      bottomNavigationBar: widget.navigation,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          children: [
            Center(
              child: Image.asset(
                'assets/figma/amigo_trip_complete.png',
                width: 190.703,
                height: 182.437,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            const Text(
              'You made it!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: amigoInk,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 26),
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(13),
                leading: const TravelerAvatar(),
                title: Text(
                  widget.travelerName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('$dates · $times PHT'),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder(
              future: _review,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.hasError) {
                  return Column(
                    children: [
                      const Text('Could not load your review.'),
                      TextButton(
                        onPressed: () => setState(
                          () => _review = widget.repository.review(),
                        ),
                        child: const Text('Try again'),
                      ),
                    ],
                  );
                }
                final saved = state.data;
                if (saved != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review saved · ${saved['rating']} out of 5',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (saved['body'] case final String body) Text(body),
                    ],
                  );
                }
                return _form(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'How was your experience?',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: amigoInk,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      Center(
        child: Wrap(
          children: [
            for (var rating = 1; rating <= 5; rating++)
              IconButton(
                tooltip: 'Rate $rating out of 5',
                isSelected: rating <= _rating,
                onPressed: _saving
                    ? null
                    : () => setState(() => _rating = rating),
                icon: Icon(
                  rating <= _rating ? Icons.star : Icons.star_border,
                  color: const Color(0xFF9F650F),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 9),
      TextField(
        controller: _body,
        enabled: !_saving,
        minLines: 2,
        maxLines: 4,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Write a review (optional)',
          hintText: 'Share what you liked about your trip…',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: amigoRust,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _saving || _rating == 0 ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Submit review'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.maybePop(context),
        child: const Text('Maybe later'),
      ),
    ],
  );
}
