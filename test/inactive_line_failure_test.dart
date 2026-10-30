// Safaricom's "Purchase failed, the customer line is inactive" SMS names no
// customer. It is held and given to the Successful(Pending) transaction it
// belongs to (same SIM, dialed shortly before), which moves to Okoa without
// an SMS to the customer; Phone A is told for a forwarded job. Synthetic
// data only; no SMS, USSD or network request may happen (asserted).
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/models/transaction_message.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/inactive_line_failure.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _failure = 'Purchase failed, the customer line is inactive. Kindly '
    'topup the line with any amount to reactivate';
const _minute = 60 * 1000;

void main() {
  final h = Stage0Harness();
  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);

  group('recognising the message', () {
    test('the Safaricom text is recognised; other texts are not', () {
      expect(isInactiveLineFailureMessage(_failure), isTrue);
      expect(isInactiveLineFailureMessage(_failure.toUpperCase()), isTrue);
      expect(
          isInactiveLineFailureMessage(
              'Recommendation for 0712345678 submitted successfully'),
          isFalse);
      expect(isInactiveLineFailureMessage('Purchase failed. Try again'),
          isFalse);
    });
  });

  group('matching rules', () {
    const t0 = 1800000000000;
    InactiveLineFailure failure(int id, int at, {int? sim = 3}) =>
        InactiveLineFailure(id: id, smsTimestamp: at, simSubId: sim);
    PendingPurchase purchase(int id, int dialedAt, {int? sim = 3}) =>
        PendingPurchase(id: id, dialedAt: dialedAt, simSubId: sim);

    test('one pending purchase on that SIM gets the failure at once', () {
      expect(
        matchInactiveLineFailures(
          failures: [failure(1, t0)],
          pending: [purchase(10, t0 - _minute)],
          now: t0,
        ),
        [(1, 10)],
      );
    });

    test('a purchase on another SIM, dialed after the SMS, or dialed too '
        'long before it is not a match', () {
      expect(
        matchInactiveLineFailures(
          failures: [failure(1, t0)],
          pending: [
            purchase(10, t0 - _minute, sim: 4),
            purchase(11, t0 + _minute),
            purchase(12, t0 - 21 * _minute),
          ],
          now: t0 + 60 * _minute,
        ),
        isEmpty,
      );
    });

    test('two pending purchases: nothing is guessed before the wait', () {
      expect(
        matchInactiveLineFailures(
          failures: [failure(1, t0)],
          pending: [purchase(10, t0 - 2 * _minute), purchase(11, t0 - _minute)],
          now: t0 + 4 * _minute,
        ),
        isEmpty,
      );
    });

    test('after the wait, one failure and two purchases is still unclear', () {
      expect(
        matchInactiveLineFailures(
          failures: [failure(1, t0)],
          pending: [purchase(10, t0 - 2 * _minute), purchase(11, t0 - _minute)],
          now: t0 + 6 * _minute,
        ),
        isEmpty,
      );
    });

    test('after the wait, as many failures as purchases pair oldest-first',
        () {
      expect(
        matchInactiveLineFailures(
          failures: [failure(2, t0 + 30 * 1000), failure(1, t0)],
          pending: [purchase(11, t0 - _minute), purchase(10, t0 - 2 * _minute)],
          now: t0 + 6 * _minute,
        ),
        [(1, 10), (2, 11)],
      );
    });

    test('one pairing can make the next failure clear', () {
      // Failure 1 fits only purchase 10; then failure 2 fits only 11.
      expect(
        matchInactiveLineFailures(
          failures: [failure(1, t0), failure(2, t0 + 5 * _minute)],
          pending: [purchase(10, t0 - _minute), purchase(11, t0 + 4 * _minute)],
          now: t0 + 5 * _minute,
        ),
        unorderedEquals([(1, 10), (2, 11)]),
      );
    });

    test('an unknown SIM on either side does not rule a purchase out', () {
      expect(
        matchInactiveLineFailures(
          failures: [failure(1, t0, sim: null)],
          pending: [purchase(10, t0 - _minute, sim: 4)],
          now: t0,
        ),
        [(1, 10)],
      );
    });
  });

  group('Phone B', () {
    tearDown(h.tearDown);

    late RecordingForwardingTransport online;
    late TransactionController controller;

    Future<void> phoneB() async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone B',
        'jwt_token': 'stage0-test-jwt',
      });
      online = RecordingForwardingTransport();
      controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransport: online,
        startConfirmationTimer: false,
      );
    }

    Future<int> pending({
      required int dialedAt,
      int number = 712345678,
      String? jobFrom,
    }) async =>
        (await h.db).insert('transactions', {
          'initialMessage': 'SJK1OKOA01 Confirmed. Ksh50.00 received from '
              'JOHN DOE 0$number. SYNTHETIC TEST MESSAGE ONLY.',
          'transactionId': 'SJK1OKOA01',
          'number': number,
          'amount': 50,
          'date': 'today',
          'time': '12:00',
          'smsDate': 'today',
          'smsTime': '12:00',
          'ussdDialed': '*180*5*2*0$number*1#',
          'ussdReply': 'Recommendation for 0$number submitted successfully',
          'simSubId': 3,
          'source': 'JOHN DOE',
          'status': TransactionStatuses.successfulPending,
          'canRetry': 0,
          'timeStamp': dialedAt,
          if (jobFrom != null) ...{
            'forwardingJobId': 'fwd_SJK1OKOA01_1',
            'forwardingSenderDeviceName': jobFrom,
          },
        });

    Future<Map<String, Object?>> row(int id) async => (await (await h.db)
            .query('transactions', where: 'id = ?', whereArgs: [id]))
        .single;

    // The customer reply to a confirmation is not part of these tests (it
    // is never sent for the failure itself).
    Future<void> receive(String body, int at, {int? sim = 3}) =>
        h.capture(() => controller.updateWithMessage(
              TransactionMessage(body: body, date: at, subscriptionId: sim),
              notifyReplies: isInactiveLineFailureMessage(body),
            ));

    test('the only pending purchase on that SIM moves to Okoa; no SMS is '
        'sent to the customer', () async {
      await phoneB();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - _minute);

      await receive(_failure, now);

      final updated = await row(id);
      expect(updated['status'], TransactionStatuses.hasOkoa);
      expect(updated['ussdReply'], startsWith(_failure));
      expect(online.submissions, isEmpty, reason: 'not a forwarded job');
      h.expectNoExternalEffects();
    });

    test('a forwarded job tells Phone A it went to Okoa', () async {
      await phoneB();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - _minute, jobFrom: 'Phone A');

      await receive(_failure, now);

      expect((await row(id))['status'], TransactionStatuses.hasOkoa);
      final data = online.submissions.single.request['data'] as Map;
      expect(data['type'], 'forwarded_sms_ack');
      expect(data['resultStatus'], TransactionStatuses.hasOkoa);
      expect(data['forwardingJobId'], 'fwd_SJK1OKOA01_1');
      expect(data['recipientDeviceName'], 'Phone A');
      h.expectNoExternalEffects();
    });

    test('two pending purchases: the failure waits until a confirmation '
        'rules one out', () async {
      await phoneB();
      final now = DateTime.now().millisecondsSinceEpoch;
      final first = await pending(dialedAt: now - 2 * _minute);
      final second =
          await pending(dialedAt: now - _minute, number: 723456789);

      await receive(_failure, now);
      expect((await row(first))['status'], TransactionStatuses.successfulPending);
      expect(
          (await row(second))['status'], TransactionStatuses.successfulPending);

      await receive(
          'You have successfully recommended offer to 0712345678. Total '
          'commission this week Ksh 10.',
          now + 1000);

      expect((await row(first))['status'], TransactionStatuses.doneConfirmed);
      expect((await row(second))['status'], TransactionStatuses.hasOkoa);
      h.expectNoExternalEffects();
    });

    test('a confirmation after Okoa wins, and frees the failure for the '
        'purchase it belonged to', () async {
      await phoneB();
      final now = DateTime.now().millisecondsSinceEpoch;
      final wrong = await pending(dialedAt: now - 2 * _minute);
      await receive(_failure, now);
      expect((await row(wrong))['status'], TransactionStatuses.hasOkoa);

      // A purchase whose confirmation had not been seen yet was the one
      // that failed: it is still pending, dialed before the failure.
      final right = await pending(dialedAt: now - 3 * _minute, number: 723456789);
      await receive(
          'You have successfully recommended offer to 0712345678. Total '
          'commission this week Ksh 10.',
          now + 1000);

      expect((await row(wrong))['status'], TransactionStatuses.doneConfirmed);
      expect((await row(right))['status'], TransactionStatuses.hasOkoa);
      h.expectNoExternalEffects();
    });

    test('the same SMS seen twice is held once', () async {
      await phoneB();
      final now = DateTime.now().millisecondsSinceEpoch;
      await receive(_failure, now);
      await receive(_failure, now);
      expect(await (await h.db).query('inactiveLineFailures'), hasLength(1));
      h.expectNoExternalEffects();
    });
  });

  group('Phone A', () {
    tearDown(h.tearDown);

    test("Phone B's Okoa result moves the forwarded copy from Forwarded "
        '(Pending) to Okoa; a later confirmation still confirms it', () async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone A',
        'jwt_token': 'stage0-test-jwt',
      });
      final id = await (await h.db).insert('transactions', {
        'initialMessage': 'SJK1OKOA02 Confirmed. Ksh50.00 received from '
            'JOHN DOE 0712345678. SYNTHETIC TEST MESSAGE ONLY.',
        'transactionId': 'SJK1OKOA02',
        'number': 712345678,
        'amount': 50,
        'date': 'today',
        'time': '12:00',
        'smsDate': 'today',
        'smsTime': '12:00',
        'ussdDialed': '',
        'ussdReply': 'Forwarded to Phone B',
        'simSubId': -1,
        'source': 'JOHN DOE',
        'status': TransactionStatuses.forwardedPending,
        'canRetry': 0,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'forwardingJobId': 'fwd_SJK1OKOA02_1',
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone B',
        'forwardingTransport': 'online',
      });
      Future<void> result(String status) => h.capture(() => handleRemoteMessage(
            RemoteMessage(data: {
              'type': 'forwarded_sms_ack',
              'ackKind': 'confirmed',
              'status': TransactionStatuses.doneConfirmed,
              'resultStatus': status,
              'forwardingJobId': 'fwd_SJK1OKOA02_1',
              'transactionId': '7',
              'senderDeviceName': 'Phone B',
              'recipientDeviceName': 'Phone A',
            }),
          ));
      Future<Object?> status() async => (await (await h.db)
              .query('transactions', where: 'id = ?', whereArgs: [id]))
          .single['status'];

      await result(TransactionStatuses.hasOkoa);
      expect(await status(), TransactionStatuses.hasOkoa);

      await result(TransactionStatuses.doneConfirmed);
      expect(await status(), TransactionStatuses.forwardedConfirmed);
      h.expectNoExternalEffects();
    });
  });
}
