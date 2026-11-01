// A forwarded Second Attempt with no alternative code: Phone B reports it to
// Phone A, Phone A waits for the customer's top-up, the combined amount is
// completed by another paired device (Phone C), and Phone A then tells
// Phone B to move its row from Second Attempt to Pata More.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/transaction_categories.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _jobB = 'fwd_SJK1ABCD23_1761650000000';
const _jobC = 'fwd_SJK1TOPUP1_1761650100000';

RemoteMessage _confirmation({
  required String from,
  required String jobId,
  required String transactionId,
  String resultStatus = TransactionStatuses.doneConfirmed,
}) =>
    RemoteMessage(messageId: 'fcm-$from-$jobId-$resultStatus', data: {
      'type': 'forwarded_sms_ack',
      'ackKind': 'confirmed',
      'status': TransactionStatuses.doneConfirmed,
      'resultStatus': resultStatus,
      'forwardingJobId': jobId,
      'transactionId': transactionId,
      'senderDeviceName': from,
      'recipientDeviceName': 'Phone A',
    });

RemoteMessage _pataMoreNotice({String from = 'Phone A'}) =>
    RemoteMessage(messageId: 'fcm-pata-more-$from', data: {
      'type': 'forwarded_sms_pata_more',
      'status': TransactionStatuses.pataMore,
      'forwardingJobId': _jobB,
      'transactionId': 'SJK1ABCD23',
      'senderDeviceName': from,
      'recipientDeviceName': 'Phone B',
    });

RemoteMessage _pataMoreReceipt({String from = 'Phone B'}) =>
    RemoteMessage(messageId: 'fcm-pata-more-receipt-$from', data: {
      'type': 'MESSAGE_ACK',
      'ackKind': 'pata_more_received',
      'status': 'pata-more-received',
      'originalType': 'forwarded_sms_pata_more',
      'forwardingJobId': _jobB,
      'transactionId': 'SJK1ABCD23',
      'senderDeviceName': from,
      'recipientDeviceName': 'Phone A',
    });

class _PaidPaymentOps extends PaymentOps {
  @override
  Future<bool> hasActiveSubscription() async => true;
}

class _ScriptedPhoneService extends PhoneService {
  final List<(String, String)> responses = [];
  final List<String> calls = [];

  @override
  Future<List> makeMyRequest(
    String code,
    int subscriptionId, {
    int? triesParam = 0,
  }) async {
    calls.add(code);
    final response = responses.isEmpty
        ? ('Error sending code: timeout', TransactionStatuses.error)
        : responses.removeAt(0);
    return [response.$1, response.$2];
  }
}

const _jobAlt = 'fwd_SJK1ALT123_1761650200000';
const _altCode = '*180*5*2*0712345678*1*1#';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<Map<String, Object?>> row(int id) async => (await (await h.db)
          .query('transactions', where: 'id = ?', whereArgs: [id]))
      .single;

  group('Phone A', () {
    setUp(() => h.setUp(prefs: {
          'user_device_name': 'Phone A',
          'jwt_token': 'test-jwt',
        }));

    Future<int> seedOriginal(
        {Map<String, Object?> overrides = const {}}) async {
      final db = await h.db;
      return db.insert('transactions', {
        'transactionId': 'SJK1ABCD23',
        'amount': 20,
        'number': 712345678,
        'source': 'JOHN DOE',
        'status': TransactionStatuses.forwardedPending,
        'canRetry': 1,
        'forwardingJobId': _jobB,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone B',
        'forwardingTransport': 'online',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        ...overrides,
      });
    }

    Future<void> seedSecondAttemptReplyTargeting21() async {
      final db = await h.db;
      final offerId = await db.insert('ussdCodes', {
        'amount': 21,
        'fromSim': 0,
        'dialSim': 0,
        'canRetry': 1,
        'isAdvanced': 0,
        'enabled': 1,
      });
      await db.insert('replies', {
        'condition': TransactionStatuses.secondAttemptMap.keys.first,
        'conditionAmount': 1,
        'dialSim': -1,
        'reply': 'Please add KSh 1 to get your bundle',
        'amounts': '[20]',
        'targetOfferId': offerId,
      });
    }

    test(
        'a Second Attempt report moves the job to Second Attempt and awaits '
        'the configured top-up', () async {
      await seedSecondAttemptReplyTargeting21();
      final id = await seedOriginal();

      // Phone A goes on to send the customer its Second Attempt reply, which
      // reaches Telephony; that is Android-only and asserts in tests.
      await expectLater(
        h.capture(() => handleRemoteMessage(_confirmation(
              from: 'Phone B',
              jobId: _jobB,
              transactionId: 'SJK1ABCD23',
              resultStatus: TransactionStatuses.secondAttempt,
            ))),
        throwsA(isA<AssertionError>()
            .having((e) => '${e.message}', 'message', contains('Android'))),
      );

      final original = await row(id);
      expect(original['status'], TransactionStatuses.secondAttempt);
      expect(original['awaitingTopUp'], 1);
      expect(original['requiredTopUp'], 1);
      expect(original['targetAmount'], 21);
      expect(original['pataMoreJobId'], _jobB);
      expect(original['pataMoreDeviceName'], 'Phone B');
      expect(original['pataMoreTransport'], 'online');
      expect(original['pataMoreState'], isNull);
      expect(h.ussdCalls, isEmpty);
    });

    test(
        'without a target offer the report still awaits a top-up of any '
        'amount', () async {
      final id = await seedOriginal();

      try {
        await h.capture(() => handleRemoteMessage(_confirmation(
              from: 'Phone B',
              jobId: _jobB,
              transactionId: 'SJK1ABCD23',
              resultStatus: TransactionStatuses.secondAttempt,
            )));
      } on AssertionError {
        // processReply reaches Telephony, which is Android-only.
      }

      final original = await row(id);
      expect(original['status'], TransactionStatuses.secondAttempt);
      expect(original['awaitingTopUp'], 1);
      expect(original['requiredTopUp'], isNull);
      expect(original['targetAmount'], isNull);
      expect(original['pataMoreJobId'], _jobB);
    });

    group('the customer tops up', () {
      const topUpSms = 'SJK1TOPUP1 Confirmed. Ksh1.00 received from JOHN DOE '
          '0712345678. SYNTHETIC TEST MESSAGE ONLY.';

      Future<int> seedAwaiting({int? requiredTopUp, int? targetAmount}) async {
        final db = await h.db;
        await db.insert('forwardingDevices', {
          'device_name': 'Phone C',
          'device_id': 'device-c',
          'owner_email': 'owner@example.test',
          'amounts_to_forward': '[21]',
          'paused': 0,
        });
        return seedOriginal(overrides: {
          'status': TransactionStatuses.secondAttempt,
          'canRetry': 0,
          'awaitingTopUp': 1,
          'requiredTopUp': requiredTopUp,
          'targetAmount': targetAmount,
          'pataMoreJobId': _jobB,
          'pataMoreDeviceName': 'Phone B',
          'initialMessage': 'SJK1ABCD23 Confirmed. Ksh20.00 received from '
              'JOHN DOE 0712345678. SYNTHETIC TEST MESSAGE ONLY.',
        });
      }

      Future<RecordingForwardingTransport> receiveTopUp() async {
        final transport = RecordingForwardingTransport();
        final controller = TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: transport,
        );
        try {
          await h
              .capture(() => controller.makeTransactionGivenSmsBody(topUpSms));
        } on AssertionError {
          // A reply after the forward reaches Telephony (Android-only).
        }
        return transport;
      }

      test('with no target, 20 + 1 is forwarded as 21 to the device for 21',
          () async {
        final id = await seedAwaiting();

        final transport = await receiveTopUp();

        expect(transport.submissions, hasLength(1));
        final request = transport.submissions.single.request;
        expect(request['recipientDeviceName'], 'Phone C');
        expect((request['data'] as Map)['body'].toString(), contains('Ksh21'));
        final original = await row(id);
        expect(original['awaitingTopUp'], 0);
        expect(original['requiredTopUp'], 1);
        expect(original['targetAmount'], 21);
        expect(original['topUpTransactionId'], 'SJK1TOPUP1');
        expect(original['pataMoreJobId'], _jobB,
            reason: 'Phone B is still told when 21 completes');
        // In tests the customer reply after the send asserts (Android-only),
        // so the pipeline also records a fallback row; only the forwarded
        // combined row is checked.
        final combined = (await (await h.db).query('transactions',
                where: 'parentTransactionId = ? AND status = ?',
                whereArgs: [id, TransactionStatuses.forwardedPending]))
            .single;
        expect(combined['amount'], 21);
        expect(combined['forwardingRecipientDeviceName'], 'Phone C');
      });

      test('a configured target still requires its exact top-up', () async {
        await seedAwaiting(requiredTopUp: 3, targetAmount: 23);

        final transport = await receiveTopUp();

        expect(
            transport.submissions
                .where((s) => s.request['recipientDeviceName'] == 'Phone C'),
            isEmpty);
      });
    });

    test(
        'a repeated Second Attempt report does not reset a top-up in '
        'progress', () async {
      await seedSecondAttemptReplyTargeting21();
      final id = await seedOriginal(overrides: {
        'status': TransactionStatuses.secondAttempt,
        'awaitingTopUp': 0,
        'topUpTransactionId': 'SJK1TOPUP1',
        'pataMoreJobId': _jobB,
        'pataMoreDeviceName': 'Phone B',
      });

      await h.capture(() => handleRemoteMessage(_confirmation(
            from: 'Phone B',
            jobId: _jobB,
            transactionId: 'SJK1ABCD23',
            resultStatus: TransactionStatuses.secondAttempt,
          )));

      final original = await row(id);
      expect(original['status'], TransactionStatuses.secondAttempt);
      expect(original['awaitingTopUp'], 0);
      expect(h.smsSends, isEmpty, reason: 'the customer is not re-notified');
    });

    test('Second Attempt is not shown as Forwarded (Pending)', () async {
      final id = await seedOriginal(
          overrides: {'status': TransactionStatuses.secondAttempt});
      final db = await h.db;
      Future<List<Object?>> idsIn(TransactionCategory category) async =>
          (await db.query('transactions', where: category.where))
              .map((r) => r['id'])
              .toList();
      expect(await idsIn(TransactionCategory.secondAttempt), [id]);
      expect(await idsIn(TransactionCategory.forwardedPending), isEmpty);
    });

    Future<({int original, int combined})> seedToppedUp() async {
      final original = await seedOriginal(overrides: {
        'status': TransactionStatuses.secondAttempt,
        'awaitingTopUp': 0,
        'topUpTransactionId': 'SJK1TOPUP1',
        'pataMoreJobId': _jobB,
        'pataMoreDeviceName': 'Phone B',
        'pataMoreTransport': 'online',
        // The merge copies the combined job onto the original.
        'forwardingJobId': _jobC,
        'forwardingRecipientDeviceName': 'Phone C',
      });
      final combined = await (await h.db).insert('transactions', {
        'transactionId': 'SJK1TOPUP1',
        'amount': 21,
        'number': 712345678,
        'source': 'JOHN DOE',
        'status': TransactionStatuses.forwardedPending,
        'parentTransactionId': original,
        'forwardingJobId': _jobC,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone C',
        'forwardingTransport': 'online',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      return (original: original, combined: combined);
    }

    test(
        'Phone C confirming the combined amount moves the original to Pata '
        'More and notifies Phone B', () async {
      final ids = await seedToppedUp();

      await h.capture(() => handleRemoteMessage(_confirmation(
            from: 'Phone C',
            jobId: _jobC,
            transactionId: 'SJK1TOPUP1',
          )));

      expect((await row(ids.combined))['status'],
          TransactionStatuses.forwardedConfirmed);
      final original = await row(ids.original);
      expect(original['status'], TransactionStatuses.pataMore);
      expect(original['pataMoreState'], 'pending');

      final notices = h.backendPosts
          .where((p) => p.data['type'] == 'forwarded_sms_pata_more')
          .toList();
      expect(notices, hasLength(1));
      expect(notices.single.json['recipientDeviceName'], 'Phone B');
      expect(notices.single.data['forwardingJobId'], _jobB);
      expect(notices.single.data['transactionId'], 'SJK1ABCD23');
      h.expectNoExternalEffects();
    });

    test('a repeated combined confirmation sends no second notice', () async {
      final ids = await seedToppedUp();
      final confirmation = _confirmation(
        from: 'Phone C',
        jobId: _jobC,
        transactionId: 'SJK1TOPUP1',
      );
      await h.capture(() => handleRemoteMessage(confirmation));
      await h.capture(() => handleRemoteMessage(confirmation));

      expect(
          h.backendPosts
              .where((p) => p.data['type'] == 'forwarded_sms_pata_more'),
          hasLength(1));
      expect((await row(ids.original))['pataMoreAttempt'], 1);
    });

    test("Phone B's receipt marks the notice delivered", () async {
      final ids = await seedToppedUp();
      await h.capture(() => handleRemoteMessage(_confirmation(
            from: 'Phone C',
            jobId: _jobC,
            transactionId: 'SJK1TOPUP1',
          )));

      await h.capture(
          () => handleRemoteMessage(_pataMoreReceipt(from: 'Phone Z')));
      expect((await row(ids.original))['pataMoreState'], 'pending',
          reason: 'a receipt from another device is ignored');

      await h.capture(() => handleRemoteMessage(_pataMoreReceipt()));
      expect((await row(ids.original))['pataMoreState'], 'delivered');
    });

    test('Phone B confirming its own Second Attempt job is not a Pata More',
        () async {
      final id = await seedOriginal(overrides: {
        'status': TransactionStatuses.secondAttempt,
        'pataMoreJobId': _jobB,
        'pataMoreDeviceName': 'Phone B',
      });

      await h.capture(() => handleRemoteMessage(_confirmation(
            from: 'Phone B',
            jobId: _jobB,
            transactionId: 'SJK1ABCD23',
          )));

      final original = await row(id);
      expect(original['status'], TransactionStatuses.forwardedConfirmed);
      expect(original['pataMoreState'], isNull);
      expect(
          h.backendPosts
              .where((p) => p.data['type'] == 'forwarded_sms_pata_more'),
          isEmpty);
    });
  });

  group('Phone B', () {
    setUp(() => h.setUp(prefs: {
          'user_device_name': 'Phone B',
          'jwt_token': 'test-jwt',
        }));

    Future<int> seedSecondAttempt() async => (await h.db).insert(
          'transactions',
          {
            'transactionId': 'SJK1ABCD23',
            'amount': 20,
            'number': 712345678,
            'source': 'JOHN DOE',
            'status': TransactionStatuses.secondAttempt,
            'forwardingJobId': _jobB,
            'forwardingSenderDeviceName': 'Phone A',
            'timeStamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

    test(
        'a Pata More notice from the origin device moves the row and is '
        'receipted', () async {
      final id = await seedSecondAttempt();

      await h.capture(() => handleRemoteMessage(_pataMoreNotice()));

      expect((await row(id))['status'], TransactionStatuses.pataMore);
      final receipt = h.backendPosts.single;
      expect(receipt.data['type'], 'MESSAGE_ACK');
      expect(receipt.data['ackKind'], 'pata_more_received');
      expect(receipt.data['originalType'], 'forwarded_sms_pata_more');
      expect(receipt.json['recipientDeviceName'], 'Phone A');
      h.expectNoExternalEffects();
    });

    test('a repeated notice is receipted again without other changes',
        () async {
      final id = await seedSecondAttempt();
      await h.capture(() async {
        await handleRemoteMessage(_pataMoreNotice());
        await handleRemoteMessage(_pataMoreNotice());
      });
      expect((await row(id))['status'], TransactionStatuses.pataMore);
      expect(h.backendPosts, hasLength(2));
    });

    test('a notice from another device is ignored', () async {
      final id = await seedSecondAttempt();

      await h
          .capture(() => handleRemoteMessage(_pataMoreNotice(from: 'Phone Z')));

      expect((await row(id))['status'], TransactionStatuses.secondAttempt);
      expect(h.backendPosts, isEmpty);
    });
  });

  group("Phone C running Phone B's alternative", () {
    late _ScriptedPhoneService phone;
    late TransactionController controller;

    setUp(() async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone C',
        'jwt_token': 'test-jwt',
      });
      phone = _ScriptedPhoneService();
      controller = TransactionController(
        phoneService: phone,
        paymentOps: _PaidPaymentOps(),
        sharedPreferencesService: SharedPreferencesService(),
        startConfirmationTimer: false,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await (await h.db).insert('alternativeJobs', {
        'forwardingJobId': _jobAlt,
        'transactionId': '7',
        'state': 'reserved',
        'ussdCode': _altCode,
        'smsMessage': 'SJK1ALT123 Confirmed. Ksh20.00 received from '
            'JOHN DOE 0712345678 on 1/11/26 at 6:16 PM.',
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': 'Phone C',
        'createdAt': now,
        'updatedAt': now,
      });
    });

    Future<Map<String, Object?>> job() async =>
        (await (await h.db).query('alternativeJobs',
                where: 'forwardingJobId = ?', whereArgs: [_jobAlt]))
            .single;

    Future<List<Map<String, Object?>>> jobRows() async =>
        (await h.db).query('transactions',
            where: 'forwardingJobId = ?', whereArgs: [_jobAlt]);

    List<Map<String, dynamic>> results() => h.backendPosts
        .where((p) => p.data['type'] == 'forwarded_alt_result')
        .map((p) => p.data)
        .toList();

    test('an error is not sent to Phone B; the alternative is retried',
        () async {
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));

      expect(phone.calls, [_altCode]);
      expect(results(), isEmpty, reason: 'the error is not reported');
      final waiting = await job();
      expect(waiting['state'], 'reserved');
      expect(waiting['retryAttempt'], 1);
      expect(waiting['retryAt'] as int,
          greaterThan(DateTime.now().millisecondsSinceEpoch));
      final failed = (await jobRows()).single;
      expect(failed['status'], TransactionStatuses.error);
      // Not the generic retry, which would dial the primary code.
      final candidates = await SQLiteService().getAutomaticRetryCandidates(
        isAutoRetrying: true,
        retryLimit: 100,
        today: failed['date'] as String,
      );
      expect(candidates.map((c) => c['id']), isNot(contains(failed['id'])));

      // Not before its time.
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));
      expect(phone.calls, hasLength(1));

      // When due, the alternative code is dialed again; the success goes to
      // Phone B and the earlier error row is gone.
      await (await h.db).update('alternativeJobs', {'retryAt': 0});
      phone.responses.add((
        'Recommendation for 0712345678 submitted successfully',
        TransactionStatuses.done,
      ));
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));

      expect(phone.calls, [_altCode, _altCode]);
      final rows = await jobRows();
      expect(rows, hasLength(1));
      expect(rows.single['id'], isNot(failed['id']));
      expect(rows.single['status'], TransactionStatuses.successfulPending);
      expect(results().single['status'], TransactionStatuses.successfulPending);
      expect(results().single['recipientDeviceName'], 'Phone B');
    });

    test('a manual retry of the error row dials the alternative now', () async {
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));
      final failed = (await jobRows()).single;
      phone.responses.add((
        'Recommendation for 0712345678 submitted successfully',
        TransactionStatuses.done,
      ));

      await h.capture(
          () => controller.manuallyRetryTransaction(failed['id'] as int));

      expect(phone.calls, [_altCode, _altCode]);
      expect((await jobRows()).single['status'],
          TransactionStatuses.successfulPending);
    });

    test('once the retries are used up the failure is reported', () async {
      await (await h.db).update('alternativeJobs', {'retryAttempt': 10});

      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));

      expect((await job())['state'], 'completed');
      expect(results().single['status'], TransactionStatuses.error);
    });
  });

  test('the notice and its receipt are LAN message kinds', () {
    expect(
      lanMessageKindOf({'type': 'forwarded_sms_pata_more'}),
      LanMessageKind.pataMoreNotice,
    );
    expect(lanRequestKinds, contains(LanMessageKind.pataMoreNotice));
    expect(
      lanMessageKindOf({
        'type': 'MESSAGE_ACK',
        'ackKind': 'pata_more_received',
        'originalType': 'forwarded_sms_pata_more',
      }),
      LanMessageKind.pataMoreReceipt,
    );
    expect(lanReplyKindsFor(LanMessageKind.pataMoreNotice),
        {LanMessageKind.pataMoreReceipt});
  });
}
