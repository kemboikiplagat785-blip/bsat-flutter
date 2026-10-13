import 'package:bsat/utils/offer_time_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evaluates separate offer windows independently', () {
    final morning = [
      {'startTime': '08:00', 'endTime': '10:00'}
    ];
    final midday = [
      {'startTime': '10:00', 'endTime': '14:00'}
    ];
    expect(isOfferWindowOpen(morning, now: DateTime(2026, 1, 1, 9)), isTrue);
    expect(isOfferWindowOpen(midday, now: DateTime(2026, 1, 1, 9)), isFalse);
    expect(isOfferWindowOpen(midday, now: DateTime(2026, 1, 1, 10)), isTrue);
    expect(isOfferWindowOpen(midday, now: DateTime(2026, 1, 1, 14)), isFalse);
  });

  test('unrestricted, malformed, and overnight windows are safe', () {
    expect(isOfferWindowOpen([], now: DateTime(2026, 1, 1, 2)), isTrue);
    expect(
      isOfferWindowOpen([
        {'startTime': 'bad', 'endTime': '10:00'}
      ]),
      isTrue,
    );
    final overnight = [
      {'startTime': '22:00', 'endTime': '06:00'}
    ];
    expect(isOfferWindowOpen(overnight, now: DateTime(2026, 1, 1, 23)), isTrue);
    expect(isOfferWindowOpen(overnight, now: DateTime(2026, 1, 1, 5)), isTrue);
    expect(
        isOfferWindowOpen(overnight, now: DateTime(2026, 1, 1, 12)), isFalse);
  });

  test('dropdown time text omits missing or invalid values', () {
    expect(formatOfferTimeWindow('08:00', '10:00'), '08:00 AM – 10:00 AM');
    expect(formatOfferTimeWindow(null, '10:00'), '');
    expect(formatOfferTimeWindow('invalid', '10:00'), '');
    expect(
      formatTaskOfferLabel(
        amount: 20,
        code: '*180*5*2#',
        startTime: '08:00',
        endTime: '10:00',
      ),
      '20 (*180*5*2#) 08:00 AM – 10:00 AM',
    );
    expect(
      formatTaskOfferLabel(
        amount: 20,
        code: '*180*5*2#',
        startTime: 'bad',
        endTime: '10:00',
      ),
      '20 (*180*5*2#)',
    );
  });
}
