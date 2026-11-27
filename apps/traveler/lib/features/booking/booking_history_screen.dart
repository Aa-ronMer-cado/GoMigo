import 'package:flutter/material.dart';

import '../../navigation/traveler_ui.dart';
import '../chat/chat_screen.dart';
import '../discovery/amigo_photo.dart';
import 'booking_detail_screen.dart';
import 'booking_repository.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({
    super.key,
    required this.repository,
    this.messages = false,
  });
  final BookingRepository repository;
  final bool messages;

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  late Stream<List<BookingRow>> _history;
  late Future<List<BookingRow>> _amigos;
  late Future<bool> _demo;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _history = widget.repository.history();
    _amigos = widget.repository.amigos();
    _demo = widget.repository.demoEnabled().catchError((_) => false);
  }

  Future<void> _open(BookingRow booking, BookingRow amigo) async {
    final demo = widget.messages ? await _demo : false;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => widget.messages
            ? ChatScreen(
                repository: widget.repository,
                booking: booking,
                amigo: amigo,
                demoEnabled: demo && amigo['is_test'] == true,
              )
            : BookingDetailScreen(
                repository: widget.repository,
                booking: booking,
                amigo: amigo,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader(widget.messages ? 'Messages' : 'Booking History'),
    body: FutureBuilder(
      future: _amigos,
      builder: (context, amigoSnapshot) {
        if (amigoSnapshot.hasError)
          return TravelerError(
            'Could not load booking details.',
            onRetry: () => setState(_load),
          );
        if (!amigoSnapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final catalog = {
          for (final amigo in amigoSnapshot.data!) amigo['id']: amigo,
        };
        return StreamBuilder(
          stream: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return TravelerError(
                'Could not load bookings.',
                onRetry: () => setState(_load),
              );
            final rows = snapshot.data;
            if (rows == null)
              return const Center(child: CircularProgressIndicator());
            final visible = rows.where((row) {
              final status = row['status'];
              return widget.messages
                  ? status == 'accepted' || status == 'completed'
                  : _status == null || status == _status;
            });
            return RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (!widget.messages) ...[
                    const Text('Keep track of your bookings.'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      children: [
                        for (final filter in [
                          'all',
                          'pending',
                          'accepted',
                          'declined',
                          'cancelled',
                          'completed',
                        ])
                          ChoiceChip(
                            label: Text(statusLabel(filter)),
                            selected: (_status ?? 'all') == filter,
                            onSelected: (_) => setState(
                              () => _status = filter == 'all' ? null : filter,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        widget.messages
                            ? 'Messages appear after an Amigo accepts a booking.'
                            : rows.isEmpty
                            ? 'You have no bookings yet.'
                            : 'No ${_status ?? ''} bookings.',
                      ),
                    ),
                  for (final booking in visible)
                    _booking(
                      booking,
                      catalog[booking['amigo_id']] ?? {'display_name': 'Amigo'},
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );

  Widget _booking(BookingRow booking, BookingRow amigo) {
    final date = philippineWallTime(
      DateTime.parse(booking['starts_at'] as String),
    );
    final dateLabel = MaterialLocalizations.of(context).formatMediumDate(date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TravelerCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: AmigoPhoto(amigo, width: 46, height: 46, radius: 24),
          title: Text(
            amigo['display_name'] as String,
            style: const TextStyle(
              color: travelerInk,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            '$dateLabel · ${TimeOfDay.fromDateTime(date).format(context)} PHT\n${booking['meeting_label']}',
          ),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                statusLabel(booking['status'] as String),
                style: const TextStyle(fontSize: 12),
              ),
              if (!widget.messages)
                Text(
                  pesos(booking['total_centavos']),
                  style: const TextStyle(
                    color: travelerRust,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          onTap: () => _open(booking, amigo),
        ),
      ),
    );
  }
}
