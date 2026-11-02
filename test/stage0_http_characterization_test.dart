// STAGE 0 characterization (disposable copy only).
//
// Records the HTTP requests HEAD 086d14e sends on its forwarding paths, so a
// later transport refactor can be checked byte-for-byte against them. These
// tests describe current behaviour; they do not endorse it. Nothing reaches a
// network: package:http is answered by a local MockClient, any other HTTP
// client is refused, SMS sends and USSD dials are refused and recorded.
import 'dart:convert';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';

const _endpoint = 'https://api.bsat2.xyz/api/fcm/send-secure';
const _jwt = 'stage0-test-jwt';
const _receipt = 'SJK1ABCD23';
const _amount = 100;
const _number = 712345678;

/// A synthetic M-PESA-style message longer than 160 characters, to show that
/// the full body (not the 160-character excerpt) is forwarded.
final _smsBody = '$_receipt Confirmed. Ksh$_amount.00 received from JOHN DOE '
    '0712345678 on 28/10/26 at 3:41 PM. New M-PESA balance is Ksh1,234.00. '
    'Transaction cost, Ksh0.00. SYNTHETIC STAGE 0 TEST MESSAGE ONLY.';

Map<String, Object> _prefs(String deviceName) => {
      'user_device_name': deviceName,
      'jwt_token': _jwt,
    };

/// JSON round trip, as the request body is encoded on the wire.
Map<String, dynamic> _wire(Map<String, dynamic> map) =>
    jsonDecode(jsonEncode(map)) as Map<String, dynamic>;

void _expectBackendPost(CapturedRequest request) {
  expect(request.method, 'POST');
  expect(request.url.toString(), _endpoint);
  expect(request.headers['content-type'], startsWith('application/json'));
  expect(request.headers['authorization'], 'Bearer $_jwt');
}

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  group('Phone A: _retryPendingForwardingDeliveries (constructor-triggered)',
      () {
    const jobId = 'fwd_${_receipt}_1761650000000';

    Future<int> seedDueRetry({required int nextAttemptAt}) async {
      await h.setUp(prefs: _prefs('Phone A'));
      final db = await h.db;
      final rowId = await db.insert('transactions', {
        'initialMessage': _smsBody,
        'transactionId': _receipt,
        'status': TransactionStatuses.forwardedPending,
        'forwardingJobId': jobId,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone B',
        // LAN integration: every in-flight Online job now persists its
        // transport (migration backfill or creation path).
        'forwardingTransport': 'online',
        'awaitingTopUp': 0,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      await db.insert('forwardingDeliveryRetries', {
        'forwardingJobId': jobId,
        'attempt': 0,
        'nextAttemptAt': nextAttemptAt,
        'acknowledged': 0,
      });
      return rowId;
    }

    test('a due retry re-sends the identical forwarded_sms payload', () async {
      final rowId = await seedDueRetry(
          nextAttemptAt: DateTime.now().millisecondsSinceEpoch - 1000);
      final before = DateTime.now().millisecondsSinceEpoch;
      await h.capture(() async {
        // The constructor starts the retry worker (unawaited); capture()
        // drains it before returning.
        TransactionController(sqliteService: SQLiteService());
      });
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(h.backendPosts, hasLength(1));
      final post = h.backendPosts.single;
      _expectBackendPost(post);
      expect(
        post.json,
        _wire(buildForwardedSmsRequestPayload(
          message: _smsBody,
          messageId: _receipt,
          transactionRowId: rowId,
          forwardingJobId: jobId,
          senderDeviceName: 'Phone A',
          recipientDeviceName: 'Phone B',
        )),
      );
      expect(post.data['transactionId'], isA<int>());

      final retry = (await (await h.db).query('forwardingDeliveryRetries',
              where: 'forwardingJobId = ?', whereArgs: [jobId]))
          .single;
      expect(retry['attempt'], 1);
      expect(retry['lastFailure'], isNull);
      final delayMs =
          forwardingDeliveryRetryDelayAfterAttempt(1)!.inMilliseconds;
      expect(retry['nextAttemptAt'] as int,
          inInclusiveRange(before + delayMs, after + delayMs));
      expect(
          await (await h.db).query('forwardingSubmissionClaims',
              where: 'forwardingJobId = ?', whereArgs: [jobId]),
          isEmpty);
      h.expectNoExternalEffects();
    });

    test('a failed retry POST records the HTTP status as lastFailure',
        () async {
      await seedDueRetry(
          nextAttemptAt: DateTime.now().millisecondsSinceEpoch - 1000);
      h.backendStatus = 500;
      h.backendResponse = {'message': 'boom'};
      await h.capture(() async {
        TransactionController(sqliteService: SQLiteService());
      });
      expect(h.backendPosts, hasLength(1));
      final retry = (await (await h.db).query('forwardingDeliveryRetries',
              where: 'forwardingJobId = ?', whereArgs: [jobId]))
          .single;
      expect(retry['attempt'], 1);
      expect(retry['lastFailure'], 'HTTP/API submission failed (500)');
      h.expectNoExternalEffects();
    });

    test('a retry that is not yet due sends nothing', () async {
      await seedDueRetry(
          nextAttemptAt:
              DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      await h.capture(() async {
        TransactionController(sqliteService: SQLiteService());
      });
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });
  });

  group('Phone B: _deliverForwardingConfirmation (via sendForwardingConfirmation)',
      () {
    const jobId = 'fwd_${_receipt}_1761650000000';

    test('confirmed result POST and durable confirmation outbox', () async {
      await h.setUp(prefs: _prefs('Phone B'));
      final controller = TransactionController(sqliteService: SQLiteService());
      final before = DateTime.now().millisecondsSinceEpoch;
      await h.capture(() => controller.sendForwardingConfirmation(
            forwardingJobId: jobId,
            recipientDeviceName: 'Phone A',
            transactionId: _receipt,
          ));
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(h.backendPosts, hasLength(1));
      final post = h.backendPosts.single;
      _expectBackendPost(post);
      expect(post.json, {
        'title': 'BSAT Online Forwarding',
        'body': 'Forwarded transaction confirmed',
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': 'Phone A',
        'data': {
          'type': 'forwarded_sms_ack',
          'ackKind': 'confirmed',
          'status': 'transaction-confirmed',
          'resultStatus': 'transaction-confirmed',
          'forwardingJobId': jobId,
          'transactionId': _receipt,
          'senderDeviceName': 'Phone B',
          'recipientDeviceName': 'Phone A',
        },
      });
      expect(post.data['transactionId'], isA<String>(),
          reason: 'this path sends the M-PESA receipt code, not a row ID');

      final queued = (await (await h.db).query('forwardingConfirmations',
              where: 'forwardingJobId = ?', whereArgs: [jobId]))
          .single;
      expect(queued['recipientDeviceName'], 'Phone A');
      expect(queued['transactionId'], _receipt);
      expect(queued['resultStatus'], 'transaction-confirmed');
      expect(queued['attempt'], 1);
      expect(queued['nextAttemptAt'] as int,
          inInclusiveRange(before + 5000, after + 5000),
          reason: 'outbox stays queued until confirmation_received');
      h.expectNoExternalEffects();
    });

    test('unavailable-offer result carries numeric top-up fields', () async {
      await h.setUp(prefs: _prefs('Phone B'));
      final controller = TransactionController(sqliteService: SQLiteService());
      await h.capture(() => controller.sendForwardingConfirmation(
            forwardingJobId: jobId,
            recipientDeviceName: 'Phone A',
            transactionId: _receipt,
            resultStatus: TransactionStatuses.unavailableOffer,
            requiredTopUp: 20,
            targetAmount: 120,
          ));
      final data = h.backendPosts.single.data;
      expect(data['ackKind'], 'confirmed');
      expect(data['status'], 'transaction-confirmed');
      expect(data['resultStatus'], TransactionStatuses.unavailableOffer);
      expect(data['requiredTopUp'], 20);
      expect(data['targetAmount'], 120);
      expect(data['requiredTopUp'], isA<int>());
      h.expectNoExternalEffects();
    });
  });

  group('Phone B: _sendImmediateAck for forwarded_sms (via handleRemoteMessage)',
      () {
    const jobId = 'fwd_${_receipt}_1761650000000';
    const originRowId = '41';

    RemoteMessage forwardedSms({String sender = 'Phone A'}) => RemoteMessage(
          messageId: 'fcm-message-1',
          data: {
            'type': 'forwarded_sms',
            'title': 'Forwarded Message',
            'body': _smsBody,
            'messageId': _receipt,
            'transactionId': originRowId,
            'forwardingJobId': jobId,
            'forwardingStatus': 'forwarding-pending',
            'senderDeviceName': sender,
            'recipientDeviceName': 'Phone B',
          },
        );

    Future<void> setUpPhoneB({String? existingSource}) async {
      await h.setUp(prefs: _prefs('Phone B'));
      final db = await h.db;
      await db.insert('whitelistedDevices', {
        'device_name': 'Phone A',
        'device_id': 'device-a',
        'owner_email': 'owner@example.test',
      });
      if (existingSource != null) {
        // An already-completed claim: the handler acknowledges receipt and
        // treats the delivery as a duplicate, so no USSD path is entered.
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('forwardedSmsJobs', {
          'forwardingJobId': jobId,
          'sourceTransactionId': existingSource,
          'state': 'completed',
          'createdAt': now,
          'updatedAt': now,
        });
      }
    }

    test('receipt ACK payload after the job claim (duplicate delivery)',
        () async {
      await setUpPhoneB(existingSource: originRowId);
      final before = DateTime.now().millisecondsSinceEpoch;
      await h.capture(() => handleRemoteMessage(forwardedSms()));
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(h.backendPosts, hasLength(1));
      final post = h.backendPosts.single;
      _expectBackendPost(post);
      expect(post.json.keys.toSet(),
          {'title', 'body', 'senderDeviceName', 'recipientDeviceName', 'data'});
      expect(post.json['title'], 'BSAT Online Forwarding');
      expect(post.json['senderDeviceName'], 'Phone B');
      expect(post.json['recipientDeviceName'], 'Phone A');

      final payload =
          jsonDecode(post.json['body'] as String) as Map<String, dynamic>;
      final receivedAt = payload['receivedAt'] as String;
      expect(int.parse(receivedAt), inInclusiveRange(before, after));
      final expectedPayload = {
        'type': 'MESSAGE_ACK',
        'ackKind': 'received',
        'messageId': 'fcm-message-1',
        'requestId': '',
        'transactionId': originRowId,
        'forwardingJobId': jobId,
        'originalType': 'forwarded_sms',
        'status': 'received',
        'receivedAt': receivedAt,
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': 'Phone A',
        'body': 'received',
        'title': 'received',
      };
      expect(payload, expectedPayload);
      expect(post.data, {
        ...expectedPayload,
        'type': 'MESSAGE_ACK',
        'title': 'Ack receive',
        'body': post.json['body'],
      });
      expect(post.data['transactionId'], isA<String>(),
          reason: 'origin row ID is echoed back as a string');
      expect(post.data['messageId'], 'fcm-message-1',
          reason: 'messageId is the FCM message ID, not the M-PESA receipt');
      h.expectNoExternalEffects();
    });

    test('job bound to a different source transaction: no receipt ACK',
        () async {
      await setUpPhoneB(existingSource: '99');
      await h.capture(() => handleRemoteMessage(forwardedSms()));
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });

    test('sender not in whitelistedDevices: rejected before any claim or ACK',
        () async {
      await setUpPhoneB();
      await h.capture(
          () => handleRemoteMessage(forwardedSms(sender: 'Unknown Phone')));
      expect(h.backendPosts, isEmpty);
      expect(await (await h.db).query('forwardedSmsJobs'), isEmpty);
      h.expectNoExternalEffects();
    });

    test('duplicate of a confirmed job re-sends confirmation with the local '
        'row ID as transactionId', () async {
      await setUpPhoneB(existingSource: originRowId);
      final db = await h.db;
      final localId = await db.insert('transactions', {
        'transactionId': _receipt,
        'status': TransactionStatuses.doneConfirmed,
        'forwardingJobId': jobId,
        'forwardingSenderDeviceName': 'Phone A',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      await h.capture(() => handleRemoteMessage(forwardedSms()));

      expect(h.backendPosts, hasLength(2));
      expect(h.backendPosts[0].data['type'], 'MESSAGE_ACK');
      final confirmation = h.backendPosts[1];
      expect(confirmation.data['type'], 'forwarded_sms_ack');
      expect(confirmation.data['ackKind'], 'confirmed');
      expect(confirmation.data['transactionId'], '$localId',
          reason: 'unlike the first confirmation (receipt code), this path '
              'sends Phone B\'s local row ID');
      expect(confirmation.json['recipientDeviceName'], 'Phone A');
      h.expectNoExternalEffects();
    });
  });

  group('Phone A: confirmation receipt after a final ACK', () {
    const jobId = 'fwd_${_receipt}_1761650000000';

    test('final confirmation updates the row and POSTs confirmation_received',
        () async {
      await h.setUp(prefs: _prefs('Phone A'));
      final db = await h.db;
      final rowId = await db.insert('transactions', {
        'transactionId': _receipt,
        'initialMessage': _smsBody,
        'amount': _amount,
        'number': _number,
        'source': 'JOHN DOE',
        'status': TransactionStatuses.forwardedPending,
        'canRetry': 1,
        'forwardingJobId': jobId,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone B',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });

      await h.capture(() => handleRemoteMessage(RemoteMessage(
            messageId: 'fcm-confirmation-1',
            data: {
              'type': 'forwarded_sms_ack',
              'ackKind': 'confirmed',
              'status': 'transaction-confirmed',
              'resultStatus': 'transaction-confirmed',
              'forwardingJobId': jobId,
              'transactionId': _receipt,
              'senderDeviceName': 'Phone B',
              'recipientDeviceName': 'Phone A',
            },
          )));

      final row = (await db
              .query('transactions', where: 'id = ?', whereArgs: [rowId]))
          .single;
      expect(row['status'], TransactionStatuses.forwardedConfirmed);
      expect(row['canRetry'], 0);
      expect(row['awaitingTopUp'], 0);

      expect(h.backendPosts, hasLength(1));
      final post = h.backendPosts.single;
      _expectBackendPost(post);
      expect(post.json, {
        'title': 'BSAT Online Forwarding',
        'body': 'Forwarding confirmation received',
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
        'data': {
          'type': 'forwarded_sms_ack',
          'ackKind': 'confirmation_received',
          'status': 'received',
          'forwardingJobId': jobId,
          'senderDeviceName': 'Phone A',
          'recipientDeviceName': 'Phone B',
        },
      });
      expect(post.data.containsKey('transactionId'), isFalse,
          reason: 'the receipt carries only the job ID');
      h.expectNoExternalEffects();
    });
  });
}
