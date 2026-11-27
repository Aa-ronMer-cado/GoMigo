import 'dart:async';

import 'package:amigo/features/chat/chat_repository.dart';
import 'package:amigo/features/chat/chat_screen.dart';
import 'package:amigo/features/session/session_controls.dart';
import 'package:amigo/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _UnusedClient extends Fake implements SupabaseClient {}

class _Chat extends AmigoChatRepository {
  _Chat(SupabaseClient client) : super(client, 'booking-id', 'amigo-id');

  final updates = StreamController<List<Map<String, dynamic>>>();
  final conversation = StreamController<List<Map<String, dynamic>>>();
  final sent = <({String id, String body})>[];
  bool failFirstSend = true;

  @override
  Stream<List<Map<String, dynamic>>> booking() => updates.stream;

  @override
  Stream<List<Map<String, dynamic>>> messages() => conversation.stream;

  @override
  Future<void> send(String id, String body) async {
    sent.add((id: id, body: body));
    if (failFirstSend) {
      failFirstSend = false;
      throw StateError('Simulated lost response');
    }
  }
}

class _Session extends AmigoSessionRepository {
  _Session(SupabaseClient client) : super(client, 'booking-id');

  Map<String, dynamic>? trip;
  var status = 'accepted';

  @override
  Future<void> start() async {
    trip = {'started_at': DateTime.now().toUtc().toIso8601String()};
  }

  @override
  Future<void> complete() async {
    trip!['ended_at'] = DateTime.now().toUtc().toIso8601String();
    status = 'completed';
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'retry reuses the message ID and booking completion closes the composer',
    (tester) async {
      _phone(tester);
      final chat = _Chat(_UnusedClient());
      await tester.pumpWidget(
        MaterialApp(
          home: AmigoChatScreen(
            repository: chat,
            travelerName: 'Test Traveler',
          ),
        ),
      );
      chat.updates.add([
        {'status': 'accepted'},
      ]);
      await tester.pump();
      chat.conversation.add([
        {'sender_id': 'traveler-id', 'body': 'I’m at the meeting point'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('I’m at the meeting point'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'See you there');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(chat.sent, hasLength(2));
      expect(chat.sent.first, chat.sent.last);
      expect(chat.sent.last.body, 'See you there');

      chat.updates.add([
        {'status': 'completed'},
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('I’m at the meeting point'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(chat.updates.close());
      unawaited(chat.conversation.close());
    },
  );

  testWidgets('paid shared session starts, completes and opens the review', (
    tester,
  ) async {
    _phone(tester);
    final session = _Session(_UnusedClient());
    final now = DateTime.now().toUtc();
    var reviewing = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AmigoSessionControls(
                repository: session,
                booking: {
                  'status': session.status,
                  'starts_at': now
                      .add(const Duration(minutes: 2))
                      .toIso8601String(),
                  'ends_at': now
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                  'payment_status': 'paid',
                },
                session: session.trip,
                onReview: () => reviewing = true,
                onChanged: () => setState(() {}),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start session'));
    await tester.pumpAndSettle();
    expect(find.text('Together now'), findsOneWidget);
    expect(find.textContaining('until goodbye'), findsOneWidget);
    await tester.tap(find.text('Complete trip'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Complete trip'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trip complete'), findsOneWidget);
    expect(reviewing, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
