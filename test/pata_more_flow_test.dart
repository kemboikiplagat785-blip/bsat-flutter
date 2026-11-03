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

/// The customer's reply needs Android's SMS API.
class _NoCustomerSmsController extends TransactionController {
  _NoCustomerSmsController({super.phoneService, super.paymentOps})
      : super(
          sharedPreferencesService: SharedPreferencesService(),
          startConfirmationTimer: false,
        );

  @override
  Future<void> processReply(
    int number,
    String transactionStatus,
    String firstName,
    String lastName,
    int amount,
  ) async {}
}

const _jobAlt = 'fwd_SJK1ALT123_1761650200000';
const _altCode = '*180*5*2*0712345678*1*1#';
const _poolStateReply = 'Sorry, there was an error. Please try again later.'
    '(The subscriber is in pool state, and service handling is not allowed.';

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
      // Phone B only learns that its queue can move on, not the error.
      expect(results().single['status'],
          TransactionStatuses.alternativeRetrying);
      expect(results().single['ussdReply'], '');
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
      expect(results().last['status'], TransactionStatuses.successfulPending);
      expect(results().last['recipientDeviceName'], 'Phone B');
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

    test('after three automatic retries it waits for a manual retry; Phone B '
        'never gets the error', () async {
      Future<void> dial() async {
        await (await h.db).update('alternativeJobs', {'retryAt': 0});
        await h.capture(
            () => controller.processReservedAlternativeRequest(_jobAlt));
      }

      for (var i = 0; i < 4; i++) {
        await dial();
      }

      expect(phone.calls, hasLength(4), reason: 'the first dial and 3 retries');
      expect((await job())['state'], 'manual_retry');
      expect(results().map((r) => r['status']),
          everyElement(TransactionStatuses.alternativeRetrying));

      // No more automatic dials.
      await dial();
      expect(phone.calls, hasLength(4));

      // The user can still retry, and a success reaches Phone B.
      final failed = (await jobRows()).single;
      expect(failed['status'], TransactionStatuses.error);
      phone.responses.add((
        'Recommendation for 0712345678 submitted successfully',
        TransactionStatuses.done,
      ));
      final result = await h.capture(
          () => controller.manuallyRetryTransaction(failed['id'] as int));

      expect(result, ManualRetryResult.executionDispatched);
      expect(phone.calls, hasLength(5));
      expect(phone.calls.last, _altCode);
      expect((await jobRows()).single['status'],
          TransactionStatuses.successfulPending);
      expect(results().last['status'], TransactionStatuses.successfulPending);
    });

    test('a manual retry that fails again stays on Phone C', () async {
      await (await h.db).update('alternativeJobs', {'retryAttempt': 3});
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));
      expect((await job())['state'], 'manual_retry');
      final failed = (await jobRows()).single;

      final result = await h.capture(
          () => controller.manuallyRetryTransaction(failed['id'] as int));

      expect(result, ManualRetryResult.executionDispatched);
      expect(phone.calls, hasLength(2));
      expect((await job())['state'], 'manual_retry');
      expect((await jobRows()).single['status'], TransactionStatuses.error);
    });

    test('an attempt that never reached the carrier uses no retry', () async {
      phone.responses.add((
        'Error sending code: MissingPluginException(no channel)',
        TransactionStatuses.error,
      ));
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));

      final waiting = await job();
      expect(waiting['state'], 'reserved');
      expect(waiting['retryAttempt'], 0);
    });

    test('a pool state reply is Okoa: it is reported and not retried',
        () async {
      phone.responses.add((_poolStateReply, TransactionStatuses.error));

      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));

      expect((await jobRows()).single['status'], TransactionStatuses.hasOkoa);
      final finished = await job();
      expect(finished['state'], 'completed');
      expect(finished['retryAttempt'], 0);
      expect(results().single['status'], TransactionStatuses.hasOkoa);
    });

    test('a confirmation after Okoa replaces the result Phone B has', () async {
      phone.responses.add((_poolStateReply, TransactionStatuses.error));
      await h
          .capture(() => controller.processReservedAlternativeRequest(_jobAlt));
      await (await h.db)
          .update('alternativeJobs', {'resultDeliveryState': 'delivered'});
      final okoa = (await jobRows()).single;
      phone.responses.add((
        'You have successfully purchased 1GB for 0712345678',
        TransactionStatuses.done,
      ));

      await h.capture(
          () => controller.manuallyRetryTransaction(okoa['id'] as int));

      expect((await jobRows()).single['status'],
          TransactionStatuses.doneConfirmed);
      expect(results().last['status'], TransactionStatuses.doneConfirmed);
    });
  });

  group('Phone B after asking Phone C for the alternative', () {
    const jobNext = 'fwd_SJK1NEXT99_1761650300000';

    setUp(() => h.setUp(prefs: {
          'user_device_name': 'Phone B',
          'jwt_token': 'test-jwt',
        }));

    Future<int> altRow(
      String jobId, {
      String queueState = 'active',
      String status = TransactionStatuses.forwardedPending,
    }) async =>
        (await h.db).insert('transactions', {
          'transactionId': 'RCPT-$jobId',
          'initialMessage': 'RCPT-$jobId Confirmed. Ksh20.00 received from '
              'JOHN DOE 0712345678.',
          'amount': 20,
          'number': 712345678,
          'status': status,
          'canRetry': 0,
          'forwardingJobId': jobId,
          'forwardingSenderDeviceName': 'Phone A',
          'forwardingRecipientDeviceName': 'Phone C',
          'forwardingTransport': 'online',
          'alternativeRequestSenderDeviceName': 'Phone B',
          'alternativeRequestCode': _altCode,
          'alternativeQueueState': queueState,
          'ussdReply': 'Alternative request durably received by target.',
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
        });

    RemoteMessage result(int rowId, String status, {String reply = ''}) =>
        RemoteMessage(messageId: 'alt-$status', data: {
          'type': 'forwarded_alt_result',
          'transactionId': '$rowId',
          'forwardingJobId': _jobAlt,
          'status': status,
          'ussdReply': reply,
          'senderDeviceName': 'Phone C',
          'recipientDeviceName': 'Phone B',
        });

    List<Map<String, dynamic>> sent(String type) => h.backendPosts
        .where((p) => p.data['type'] == type)
        .map((p) => p.data)
        .toList();

    test('"still retrying" keeps Forwarded (Pending) and frees the queue',
        () async {
      final id = await altRow(_jobAlt);
      final next = await altRow(
        jobNext,
        queueState: 'waiting',
        status: TransactionStatuses.alternativeDeliveryPending,
      );

      await h.capture(() => handleRemoteMessage(
          result(id, TransactionStatuses.alternativeRetrying)));

      final mine = await row(id);
      expect(mine['status'], TransactionStatuses.forwardedPending);
      expect(mine['ussdReply'],
          'Alternative request durably received by target.');
      expect(mine['alternativeQueueState'], 'released');
      expect((await row(next))['alternativeQueueState'], 'active');
      expect(sent('process_alt_request').single['forwardingJobId'], jobNext);
      expect(sent('MESSAGE_ACK').single['ackKind'],
          'alternative_result_received');
      expect(sent('forwarded_sms_ack'), isEmpty,
          reason: 'Phone A is not told about an attempt that failed');
    });

    test('an error from a Phone C that is not updated yet does the same',
        () async {
      final id = await altRow(_jobAlt);

      await h.capture(() => handleRemoteMessage(
          result(id, TransactionStatuses.error, reply: 'Sorry, try later')));

      final mine = await row(id);
      expect(mine['status'], TransactionStatuses.forwardedPending);
      expect(mine['ussdReply'], isNot(contains('Sorry')));
    });

    test('the retry succeeding on Phone C still reaches this row', () async {
      final id = await altRow(_jobAlt, queueState: 'released');

      await h.capture(() => handleRemoteMessage(
          result(id, TransactionStatuses.successfulPending, reply: 'ok')));

      expect((await row(id))['status'], TransactionStatuses.successfulPending);
      expect(sent('MESSAGE_ACK').single['ackKind'],
          'alternative_result_received');
    });

    test('Okoa moves this row and tells Phone A; a later confirmation '
        'upgrades both', () async {
      final id = await altRow(_jobAlt);
      final next = await altRow(
        jobNext,
        queueState: 'waiting',
        status: TransactionStatuses.alternativeDeliveryPending,
      );

      await h.capture(() => handleRemoteMessage(result(
          id, TransactionStatuses.hasOkoa,
          reply: _poolStateReply)));

      final mine = await row(id);
      expect(mine['status'], TransactionStatuses.hasOkoa);
      expect(mine['alternativeQueueState'], 'released');
      expect((await row(next))['alternativeQueueState'], 'active');
      final toA = sent('forwarded_sms_ack').single;
      expect(toA['resultStatus'], TransactionStatuses.hasOkoa);
      expect(toA['recipientDeviceName'], 'Phone A');

      h.requests.clear();
      await h.capture(() => handleRemoteMessage(
          result(id, TransactionStatuses.doneConfirmed, reply: 'purchased')));

      expect((await row(id))['status'], TransactionStatuses.pataMore);
      expect(sent('forwarded_sms_ack').single['resultStatus'],
          TransactionStatuses.doneConfirmed);
    });
  });

  group('a forwarded transaction that gets a pool state reply on Phone B', () {
    late _ScriptedPhoneService phone;
    late TransactionController controller;

    setUp(() async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone B',
        'jwt_token': 'test-jwt',
      });
      phone = _ScriptedPhoneService();
      controller = TransactionController(
        phoneService: phone,
        paymentOps: _PaidPaymentOps(),
        sharedPreferencesService: SharedPreferencesService(),
        startConfirmationTimer: false,
      );
    });

    test('is Okoa even if a custom code matches its text', () async {
      await (await h.db).rawInsert(
        'INSERT INTO "custom codes" '
        '(pattern, transactionStatus, isCaseSensitive) VALUES (?, ?, 0)',
        ['Sorry', TransactionStatuses.error],
      );

      expect(
        await controller
            .transactionStatus([_poolStateReply, TransactionStatuses.paused]),
        TransactionStatuses.hasOkoa,
      );
    });

    test('keeps its job and tells Phone A', () async {
      final id = await h.capture(() => controller.dontProcess(
            'message',
            'SJK1ABCD23',
            712345678,
            '*180#',
            20,
            1,
            status: TransactionStatuses.hasOkoa,
            reply: _poolStateReply,
            forwardingJobId: _jobB,
            forwardingSenderDeviceName: 'Phone A',
          ));

      expect((await row(id!))['forwardingJobId'], _jobB);
      final toA = h.backendPosts
          .singleWhere((p) => p.data['type'] == 'forwarded_sms_ack')
          .data;
      expect(toA['resultStatus'], TransactionStatuses.hasOkoa);
      expect(toA['recipientDeviceName'], 'Phone A');
    });

    test('on a retry also tells Phone A', () async {
      final db = await h.db;
      final offer = await db.insert('ussdCodes', {
        'amount': 20,
        'fromSim': -1,
        'dialSim': 1,
        'canRetry': 1,
        'isAdvanced': 0,
        'enabled': 1,
      });
      await db.insert('ussdCodeVariants', {'ussdCodeId': offer, 'code': '*180#'});
      final id = await db.insert('transactions', {
        'transactionId': 'SJK1ABCD23',
        'initialMessage': 'SJK1ABCD23 Confirmed. Ksh20.00 received from '
            'JOHN DOE 0712345678 on 1/11/26 at 6:16 PM.',
        'amount': 20,
        'number': 712345678,
        'status': TransactionStatuses.error,
        'ussdDialed': '*180#',
        'ussdReply': 'Error sending code: timeout',
        'source': 'JOHN DOE',
        'simSubId': 1,
        'canRetry': 1,
        'date': 'today',
        'smsDate': 'today',
        'smsTime': 'now',
        'forwardingJobId': _jobB,
        'forwardingSenderDeviceName': 'Phone A',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      phone.responses.add((_poolStateReply, TransactionStatuses.done));

      await h.capture(() => _NoCustomerSmsController(
            phoneService: phone,
            paymentOps: _PaidPaymentOps(),
          ).manuallyRetryTransaction(id));

      expect((await row(id))['status'], TransactionStatuses.hasOkoa);
      final toA = h.backendPosts
          .singleWhere((p) => p.data['type'] == 'forwarded_sms_ack')
          .data;
      expect(toA['resultStatus'], TransactionStatuses.hasOkoa);
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
