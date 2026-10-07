import 'package:bsat/utils/top_up.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected target offer computes the exact required top-up', () {
    expect(calculateRequiredTopUp(19, 23), 4);
    expect(combinedTransactionAmount(19, 4), 23);
  });

  test('a target not above the original amount requires no top-up', () {
    expect(calculateRequiredTopUp(19, null), isNull);
    expect(calculateRequiredTopUp(19, 19), isNull);
    expect(calculateRequiredTopUp(19, 18), isNull);
  });

  test('top-up payment must match both amount and normalized customer', () {
    bool matches(int customerNumber, int incomingAmount) => matchesTopUpPayment(
          expectedCustomerNumber: 718008330,
          paymentCustomerNumber: customerNumber,
          requiredTopUp: 4,
          paymentAmount: incomingAmount,
        );

    expect(matches(718008330, 4), isTrue);
    expect(matches(718008330, 5), isFalse);
    expect(matches(718008331, 4), isFalse);
  });
}
