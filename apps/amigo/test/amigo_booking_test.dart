import 'package:amigo/features/booking/amigo_booking_detail_screen.dart';
import 'package:amigo/features/booking/amigo_booking_history_screen.dart';
import 'package:amigo/features/booking/amigo_booking_repository.dart';
import 'package:amigo/features/earnings/amigo_earnings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';

void main() {
  test('withdrawal amounts are parsed exactly in centavos', () {
    expect(parseWithdrawalCentavos(' 1,234.56 '), 123456);
    expect(parseWithdrawalCentavos('5.7'), 570);
    expect(parseWithdrawalCentavos('0.01'), 1);
    expect(parseWithdrawalCentavos('21474836.47'), 2147483647);
    for (final invalid in [
      '',
      '0.00',
      '-1',
      '1.001',
      '1,23',
      '1e3',
      '21474836.48',
    ]) {
      expect(parseWithdrawalCentavos(invalid), isNull, reason: invalid);
    }
  });

  testWidgets('accepts an incoming request and exposes booking actions', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final repository = _BookingRepository([_sample('pending')]);
    AmigoBooking? openedChat;
    await tester.pumpWidget(
      _app(
        AmigoBookingDetailScreen(
          repository: repository,
          booking: repository.bookings.first,
          onOpenChat: (booking) => openedChat = booking,
          onOpenMap: (_) {},
          onOpenSession: (_) {},
          onOpenReview: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Accept booking'), 140);
    await tester.tap(find.text('Accept booking'));
    await tester.pumpAndSettle();
    expect(repository.bookings.first.status, 'accepted');
    await tester.scrollUntilVisible(find.text('Open chat').hitTestable(), 140);
    await tester.tap(find.text('Open chat'));
    expect(openedChat?.status, 'accepted');
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters history and opens saved trip routes', (tester) async {
    _setPhoneViewport(tester);
    final repository = _BookingRepository([
      _sample('cancelled'),
      _sample('completed'),
    ]);
    AmigoBooking? openedRoute;
    await tester.pumpWidget(
      _app(
        AmigoBookingHistoryScreen(
          repository: repository,
          onOpenBooking: (_) {},
          onOpenMap: (booking) => openedRoute = booking,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsNothing);
    await tester.tap(find.text('View route'));
    expect(openedRoute?.status, 'completed');
    expect(tester.takeException(), isNull);
  });
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget screen) => MaterialApp(
  theme: goMigoTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.25)),
    child: child!,
  ),
  home: screen,
);

AmigoBooking _sample(String status) => AmigoBooking(
  {
    'id': 'booking-$status',
    'traveler_id': 'traveler',
    'status': status,
    'payment_status': 'unpaid',
    'meeting_label': 'Market entrance',
    'notes': 'Try a local snack.',
    'starts_at': '2029-11-27T02:00:00Z',
    'ends_at': '2029-11-27T03:00:00Z',
    'subtotal_centavos': 10000,
    'fee_centavos': 0,
    'total_centavos': 10000,
  },
  travelerName: 'Demo Traveler',
  travelerVerified: true,
);

class _BookingRepository extends Fake implements AmigoBookingRepository {
  _BookingRepository(this.bookings);

  final List<AmigoBooking> bookings;

  @override
  Stream<List<AmigoBooking>> history() => Stream.value(bookings);

  @override
  Stream<AmigoBooking?> watch(AmigoBooking initial) => Stream.value(
    bookings.where((booking) => booking.id == initial.id).firstOrNull,
  );

  @override
  Future<AmigoBooking> respond(
    AmigoBooking booking, {
    required bool accept,
    String? reason,
  }) async {
    final index = bookings.indexWhere((item) => item.id == booking.id);
    return bookings[index] = booking.withRow({
      ...booking.row,
      'status': accept ? 'accepted' : 'declined',
      'decline_reason': reason,
    });
  }
}
