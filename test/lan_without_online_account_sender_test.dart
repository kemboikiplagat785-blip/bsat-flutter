@Tags(['requires-system-sqlite'])
// Phone A without an Online account sends a LAN job (Windows-SQLite variant,
// like lan_bsat_forward_if_needed_test: forwardIfNeeded reaches the
// double-quoted SQL literal in _findReplyFor, which the host's bundled
// SQLite refuses). Only the local LAN name is set; synthetic data only.
library;

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_local_identity.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1LAN098';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC LAN TEST MESSAGE ONLY.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  /// No Online account; Phone A's LAN rule for Phone B, created as LAN
  /// management does.
  Future<void> lanRuleForPhoneB() async {
    await h.setUp(prefs: {lanLocalDeviceNameKey: 'Phone A'});
    final peers = LanPeerStore();
    await peers.trust(
      publicKey: List<int>.generate(32, (i) => 200 - i),
      deviceName: 'Phone B',
      deviceId: '',
      address: '192.168.1.20',
      port: 47000,
    );
    await LanForwardingRuleStore(peers: peers)
        .create(deviceName: 'Phone B', amounts: [100]);
  }

    test('a reachable LAN destination gets the job over LAN only, sent as '
        "this phone's local LAN name", () async {
      await lanRuleForPhoneB();
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport()
        ..result = const ForwardingSubmissionResult(
            accepted: false,
            statusCode: null,
            details: {'transport': 'lan', 'lanOutcome': 'unreachable'});
      await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
            lanReachability: (_) async => LanReachability.reachable,
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
      final submission = lan.submissions.single.request;
      expect(submission['senderDeviceName'], 'Phone A');
      expect(submission['recipientDeviceName'], 'Phone B');
      final row = (await (await h.db).query('transactions',
              where: 'transactionId = ?', whereArgs: [_receipt]))
          .single;
      expect(row['forwardingTransport'], 'lan');
      expect(row['forwardingRecipientDeviceName'], 'Phone B');
      expect(row['forwardingSenderDeviceName'], 'Phone A');
      expect(online.submissions, isEmpty, reason: 'no fallback to Online');
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });

    test('a payment held while the LAN rule was disabled is sent over LAN '
        'when the rule is enabled again', () async {
      await lanRuleForPhoneB();
      // As _persistUnavailableForwardingTransaction stores it while the
      // rule is disabled.
      final id = await (await h.db).insert('transactions', {
        'initialMessage': _sms,
        'transactionId': _receipt,
        'number': 712345678,
        'amount': 100,
        'date': 'today',
        'time': '12:00',
        'smsDate': 'today',
        'smsTime': '12:00',
        'ussdDialed': '',
        'simSubId': -1,
        'source': 'JOHN DOE',
        'status': TransactionStatuses.paused,
        'ussdReply': 'Paired device forwarding is configured but currently '
            'on pause. Will retry after initiation play',
        'canRetry': 0,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();

      await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
            lanReachability: (_) async => LanReachability.reachable,
          ).resumePausedForwardingTransactions('Phone B'));

      final submission = lan.submissions.single.request;
      expect(submission['recipientDeviceName'], 'Phone B');
      expect(submission['senderDeviceName'], 'Phone A');
      final row = (await (await h.db)
              .query('transactions', where: 'id = ?', whereArgs: [id]))
          .single;
      expect(row['status'], isNot(TransactionStatuses.paused));
      expect(row['forwardingTransport'], 'lan');
      expect(row['forwardingRecipientDeviceName'], 'Phone B');
      expect(online.submissions, isEmpty, reason: 'no fallback to Online');
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });
}
