import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../navigation/traveler_ui.dart';
import '../chat/chat_screen.dart';
import '../discovery/amigo_photo.dart';
import '../meetup/meetup_screen.dart';
import '../payments/test_payment_repository.dart';
import 'booking_repository.dart';
import 'review_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.repository,
    required this.booking,
    required this.amigo,
  });
  final BookingRepository repository;
  final BookingRow booking;
  final BookingRow amigo;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen>
    with WidgetsBindingObserver {
  late BookingRow _booking = widget.booking;
  String get _id => _booking['id'] as String;
  late Stream<List<BookingRow>> _updates = widget.repository.watch(_id);
  late final Stream<List<BookingRow>> _session = widget.repository.session(_id);
  late final Future<bool> _demo = widget.amigo['is_test'] == true
      ? widget.repository.demoEnabled().catchError((_) => false)
      : Future.value(false);
  late final Timer _clock;
  DateTime _now = DateTime.now();
  bool _busy = false;
  bool _checkoutLaunched = false;
  Uri? _checkout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _checkoutLaunched && !_busy) {
      _checkoutLaunched = false;
      unawaited(_payment('status'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } on PostgrestException catch (error) {
      if (mounted) notifyTraveler(context, error.message);
    } on FunctionException catch (error) {
      if (mounted) {
        notifyTraveler(
          context,
          error.status == 503
              ? 'PayMongo test checkout is not configured or temporarily unavailable.'
              : 'Could not update test checkout. Try again.',
        );
      }
    } catch (_) {
      if (mounted)
        notifyTraveler(
          context,
          'Could not finish the request. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payment(String action) => _run(() async {
    final result = await TestPaymentRepository(
      widget.repository.client,
    ).checkout(_id, action);
    if (!mounted) return;
    setState(() {
      _checkout = result.checkout;
      _updates = widget.repository.watch(_id);
    });
    if (action != 'open' || result.checkout == null) {
      notifyTraveler(context, 'Test payment: ${statusLabel(result.status)}.');
    }
  });

  Future<void> _openCheckout() => _run(() async {
    final checkout = _checkout;
    if (checkout == null) return;
    _checkoutLaunched = true;
    if (!await launchUrl(checkout, mode: LaunchMode.externalApplication)) {
      _checkoutLaunched = false;
      if (mounted) notifyTraveler(context, 'Could not open the PayMongo page.');
    }
  });

  Future<void> _confirm(String question, String button, String action) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(button),
          ),
        ],
      ),
    );
    if (confirm == true && mounted)
      await _run(() => widget.repository.action(action, _id));
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  String _schedule(DateTime instant) {
    final time = philippineWallTime(instant);
    return '${MaterialLocalizations.of(context).formatMediumDate(time)} · ${TimeOfDay.fromDateTime(time).format(context)} PHT';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _updates,
    builder: (context, snapshot) {
      // Keep an existing authorized view on a transient error. An empty
      // successful result means the booking can no longer be read.
      final rows = snapshot.data;
      if (rows != null && rows.isEmpty) {
        return Scaffold(
          appBar: travelerHeader('Booking'),
          body: const TravelerError('This booking is unavailable.'),
        );
      }
      if (rows != null) _booking = rows.first;
      final status = _booking['status'] as String;
      final payment = _booking['payment_status'] as String;
      final start = DateTime.parse(_booking['starts_at'] as String);
      final end = DateTime.parse(_booking['ends_at'] as String);
      return Scaffold(
        appBar: travelerHeader(
          status == 'completed' ? 'Trip Complete' : 'Booking',
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (snapshot.hasError)
              TravelerError(
                'Live updates are unavailable.',
                onRetry: () =>
                    setState(() => _updates = widget.repository.watch(_id)),
              ),
            if (status == 'pending' || status == 'declined') ...[
              Image.asset(
                'assets/figma/booking_$status.png',
                height: 220,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 14),
              Text(
                status == 'pending' ? 'Holding your spot…' : 'Booking declined',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: travelerInk,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (status == 'pending') ...[
              const TravelerCard(
                child: Row(
                  children: [
                    TravelerAsset('booking_pending_clock', size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Waiting for your Amigo to confirm.')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            TravelerCard(
              child: Row(
                children: [
                  AmigoPhoto(widget.amigo, width: 68, height: 68, radius: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.amigo['display_name'] as String? ?? 'Amigo',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: travelerInk,
                          ),
                        ),
                        Text(statusLabel(status)),
                        if (widget.amigo['is_test'] == true)
                          const Text('Demo booking'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TravelerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Starts ${_schedule(start)}'),
                  Text('Ends ${_schedule(end)}'),
                  const SizedBox(height: 8),
                  Text(_booking['meeting_label'] as String),
                  if ((_booking['notes'] as String? ?? '').isNotEmpty)
                    Text(_booking['notes'] as String),
                  if (_booking['decline_reason'] case final String reason)
                    Text(reason),
                  const Divider(),
                  Text('Amigo time  ${pesos(_booking['subtotal_centavos'])}'),
                  Text('Service fee  ${pesos(_booking['fee_centavos'])}'),
                  Text(
                    'Total  ${pesos(_booking['total_centavos'])}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder(
              future: _demo,
              builder: (context, demo) {
                if (demo.data != true || status != 'pending')
                  return const SizedBox.shrink();
                return TravelerCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Demo only · Simulated Amigo response'),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => widget.repository.action(
                                      'simulate_amigo_response',
                                      _id,
                                      {
                                        'p_decision': 'accepted',
                                        'p_reason': null,
                                      },
                                    ),
                                  ),
                            child: const Text('Simulate acceptance'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => widget.repository.action(
                                      'simulate_amigo_response',
                                      _id,
                                      {
                                        'p_decision': 'declined',
                                        'p_reason':
                                            'Simulated decline for this demo.',
                                      },
                                    ),
                                  ),
                            child: const Text('Simulate decline'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            if (status == 'accepted') ...[
              Text(
                'PayMongo test payment · ${statusLabel(payment)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (payment != 'paid' && end.isAfter(_now)) ...[
                TravelerButton(
                  _checkout != null
                      ? 'Continue to PayMongo'
                      : 'Prepare test checkout',
                  _busy
                      ? null
                      : _checkout == null
                      ? () => _payment('open')
                      : _openCheckout,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _payment('status'),
                      child: const Text('Refresh payment'),
                    ),
                    if (payment == 'pending' || payment == 'failed')
                      TextButton(
                        onPressed: _busy ? null : () => _payment('cancel'),
                        child: const Text('Cancel test checkout'),
                      ),
                  ],
                ),
              ],
              if (payment == 'paid') _sessionControls(start, end),
            ],
            if (status == 'accepted' || status == 'completed') ...[
              const SizedBox(height: 8),
              FutureBuilder(
                future: _demo,
                builder: (context, demo) => OutlinedButton(
                  onPressed: () => _open(
                    ChatScreen(
                      repository: widget.repository,
                      booking: _booking,
                      amigo: widget.amigo,
                      demoEnabled: demo.data == true,
                    ),
                  ),
                  child: const Text('Open chat'),
                ),
              ),
              OutlinedButton(
                onPressed: () => _open(
                  MeetupScreen(
                    client: widget.repository.client,
                    booking: _booking,
                    amigo: widget.amigo,
                  ),
                ),
                child: Text(
                  status == 'completed' ? 'View recorded route' : 'Meetup map',
                ),
              ),
            ],
            if (status == 'completed') ...[
              StreamBuilder(
                stream: _session,
                builder: (context, snapshot) {
                  final session = snapshot.data?.firstOrNull;
                  if (session == null) return const SizedBox.shrink();
                  final actualStart = DateTime.parse(
                    session['started_at'] as String,
                  );
                  final actualEnd = DateTime.tryParse(
                    session['ended_at'] as String? ?? '',
                  );
                  return TravelerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Started ${_schedule(actualStart)}'),
                        if (actualEnd != null)
                          Text('Ended ${_schedule(actualEnd)}'),
                      ],
                    ),
                  );
                },
              ),
              TravelerButton(
                'Rating and review',
                () => _open(
                  ReviewScreen(
                    repository: widget.repository,
                    booking: _booking,
                    amigo: widget.amigo,
                  ),
                ),
              ),
            ],
            if ((status == 'pending' || status == 'accepted') &&
                (payment == 'unpaid' || payment == 'cancelled'))
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _confirm(
                        'Cancel this booking?',
                        'Cancel booking',
                        'cancel_booking',
                      ),
                child: const Text('Cancel booking'),
              ),
          ],
        ),
      );
    },
  );

  Widget _sessionControls(DateTime start, DateTime end) => StreamBuilder(
    stream: _session,
    builder: (context, snapshot) {
      if (snapshot.hasError && !snapshot.hasData) {
        return const Text('Session status is temporarily unavailable.');
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final active = snapshot.data!.firstOrNull;
      if (active == null) {
        final available =
            !_now.isBefore(start.subtract(const Duration(minutes: 15))) &&
            _now.isBefore(end);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!available)
              Text(
                _now.isBefore(start)
                    ? 'You can start within 15 minutes of the scheduled time.'
                    : 'The scheduled session window has ended.',
              ),
            TravelerButton(
              'Start session',
              _busy || !available
                  ? null
                  : () => _run(
                      () => widget.repository.action(
                        'start_booking_session',
                        _id,
                      ),
                    ),
            ),
          ],
        );
      }
      final seconds = (end.difference(_now).inMilliseconds / 1000).ceil();
      final minutes = seconds ~/ 60;
      return TravelerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Started ${_schedule(DateTime.parse(active['started_at'] as String))}',
            ),
            Text(
              seconds > 0
                  ? '${minutes}m ${(seconds % 60).toString().padLeft(2, '0')}s until goodbye'
                  : 'Scheduled time is up',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: travelerRust,
              ),
            ),
            if (seconds <= 300)
              Semantics(
                liveRegion: true,
                child: Text(
                  seconds > 0
                      ? 'Your session ends soon.'
                      : 'Complete the trip when ready.',
                ),
              ),
            TravelerButton(
              'Complete trip',
              _busy
                  ? null
                  : () => _confirm(
                      'Complete this trip?',
                      'Complete trip',
                      'complete_booking_session',
                    ),
            ),
          ],
        ),
      );
    },
  );
}
