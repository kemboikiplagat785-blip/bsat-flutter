// STAGE 2 (disposable copy): the pure correlation rule for final forwarded-
// SMS confirmations on the origin device.
import 'package:bsat/utils/forwarding_identifiers.dart';
import 'package:flutter_test/flutter_test.dart';

ForwardingConfirmationRejection? _check({
  String expectedRecipient = 'Phone B',
  String expectedSender = 'Phone A',
  String localDevice = 'Phone A',
  String receipt = 'SJK1ABCD23',
  String sender = 'Phone B',
  String recipient = 'Phone A',
  String transactionId = 'SJK1ABCD23',
  String? authenticated,
}) =>
    forwardingConfirmationRejection(
      expectedRecipientDeviceName: expectedRecipient,
      expectedSenderDeviceName: expectedSender,
      localDeviceName: localDevice,
      expectedReceiptCode: receipt,
      receivedSenderDeviceName: sender,
      receivedRecipientDeviceName: recipient,
      receivedTransactionId: transactionId,
      authenticatedSenderDeviceName: authenticated,
    );

void main() {
  test('a fully correlated confirmation is accepted', () {
    expect(_check(), isNull);
  });

  test('device names and receipt are compared after trimming', () {
    expect(
        _check(sender: ' Phone B ', recipient: 'Phone A ',
            transactionId: ' SJK1ABCD23 '),
        isNull);
  });

  test('the sender must be the persisted recipient', () {
    expect(_check(sender: 'Phone Z'),
        ForwardingConfirmationRejection.unexpectedSender);
    expect(_check(sender: ''), ForwardingConfirmationRejection.unexpectedSender);
    expect(_check(sender: 'phone b'),
        ForwardingConfirmationRejection.unexpectedSender,
        reason: 'device names are compared exactly, as for receipts');
  });

  test('it must be addressed to the persisted origin device', () {
    expect(_check(recipient: 'Phone Q'),
        ForwardingConfirmationRejection.unexpectedRecipient);
  });

  test('a legacy row without a persisted sender uses this device\'s name', () {
    expect(_check(expectedSender: '', localDevice: 'Phone A'), isNull);
    expect(_check(expectedSender: '', localDevice: 'Phone A', recipient: 'X'),
        ForwardingConfirmationRejection.unexpectedRecipient);
  });

  test('missing persisted correlation data fails closed', () {
    expect(_check(expectedRecipient: ''),
        ForwardingConfirmationRejection.incompleteForwardingIdentity);
    expect(_check(expectedSender: '', localDevice: ''),
        ForwardingConfirmationRejection.incompleteForwardingIdentity);
  });

  test('transaction ID: matching receipt, empty or a numeric row ID pass', () {
    expect(_check(transactionId: 'SJK1ABCD23'), isNull);
    expect(_check(transactionId: ''), isNull);
    expect(_check(transactionId: '987'), isNull,
        reason: 'destination-local row IDs cannot be verified here');
  });

  test('transaction ID: any other value is a mismatch', () {
    for (final id in ['QWE9XYZ123', 'sjk1abcd23', '0', '-5', '12a', 'UNRELATED-ID']) {
      expect(_check(transactionId: id),
          ForwardingConfirmationRejection.transactionMismatch,
          reason: id);
    }
    expect(_check(receipt: '', transactionId: 'SJK1ABCD23'),
        ForwardingConfirmationRejection.transactionMismatch,
        reason: 'a receipt cannot match a row that has none');
  });

  test('an authenticated sender must be the recipient and agree with the '
      'claim', () {
    expect(_check(authenticated: 'Phone B'), isNull);
    expect(_check(authenticated: 'Phone Z'),
        ForwardingConfirmationRejection.authenticatedSenderMismatch);
    expect(_check(authenticated: 'Phone B', sender: 'Phone Z'),
        ForwardingConfirmationRejection.authenticatedSenderMismatch);
    expect(_check(authenticated: ''),
        ForwardingConfirmationRejection.authenticatedSenderMismatch);
  });

  test('without an authenticated sender only the claim is compared', () {
    expect(_check(authenticated: null, sender: 'Phone B'), isNull);
    expect(_check(authenticated: null, sender: 'Phone Z'),
        ForwardingConfirmationRejection.unexpectedSender);
  });
}
