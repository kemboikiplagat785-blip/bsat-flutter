@Tags(['requires-system-sqlite'])
// STAGE 2B persistence (disposable copy; Windows-SQLite variant, because
// forwardIfNeeded reaches the double-quoted SQL literal in _findReplyFor
// before submitting). Preferences come from the production default store
// (forwardingDevices.forwarding_transport); nothing is injected. As in
// Stage 0/1, the success path's return value is not asserted (host telephony
// assertion after the send); submissions are asserted instead.
library;

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1ABCD23';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC STAGE 2B TEST MESSAGE ONLY.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<void> phoneA(Map<String, ForwardingTransportKind?> devices) async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone A',
      'jwt_token': 'stage2b-test-jwt',
      'online_forwarding_index_100': 1,
    });
    final db = await h.db;
    for (final MapEntry(key: name, value: kind) in devices.entries) {
      final id = 'device-${name.substring(6).toLowerCase()}';
      await db.insert('forwardingDevices', {
        'device_name': name,
        'device_id': id,
        'owner_email': 'owner@example.test',
        'amounts_to_forward': '[100]',
        'paused': 0,
      });
      if (kind != null) {
        await SQLiteForwardingTransportPreferences().save(
            ForwardingDestination(deviceId: id, deviceName: name), kind);
      }
    }
  }

  Future<RecordingForwardingTransport> forward() async {
    final transport = RecordingForwardingTransport();
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: transport,
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
    return transport;
  }

  test('stored B online, stored C LAN: index 1 (C) still goes to B with the '
      'unchanged online payload', () async {
    await phoneA({
      'Phone B': ForwardingTransportKind.online,
      'Phone C': ForwardingTransportKind.lan,
    });
    final transport = await forward();

    expect(transport.submissions, hasLength(1));
    final request = transport.submissions.single.request;
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
    );
    expect(h.backendPosts, isEmpty, reason: 'only via the injected transport');
    expect(h.requests.map((r) => '${r.method} ${r.url}'),
        ['GET https://google.com']);
    h.expectNoExternalEffects();
  });

  test('legacy rows (no stored preference): index 1 selects C exactly as '
      'before persistence', () async {
    await phoneA({'Phone B': null, 'Phone C': null});
    final transport = await forward();
    expect(transport.submissions.single.request['recipientDeviceName'],
        'Phone C');
    expect(h.requests.where((r) => r.method == 'GET'), hasLength(2));
    h.expectNoExternalEffects();
  });
}
