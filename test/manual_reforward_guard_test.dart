// Corrective patch: manual re-forward guard (disposable copy). The manual
// screens call TransactionController.manualReforwardRefusal before creating a
// new forwarding job. Synthetic data; no network, SMS or USSD.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';

const _sms = 'SJK1RFW002 Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC RE-FORWARD TEST MESSAGE ONLY.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<int> row({
    String? jobId,
    String status = TransactionStatuses.forwardedPending,
    String transport = 'online',
    String reply = 'Forwarding to device',
    bool acknowledged = false,
  }) async {
    final db = await h.db;
    final id = await db.insert('transactions', {
      'initialMessage': _sms,
      'transactionId': 'SJK1RFW002',
      'amount': 100,
      'number': 712345678,
      'status': status,
      'forwardingJobId': jobId,
      'forwardingSenderDeviceName': jobId == null ? null : 'Phone A',
      'forwardingRecipientDeviceName': jobId == null ? null : 'Phone B',
      'forwardingTransport': jobId == null ? null : transport,
      'ussdReply': reply,
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (acknowledged && jobId != null) {
      await db.insert('forwardingDeliveryRetries', {
        'forwardingJobId': jobId,
        'attempt': 0,
        'nextAttemptAt': 0,
        'acknowledged': 1,
      });
    }
    return id;
  }

  test('a job its destination received or confirmed is never re-forwarded as '
      'a new job, for both transports', () async {
    await h.setUp(prefs: {'user_device_name': 'Phone A'});
    final guard = TransactionController(sqliteService: SQLiteService());
    for (final transport in ['online', 'lan']) {
      final acked = await row(
          jobId: 'fwd_ACK_${transport}_1', transport: transport,
          acknowledged: true);
      final noted = await row(
          jobId: 'fwd_NOTE_${transport}_1',
          transport: transport,
          reply: 'Forwarding to device\n•\n'
              'Receipt acknowledged by destination device');
      final confirmed = await row(
          jobId: 'fwd_CONF_${transport}_1',
          transport: transport,
          status: TransactionStatuses.forwardedConfirmed);
      for (final id in [acked, noted, confirmed]) {
        expect(await guard.manualReforwardRefusal(id),
            contains('Phone B already received this transaction'),
            reason: '$transport row $id');
      }
    }
    h.expectNoExternalEffects();
  });

  test('normal manual forwarding is unchanged: no job, or a job without any '
      'receipt (left to a product decision), is allowed', () async {
    await h.setUp(prefs: {'user_device_name': 'Phone A'});
    final guard = TransactionController(sqliteService: SQLiteService());
    final plain = await row(status: TransactionStatuses.error);
    final done = await row(status: TransactionStatuses.doneConfirmed);
    final pending = await row(jobId: 'fwd_PEND_1');
    final failed =
        await row(jobId: 'fwd_FAIL_1', status: TransactionStatuses.error);
    for (final id in [plain, done, pending, failed]) {
      expect(await guard.manualReforwardRefusal(id), isNull, reason: 'row $id');
    }
    expect(await guard.manualReforwardRefusal(99999), isNull);
    h.expectNoExternalEffects();
  });
}
