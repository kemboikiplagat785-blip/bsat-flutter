@Tags(['requires-system-sqlite'])
// STAGE 2B (disposable copy; Windows-SQLite variant, because forwardIfNeeded
// reaches the double-quoted SQL literal in _findReplyFor before submitting).
// As in Stage 0/1, the success path's return value is not asserted (host
// telephony assertion after the send); submissions are asserted instead.
library;

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';
import 'support/stage2b_fakes.dart';

const _receipt = 'SJK1ABCD23';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC STAGE 2B TEST MESSAGE ONLY.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<void> phoneA({int? roundRobinIndex}) async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone A',
      'jwt_token': 'stage2b-test-jwt',
      if (roundRobinIndex != null) 'online_forwarding_index_100': roundRobinIndex,
    });
    final db = await h.db;
    for (final (name, id) in [('Phone B', 'device-b'), ('Phone C', 'device-c')]) {
      await db.insert('forwardingDevices', {
        'device_name': name,
        'device_id': id,
        'owner_email': 'owner@example.test',
        'amounts_to_forward': '[100]',
        'paused': 0,
      });
    }
  }

  test('Rule D: B online, C LAN - a new job goes to B even when the '
      'round-robin index points at C', () async {
    // Index 1 would select Phone C among [B, C]; C is not eligible.
    await phoneA(roundRobinIndex: 1);
    final transport = RecordingForwardingTransport();
    final controller = TransactionController(
      sqliteService: SQLiteService(),
      forwardingTransport: transport,
      forwardingTransportPreferences:
          MapForwardingTransportPreferences({'device-c': 'lan'}),
    );
    await h.capture(() => controller.forwardIfNeeded(
        100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));

    expect(transport.submissions, hasLength(1));
    final request = transport.submissions.single.request;
    expect(request['recipientDeviceName'], 'Phone B');
    final row = (await (await h.db).query('transactions',
            where: 'transactionId = ?', whereArgs: [_receipt]))
        .single;
    expect(row['forwardingRecipientDeviceName'], 'Phone B');
    expect(
      request,
      buildForwardedSmsRequestPayload(
        message: _sms,
        messageId: _receipt,
        transactionRowId: row['id'] as int,
        forwardingJobId: row['forwardingJobId'] as String,
        senderDeviceName: 'Phone A',
        recipientDeviceName: 'Phone B',
      ),
      reason: 'online payload unchanged',
    );
    expect(h.backendPosts, isEmpty, reason: 'only via the injected transport');
    expect(h.requests.map((r) => '${r.method} ${r.url}'),
        ['GET https://google.com'],
        reason: 'only the online destination is pinged');
    h.expectNoExternalEffects();
  });

  test('default preferences: both destinations online, index 1 selects C '
      'as before (no behaviour change without a stored preference)', () async {
    await phoneA(roundRobinIndex: 1);
    final transport = RecordingForwardingTransport();
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: transport,
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
    expect(transport.submissions.single.request['recipientDeviceName'],
        'Phone C');
    expect(h.requests.where((r) => r.method == 'GET'), hasLength(2),
        reason: 'both destinations pinged, as before');
  });

  test('Rule E: retrying an existing job saved for C keeps the Internet '
      'transport and the same job ID after C is switched to LAN', () async {
    await phoneA();
    const jobId = 'fwd_${_receipt}_1761650000000';
    final id = await (await h.db).insert('transactions', {
      'transactionId': _receipt,
      'initialMessage': _sms,
      'amount': 100,
      'number': 712345678,
      'source': 'JOHN DOE',
      'status': TransactionStatuses.error,
      'canRetry': 1,
      'forwardingJobId': jobId,
      'forwardingSenderDeviceName': 'Phone A',
      'forwardingRecipientDeviceName': 'Phone C',
      // LAN integration: every in-flight Online job now persists its
      // transport (migration backfill or creation path).
      'forwardingTransport': 'online',
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
    final transport = RecordingForwardingTransport();
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: transport,
          forwardingTransportPreferences:
              MapForwardingTransportPreferences({'device-c': 'lan'}),
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false,
            txId: id, forwardingRecipientDeviceName: 'Phone C'));

    expect(transport.submissions, hasLength(1));
    final data = transport.submissions.single.request['data'] as Map;
    expect(data['forwardingJobId'], jobId);
    expect(data['recipientDeviceName'], 'Phone C');
    h.expectNoExternalEffects();
  });
}
