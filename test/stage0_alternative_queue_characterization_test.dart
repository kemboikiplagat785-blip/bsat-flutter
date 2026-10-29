// STAGE 0 characterization (disposable copy only) of the alternative-device
// queue at HEAD 086d14e. Three concepts are kept apart:
//  * queue slot: Phone B's per-recipient 'active' slot (alternativeQueueState);
//  * delivery retry: re-sending the same process_alt_request to Phone C;
//  * purchase repetition: dialling USSD again for a job that may have run.
// No USSD is dialled and no SMS is sent (both channels refuse and record).
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';

const _phoneC = 'Phone C';
const _phoneD = 'Phone D';

Future<int> _altRow(
  Stage0Harness h, {
  required String jobId,
  required String recipient,
  required String queueState,
  required String status,
  required String code,
  int ageMinutes = 10,
}) async {
  final db = await h.db;
  final at = DateTime.now()
      .subtract(Duration(minutes: ageMinutes))
      .millisecondsSinceEpoch;
  return db.insert('transactions', {
    'transactionId': 'RCPT-$jobId',
    'initialMessage': 'RCPT-$jobId Confirmed. Ksh50.00 received from '
        'SYNTHETIC TEST 0712345678.',
    'amount': 50,
    'number': 712345678,
    'status': status,
    'canRetry': 0,
    'forwardingJobId': jobId,
    'forwardingSenderDeviceName': 'Phone A',
    'forwardingRecipientDeviceName': recipient,
    // LAN integration: a queued alternative persists its (Online) transport.
    'forwardingTransport': 'online',
    'alternativeRequestCode': code,
    'alternativeRequestIsAdvanced': 0,
    'alternativeRequestSenderDeviceName': 'Phone B',
    'alternativeQueueState': queueState,
    'firstFailedTimeStamp': at,
    'timeStamp': at,
  });
}

RemoteMessage _altResult({
  required String jobId,
  required int rowId,
  required String status,
}) =>
    RemoteMessage(messageId: 'fcm-alt-$jobId-$status', data: {
      'type': 'forwarded_alt_result',
      'forwardingJobId': jobId,
      'transactionId': '$rowId',
      'status': status,
      'ussdReply': 'SYNTHETIC result $status',
      'senderDeviceName': _phoneC,
      'recipientDeviceName': 'Phone B',
    });

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<Map<String, Object?>> row(int id) async =>
      (await (await h.db).query('transactions', where: 'id = ?', whereArgs: [id]))
          .single;

  List<CapturedRequest> postsOfType(String type) =>
      h.backendPosts.where((p) => p.data['type'] == type).toList();

  group('Phone B queue: claimNextAlternativeDelivery', () {
    setUp(() => h.setUp(prefs: {
          'user_device_name': 'Phone B',
          'jwt_token': 'stage0-test-jwt',
        }));

    test('an active ambiguous slot blocks that recipient\'s queue indefinitely',
        () async {
      await _altRow(h,
          jobId: 'J1',
          recipient: _phoneC,
          queueState: 'active',
          status: TransactionStatuses.alternativeAmbiguous,
          code: '*180*1#');
      final waiting = await _altRow(h,
          jobId: 'J2',
          recipient: _phoneC,
          queueState: 'waiting',
          status: TransactionStatuses.alternativeDeliveryPending,
          code: '*180*2#');
      final sqlite = SQLiteService();
      for (final daysLater in [0, 1, 30]) {
        final now = DateTime.now()
            .add(Duration(days: daysLater))
            .millisecondsSinceEpoch;
        expect(
          await sqlite.claimNextAlternativeDelivery(
              recipientDeviceName: _phoneC, now: now, nextAttemptAt: now),
          isNull,
          reason: 'blocked $daysLater day(s) later',
        );
      }
      expect((await row(waiting))['alternativeQueueState'], 'waiting');
    });

    test('the block is per recipient: another recipient\'s queue advances',
        () async {
      await _altRow(h,
          jobId: 'J1',
          recipient: _phoneC,
          queueState: 'active',
          status: TransactionStatuses.alternativeAmbiguous,
          code: '*180*1#');
      final other = await _altRow(h,
          jobId: 'J3',
          recipient: _phoneD,
          queueState: 'waiting',
          status: TransactionStatuses.alternativeDeliveryPending,
          code: '*180*3#');
      final now = DateTime.now().millisecondsSinceEpoch;
      final claimed = await SQLiteService().claimNextAlternativeDelivery(
          recipientDeviceName: _phoneD, now: now, nextAttemptAt: now + 20000);
      expect(claimed?['id'], other);
      expect((await row(other))['alternativeQueueState'], 'active');
    });

    test('contrast: an active delivery-pending slot is re-offered when due, '
        'and not before', () async {
      final active = await _altRow(h,
          jobId: 'J4',
          recipient: _phoneC,
          queueState: 'active',
          status: TransactionStatuses.alternativeDeliveryPending,
          code: '*180*4#');
      final now = DateTime.now().millisecondsSinceEpoch;
      final sqlite = SQLiteService();
      final first = await sqlite.claimNextAlternativeDelivery(
          recipientDeviceName: _phoneC, now: now, nextAttemptAt: now + 20000);
      expect(first?['id'], active, reason: 'delivery retry of the same job');
      expect(
          await sqlite.claimNextAlternativeDelivery(
              recipientDeviceName: _phoneC,
              now: now + 1000,
              nextAttemptAt: now + 21000),
          isNull,
          reason: 'not before its next attempt time');
    });
  });

  group('Phone B: results from Phone C (via handleRemoteMessage)', () {
    setUp(() => h.setUp(prefs: {
          'user_device_name': 'Phone B',
          'jwt_token': 'stage0-test-jwt',
        }));

    test('an ambiguous result keeps the slot active, is not retryable, and '
        'dispatches nothing', () async {
      final t1 = await _altRow(h,
          jobId: 'J1',
          recipient: _phoneC,
          queueState: 'active',
          status: TransactionStatuses.forwardedPending,
          code: '*180*1#');
      final t2 = await _altRow(h,
          jobId: 'J2',
          recipient: _phoneC,
          queueState: 'waiting',
          status: TransactionStatuses.alternativeDeliveryPending,
          code: '*180*2#',
          ageMinutes: 5);

      await h.capture(() => handleRemoteMessage(_altResult(
          jobId: 'J1',
          rowId: t1,
          status: TransactionStatuses.alternativeAmbiguous)));

      final r1 = await row(t1);
      expect(r1['status'], TransactionStatuses.alternativeAmbiguous);
      expect(r1['canRetry'], 0);
      expect(r1['alternativeQueueState'], 'active',
          reason: 'HEAD does not release the slot on an ambiguous result');

      final acks = postsOfType('MESSAGE_ACK');
      expect(acks, hasLength(1));
      expect(acks.single.data['ackKind'], 'alternative_result_received');
      expect(acks.single.data['status'], 'alternative-result-received');
      expect(acks.single.data['originalType'], 'forwarded_alt_result');
      expect(acks.single.data['resultStatus'],
          TransactionStatuses.alternativeAmbiguous);
      expect(acks.single.json['recipientDeviceName'], _phoneC);

      // Nothing else is sent to Phone C afterwards.
      h.requests.clear();
      await h.capture(() =>
          TransactionController(sqliteService: SQLiteService())
              .dispatchNextAlternativeDelivery(_phoneC));
      expect(postsOfType('process_alt_request'), isEmpty);
      expect((await row(t2))['alternativeQueueState'], 'waiting');

      // The ambiguous row is not an automatic retry candidate.
      final candidates = await SQLiteService().getAutomaticRetryCandidates(
          isAutoRetrying: true, retryLimit: 6, today: '2099-01-01');
      expect(candidates.map((c) => c['id']), isNot(contains(t1)));
      h.expectNoExternalEffects();
    });

    test('a later definitive result releases the slot and dispatches the NEXT '
        'job, never the ambiguous one again', () async {
      final t1 = await _altRow(h,
          jobId: 'J1',
          recipient: _phoneC,
          queueState: 'active',
          status: TransactionStatuses.alternativeAmbiguous,
          code: '*180*1#');
      final t2 = await _altRow(h,
          jobId: 'J2',
          recipient: _phoneC,
          queueState: 'waiting',
          status: TransactionStatuses.alternativeDeliveryPending,
          code: '*180*2#',
          ageMinutes: 5);

      await h.capture(() => handleRemoteMessage(_altResult(
          jobId: 'J1', rowId: t1, status: TransactionStatuses.doneConfirmed)));

      final r1 = await row(t1);
      expect(r1['status'], TransactionStatuses.doneConfirmed);
      expect(r1['alternativeQueueState'], 'released');
      expect((await row(t2))['alternativeQueueState'], 'active');

      final requests = postsOfType('process_alt_request');
      expect(requests, hasLength(1));
      expect(requests.single.json['recipientDeviceName'], _phoneC);
      expect(requests.single.data, {
        'type': 'process_alt_request',
        'transactionId': '$t2',
        'forwardingJobId': 'J2',
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': _phoneC,
        'ussdCode': '*180*2#',
        'isAdvanced': 'false',
        'smsMessage': 'RCPT-J2 Confirmed. Ksh50.00 received from '
            'SYNTHETIC TEST 0712345678.',
        'body': 'Forwarded alternative USSD request',
        'title': 'Forwarded Code',
      });
      expect(
          h.backendPosts.where((p) =>
              p.data['type'] == 'process_alt_request' &&
              p.data['forwardingJobId'] == 'J1'),
          isEmpty,
          reason: 'the possibly-completed job is not requested again');
      // B also makes sure Phone A will be told, then acknowledges Phone C.
      expect(postsOfType('forwarded_sms_ack').single.json['recipientDeviceName'],
          'Phone A');
      expect(postsOfType('MESSAGE_ACK').single.data['ackKind'],
          'alternative_result_received');
      h.expectNoExternalEffects();
    });
  });

  group('Phone C: recovery of an interrupted alternative job', () {
    const jobId = 'JX';

    Future<void> seedExecutingJob({required int updatedMinutesAgo}) async {
      await h.setUp(prefs: {
        'user_device_name': _phoneC,
        'jwt_token': 'stage0-test-jwt',
      });
      final at = DateTime.now()
          .subtract(Duration(minutes: updatedMinutesAgo))
          .millisecondsSinceEpoch;
      await (await h.db).insert('alternativeJobs', {
        'forwardingJobId': jobId,
        'transactionId': '55',
        'state': 'executing',
        'ussdCode': '*180*5#',
        'isAdvanced': 0,
        'smsMessage': 'RCPT-JX Confirmed. Ksh50.00 received from SYNTHETIC '
            'TEST 0712345678.',
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': _phoneC,
        'executionStartedAt': at,
        'createdAt': at,
        'updatedAt': at,
      });
    }

    Future<Map<String, Object?>> job() async =>
        (await (await h.db).query('alternativeJobs',
                where: 'forwardingJobId = ?', whereArgs: [jobId]))
            .single;

    test('an executing job older than 5 minutes becomes ambiguous and is '
        'reported, without dialling', () async {
      await seedExecutingJob(updatedMinutesAgo: 6);
      final controller = TransactionController(sqliteService: SQLiteService());
      await h.capture(() => controller.processReservedAlternativeRequest(jobId));

      final j = await job();
      expect(j['state'], 'ambiguous');
      expect(j['resultStatus'], TransactionStatuses.alternativeAmbiguous);
      expect(
          j['ussdReply'],
          'Alternative USSD outcome is unknown after interruption. '
          'It was not automatically dialed again.');
      final results = postsOfType('forwarded_alt_result');
      expect(results, hasLength(1));
      expect(results.single.json['recipientDeviceName'], 'Phone B');
      expect(results.single.data, {
        'type': 'forwarded_alt_result',
        'transactionId': '55',
        'forwardingJobId': jobId,
        'status': TransactionStatuses.alternativeAmbiguous,
        'ussdReply': j['ussdReply'],
        'senderDeviceName': _phoneC,
        'recipientDeviceName': 'Phone B',
      });

      // Processing the ambiguous job again never dials. It re-queues the same
      // result immediately (resultNextAttemptAt reset to 0), so the identical
      // ambiguous result is re-sent: a delivery repetition, not a purchase.
      h.requests.clear();
      await h.capture(() => controller.processReservedAlternativeRequest(jobId));
      expect((await job())['state'], 'ambiguous');
      final resent = postsOfType('forwarded_alt_result');
      expect(resent, hasLength(1));
      expect(resent.single.data, results.single.data);
      h.expectNoExternalEffects();
    });

    test('a recently started executing job is left alone', () async {
      await seedExecutingJob(updatedMinutesAgo: 1);
      final controller = TransactionController(sqliteService: SQLiteService());
      await h.capture(() => controller.processReservedAlternativeRequest(jobId));
      expect((await job())['state'], 'executing');
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });
  });
}
