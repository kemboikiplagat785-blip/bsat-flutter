@Tags(['requires-system-sqlite'])
// STAGE 1 (disposable copy; run in the Windows-SQLite variant like the
// Stage 0 forwardIfNeeded tests, because forwardIfNeeded reaches the
// double-quoted SQL literal in _findReplyFor before sending).
library;

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1ABCD23';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC STAGE 1 TEST MESSAGE ONLY.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<TransactionController> phoneA(
      RecordingForwardingTransport transport) async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone A',
      'jwt_token': 'stage1-test-jwt',
    });
    await (await h.db).insert('forwardingDevices', {
      'device_name': 'Phone B',
      'device_id': 'device-b',
      'owner_email': 'owner@example.test',
      'amounts_to_forward': '[100]',
      'paused': 0,
    });
    return TransactionController(
      sqliteService: SQLiteService(),
      forwardingTransport: transport,
    );
  }

  Future<Map<String, Object?>> row() async => (await (await h.db).query(
          'transactions',
          where: 'transactionId = ?',
          whereArgs: [_receipt]))
      .single;

  // As in Stage 0, the success path's return value is not asserted: after
  // the send, processReply hits another_telephony's Android-only assertion
  // on a test host.
  test('forwardIfNeeded submits the characterized payload via the transport',
      () async {
    final transport = RecordingForwardingTransport();
    final controller = await phoneA(transport);
    await h.capture(() => controller.forwardIfNeeded(
        100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));

    final r = await row();
    expect(h.backendPosts, isEmpty, reason: 'no direct backend POST');
    expect(h.requests.map((q) => '${q.method} ${q.url}'),
        ['GET https://google.com'],
        reason: 'only the unchanged pingDevice request');
    expect(transport.submissions, hasLength(1));
    expect(
      transport.submissions.single.request,
      buildForwardedSmsRequestPayload(
        message: _sms,
        messageId: _receipt,
        transactionRowId: r['id'] as int,
        forwardingJobId: r['forwardingJobId'] as String,
        senderDeviceName: 'Phone A',
        recipientDeviceName: 'Phone B',
      ),
    );
    expect(r['status'], TransactionStatuses.forwardedPending);
    expect(
        await (await h.db).query('forwardingDeliveryRetries',
            where: 'forwardingJobId = ?', whereArgs: [r['forwardingJobId']]),
        hasLength(1));
    h.expectNoExternalEffects();
  });

  test('a rejected submission yields the same outcome as an HTTP failure',
      () async {
    final transport = RecordingForwardingTransport()
      ..result = const ForwardingSubmissionResult(
        accepted: false,
        statusCode: 503,
        details: {'success': false, 'statusCode': 503},
      );
    final controller = await phoneA(transport);
    final result = await h.capture(() => controller.forwardIfNeeded(
        100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));

    expect(result.state, ForwardingAttemptState.configuredButUnavailable);
    final r = await row();
    expect(r['status'], TransactionStatuses.error);
    expect(r['ussdReply'],
        'Forwarding failed: Phone offline or server not reachable. Will retry later.');
    expect(
        await (await h.db).query('forwardingDeliveryRetries',
            where: 'forwardingJobId = ?', whereArgs: [r['forwardingJobId']]),
        isEmpty);
    expect(
        (await SharedPreferences.getInstance())
            .getInt('online_forwarding_index_100'),
        isNull);
    expect(transport.submissions, hasLength(1), reason: 'no retry inside');
    h.expectNoExternalEffects();
  });
}
