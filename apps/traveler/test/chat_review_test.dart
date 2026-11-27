import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traveler/features/booking/booking_repository.dart';
import 'package:traveler/features/booking/review_screen.dart';
import 'package:traveler/features/chat/chat_screen.dart';

const _amigo = {'id': 'test-amigo', 'display_name': 'Test Amigo'};
const _booking = {
  'id': 'test-booking',
  'amigo_id': 'test-amigo',
  'starts_at': '2026-11-27T01:00:00Z',
  'ends_at': '2026-11-27T03:00:00Z',
};

class _TestRepository extends BookingRepository {
  _TestRepository()
    : super(
        SupabaseClient(
          'https://gomigo.example',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  ({String id, String amigo, int rating, String text})? submitted;

  @override
  Future<BookingRow?> review(String id) async => null;

  @override
  Future<void> reviewTrip(
    String id,
    String amigo,
    int rating,
    String text,
  ) async {
    submitted = (id: id, amigo: amigo, rating: rating, text: text);
  }

  @override
  Stream<List<BookingRow>> watch(String id) => Stream.value([
    {'id': id, 'status': 'declined'},
  ]);
}

void main() {
  late _TestRepository repository;

  setUp(() => repository = _TestRepository());
  tearDown(() => repository.client.dispose());

  testWidgets('declined booking opens a closed chat state without a composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: goMigoTheme(),
        home: ChatScreen(
          repository: repository,
          booking: _booking,
          amigo: _amigo,
          demoEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Chat is available for accepted and completed bookings.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Simulate Amigo reply'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trip review requires a star and accepts an empty comment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: goMigoTheme(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReviewScreen(
                      repository: repository,
                      booking: _booking,
                      amigo: _amigo,
                    ),
                  ),
                ),
                child: const Text('Open review'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Submit Review');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.byTooltip('Rate 4 stars'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 5 stars'), findsOneWidget);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.submitted, (
      id: 'test-booking',
      amigo: 'test-amigo',
      rating: 4,
      text: '',
    ));
    expect(find.text('Open review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
