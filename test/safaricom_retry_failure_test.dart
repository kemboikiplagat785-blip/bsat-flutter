// Safaricom's temporary failure SMSes name no customer. Each is held for a
// minute, then given to the Successful(Pending) transaction it belongs to
// (same SIM, dialed shortly before), which moves to Error and is auto retried
// up to three times, a minute apart. Synthetic data only; no SMS, USSD or
// network request may happen (asserted).
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/models/transaction_message.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/inactive_line_failure.dart';
import 'package:bsat/utils/safaricom_retry_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _sorry =
    "We're sorry, your transaction could not be completed. Please try again later.";
const _unable = 'Sorry, we are unable to process your request at the moment.';
const _inactive = 'Purchase failed, the customer line is inactive. Kindly '
    'topup the line with any amount to reactivate';
const _minute = 60 * 1000;

void main() {
  final h = Stage0Harness();
  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);

  group('recognising the messages', () {
    test('both Safaricom texts are recognised, with or without the apostrophe',
        () {
      expect(isSafaricomRetryFailureMessage(_sorry), isTrue);
      expect(
          isSafaricomRetryFailureMessage(_sorry.replaceAll("'", '')), isTrue);
      expect(isSafaricomRetryFailureMessage(_sorry.toUpperCase()), isTrue);
      expect(isSafaricomRetryFailureMessage(_unable), isTrue);
    });

    test('Okoa and success messages are not', () {
      expect(isSafaricomRetryFailureMessage(_inactive), isFalse);
      expect(isInactiveLineFailureMessage(_sorry), isFalse);
      expect(isInactiveLineFailureMessage(_unable), isFalse);
      expect(
        isSafaricomRetryFailureMessage(
            'Recommendation for 0712345678 submitted successfully'),
        isFalse,
      );
    });
  });

  group('held failures', () {
    tearDown(h.tearDown);

    late TransactionController controller;
    late SQLiteService sqlite;

    Future<void> phone() async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone B',
        'jwt_token': 'stage0-test-jwt',
      });
      sqlite = SQLiteService();
      controller = TransactionController(
        sqliteService: sqlite,
        forwardingTransport: RecordingForwardingTransport(),
        startConfirmationTimer: false,
      );
    }

    Future<int> pending({
      required int dialedAt,
      int number = 712345678,
      String? jobId,
    }) async =>
        (await h.db).insert('transactions', {
          'initialMessage': 'SJK1RETRY1 Confirmed. Ksh50.00 received from '
              'JOHN DOE 0$number. SYNTHETIC TEST MESSAGE ONLY.',
          'transactionId': 'SJK1RETRY1',
          'number': number,
          'amount': 50,
          'date': 'today',
          'time': '12:00',
          'smsDate': 'today',
          'smsTime': '12:00',
          'ussdDialed': '*180*5*2*0$number*1#',
          'ussdReply': 'Recommendation for 0$number submitted successfully',
          'simSubId': 3,
          'source': jobId == null ? 'JOHN DOE' : 'manual',
          'status': TransactionStatuses.successfulPending,
          'retryState': 'blocked',
          'canRetry': 0,
          'timeStamp': dialedAt,
          if (jobId != null) 'forwardingJobId': jobId,
        });

    Future<Map<String, Object?>> row(int id) async => (await (await h.db)
            .query('transactions', where: 'id = ?', whereArgs: [id]))
        .single;

    Future<void> receive(String body, int at) =>
        h.capture(() => controller.updateWithMessage(
              TransactionMessage(body: body, date: at, subscriptionId: 3),
              notifyReplies: false,
            ));

    Future<List<int>> retryCandidates() async =>
        (await sqlite.getAutomaticRetryCandidates(
          isAutoRetrying: true,
          retryLimit: 12,
          today: 'today',
        ))
            .map((candidate) => candidate['id'] as int)
            .toList();

    Future<void> dial(int id) async {
      expect(await sqlite.claimTransactionRetry(id), 1);
      expect(await sqlite.beginTransactionRetryDispatch(id), 1);
    }

    test('nothing moves during the minute waiting for a confirmation',
        () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - 2 * _minute);

      await receive(_sorry, now - 30 * 1000);
      await controller.resolveSafaricomRetryFailures();

      expect((await row(id))['status'], TransactionStatuses.successfulPending);
      expect(await retryCandidates(), isEmpty);
      h.expectNoExternalEffects();
    });

    for (final message in [_sorry, _unable]) {
      test(
          'after the minute the only pending purchase moves to Error and is '
          'retried: $message', () async {
        await phone();
        final now = DateTime.now().millisecondsSinceEpoch;
        final id = await pending(dialedAt: now - 3 * _minute);

        await receive(message, now - _minute - 1000);
        await controller.resolveSafaricomRetryFailures();

        final updated = await row(id);
        expect(updated['status'], TransactionStatuses.error);
        expect(updated['ussdReply'], startsWith(message));
        expect(await retryCandidates(), [id]);
        await dial(id);
        h.expectNoExternalEffects();
      });
    }

    test('a confirmation during the wait keeps the purchase confirmed',
        () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - 3 * _minute);

      await receive(_sorry, now - _minute - 1000);
      await receive(
          'You have successfully recommended offer to 0712345678. Total '
          'commission this week Ksh 10.',
          now - 1000);
      await controller.resolveSafaricomRetryFailures();

      expect((await row(id))['status'], TransactionStatuses.doneConfirmed);
      expect(await retryCandidates(), isEmpty);
      h.expectNoExternalEffects();
    });

    test(
        'one failure with two pending waits until a confirmation rules one '
        'out', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final first = await pending(dialedAt: now - 3 * _minute);
      final second =
          await pending(dialedAt: now - 2 * _minute, number: 723456789);

      await receive(_unable, now - _minute - 1000);
      await controller.resolveSafaricomRetryFailures();
      expect(
          (await row(first))['status'], TransactionStatuses.successfulPending);
      expect(
          (await row(second))['status'], TransactionStatuses.successfulPending);

      await receive(
          'You have successfully recommended offer to 0712345678. Total '
          'commission this week Ksh 10.',
          now);
      await controller.resolveSafaricomRetryFailures();

      expect((await row(first))['status'], TransactionStatuses.doneConfirmed);
      expect((await row(second))['status'], TransactionStatuses.error);
      h.expectNoExternalEffects();
    });

    test('two failures with two pending move both', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final first = await pending(dialedAt: now - 4 * _minute);
      final second =
          await pending(dialedAt: now - 3 * _minute, number: 723456789);

      await receive(_sorry, now - 2 * _minute);
      await receive(_unable, now - 2 * _minute + 1000);
      await controller.resolveSafaricomRetryFailures();

      expect((await row(first))['status'], TransactionStatuses.error);
      expect((await row(second))['status'], TransactionStatuses.error);
      h.expectNoExternalEffects();
    });

    test(
        'a purchase dialed after the failure, or on another SIM, is left '
        'alone', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final later = await pending(dialedAt: now - _minute);
      final otherSim =
          await pending(dialedAt: now - 3 * _minute, number: 723456789);
      await (await h.db).update('transactions', {'simSubId': 4},
          where: 'id = ?', whereArgs: [otherSim]);

      await receive(_sorry, now - 2 * _minute);
      await controller.resolveSafaricomRetryFailures();

      expect(
          (await row(later))['status'], TransactionStatuses.successfulPending);
      expect((await row(otherSim))['status'],
          TransactionStatuses.successfulPending);
      h.expectNoExternalEffects();
    });

    test('the inactive-line failure still goes to Okoa', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - _minute);

      await receive(_inactive, now);

      expect((await row(id))['status'], TransactionStatuses.hasOkoa);
      expect(await (await h.db).query('safaricomRetryFailures'), isEmpty);
      h.expectNoExternalEffects();
    });

    test('the same SMS seen twice is held once', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      await receive(_sorry, now);
      await receive(_sorry, now);
      expect(await (await h.db).query('safaricomRetryFailures'), hasLength(1));
      h.expectNoExternalEffects();
    });

    test('three retries a minute apart, then it stays in Error', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - 3 * _minute);

      await receive(_sorry, now - _minute - 1000);
      await controller.resolveSafaricomRetryFailures();

      for (var retry = 1; retry <= maxSafaricomFailureRetries; retry++) {
        expect(await retryCandidates(), [id], reason: 'retry $retry is due');
        await dial(id);
        await (await h.db).update(
          'transactions',
          {'retryState': 'ready', 'retryClaimOwner': null},
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(await retryCandidates(), isEmpty,
            reason: 'no retry within a minute of retry $retry');
        await (await h.db).update(
          'safaricomFailureRetries',
          {'lastRetryAt': now - 2 * _minute},
        );
      }

      expect(await retryCandidates(), isEmpty, reason: 'retries are used up');
      expect((await row(id))['status'], TransactionStatuses.error);
      h.expectNoExternalEffects();
    });

    test('other Error transactions keep their usual retry', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await pending(dialedAt: now - 3 * _minute);
      await (await h.db).update(
        'transactions',
        {'status': TransactionStatuses.error, 'retryState': 'ready'},
        where: 'id = ?',
        whereArgs: [id],
      );

      expect(await retryCandidates(), [id]);
      await dial(id);
      await (await h.db).update(
        'transactions',
        {'retryState': 'ready', 'retryClaimOwner': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(await retryCandidates(), [id]);
      h.expectNoExternalEffects();
    });

    test(
        'an alternative run for another phone stays pending with the SMS in '
        'its reply', () async {
      await phone();
      final now = DateTime.now().millisecondsSinceEpoch;
      const jobId = 'alt_SJK1RETRY1_1';
      await (await h.db).insert('alternativeJobs', {
        'forwardingJobId': jobId,
        'transactionId': '7',
        'state': 'awaiting_confirmation',
        'ussdCode': '*180*5*2*n*1#',
        'smsMessage': 'SJK1RETRY1 Confirmed. Ksh50.00 received from JOHN DOE',
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
        'createdAt': now,
        'updatedAt': now,
      });
      final id = await pending(dialedAt: now - 3 * _minute, jobId: jobId);

      await receive(_sorry, now - _minute - 1000);
      await controller.resolveSafaricomRetryFailures();

      final updated = await row(id);
      expect(updated['status'], TransactionStatuses.successfulPending);
      expect(updated['ussdReply'], startsWith(_sorry));
      expect(await retryCandidates(), isEmpty);
      h.expectNoExternalEffects();
    });
  });
}
