import 'package:flutter/material.dart';

import 'amigo_booking_repository.dart';
import 'amigo_decline_screen.dart';
import 'booking_widgets.dart';

class AmigoBookingDetailScreen extends StatefulWidget {
  const AmigoBookingDetailScreen({
    super.key,
    required this.repository,
    required this.booking,
    required this.onOpenChat,
    required this.onOpenMap,
    required this.onOpenSession,
    required this.onOpenReview,
  });

  final AmigoBookingRepository repository;
  final AmigoBooking booking;
  final ValueChanged<AmigoBooking> onOpenChat;
  final ValueChanged<AmigoBooking> onOpenMap;
  final ValueChanged<AmigoBooking> onOpenSession;
  final ValueChanged<AmigoBooking> onOpenReview;

  @override
  State<AmigoBookingDetailScreen> createState() =>
      _AmigoBookingDetailScreenState();
}

class _AmigoBookingDetailScreenState extends State<AmigoBookingDetailScreen> {
  late AmigoBooking _booking = widget.booking;
  late Stream<AmigoBooking?> _updates = widget.repository.watch(_booking);
  bool _saving = false;

  void _retry() => setState(() => _updates = widget.repository.watch(_booking));

  Future<void> _decline(AmigoBooking booking) async {
    final reason = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AmigoDeclineScreen(travelerName: booking.travelerName),
      ),
    );
    if (reason != null && mounted) {
      await _respond(booking, accept: false, reason: reason);
    }
  }

  Future<void> _respond(
    AmigoBooking booking, {
    required bool accept,
    String? reason,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.respond(
        booking,
        accept: accept,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _booking = updated;
        _updates = widget.repository.watch(updated);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Booking accepted.' : 'Booking declined.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bookingError(error, 'Could not update this booking. Try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _updates,
    initialData: _booking,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: bookingHeader(context, 'Booking Details'),
          body: Center(
            child: BookingRetry(
              'Could not load booking details.',
              onRetry: _retry,
            ),
          ),
        );
      }
      final booking = snapshot.connectionState == ConnectionState.waiting
          ? _booking
          : snapshot.data;
      if (booking == null) {
        return Scaffold(
          appBar: bookingHeader(context, 'Booking Request'),
          body: const Center(child: Text('This booking is unavailable.')),
        );
      }
      final pending = booking.status == 'pending';
      return Scaffold(
        appBar: bookingHeader(
          context,
          pending ? 'Booking Request' : 'Booking Details',
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(19, 22, 19, 24),
          children: [
            Center(child: BookingAvatar(booking.travelerName, radius: 61)),
            const SizedBox(height: 6),
            Text(
              booking.travelerName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                color: bookingInk,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (booking.travelerVerified)
                  'Verified Traveler'
                else
                  'Traveler',
                if (!pending) bookingStatus(booking.status),
              ].join('  •  '),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: bookingGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _BookingMetaTile(
                          'calendar',
                          bookingDate(context, booking.startsAt),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BookingMetaTile(
                          'meeting_pin',
                          booking.meetingPoint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _BookingMetaTile(
                          'clock',
                          '${bookingTime(context, booking.startsAt)} PHT',
                          label: 'Start time',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BookingMetaTile(
                          'clock',
                          '${bookingTime(context, booking.endsAt)} PHT',
                          label: 'End time',
                        ),
                      ),
                    ],
                  ),
                  if (bookingPhilippineTime(booking.startsAt).day !=
                      bookingPhilippineTime(booking.endsAt).day)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        'Ends on ${bookingDate(context, booking.endsAt)}',
                        style: const TextStyle(color: bookingMuted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Trip preferences / Itinerary',
              style: TextStyle(
                fontSize: 15,
                color: bookingInk,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              constraints: const BoxConstraints(minHeight: 75),
              decoration: BoxDecoration(
                color: bookingCream,
                border: Border.all(color: bookingBorder),
                borderRadius: BorderRadius.circular(13),
              ),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.centerLeft,
              child: Text(
                booking.notes.isEmpty
                    ? 'The Traveler hasn’t added any notes.'
                    : booking.notes,
                style: const TextStyle(color: bookingInk),
              ),
            ),
            const SizedBox(height: 20),
            _PriceBreakdown(booking: booking),
            const SizedBox(height: 16),
            if (booking.declineReason case final String reason)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Decline reason: $reason',
                  style: const TextStyle(color: bookingInk),
                ),
              ),
            if (pending)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _decline(booking),
                      style: bookingOutlineStyle(),
                      child: const Text('Decline request'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _respond(booking, accept: true),
                      style: bookingPrimaryStyle(),
                      child: const Text('Accept booking'),
                    ),
                  ),
                ],
              ),
            if (_saving) const LinearProgressIndicator(),
            if (booking.hasConversation) ...[
              Text(
                'Test payment · ${bookingStatus(booking.paymentStatus)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: bookingInk,
                ),
              ),
              const SizedBox(height: 8),
              if (booking.status == 'accepted')
                FilledButton(
                  onPressed: booking.paymentStatus == 'paid'
                      ? () => widget.onOpenSession(booking)
                      : null,
                  style: bookingPrimaryStyle(),
                  child: const Text('Trip session'),
                ),
              if (booking.status == 'accepted' &&
                  booking.paymentStatus != 'paid')
                const Text(
                  'The trip session opens after the Traveler’s test payment is confirmed.',
                  style: TextStyle(color: bookingMuted),
                ),
              if (booking.status == 'completed')
                FilledButton(
                  onPressed: () => widget.onOpenReview(booking),
                  style: bookingPrimaryStyle(),
                  child: const Text('Rating and review'),
                ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => widget.onOpenChat(booking),
                style: bookingOutlineStyle(),
                child: const Text('Open chat'),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => widget.onOpenMap(booking),
                style: bookingOutlineStyle(),
                child: Text(
                  booking.status == 'completed'
                      ? 'View recorded route'
                      : 'Meetup map',
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _BookingMetaTile extends StatelessWidget {
  const _BookingMetaTile(this.asset, this.value, {this.label});

  final String asset;
  final String value;
  final String? label;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    shadowColor: const Color(0x55000000),
    borderRadius: BorderRadius.circular(14),
    color: bookingPaper,
    child: Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          bookingAsset(asset),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: const TextStyle(color: bookingMuted, fontSize: 12),
                  ),
                Text(
                  value,
                  style: const TextStyle(
                    color: bookingInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({required this.booking});

  final AmigoBooking booking;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: bookingPaper,
      border: Border.all(color: bookingBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ColoredBox(
          color: Color(0xFFECDED2),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Estimated Price',
              style: TextStyle(
                fontSize: 18,
                color: bookingInk,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _line('Booking subtotal', booking.subtotalCentavos),
              _line('Service fee', booking.feeCentavos),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: bookingAsset('price_divider'),
              ),
              _line('Total', booking.totalCentavos, total: true),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _line(String label, int amount, {bool total = false}) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: bookingInk,
            fontWeight: total ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          bookingPesos(amount),
          textAlign: TextAlign.end,
          style: const TextStyle(
            color: bookingInk,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}
