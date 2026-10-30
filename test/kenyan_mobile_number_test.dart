import 'package:bsat/utils/forwarding_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepted forms all give the 9-digit number SMS are sent to', () {
    for (final input in [
      '0712345678',
      '254712345678',
      '+254 712 345 678',
      '712345678',
    ]) {
      expect(normalizeKenyanMobileNumber(input), '712345678', reason: input);
    }
    expect(normalizeKenyanMobileNumber('0112345678'), '112345678');
  });

  test('anything else is refused, so nothing is sent to a wrong number', () {
    for (final input in [null, '', '00', '071234567', '07123456789', '0212345678']) {
      expect(normalizeKenyanMobileNumber(input), isNull, reason: '$input');
    }
  });
}
