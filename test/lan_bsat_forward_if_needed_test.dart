@Tags(['requires-system-sqlite'])
// Phone A creates and sends LAN jobs (disposable copy; Windows-SQLite
// variant, because forwardIfNeeded reaches the double-quoted SQL literal in
// _findReplyFor). Phone A is real: production controller, default database.
// One test runs a real LAN delivery to a simulated paired Phone B (own
// database, real authenticated session on 127.0.0.1); the others inject
// recording transports. Synthetic data only.
library;

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/lan/lan_forwarding_bootstrap.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan_forwarding_transport.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_test_support.dart';
import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1LAN077';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC LAN TEST MESSAGE ONLY.';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  Future<void> phoneA(Map<String, String?> devices, {int index = 0}) async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone A',
      'jwt_token': 'lan-test-jwt',
      'online_forwarding_index_100': index,
    });
    final db = await h.db;
    for (final MapEntry(key: name, value: transport) in devices.entries) {
      await db.insert('forwardingDevices', {
        'device_name': name,
        'device_id': 'device-${name.substring(6).toLowerCase()}',
        'owner_email': 'owner@example.test',
        'amounts_to_forward': '[100]',
        'paused': 0,
        'forwarding_transport': transport,
      });
    }
  }

  Future<Map<String, Object?>> jobRow() async => (await (await h.db).query(
          'transactions',
          where: 'transactionId = ?',
          whereArgs: [_receipt]))
      .single;

  test('a new job for a paired LAN destination is delivered over LAN, durably '
      'received by Phone B, and never sent online', () async {
    await phoneA({'Phone B': 'lan'});
    final received = <Map<String, String>>[];
    // Phone B's own database.
    final bDatabase = SQLiteService(databaseOverride: await openPhoneDatabase());
    final b = await LanTestPhone.create('Phone B',
        inboundHandler: (message, peer, reply) async {
      // Phone B's essential contract: durable claim, then receipt ACK.
      final claim = await bDatabase.claimForwardedSmsJob(
              forwardingJobId: message.forwardingJobId,
              sourceTransactionId: message.data['transactionId'],
              transport: 'lan');
      received.add(message.data);
      if (claim['state'] == 'identifier_mismatch') return;
      await reply({
        'data': {
          'type': 'MESSAGE_ACK',
          'ackKind': 'received',
          'messageId': '',
          'requestId': '',
          'transactionId': message.data['transactionId'],
          'forwardingJobId': message.forwardingJobId,
          'originalType': 'forwarded_sms',
          'status': 'received',
          'receivedAt': '${DateTime.now().millisecondsSinceEpoch}',
          'senderDeviceName': 'Phone B',
          'recipientDeviceName': 'Phone A',
          'body': 'received',
          'title': 'Ack receive',
        },
      });
    });
    final a = await LanTestPhone.create('Phone A',
        sqlite: SQLiteService(), replyProcessor: handleLanForwardingReply);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });
    await pairPhones(b, a);

    final online = RecordingForwardingTransport();
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: online,
          lanForwardingTransport: LanForwardingTransport(client: a.service),
          lanReachability: a.service.probe,
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));

    final row = await jobRow();
    expect(row['forwardingTransport'], 'lan');
    expect(row['forwardingRecipientDeviceName'], 'Phone B');
    expect(row['status'], TransactionStatuses.forwardedPending,
        reason: 'receipt is not a purchase confirmation');
    // As for Online (Stage 0/1/2B), the post-send text update cannot run on
    // the host: the Safaricom-success guard reaches a telephony call that
    // asserts Android. The receipt below was recorded before it.
    expect(row['ussdReply'],
        contains('Receipt acknowledged by destination device'));
    final expected = buildForwardedSmsRequestPayload(
      message: _sms,
      messageId: _receipt,
      transactionRowId: row['id'] as int,
      forwardingJobId: row['forwardingJobId'] as String,
      senderDeviceName: 'Phone A',
      recipientDeviceName: 'Phone B',
    )['data'] as Map<String, dynamic>;
    expect(received.single,
        expected.map((key, value) => MapEntry(key, value.toString())));
    expect(
        await SQLiteService()
            .isForwardingDeliveryAcknowledged(row['forwardingJobId'] as String),
        isTrue);
    expect(online.submissions, isEmpty);
    expect(h.requests, isEmpty, reason: 'no Internet ping, no backend POST');
    h.expectNoExternalEffects();
  });

  test('an unreachable LAN destination gets no job; nothing goes online',
      () async {
    await phoneA({'Phone B': 'lan'});
    final online = RecordingForwardingTransport();
    final lan = RecordingForwardingTransport();
    final result = await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: online,
          lanForwardingTransport: lan,
          lanReachability: (_) async => LanReachability.unreachable,
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
    expect(result.state, ForwardingAttemptState.configuredButUnavailable);
    expect(online.submissions, isEmpty);
    expect(lan.submissions, isEmpty);
    expect(h.requests, isEmpty);
    h.expectNoExternalEffects();
  });

  test('an unreachable LAN destination leaves the established routing to an '
      'eligible Online destination (unchanged payload)', () async {
    await phoneA({'Phone B': 'lan', 'Phone C': 'online'});
    final online = RecordingForwardingTransport();
    final lan = RecordingForwardingTransport();
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: online,
          lanForwardingTransport: lan,
          lanReachability: (_) async => LanReachability.unreachable,
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
    final row = await jobRow();
    expect(lan.submissions, isEmpty);
    expect(row['forwardingRecipientDeviceName'], 'Phone C');
    expect(row['forwardingTransport'], 'online');
    expect(
      online.submissions.single.request,
      buildForwardedSmsRequestPayload(
        message: _sms,
        messageId: _receipt,
        transactionRowId: row['id'] as int,
        forwardingJobId: row['forwardingJobId'] as String,
        senderDeviceName: 'Phone A',
        recipientDeviceName: 'Phone C',
      ),
    );
    h.expectNoExternalEffects();
  });

  test('a LAN job that was not acknowledged is kept for retry, LAN only',
      () async {
    await phoneA({'Phone B': 'lan'});
    final online = RecordingForwardingTransport();
    final lan = RecordingForwardingTransport()
      ..result = const ForwardingSubmissionResult(
          accepted: false,
          statusCode: null,
          details: {'transport': 'lan', 'lanOutcome': 'deliveryUnknown'});
    final result = await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: online,
          lanForwardingTransport: lan,
          lanReachability: (_) async => LanReachability.reachable,
        ).forwardIfNeeded(
            100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
    expect(result.state, ForwardingAttemptState.configuredButUnavailable);
    final row = await jobRow();
    expect(lan.submissions, hasLength(1));
    expect(row['forwardingTransport'], 'lan');
    expect(row['status'], TransactionStatuses.error);
    expect(row['ussdReply'], contains('LAN forwarding failed'));
    expect(online.submissions, isEmpty);
    expect(h.backendPosts, isEmpty);
    h.expectNoExternalEffects();
  });

  group('existing jobs keep their persisted transport', () {
    Future<int> existing(String transport) async =>
        (await h.db).insert('transactions', {
          'initialMessage': _sms,
          'transactionId': _receipt,
          'amount': 100,
          'number': 712345678,
          'status': TransactionStatuses.error,
          'canRetry': 1,
          'forwardingJobId': 'fwd_${_receipt}_1793000000000',
          'forwardingSenderDeviceName': 'Phone A',
          'forwardingRecipientDeviceName': 'Phone B',
          'forwardingTransport': transport,
          'source': 'JOHN DOE',
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
        });

    test('an Online job stays Online after the destination switched to LAN',
        () async {
      await phoneA({'Phone B': 'lan'});
      final id = await existing('online');
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();
      await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
            lanReachability: (_) async => LanReachability.reachable,
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', true,
              txId: id));
      expect(lan.submissions, isEmpty);
      expect(online.submissions.single.request['data']['forwardingJobId'],
          'fwd_${_receipt}_1793000000000');
      h.expectNoExternalEffects();
    });

    test('a LAN job stays LAN after the destination switched to Online, '
        'without an Internet presence check', () async {
      await phoneA({'Phone B': 'online'});
      final id = await existing('lan');
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();
      await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
            lanReachability: (_) async => LanReachability.reachable,
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', true,
              txId: id));
      expect(online.submissions, isEmpty);
      expect(lan.submissions.single.request['data']['forwardingJobId'],
          'fwd_${_receipt}_1793000000000');
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });
  });

  test('forward to all: LAN destinations only over LAN, Online destinations '
      'exactly as before, unreachable LAN skipped', () async {
    await phoneA({'Phone B': 'lan', 'Phone C': 'online', 'Phone D': 'lan'});
    final lan = RecordingForwardingTransport();
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          lanForwardingTransport: lan,
          lanReachability: (name) async => name == 'Phone B'
              ? LanReachability.reachable
              : LanReachability.unreachable,
        ).forwardToAllAvenues(_sms));
    expect(lan.submissions.single.request['recipientDeviceName'], 'Phone B');
    final posts = h.backendPosts;
    expect(posts, hasLength(1));
    expect(posts.single.json['recipientDeviceName'], 'Phone C');
    expect(posts.single.data['type'], 'forwarded_sms');
    final rows = await (await h.db).query('transactions');
    expect(
      {
        for (final r in rows)
          r['forwardingRecipientDeviceName']: r['forwardingTransport']
      },
      {'Phone B': 'lan', 'Phone C': 'online'},
    );
    h.expectNoExternalEffects();
  });
}
