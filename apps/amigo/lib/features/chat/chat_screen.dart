import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import '../../navigation/amigo_ui.dart';
import 'chat_repository.dart';

class AmigoChatScreen extends StatefulWidget {
  const AmigoChatScreen({
    super.key,
    required this.repository,
    required this.travelerName,
    this.navigation,
  });
  final AmigoChatRepository repository;
  final String travelerName;
  final Widget? navigation;

  @override
  State<AmigoChatScreen> createState() => _AmigoChatScreenState();
}

class _AmigoChatScreenState extends State<AmigoChatScreen> {
  final _text = TextEditingController();
  late var _booking = widget.repository.booking();
  late var _messages = widget.repository.messages();
  ({String id, String body})? _unsent;
  bool _sending = false;
  bool _sendFailed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    final message = _unsent?.body == body
        ? _unsent!
        : (id: const Uuid().v4(), body: body);
    setState(() {
      _unsent = message;
      _sending = true;
      _sendFailed = false;
    });
    try {
      await widget.repository.send(message.id, message.body);
      if (!mounted) return;
      _unsent = null;
      _text.clear();
    } catch (_) {
      if (mounted) setState(() => _sendFailed = true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF6F1),
    appBar: AppBar(
      leading: const AmigoBackButton(chat: true),
      toolbarHeight: 80,
      titleSpacing: 7,
      elevation: 0,
      foregroundColor: amigoInk,
      backgroundColor: const Color(0xFFEBDED3),
      title: Row(
        children: [
          const TravelerAvatar(radius: 29),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.travelerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text('Booking chat', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: widget.navigation,
    body: SafeArea(
      child: StreamBuilder(
        stream: _booking,
        builder: (context, state) {
          if (state.hasError) {
            return _error(
              'Could not load the booking.',
              () => setState(() => _booking = widget.repository.booking()),
            );
          }
          final rows = state.data;
          if (rows == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final status = rows.firstOrNull?['status'];
          if (status != 'accepted' && status != 'completed') {
            return const Center(
              child: Text('Chat is available after acceptance.'),
            );
          }
          return Column(
            children: [
              Expanded(child: _conversation()),
              if (status == 'accepted' && _sendFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Semantics(
                    liveRegion: true,
                    child: const Text('Could not send the message. Try again.'),
                  ),
                ),
              if (status == 'accepted')
                _composer()
              else
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Trip completed. Your messages are available to read.',
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _conversation() => StreamBuilder(
    stream: _messages,
    builder: (context, state) {
      if (state.hasError) {
        return _error(
          'Could not load messages.',
          () => setState(() => _messages = widget.repository.messages()),
        );
      }
      final messages = state.data;
      if (messages == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (messages.isEmpty) {
        return const Center(child: Text('No messages for this booking yet.'));
      }
      return ListView.builder(
        reverse: true,
        padding: const EdgeInsets.all(20),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final row = messages[index];
          final mine = row['sender_id'] == widget.repository.amigoId;
          final time = DateTime.tryParse(row['created_at'] as String? ?? '');
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: .83,
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Card(
                color: mine ? amigoSage : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['body'] as String,
                        style: const TextStyle(color: amigoInk),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          mine ? 'You' : widget.travelerName,
                          if (time != null)
                            TimeOfDay.fromDateTime(
                              manilaTime(time),
                            ).format(context),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11, color: amigoInk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _composer() => Container(
    margin: const EdgeInsets.fromLTRB(24, 8, 24, 26),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: amigoBorder),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            enabled: !_sending,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Type a message…',
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 18,
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => IconButton(
            tooltip: 'Send message',
            onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : SvgPicture.asset('assets/figma/amigo_chat_send.svg'),
          ),
        ),
      ],
    ),
  );

  Widget _error(String message, VoidCallback retry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        TextButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}
