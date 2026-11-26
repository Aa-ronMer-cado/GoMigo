import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../navigation/traveler_ui.dart';
import '../booking/booking_repository.dart';
import '../discovery/amigo_photo.dart';
import 'chat_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.repository,
    required this.booking,
    required this.amigo,
    required this.demoEnabled,
  });

  final BookingRepository repository;
  final BookingRow booking;
  final BookingRow amigo;
  final bool demoEnabled;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  late final _userId = widget.repository.userId;
  late final _bookingId = widget.booking['id'] as String;
  late Stream<List<BookingRow>> _bookingUpdates;
  late Stream<List<BookingRow>> _messages;
  ({String id, String body})? _unsent;
  bool _sending = false;
  bool _simulating = false;

  @override
  void initState() {
    super.initState();
    _bookingUpdates = widget.repository.watch(_bookingId);
    _messages = widget.repository.messages(_bookingId);
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;

    final message = _unsent?.body == body
        ? _unsent!
        : (id: const Uuid().v4(), body: body);
    setState(() {
      _sending = true;
      _unsent = message;
    });
    try {
      await widget.repository.sendMessage(_bookingId, message.id, message.body);
      if (!mounted) return;
      _composer.clear();
      _unsent = null;
    } catch (_) {
      if (mounted)
        notifyTraveler(context, 'Could not send your message. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _simulateReply() async {
    setState(() => _simulating = true);
    try {
      await widget.repository.action('simulate_amigo_message', _bookingId, {
        'p_body': 'I’ll meet you at the pinned meeting point.',
      });
    } catch (_) {
      if (mounted)
        notifyTraveler(context, 'Could not send the simulated reply.');
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amigo = widget.amigo;
    final demo = widget.demoEnabled && amigo['is_test'] == true;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F1),
      appBar: AppBar(
        toolbarHeight: 80,
        titleSpacing: 4,
        elevation: 0,
        backgroundColor: const Color(0xFFEBDED3),
        foregroundColor: travelerInk,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const TravelerAsset('finding_chevron_backward', size: 29),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          children: [
            AmigoPhoto(amigo, width: 63, height: 63, radius: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    amigo['display_name'] as String? ?? 'Amigo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    demo ? 'Demo booking chat' : 'Booking chat',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<BookingRow>>(
          stream: _bookingUpdates,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TravelerError(
                'Could not load the booking.',
                onRetry: () {
                  setState(
                    () => _bookingUpdates = widget.repository.watch(_bookingId),
                  );
                },
              );
            }
            final rows = snapshot.data;
            if (rows == null)
              return const Center(child: CircularProgressIndicator());
            final status = rows.isEmpty ? null : rows.first['status'];
            if (status != 'accepted' && status != 'completed') {
              return const TravelerError(
                'Chat is available for accepted and completed bookings.',
              );
            }
            final canSend = status == 'accepted';
            return Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<BookingRow>>(
                    stream: _messages,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return TravelerError(
                          'Could not load messages.',
                          onRetry: () {
                            setState(
                              () => _messages = widget.repository.messages(
                                _bookingId,
                              ),
                            );
                          },
                        );
                      }
                      final messages = snapshot.data;
                      if (messages == null)
                        return const Center(child: CircularProgressIndicator());
                      if (messages.isEmpty) {
                        return Center(
                          child: Text(
                            canSend
                                ? 'Start the conversation.'
                                : 'No messages for this trip.',
                          ),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) =>
                            _message(messages[index]),
                      );
                    },
                  ),
                ),
                if (canSend) ...[
                  if (demo)
                    TextButton(
                      onPressed: _simulating ? null : _simulateReply,
                      child: Text(
                        _simulating ? 'Simulating…' : 'Simulate Amigo reply',
                      ),
                    ),
                  _buildComposer(),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'This trip is complete. You can still read your messages.',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildComposer() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: travelerBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                enabled: !_sending,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(16, 14, 4, 14),
                  counterText: '',
                ),
              ),
            ),
            ListenableBuilder(
              listenable: _composer,
              builder: (context, _) => IconButton(
                tooltip: 'Send message',
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TravelerAsset(
                        'chat_send',
                        size: 20,
                        color: _composer.text.trim().isEmpty
                            ? Colors.black38
                            : null,
                      ),
                onPressed: _sending || _composer.text.trim().isEmpty
                    ? null
                    : _send,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    ),
  );

  Widget _message(BookingRow row) {
    final mine = row['sender_id'] == _userId;
    final sender = mine
        ? 'You'
        : widget.amigo['display_name'] as String? ?? 'Amigo';
    final time = DateTime.tryParse(row['created_at'] as String? ?? '');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .85,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
            decoration: BoxDecoration(
              color: mine ? travelerSage : Colors.white,
              border: Border.all(color: travelerBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['body'] as String,
                  style: const TextStyle(color: travelerInk),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (row['is_test'] == true) 'Simulated reply' else sender,
                    if (time != null)
                      TimeOfDay.fromDateTime(time.toLocal()).format(context),
                  ].join(' · '),
                  style: const TextStyle(color: travelerInk, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
