// STAGE 0 (disposable copy): tests copied VERBATIM from
// test/forwarded_confirmation_test.dart at HEAD 086d14e, lines 789-805,
// 1287-1304 and 1351-1379. They use no symbols missing from HEAD and no
// database. The original suite is left unchanged.
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_confirmation_retry.dart';
import 'package:bsat/utils/forwarding_display.dart';
import 'package:bsat/utils/forwarding_identifiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('received acknowledgement is never treated as final confirmation', () {
    expect(
      isFinalForwardedSmsConfirmation(ackKind: 'received', status: 'received'),
      isFalse,
    );
    expect(
      isFinalForwardedSmsConfirmation(
        ackKind: '',
        status: TransactionStatuses.doneConfirmed,
      ),
      isTrue,
    );
    expect(
      isFinalForwardedSmsConfirmation(ackKind: 'confirmed', status: 'received'),
      isFalse,
    );
  });

  test('transient failure uses bounded ordinary backoff', () {
    expect(
      forwardingConfirmationRetryDelay(
        attempt: 2,
        statusCode: 503,
        message: 'Temporary service error',
      ),
      const Duration(seconds: 15),
    );
    expect(
      forwardingConfirmationRetryDelay(
        attempt: 100,
        statusCode: 403,
        message: 'Forbidden',
      ),
      const Duration(seconds: 300),
    );
  });

  test('forwarded display prefers configured name and safely falls back', () {
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedPending,
        reply: 'Forwarded to Old Device',
        destinationDeviceName: 'Shop Counter',
      ),
      'Forwarded to Shop Counter',
    );
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedConfirmed,
        reply: 'Forwarded to Historical Phone',
      ),
      'Forwarded to Historical Phone',
    );
    expect(
      meaningfulForwardingDeviceName('device_id: 1234'),
      isNull,
    );
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.doneConfirmed,
        reply: 'Purchase successful',
        destinationDeviceName: 'Shop Counter',
      ),
      'Purchase successful',
    );
  });
}
