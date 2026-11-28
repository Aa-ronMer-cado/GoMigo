import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/meetup.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../navigation/traveler_ui.dart';
import '../discovery/amigo_photo.dart';
import '../meetup/meetup_screen.dart';
import 'booking_repository.dart';

class BookingFormScreen extends StatefulWidget {
  const BookingFormScreen({
    super.key,
    required this.repository,
    required this.amigo,
  });
  final BookingRepository repository;
  final BookingRow amigo;

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _meeting = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  LatLng? _pin;
  BookingRow? _quote;
  String _requestId = const Uuid().v4();
  bool _busy = false;
  bool _shareLocation = false;
  String? _error;

  @override
  void dispose() {
    _meeting.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _change(VoidCallback edit, {bool reprice = true}) {
    setState(() {
      edit();
      if (reprice) _quote = null;
      _error = null;
      _requestId = const Uuid().v4();
    });
  }

  Future<void> _datePicker() async {
    final now = philippineWallTime(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (date != null && mounted) _change(() => _date = date);
  }

  Future<void> _timePicker(bool isStart) async {
    final time = await showTimePicker(
      context: context,
      initialTime:
          (isStart ? _start : _end) ??
          TimeOfDay(hour: isStart ? 9 : 10, minute: 0),
    );
    if (time == null || !mounted) return;
    _change(() {
      if (isStart) {
        _start = time;
      } else {
        _end = time;
      }
    });
  }

  Future<void> _pickPin() async {
    final chosen = await pickMeetingPoint(context, _pin);
    if (chosen != null && mounted) _change(() => _pin = chosen, reprice: false);
  }

  Future<void> _save() async {
    final date = _date;
    final start = _start;
    final end = _end;
    if (date == null || start == null || end == null) {
      setState(() => _error = 'Choose the trip date and both times.');
      return;
    }
    final startsAt = philippineBookingTime(date, start.hour, start.minute);
    final endsAt = philippineBookingTime(date, end.hour, end.minute);
    if (!startsAt.isAfter(DateTime.now()) || !endsAt.isAfter(startsAt)) {
      setState(
        () => _error = 'Choose a future start and an end time after it.',
      );
      return;
    }

    final pin = _pin;
    final label = _meeting.text.trim();
    if (_quote != null && (pin == null || label.isEmpty)) {
      setState(
        () => _error = 'Add a meeting place name and pin it on the map.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final amigo = widget.amigo['id'] as String;
      if (_quote == null) {
        final quote = await widget.repository.quote(amigo, startsAt, endsAt);
        if (mounted) setState(() => _quote = quote);
      } else {
        final booking = await widget.repository.create(
          amigo: amigo,
          start: startsAt,
          end: endsAt,
          label: label,
          pin: pin!,
          notes: _notes.text.trim(),
          requestId: _requestId,
        );
        if (mounted && _shareLocation) {
          await BookingLocationConsent.optIn(context, booking);
        }
        if (mounted) Navigator.pop(context, booking);
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not reach GoMigo. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choice(
    IconData icon,
    String title,
    String detail,
    VoidCallback action,
  ) => TravelerCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      minLeadingWidth: 24,
      leading: Icon(icon, color: travelerInk),
      title: Text(title, style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        detail,
        style: const TextStyle(fontWeight: FontWeight.bold, color: travelerInk),
      ),
      onTap: _busy ? null : action,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final quote = _quote;
    return Scaffold(
      appBar: travelerHeader('Booking Request'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TravelerCard(
            child: Row(
              children: [
                AmigoPhoto(widget.amigo, width: 78, height: 78, radius: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.amigo['display_name'] as String,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: travelerInk,
                        ),
                      ),
                      Text('${pesos(widget.amigo['rate_centavos'])} / hr'),
                      if (widget.amigo['is_test'] == true)
                        const Text('Demo profile'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _choice(
            Icons.calendar_today_outlined,
            'Trip date · Philippine time',
            _date == null ? 'Choose date' : material.formatMediumDate(_date!),
            _datePicker,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _choice(
                  Icons.schedule,
                  'Start time',
                  _start?.format(context) ?? 'Choose time',
                  () => _timePicker(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choice(
                  Icons.schedule,
                  'End time',
                  _end?.format(context) ?? 'Choose time',
                  () => _timePicker(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _choice(
            Icons.location_on_outlined,
            'Meeting point',
            _pin == null ? 'Pin on map' : 'Pin selected · edit',
            _pickPin,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _meeting,
            enabled: !_busy,
            maxLength: 160,
            onChanged: (_) => _change(() {}, reprice: false),
            decoration: travelerField(
              'Meeting place',
              hint: 'Landmark or entrance',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            enabled: !_busy,
            maxLines: 3,
            maxLength: 350,
            onChanged: (_) => _change(() {}, reprice: false),
            decoration: travelerField(
              'Your plans (optional)',
              hint: 'Share what you would like to do.',
            ),
          ),
          if (quote != null) ...[
            const SizedBox(height: 12),
            TravelerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Estimated Price',
                    style: TextStyle(
                      color: travelerInk,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _amount('Amigo time', quote['subtotal_centavos']),
                  _amount('Service fee', quote['fee_centavos']),
                  const Divider(),
                  _amount('Total', quote['total_centavos']),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share my location when accepted'),
              subtitle: Text(BookingLocationConsent.description('Amigo')),
              value: _shareLocation,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _shareLocation = value),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(color: travelerRust),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TravelerButton(
            _busy
                ? 'Please wait…'
                : quote == null
                ? 'Get price'
                : 'Send booking request',
            _busy ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, Object? cents) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(pesos(cents), style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  );
}
