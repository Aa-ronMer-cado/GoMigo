import 'package:flutter/material.dart';

import 'amigo_booking_repository.dart';
import 'booking_widgets.dart';

class AmigoBookingHistoryScreen extends StatefulWidget {
  const AmigoBookingHistoryScreen({
    super.key,
    required this.repository,
    required this.onOpenBooking,
    this.onOpenMap,
    this.messagesOnly = false,
    this.pendingOnly = false,
  });

  final AmigoBookingRepository repository;
  final ValueChanged<AmigoBooking> onOpenBooking;
  final ValueChanged<AmigoBooking>? onOpenMap;
  final bool messagesOnly;
  final bool pendingOnly;

  @override
  State<AmigoBookingHistoryScreen> createState() =>
      _AmigoBookingHistoryScreenState();
}

class _AmigoBookingHistoryScreenState extends State<AmigoBookingHistoryScreen> {
  late Stream<List<AmigoBooking>> _bookings = widget.repository.history();
  String? _filter;

  bool get _isHistory => !widget.messagesOnly && !widget.pendingOnly;

  void _retry() => setState(() => _bookings = widget.repository.history());

  @override
  Widget build(BuildContext context) {
    final title = widget.messagesOnly
        ? 'Messages'
        : widget.pendingOnly
        ? 'Booking Requests'
        : 'Booking History';
    return Scaffold(
      appBar: bookingHeader(context, title),
      body: StreamBuilder(
        stream: _bookings,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: BookingRetry('Could not load bookings.', onRetry: _retry),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final visible = snapshot.data!.where((booking) {
            if (widget.messagesOnly) return booking.hasConversation;
            if (widget.pendingOnly) return booking.status == 'pending';
            return _filter == null || booking.status == _filter;
          }).toList();
          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 16, 20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_isHistory) ...[
                  const Text(
                    'Keep track of your Traveler bookings.',
                    style: TextStyle(color: bookingMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (label, filter) in <(String, String?)>[
                        ('All', null),
                        ('Completed', 'completed'),
                        ('Cancelled', 'cancelled'),
                        ('Upcoming', 'accepted'),
                        ('Declined', 'declined'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          labelStyle: TextStyle(
                            color: _filter == filter
                                ? Colors.white
                                : bookingMuted,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: bookingPaper,
                          selectedColor: bookingRust,
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (snapshot.hasError)
                  BookingRetry(
                    'Live updates are unavailable.',
                    onRetry: _retry,
                  ),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      widget.messagesOnly
                          ? 'You can message a Traveler once you accept their booking.'
                          : widget.pendingOnly
                          ? 'No new booking requests.'
                          : 'No bookings to show.',
                    ),
                  ),
                for (final booking in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HistoryCard(
                      booking: booking,
                      action: widget.messagesOnly
                          ? 'Open chat'
                          : booking.status == 'completed' &&
                                widget.onOpenMap != null
                          ? 'View route'
                          : 'View details',
                      onAction:
                          booking.status == 'completed' &&
                              !widget.messagesOnly &&
                              widget.onOpenMap != null
                          ? () => widget.onOpenMap!(booking)
                          : () => widget.onOpenBooking(booking),
                      onOpen: () => widget.onOpenBooking(booking),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.booking,
    required this.action,
    required this.onAction,
    required this.onOpen,
  });

  final AmigoBooking booking;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final positive = booking.hasConversation;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BookingAvatar(booking.travelerName),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.travelerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      bookingStatus(booking.status),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: positive ? bookingGreen : bookingRust,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                bookingSchedule(context, booking),
                style: const TextStyle(fontSize: 13),
              ),
              Row(
                children: [
                  bookingAsset('area_pin'),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      booking.meetingPoint,
                      style: const TextStyle(color: bookingMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    backgroundColor: bookingSage,
                    foregroundColor: bookingInk,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(48, 34),
                    shape: const StadiumBorder(),
                  ),
                  label: Text(
                    action,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: bookingAsset('chevron_forward'),
                  iconAlignment: IconAlignment.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
