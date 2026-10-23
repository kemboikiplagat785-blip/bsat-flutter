import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_display.dart';
import 'package:bsat/utils/forwarding_identifiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwarding history identifies destination and stable transaction ID',
      () {
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedPending,
        reply: 'Old forwarding message',
        destinationDeviceName: 'Phone B',
        transactionId: 'MPESA123456789',
      ),
      'Forwarded to Phone B — Transaction ID: MPESA123456789'
      '\n•\nOld forwarding message',
    );
  });

  test('existing registered ID in reply is fallback for a missing name', () {
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedPending,
        reply: 'Forwarded to old label (ID: REG-73)',
        transactionId: 'MPESA987654321',
      ),
      'Forwarded to REG-73 — Transaction ID: MPESA987654321',
    );
  });

  test('forwarding label update preserves other transaction events', () {
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedPending,
        reply: 'Forwarded to old label (ID: REG-73)'
            '\n•\nReceipt acknowledged by destination device',
        transactionId: 'MPESA987654321',
      ),
      'Forwarded to REG-73 — Transaction ID: MPESA987654321'
      '\n•\nReceipt acknowledged by destination device',
    );
  });

  test('non-forwarded transaction replies and IDs are left alone', () {
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.doneConfirmed,
        reply: 'Purchase complete',
        destinationDeviceName: 'Phone B',
        transactionId: 'MPESA123456789',
      ),
      'Purchase complete',
    );
  });

  test('receipt ACK requires matching job, transaction, and both devices', () {
    const expected = {
      'expectedJobId': 'job-1',
      'receivedJobId': 'job-1',
      'expectedTransactionId': '42',
      'receivedTransactionId': '42',
      'expectedRecipientDeviceName': 'Phone B',
      'receivedSenderDeviceName': 'Phone B',
      'expectedSenderDeviceName': 'Phone A',
      'receivedRecipientDeviceName': 'Phone A',
    };
    expect(
        isMatchingForwardingReceipt(
          expectedJobId: expected['expectedJobId']!,
          receivedJobId: expected['receivedJobId']!,
          expectedTransactionId: expected['expectedTransactionId']!,
          receivedTransactionId: expected['receivedTransactionId']!,
          expectedRecipientDeviceName: expected['expectedRecipientDeviceName']!,
          receivedSenderDeviceName: expected['receivedSenderDeviceName']!,
          expectedSenderDeviceName: expected['expectedSenderDeviceName']!,
          receivedRecipientDeviceName: expected['receivedRecipientDeviceName']!,
        ),
        isTrue);
    expect(
        isMatchingForwardingReceipt(
          expectedJobId: 'job-1',
          receivedJobId: 'job-old',
          expectedTransactionId: '42',
          receivedTransactionId: '42',
          expectedRecipientDeviceName: 'Phone B',
          receivedSenderDeviceName: 'Phone B',
          expectedSenderDeviceName: 'Phone A',
          receivedRecipientDeviceName: 'Phone A',
        ),
        isFalse);
    expect(
        isMatchingForwardingReceipt(
          expectedJobId: 'job-1',
          receivedJobId: 'job-1',
          expectedTransactionId: '42',
          receivedTransactionId: '',
          expectedRecipientDeviceName: 'Phone B',
          receivedSenderDeviceName: 'Phone B',
          expectedSenderDeviceName: 'Phone A',
          receivedRecipientDeviceName: 'Phone A',
        ),
        isFalse);
  });
}
