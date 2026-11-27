import 'package:amigo/features/session/session_controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rounds up partial seconds and stops the countdown at zero', () {
    expect(sessionCountdown(const Duration(milliseconds: 500)), '00:01');
    expect(
      sessionCountdown(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(sessionCountdown(Duration.zero), '00:00');
    expect(sessionCountdown(const Duration(seconds: -5)), '00:00');
  });
}
