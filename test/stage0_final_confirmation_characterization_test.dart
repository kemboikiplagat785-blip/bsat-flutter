// STAGE 0 characterization (disposable copy only) of Phone A's handling of
// forwarding acknowledgements, updated in STAGE 2.
//
// At HEAD 086d14e (Stage 0/1) a FINAL confirmation (ackKind 'confirmed') was
// applied by forwardingJobId alone. Stage 2 correlates it with the persisted
// row: the named sender must be the job's recipient, it must be addressed to
// this origin device, a supplied M-PESA receipt must match, and a transport-
// authenticated sender (when one exists) must agree. A RECEIPT
// acknowledgement (ackKind 'received') was already correlated and is
// unchanged. Over FCM the sender name is a claim, not authentication.
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';

const _jobId = 'fwd_SJK1ABCD23_1761650000000';

Future<int> _seedForwardedRow(Stage0Harness h,
    {Map<String, Object?> overrides = const {}}) async {
  final db = await h.db;
  return db.insert('transactions', {
    'transactionId': 'SJK1ABCD23',
    'amount': 100,
    'number': 712345678,
    'source': 'JOHN DOE',
    'status': TransactionStatuses.forwardedPending,
    'canRetry': 1,
    'forwardingJobId': _jobId,
    'forwardingSenderDeviceName': 'Phone A',
    'forwardingRecipientDeviceName': 'Phone B',
    'ussdReply': 'Forwarded to Phone B',
    'timeStamp': DateTime.now().millisecondsSinceEpoch,
    ...overrides,
  });
}

RemoteMessage _finalConfirmation({
  required String from,
  String jobId = _jobId,
  String transactionId = 'SJK1ABCD23',
  String resultStatus = 'transaction-confirmed',
}) =>
    RemoteMessage(messageId: 'fcm-final-$from', data: {
      'type': 'forwarded_sms_ack',
      'ackKind': 'confirmed',
      'status': 'transaction-confirmed',
      'resultStatus': resultStatus,
      'forwardingJobId': jobId,
      'transactionId': transactionId,
      'senderDeviceName': from,
      'recipientDeviceName': 'Phone A',
    });

RemoteMessage _receiptAck({required String from, required int rowId}) =>
    RemoteMessage(messageId: 'fcm-receipt-$from', data: {
      'type': 'MESSAGE_ACK',
      'ackKind': 'received',
      'status': 'received',
      'originalType': 'forwarded_sms',
      'forwardingJobId': _jobId,
      'transactionId': '$rowId',
      'senderDeviceName': from,
      'recipientDeviceName': 'Phone A',
    });

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);
  setUp(() => h.setUp(prefs: {
        'user_device_name': 'Phone A',
        'jwt_token': 'stage0-test-jwt',
      }));

  Future<Map<String, Object?>> row(int id) async =>
      (await (await h.db).query('transactions', where: 'id = ?', whereArgs: [id]))
          .single;

  // Stage 2: this was the "KNOWN GAP" characterization (same inputs). At
  // Stage 0/1 HEAD the job was confirmed and the receipt went to Phone Z.
  test('FIXED GAP: a final confirmation from an unrelated device is rejected',
      () async {
    final id = await _seedForwardedRow(h);
    await h.capture(() => handleRemoteMessage(_finalConfirmation(
          from: 'Phone Z', // not the job's recipient (Phone B)
          transactionId: 'UNRELATED-ID',
        )));

    final updated = await row(id);
    expect(updated['status'], TransactionStatuses.forwardedPending);
    expect(updated['canRetry'], 1);
    expect(updated['forwardingRecipientDeviceName'], 'Phone B');
    expect(h.backendPosts, isEmpty,
        reason: 'no confirmation receipt for a rejected confirmation');
    h.expectNoExternalEffects();
  });

  test('a final confirmation from the expected recipient completes the job',
      () async {
    final id = await _seedForwardedRow(h);
    await h.capture(
        () => handleRemoteMessage(_finalConfirmation(from: 'Phone B')));
    expect((await row(id))['status'], TransactionStatuses.forwardedConfirmed);
    expect(h.backendPosts.single.json['recipientDeviceName'], 'Phone B');
    h.expectNoExternalEffects();
  });

  test('a final confirmation for an unknown job changes nothing and sends no '
      'receipt', () async {
    final id = await _seedForwardedRow(h);
    await h.capture(() => handleRemoteMessage(
        _finalConfirmation(from: 'Phone B', jobId: 'fwd_UNKNOWN_1')));
    expect((await row(id))['status'], TransactionStatuses.forwardedPending);
    expect(h.backendPosts, isEmpty);
    h.expectNoExternalEffects();
  });

  test('a duplicate final confirmation is idempotent and re-sends the receipt',
      () async {
    final id = await _seedForwardedRow(h);
    await h.capture(() async {
      await handleRemoteMessage(_finalConfirmation(from: 'Phone B'));
      await handleRemoteMessage(_finalConfirmation(from: 'Phone B'));
    });
    expect((await row(id))['status'], TransactionStatuses.forwardedConfirmed);
    expect(h.backendPosts, hasLength(2));
    expect(h.backendPosts.map((p) => p.data['ackKind']).toSet(),
        {'confirmation_received'});
    h.expectNoExternalEffects();
  });

  test('contrast: a receipt ACK from an unrelated device is ignored', () async {
    final id = await _seedForwardedRow(h);
    await h.capture(
        () => handleRemoteMessage(_receiptAck(from: 'Phone Z', rowId: id)));
    final retries = await (await h.db).query('forwardingDeliveryRetries',
        where: 'forwardingJobId = ? AND acknowledged = 1', whereArgs: [_jobId]);
    expect(retries, isEmpty);
    expect((await row(id))['ussdReply'], 'Forwarded to Phone B');
    expect(h.backendPosts, isEmpty);
    h.expectNoExternalEffects();
  });

  test('contrast: a receipt ACK from the job\'s recipient is recorded and '
      'does not confirm the transaction', () async {
    final id = await _seedForwardedRow(h);
    await h.capture(
        () => handleRemoteMessage(_receiptAck(from: 'Phone B', rowId: id)));
    final retries = await (await h.db).query('forwardingDeliveryRetries',
        where: 'forwardingJobId = ? AND acknowledged = 1', whereArgs: [_jobId]);
    expect(retries, hasLength(1));
    final updated = await row(id);
    expect(updated['status'], TransactionStatuses.forwardedPending);
    expect(updated['ussdReply'],
        contains('Receipt acknowledged by destination device'));
    expect(h.backendPosts, isEmpty);
    h.expectNoExternalEffects();
  });

  group('Stage 2: final-confirmation correlation', () {
    void expectSingleReceiptTo(String device) {
      expect(h.backendPosts, hasLength(1));
      expect(h.backendPosts.single.json['recipientDeviceName'], device);
      expect(h.backendPosts.single.data['ackKind'], 'confirmation_received');
    }

    test('the expected recipient with the matching receipt code confirms',
        () async {
      final id = await _seedForwardedRow(h);
      await h.capture(() => handleRemoteMessage(
          _finalConfirmation(from: 'Phone B', transactionId: 'SJK1ABCD23')));
      final updated = await row(id);
      expect(updated['status'], TransactionStatuses.forwardedConfirmed);
      expect(updated['canRetry'], 0);
      expect(updated['awaitingTopUp'], 0);
      expectSingleReceiptTo('Phone B');
      h.expectNoExternalEffects();
    });

    test('an unrelated device is rejected even with the correct receipt code',
        () async {
      final id = await _seedForwardedRow(h);
      await h.capture(() => handleRemoteMessage(
          _finalConfirmation(from: 'Phone Z', transactionId: 'SJK1ABCD23')));
      expect((await row(id))['status'], TransactionStatuses.forwardedPending);
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });

    test('a confirmation addressed to a different origin device is rejected',
        () async {
      final id = await _seedForwardedRow(h);
      final message = _finalConfirmation(from: 'Phone B');
      await h.capture(() => handleRemoteMessage(RemoteMessage(
          messageId: message.messageId,
          data: {...message.data, 'recipientDeviceName': 'Phone Q'})));
      expect((await row(id))['status'], TransactionStatuses.forwardedPending);
      expect(h.backendPosts, isEmpty);
    });

    test('valid job ID but a mismatched receipt code is rejected', () async {
      final id = await _seedForwardedRow(h);
      await h.capture(() => handleRemoteMessage(
          _finalConfirmation(from: 'Phone B', transactionId: 'QWE9XYZ123')));
      final unchanged = await row(id);
      expect(unchanged['status'], TransactionStatuses.forwardedPending);
      expect(unchanged['canRetry'], 1);
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });

    test('LIMITATION: the destination\'s own numeric row ID cannot be checked '
        'and is accepted', () async {
      final id = await _seedForwardedRow(h);
      await h.capture(() => handleRemoteMessage(
          _finalConfirmation(from: 'Phone B', transactionId: '987')));
      expect((await row(id))['status'], TransactionStatuses.forwardedConfirmed);
      expectSingleReceiptTo('Phone B');
    });

    test('only the correlated row of a shared job ID changes', () async {
      final mine = await _seedForwardedRow(h);
      final other = await _seedForwardedRow(h, overrides: {
        'forwardingRecipientDeviceName': 'Phone C',
        'ussdReply': 'Forwarded to Phone C',
      });
      await h.capture(() =>
          handleRemoteMessage(_finalConfirmation(from: 'Phone B')));
      expect((await row(mine))['status'], TransactionStatuses.forwardedConfirmed);
      final untouched = await row(other);
      expect(untouched['status'], TransactionStatuses.forwardedPending);
      expect(untouched['canRetry'], 1);
      expectSingleReceiptTo('Phone B');
    });

    test('a late unavailable-offer confirmation does not downgrade a '
        'confirmed row; the receipt is still sent', () async {
      final db = await h.db;
      await db.insert('ussdCodes', {'id': 7, 'amount': 120});
      await db.insert('replies', {
        'condition': 3, // TransactionStatuses.unavailableOfferMap key
        'conditionAmount': 1,
        'reply': 'SYNTHETIC top-up reply',
        'amounts': '[]',
      });
      final id = await _seedForwardedRow(h, overrides: {
        'status': TransactionStatuses.forwardedConfirmed,
        'canRetry': 0,
        'awaitingTopUp': 0,
        'targetOfferId': 7,
      });
      await h.capture(() => handleRemoteMessage(_finalConfirmation(
          from: 'Phone B',
          resultStatus: TransactionStatuses.unavailableOffer)));
      final unchanged = await row(id);
      expect(unchanged['status'], TransactionStatuses.forwardedConfirmed);
      expect(unchanged['awaitingTopUp'], 0);
      expect(unchanged['requiredTopUp'], isNull);
      expect(h.telephonyCalls, isEmpty,
          reason: 'no unavailable-offer reply for an unchanged row');
      expectSingleReceiptTo('Phone B');
      h.expectNoExternalEffects();
    });

    test('a late valid confirmation still completes a row that fell back to '
        'error', () async {
      final id = await _seedForwardedRow(h, overrides: {
        'status': TransactionStatuses.error,
        'ussdReply':
            'Forwarding failed: Phone offline or server not reachable. Will retry later.',
      });
      await h.capture(() =>
          handleRemoteMessage(_finalConfirmation(from: 'Phone B')));
      expect((await row(id))['status'], TransactionStatuses.forwardedConfirmed);
      expectSingleReceiptTo('Phone B');
    });

    test('a valid confirmation after a rejected one is applied', () async {
      final id = await _seedForwardedRow(h);
      await h.capture(() async {
        await handleRemoteMessage(_finalConfirmation(from: 'Phone Z'));
        await handleRemoteMessage(_finalConfirmation(from: 'Phone B'));
      });
      expect((await row(id))['status'], TransactionStatuses.forwardedConfirmed);
      expectSingleReceiptTo('Phone B');
      h.expectNoExternalEffects();
    });

    group('transport-authenticated sender', () {
      test('claimed sender matches but the authenticated identity does not: '
          'rejected', () async {
        final id = await _seedForwardedRow(h);
        await h.capture(() => handleForwardedSmsAcknowledgement(
              _finalConfirmation(from: 'Phone B'),
              authenticatedSenderDeviceName: 'Phone Z',
            ));
        expect((await row(id))['status'], TransactionStatuses.forwardedPending);
        expect(h.backendPosts, isEmpty);
        h.expectNoExternalEffects();
      });

      test('authenticated identity is the recipient but the claim differs: '
          'rejected', () async {
        final id = await _seedForwardedRow(h);
        await h.capture(() => handleForwardedSmsAcknowledgement(
              _finalConfirmation(from: 'Phone Z'),
              authenticatedSenderDeviceName: 'Phone B',
            ));
        expect((await row(id))['status'], TransactionStatuses.forwardedPending);
        expect(h.backendPosts, isEmpty);
      });

      test('authenticated identity and claim both match: confirmed', () async {
        final id = await _seedForwardedRow(h);
        await h.capture(() => handleForwardedSmsAcknowledgement(
              _finalConfirmation(from: 'Phone B'),
              authenticatedSenderDeviceName: 'Phone B',
            ));
        expect(
            (await row(id))['status'], TransactionStatuses.forwardedConfirmed);
        expectSingleReceiptTo('Phone B');
      });
    });
  });
}
