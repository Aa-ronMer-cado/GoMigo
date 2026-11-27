import 'dart:async';

import 'package:flutter/material.dart';

import '../../navigation/amigo_ui.dart';
import 'session_repository.dart';

class AmigoSessionControls extends StatefulWidget {
  const AmigoSessionControls({
    super.key,
    required this.repository,
    required this.booking,
    required this.session,
    required this.onReview,
    required this.onChanged,
  });
  final AmigoSessionRepository repository;
  final Map<String, dynamic> booking;
  final Map<String, dynamic>? session;
  final VoidCallback onReview;
  final VoidCallback onChanged;

  @override
  State<AmigoSessionControls> createState() => _AmigoSessionControlsState();
}

class _AmigoSessionControlsState extends State<AmigoSessionControls> {
  late final Timer _clock;
  bool _busy = false;
  String? _alert;
  String? _error;

  DateTime get _scheduledStart =>
      DateTime.parse(widget.booking['starts_at'] as String);
  DateTime get _scheduledEnd =>
      DateTime.parse(widget.booking['ends_at'] as String);
  DateTime? get _started =>
      DateTime.tryParse(widget.session?['started_at'] as String? ?? '');
  DateTime? get _ended =>
      DateTime.tryParse(widget.session?['ended_at'] as String? ?? '');

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final previous = _alert;
      final left = _scheduledEnd.difference(DateTime.now());
      setState(
        () => _alert = _started != null && _ended == null
            ? left <= Duration.zero
                  ? 'The scheduled end time has arrived.'
                  : left <= const Duration(minutes: 5)
                  ? 'Your trip is due to end in five minutes or less.'
                  : null
            : null,
      );
      if (_alert != null &&
          _alert != previous &&
          ModalRoute.isCurrentOf(context) == true) {
        amigoNotice(context, _alert!);
      }
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  Future<void> _change({required bool complete}) async {
    if (_busy) return;
    if (complete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Complete this trip?'),
          content: const Text(
            'This ends the shared session and stops live location sharing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep going'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Complete trip'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || _busy) return;
    }
    setState(() => _busy = true);
    try {
      if (complete) {
        await widget.repository.complete();
      } else {
        await widget.repository.start();
      }
      if (mounted) {
        setState(() => _error = null);
        widget.onChanged();
        if (complete) widget.onReview();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not update the session. Check the booking status and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateTime(DateTime instant) {
    final time = manilaTime(instant);
    return '${MaterialLocalizations.of(context).formatMediumDate(time)}'
        ' · ${TimeOfDay.fromDateTime(time).format(context)} PHT';
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.booking['status'];
    if (status != 'accepted' && status != 'completed') {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final started = _started;
    final ended = _ended;
    final remaining = _scheduledEnd.difference(now);
    final paid = widget.booking['payment_status'] == 'paid';
    final canStart =
        paid &&
        !now.isBefore(_scheduledStart.subtract(const Duration(minutes: 15))) &&
        now.isBefore(_scheduledEnd);
    final completed = status == 'completed' || ended != null;
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              completed
                  ? 'Trip complete'
                  : started == null
                  ? 'Session'
                  : 'Together now',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              started == null
                  ? 'Scheduled start · ${_dateTime(_scheduledStart)}'
                  : 'Started · ${_dateTime(started)}',
            ),
            Text(
              ended == null
                  ? 'Scheduled end · ${_dateTime(_scheduledEnd)}'
                  : 'Ended · ${_dateTime(ended)}',
            ),
            if (!completed && started != null) ...[
              const SizedBox(height: 7),
              Text(
                '${sessionCountdown(remaining)} until goodbye',
                style: const TextStyle(
                  color: amigoRust,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_alert case final alert?)
                Semantics(liveRegion: true, child: Text(alert)),
              FilledButton(
                onPressed: _busy ? null : () => _change(complete: true),
                child: const Text('Complete trip'),
              ),
            ] else if (completed)
              OutlinedButton(
                onPressed: widget.onReview,
                child: const Text('Rate traveler'),
              )
            else ...[
              if (!paid)
                const Text('Waiting for the traveler’s test payment.')
              else if (!canStart)
                Text(
                  now.isBefore(_scheduledStart)
                      ? 'You can start within 15 minutes of the booking time.'
                      : 'The scheduled booking window has ended.',
                ),
              FilledButton(
                onPressed: _busy || !canStart
                    ? null
                    : () => _change(complete: false),
                child: const Text('Start session'),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Semantics(liveRegion: true, child: Text(error)),
          ],
        ),
      ),
    );
  }
}

String sessionCountdown(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(0, 1 << 31);
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$rest' : '$minutes:$rest';
}
