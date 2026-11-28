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
  late Future<Map<String, double>> _ratings;
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
    if (!widget.messages) _ratings = widget.repository.amigoRatings();
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
    backgroundColor: widget.messages ? null : const Color(0xFFFAEFE5),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                children: [
                  if (!widget.messages) ...[
                    const Text('Keep track of your traveler bookings.'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final filter in ['all', 'accepted', 'declined'])
                          ChoiceChip(
                            label: Text(statusLabel(filter)),
                            selected: (_status ?? 'all') == filter,
                            showCheckmark: false,
                            backgroundColor: Colors.white,
                            selectedColor: travelerSage,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            onSelected: (_) => setState(
                              () => _status = filter == 'all' ? null : filter,
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'More booking statuses',
                          initialValue: _status,
                          onSelected: (status) =>
                              setState(() => _status = status),
                          itemBuilder: (_) => [
                            for (final status in [
                              'pending',
                              'cancelled',
                              'completed',
                            ])
                              PopupMenuItem(
                                value: status,
                                child: Text(statusLabel(status)),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 4,
                            ),
                            child: switch (_status) {
                              'pending' ||
                              'cancelled' ||
                              'completed' => Text(statusLabel(_status!)),
                              _ => const Icon(
                                Icons.more_horiz,
                                color: travelerInk,
                              ),
                            },
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
                    if (widget.messages)
                      _message(
                        booking,
                        catalog[booking['amigo_id']] ??
                            {'display_name': 'Amigo'},
                      )
                    else
                      FutureBuilder(
                        future: _ratings,
                        builder: (context, ratings) {
                          final amigo =
                              catalog[booking['amigo_id']] ??
                              {'display_name': 'Amigo'};
                          return _HistoryCard(
                            booking: booking,
                            amigo: amigo,
                            rating: ratings.data?[booking['amigo_id']],
                            onTap: () => _open(booking, amigo),
                          );
                        },
                      ),
                ],
              ),
            );
          },
        );
      },
    ),
  );

  Widget _message(BookingRow booking, BookingRow amigo) {
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
            ],
          ),
          onTap: () => _open(booking, amigo),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.booking,
    required this.amigo,
    required this.rating,
    required this.onTap,
  });
  final BookingRow booking;
  final BookingRow amigo;
  final double? rating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String;
    final (badge, statusColor) = switch (status) {
      'accepted' ||
      'completed' => (const Color(0xFF6B8F71), const Color(0xFF36563A)),
      'declined' ||
      'cancelled' => (const Color(0xFFDA7770), const Color(0xFF9A342A)),
      _ => (travelerRust, travelerInk),
    };
    final name = amigo['display_name'] as String;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final start = philippineWallTime(
      DateTime.parse(booking['starts_at'] as String),
    );
    final end = philippineWallTime(
      DateTime.parse(booking['ends_at'] as String),
    );
    final dates = MaterialLocalizations.of(context);
    final startDay = dates.formatMediumDate(start);
    final endDay = dates.formatMediumDate(end);
    final range =
        '$startDay · ${TimeOfDay.fromDateTime(start).format(context)} – '
        '${endDay == startDay ? '' : '$endDay · '}${TimeOfDay.fromDateTime(end).format(context)} PHT';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 3),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (amigo['photo_url'] != null ||
                            amigo['storage_photo_url'] != null)
                          AmigoPhoto(amigo, width: 50, height: 50, radius: 25)
                        else
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: const Color(0xFFE8D9CC),
                            child: Text(
                              initials,
                              style: const TextStyle(color: travelerInk),
                            ),
                          ),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: travelerInk,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (rating case final value?)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 16,
                                      color: Color(0xFFC18E4F),
                                    ),
                                    Text(value.toStringAsFixed(1)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      statusLabel(status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 5, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            range,
                            style: const TextStyle(color: travelerInk),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: travelerRust,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(booking['meeting_label'] as String),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 94,
                      minHeight: 65,
                    ),
                    padding: const EdgeInsets.fromLTRB(13, 15, 10, 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badge,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.elliptical(66, 49),
                      ),
                    ),
                    child: Text(
                      pesos(booking['total_centavos']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Color(0x99000000), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
