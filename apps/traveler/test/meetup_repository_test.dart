import 'package:flutter_test/flutter_test.dart';
import 'package:traveler/features/meetup/meetup_repository.dart';

void main() {
  test('sharing is allowed only for an accepted booking near its schedule', () {
    final booking = <String, dynamic>{
      'status': 'accepted',
      'starts_at': '2026-11-27T02:00:00Z',
      'ends_at': '2026-11-27T03:00:00Z',
    };
    expect(
      isMeetupSharingWindow(booking, DateTime.utc(2026, 11, 26, 23, 59)),
      isFalse,
    );
    expect(isMeetupSharingWindow(booking, DateTime.utc(2026, 11, 27)), isTrue);
    expect(
      isMeetupSharingWindow(booking, DateTime.utc(2026, 11, 27, 4)),
      isTrue,
    );
    expect(
      isMeetupSharingWindow(booking, DateTime.utc(2026, 11, 27, 4, 1)),
      isFalse,
    );
    booking['status'] = 'completed';
    expect(
      isMeetupSharingWindow(booking, DateTime.utc(2026, 11, 27, 3)),
      isFalse,
    );
  });

  test(
    'an opted-out location stays hidden and zero coordinates remain valid',
    () {
      expect(meetupCoordinates({'latitude': null, 'longitude': null}), isNull);
      final point = meetupCoordinates({'latitude': 0, 'longitude': 0});
      expect(point?.latitude, 0);
      expect(point?.longitude, 0);
    },
  );
}
