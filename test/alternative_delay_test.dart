import 'package:bsat/utils/forwarding_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seconds values including zero are accepted', () {
    for (final value in ['0', '5', '15', '30', '60']) {
      expect(parseAlternativeDelaySeconds(value), int.parse(value));
    }
  });

  test('negative and non-integer delays are rejected', () {
    expect(() => parseAlternativeDelaySeconds('-1'), throwsFormatException);
    expect(() => parseAlternativeDelaySeconds('1.5'), throwsFormatException);
  });

  test('delay deadlines use seconds and zero is immediately eligible', () {
    expect(alternativeDelayDeadlineMs(100000, 0), 100000);
    expect(alternativeDelayDeadlineMs(100000, 15), 115000);
    expect(114999 >= alternativeDelayDeadlineMs(100000, 15), isFalse);
    expect(115000 >= alternativeDelayDeadlineMs(100000, 15), isTrue);
  });

  test('legacy minutes convert once to seconds', () {
    expect(legacyAlternativeDelayMinutesToSeconds(1), 60);
    expect(readAlternativeDelaySeconds(60, 1), 60);
    expect(readAlternativeDelaySeconds(null, 1), 60);
  });
}
