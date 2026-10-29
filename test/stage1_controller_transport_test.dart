// STAGE 1 (disposable copy): TransactionController submits forwarding
// messages through its injected ForwardingTransport. With a recording fake,
// no HTTP request may appear, the submitted request must equal the Stage 0
// characterized payload, and the controller's durable state must react to
// the result exactly as it reacted to BackendService's result map.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1ABCD23';
const _jobId = 'fwd_${_receipt}_1761650000000';
const _sms = '$_receipt Confirmed. Ksh100.00 received from SYNTHETIC TEST '
    '0712345678.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  group('final confirmation (_deliverForwardingConfirmation)', () {
    setUp(() => h.setUp(prefs: {
          'user_device_name': 'Phone B',
          'jwt_token': 'stage1-test-jwt',
        }));

    Future<Map<String, Object?>> sendWith(
        RecordingForwardingTransport transport) async {
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransport: transport,
      );
      await h.capture(() => controller.sendForwardingConfirmation(
            forwardingJobId: _jobId,
            recipientDeviceName: 'Phone A',
            transactionId: _receipt,
          ));
      return (await (await h.db).query('forwardingConfirmations',
              where: 'forwardingJobId = ?', whereArgs: [_jobId]))
          .single;
    }

    test('submits the characterized payload through the injected transport',
        () async {
      final transport = RecordingForwardingTransport();
      final queued = await sendWith(transport);

      expect(h.requests, isEmpty, reason: 'no direct HTTP');
      expect(transport.submissions, hasLength(1));
      expect(transport.submissions.single.request, {
        'title': 'BSAT Online Forwarding',
        'body': 'Forwarded transaction confirmed',
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': 'Phone A',
        'data': {
          'type': 'forwarded_sms_ack',
          'ackKind': 'confirmed',
          'status': 'transaction-confirmed',
          'resultStatus': 'transaction-confirmed',
          'forwardingJobId': _jobId,
          'transactionId': _receipt,
          'senderDeviceName': 'Phone B',
          'recipientDeviceName': 'Phone A',
        },
      });
      expect(queued['attempt'], 1);
      h.expectNoExternalEffects();
    });

    test('a rejected submission leaves the outbox exactly as an accepted one',
        () async {
      final accepted = await sendWith(RecordingForwardingTransport());
      await h.setUp(prefs: {
        'user_device_name': 'Phone B',
        'jwt_token': 'stage1-test-jwt',
      });
      final rejecting = RecordingForwardingTransport()
        ..result = const ForwardingSubmissionResult(
          accepted: false,
          statusCode: 503,
          details: {'success': false, 'statusCode': 503},
        );
      final rejected = await sendWith(rejecting);

      Map<String, Object?> stable(Map<String, Object?> row) =>
          Map.of(row)..remove('nextAttemptAt');
      expect(stable(rejected), stable(accepted));
      expect(rejected['attempt'], 1);
      expect(rejecting.submissions, hasLength(1), reason: 'no retry inside');
      h.expectNoExternalEffects();
    });
  });

  group('delivery retry (_retryPendingForwardingDeliveries)', () {
    Future<int> seed() async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone A',
        'jwt_token': 'stage1-test-jwt',
      });
      final db = await h.db;
      final rowId = await db.insert('transactions', {
        'initialMessage': _sms,
        'transactionId': _receipt,
        'status': TransactionStatuses.forwardedPending,
        'canRetry': 1,
        'forwardingJobId': _jobId,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone B',
        // LAN integration: every in-flight Online job now persists its
        // transport (migration backfill or creation path).
        'forwardingTransport': 'online',
        'awaitingTopUp': 0,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      await db.insert('forwardingDeliveryRetries', {
        'forwardingJobId': _jobId,
        'attempt': 0,
        'nextAttemptAt': DateTime.now().millisecondsSinceEpoch - 1000,
        'acknowledged': 0,
      });
      return rowId;
    }

    Future<Map<String, Object?>> retryRow() async =>
        (await (await h.db).query('forwardingDeliveryRetries',
                where: 'forwardingJobId = ?', whereArgs: [_jobId]))
            .single;

    Future<void> runWorker(RecordingForwardingTransport transport) =>
        h.capture(() async {
          TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: transport,
          );
        });

    test('accepted: identical payload, attempt 1, no failure recorded',
        () async {
      final rowId = await seed();
      final transport = RecordingForwardingTransport();
      await runWorker(transport);

      expect(h.requests, isEmpty);
      expect(transport.submissions, hasLength(1));
      expect(
        transport.submissions.single.request,
        buildForwardedSmsRequestPayload(
          message: _sms,
          messageId: _receipt,
          transactionRowId: rowId,
          forwardingJobId: _jobId,
          senderDeviceName: 'Phone A',
          recipientDeviceName: 'Phone B',
        ),
      );
      final retry = await retryRow();
      expect(retry['attempt'], 1);
      expect(retry['lastFailure'], isNull);
      h.expectNoExternalEffects();
    });

    for (final (label, details, expected) in [
      (
        'HTTP status',
        <String, dynamic>{'success': false, 'statusCode': 500},
        'HTTP/API submission failed (500)'
      ),
      (
        'no status (network error)',
        <String, dynamic>{'success': false, 'message': 'Network error: x'},
        'HTTP/API submission failed (unknown)'
      ),
    ]) {
      test('rejected ($label): same lastFailure text as before', () async {
        await seed();
        final transport = RecordingForwardingTransport()
          ..result = ForwardingSubmissionResult(
            accepted: false,
            statusCode: details['statusCode'] as int?,
            details: details,
          );
        await runWorker(transport);
        final retry = await retryRow();
        expect(retry['attempt'], 1);
        expect(retry['lastFailure'], expected);
        expect(transport.submissions, hasLength(1), reason: 'no retry inside');
        h.expectNoExternalEffects();
      });
    }

    test('a transport failure never changes purchase-retry state or dials',
        () async {
      final rowId = await seed();
      final before = (await (await h.db)
              .query('transactions', where: 'id = ?', whereArgs: [rowId]))
          .single;
      final transport = RecordingForwardingTransport()
        ..result = const ForwardingSubmissionResult(
          accepted: false,
          statusCode: 503,
          details: {'success': false, 'statusCode': 503},
        );
      await runWorker(transport);

      final after = (await (await h.db)
              .query('transactions', where: 'id = ?', whereArgs: [rowId]))
          .single;
      expect(after, before, reason: 'transaction row untouched');
      expect(after['retryState'], 'ready');
      final candidates = await SQLiteService().getAutomaticRetryCandidates(
          isAutoRetrying: true, retryLimit: 6, today: '2099-01-01');
      expect(candidates.map((c) => c['id']), isNot(contains(rowId)),
          reason: 'forwarded-pending is never a purchase-retry candidate');
      expect(h.ussdCalls, isEmpty);
      h.expectNoExternalEffects();
    });
  });
}
