import 'package:flutter/material.dart';

import '../booking/amigo_booking_repository.dart';
import '../booking/booking_widgets.dart';
import '../earnings/amigo_earnings_repository.dart';

class AmigoHomeScreen extends StatefulWidget {
  const AmigoHomeScreen({
    super.key,
    required this.repository,
    required this.amigoName,
    required this.onOpenBooking,
    required this.onViewAll,
    required this.onOpenEarnings,
    this.onOpenMessages,
    this.onOpenNotifications,
  });

  final AmigoBookingRepository repository;
  final String amigoName;
  final ValueChanged<AmigoBooking> onOpenBooking;
  final VoidCallback onViewAll;
  final VoidCallback onOpenEarnings;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenNotifications;

  @override
  State<AmigoHomeScreen> createState() => _AmigoHomeScreenState();
}

class _AmigoHomeScreenState extends State<AmigoHomeScreen> {
  late Stream<List<AmigoBooking>> _bookings = widget.repository.history();
  late Future<Map<String, dynamic>?> _profile = widget.repository
      .availability();
  late Future<DemoEarnings> _earnings = _loadEarnings();
  bool? _savedAvailability;
  bool _savingAvailability = false;

  Future<DemoEarnings> _loadEarnings() =>
      AmigoEarningsRepository(widget.repository.client).load();

  Future<void> _refresh() async {
    setState(() {
      _bookings = widget.repository.history();
      _profile = widget.repository.availability();
      _earnings = _loadEarnings();
      _savedAvailability = null;
    });
    // The individual cards display their own load errors.
    await Future.wait<void>([
      _profile.then<void>((_) {}, onError: (Object _) {}),
      _earnings.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  Future<void> _setAvailability(bool value) async {
    if (_savingAvailability) return;
    setState(() => _savingAvailability = true);
    try {
      final saved = await widget.repository.setAvailable(value);
      if (mounted) setState(() => _savedAvailability = saved);
    } catch (error) {
      if (!mounted) return;
      final message = bookingError(error, 'Could not update availability.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _savingAvailability = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: bookingSage,
      foregroundColor: bookingInk,
      elevation: 0,
      title: Semantics(
        label: 'GoMigo',
        header: true,
        child: Row(
          children: [
            bookingAsset('brand_mark'),
            const SizedBox(width: 8),
            bookingAsset('brand_word'),
          ],
        ),
      ),
      actions: [
        if (widget.onOpenMessages != null)
          IconButton(
            tooltip: 'Messages',
            onPressed: widget.onOpenMessages,
            icon: bookingAsset('message'),
          ),
        if (widget.onOpenNotifications != null)
          IconButton(
            tooltip: 'Booking notifications',
            onPressed: widget.onOpenNotifications,
            icon: bookingAsset('notification_bell'),
          ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Welcome, ${widget.amigoName}!',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: bookingInk,
              ),
            ),
            const SizedBox(height: 9),
            _availability(),
            const SizedBox(height: 15),
            _earningsOverview(),
            const SizedBox(height: 17),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Booking requests',
                    style: TextStyle(
                      fontSize: 19,
                      color: bookingInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onViewAll,
                  style: TextButton.styleFrom(foregroundColor: bookingRust),
                  child: const Text('View all'),
                ),
              ],
            ),
            _incoming(),
          ],
        ),
      ),
    ),
  );

  Widget _availability() => FutureBuilder(
    future: _profile,
    builder: (context, state) {
      if (state.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
      }
      final profile = state.data;
      if (state.hasError || profile == null) {
        return BookingRetry(
          'Could not load your availability.',
          onRetry: _refresh,
        );
      }
      final available = _savedAvailability ?? profile['available'] == true;
      final action = _savingAvailability
          ? null
          : () => _setAvailability(!available);
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: bookingPaper,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    available
                        ? 'Available for requests'
                        : 'Unavailable for requests',
                    style: const TextStyle(
                      color: bookingInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (profile['area'] case final String area
                      when area.isNotEmpty)
                    Row(
                      children: [
                        bookingAsset('area_pin'),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            area,
                            style: const TextStyle(color: bookingMuted),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Semantics(
              toggled: available,
              enabled: action != null,
              label: 'Accept booking requests',
              onTap: action,
              excludeSemantics: true,
              child: SizedBox.square(
                dimension: 48,
                child: IconButton(
                  onPressed: action,
                  tooltip: available
                      ? 'Turn off availability'
                      : 'Turn on availability',
                  icon: _savingAvailability
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : available
                      ? bookingAsset('availability_on')
                      : const Icon(
                          Icons.toggle_off_outlined,
                          color: bookingMuted,
                          size: 26,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _earningsOverview() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: bookingGradient,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
      child: FutureBuilder(
        future: _earnings,
        builder: (context, state) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulated earnings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (state.hasError)
                    const Text(
                      'Balance unavailable',
                      style: TextStyle(color: Colors.white),
                    )
                  else if (state.data case final demo?)
                    Text(
                      bookingPesos(demo.available),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: LinearProgressIndicator(
                        semanticsLabel: 'Loading balance',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            IconButton.filled(
              onPressed: widget.onOpenEarnings,
              tooltip: 'Open earnings',
              style: IconButton.styleFrom(
                backgroundColor: bookingSage,
                foregroundColor: bookingInk,
              ),
              icon: bookingAsset('chevron_forward'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _incoming() => StreamBuilder(
    stream: _bookings,
    builder: (context, state) {
      if (state.hasError && !state.hasData) {
        return BookingRetry(
          'Could not load booking requests.',
          onRetry: () =>
              setState(() => _bookings = widget.repository.history()),
        );
      }
      if (!state.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final pending = state.data!
          .where((booking) => booking.status == 'pending')
          .take(3)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.hasError)
            BookingRetry(
              'Live booking updates are unavailable.',
              onRetry: () =>
                  setState(() => _bookings = widget.repository.history()),
            ),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No new booking requests.',
                style: TextStyle(color: bookingMuted),
              ),
            ),
          for (final booking in pending)
            Card(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                onTap: () => widget.onOpenBooking(booking),
                leading: BookingAvatar(booking.travelerName, radius: 21),
                title: Text(
                  booking.travelerName,
                  style: const TextStyle(
                    color: bookingInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  '${bookingSchedule(context, booking)}\n${booking.meetingPoint}',
                ),
                trailing: bookingAsset('chevron_forward'),
              ),
            ),
        ],
      );
    },
  );
}
