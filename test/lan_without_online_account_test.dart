// LAN forwarding between two phones that have NO Online BSAT account: no
// Online device name, no login token, no whitelisted (backend-paired)
// devices. Each phone has only its local LAN name and the LAN pairing.
// Phone B runs the production handler on the default database; Phone A is
// a simulated paired phone over a real authenticated session on 127.0.0.1.
// Synthetic data; no SMS, USSD or network request may happen (asserted).
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/lan/lan_forwarding_bootstrap.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_local_identity.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_test_support.dart';
import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1LAN099';
const _jobId = 'fwd_${_receipt}_1793000000000';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC LAN TEST MESSAGE ONLY.';

Map<String, dynamic> _job({String sender = 'Phone A'}) => {
      'type': 'forwarded_sms',
      'body': _sms,
      'title': 'Forwarded Message',
      'messageId': _receipt,
      'transactionId': 41,
      'forwardingJobId': _jobId,
      'forwardingStatus': 'forwarding-pending',
      'senderDeviceName': sender,
      'recipientDeviceName': 'Phone B',
    };

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);

  /// No Online account: only the local LAN name is set.
  Future<void> lanOnlyPhone(String name) =>
      h.setUp(prefs: {lanLocalDeviceNameKey: name});

  group('Phone B (receiver) without an Online account', () {
    late LanTestPhone a;
    late LanTestPhone b;
    final repliesOnA = <LanForwardingData>[];

    setUp(() async {
      await lanOnlyPhone('Phone B');
      repliesOnA.clear();
      b = await LanTestPhone.create(
        'Phone B',
        sqlite: SQLiteService(),
        inboundHandler: handleLanForwardingRequest,
        replyProcessor: handleLanForwardingReply,
      );
      a = await LanTestPhone.create(
        'Phone A',
        replyProcessor: (reply, peer) async => repliesOnA.add(reply),
      );
      await pairPhones(b, a);
    });

    tearDown(() async {
      LanForwardingService.instance = null;
      await a.dispose();
      await b.dispose();
      await h.tearDown();
    });

    test('a job from the LAN-trusted phone is claimed (as LAN) and receipted '
        'over LAN: no Online name, login or whitelist is needed', () async {
      final db = await h.db;
      expect(await db.query('whitelistedDevices'), isEmpty);
      expect(await forwardingDeviceName(), 'Phone B');

      final result = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _job(),
        isFinalReply: (reply) => reply.kind == LanMessageKind.receiptAck,
      );
      expect(result.outcome, LanExchangeOutcome.completed);
      final receipt = repliesOnA.single;
      expect(receipt.data['ackKind'], 'received');
      expect(receipt.senderDeviceName, 'Phone B');
      expect(receipt.recipientDeviceName, 'Phone A');
      final claim = (await db.query('forwardedSmsJobs')).single;
      expect(claim['forwardingJobId'], _jobId);
      expect(claim['transport'], 'lan');

      await waitForAsync(
        () async => (await db.query('forwardedSmsJobs'))
            .any((claim) => claim['state'] == 'completed'),
        reason: "B's handler finished the job",
      );
      expect(h.requests, isEmpty, reason: 'nothing goes over the Internet');
      h.expectNoExternalEffects();
    });

    test('a job naming a sender other than the authenticated phone is refused '
        'before any claim', () async {
      final result = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _job(sender: 'Phone C'),
        isFinalReply: (reply) => reply.kind == LanMessageKind.receiptAck,
      );
      expect(result.outcome, LanExchangeOutcome.refused);
      expect(await (await h.db).query('forwardedSmsJobs'), isEmpty);
      h.expectNoExternalEffects();
    });

    test('a revoked LAN pairing gets no claim', () async {
      await b.service.revoke(a.service.identity!.fingerprint);
      final result = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _job(),
        isFinalReply: (reply) => reply.kind == LanMessageKind.receiptAck,
      );
      expect(result.outcome, LanExchangeOutcome.authenticationFailed);
      expect(await (await h.db).query('forwardedSmsJobs'), isEmpty);
      h.expectNoExternalEffects();
    });

    test('defence in depth: the handler refuses a LAN delivery whose sender is '
        'not (or no longer) a trusted LAN pairing on this phone', () async {
      await b.service.remove(a.service.identity!.fingerprint);
      await h.capture(() => handleRemoteMessage(
            RemoteMessage(
              data: _job().map((key, value) => MapEntry(key, '$value')),
            ),
            replySink: (_) async => fail('no receipt may be sent'),
            authenticatedSenderDeviceName: 'Phone A',
          ));
      expect(await (await h.db).query('forwardedSmsJobs'), isEmpty);
      expect(await (await h.db).query('transactions'), isEmpty);
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });
  });

  group('Phone A (sender) without an Online account', () {
    tearDown(h.tearDown);

    /// Phone A's LAN rule for Phone B, created as LAN management does.
    Future<void> lanRuleForPhoneB({bool enabled = true}) async {
      await lanOnlyPhone('Phone A');
      final peers = LanPeerStore();
      await peers.trust(
        publicKey: List<int>.generate(32, (i) => 200 - i),
        deviceName: 'Phone B',
        deviceId: '',
        address: '192.168.1.20',
        port: 47000,
      );
      final rule = await LanForwardingRuleStore(peers: peers)
          .create(deviceName: 'Phone B', amounts: [100]);
      if (!enabled) {
        await LanForwardingRuleStore(peers: peers).setEnabled(rule.id, false);
      }
    }

    test('an unreachable LAN destination gets no job, and nothing falls back '
        'to Online or SMS', () async {
      await lanRuleForPhoneB();
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();
      final probed = <String>[];
      final result = await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
            lanReachability: (name) async {
              probed.add(name);
              return LanReachability.unreachable;
            },
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
      expect(probed, ['Phone B'], reason: 'checked over LAN only');
      expect(result.state, ForwardingAttemptState.configuredButUnavailable);
      expect(online.submissions, isEmpty);
      expect(lan.submissions, isEmpty);
      expect(h.requests, isEmpty, reason: 'no Internet ping, no backend POST');
      h.expectNoExternalEffects();
    });

    test('a disabled LAN rule gets no job and no probe', () async {
      await lanRuleForPhoneB(enabled: false);
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();
      final probed = <String>[];
      await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
            lanReachability: (name) async {
              probed.add(name);
              return LanReachability.reachable;
            },
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
      expect(probed, isEmpty);
      expect(online.submissions, isEmpty);
      expect(lan.submissions, isEmpty);
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });
  });
}
